const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const { defineSecret } = require("firebase-functions/params");

admin.initializeApp();

setGlobalOptions({ region: "asia-southeast1" });

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");
const lineChannelAccessToken = defineSecret("LINE_CHANNEL_ACCESS_TOKEN");
const lineChannelSecret = defineSecret("LINE_CHANNEL_SECRET");
const geminiApiKey = defineSecret("GEMINI_API_KEY");

const PLANS = {
  monthly: { amount: 29900, days: 30, label: "Shop POS รายเดือน" },
  yearly:  { amount: 299000, days: 365, label: "Shop POS รายปี" },
};

const SUCCESS_URL = "https://pok-pok.app/payment/success";
const CANCEL_URL  = "https://pok-pok.app/payment/cancel";

// ────────────────────────────────────────────────
// Subscription checkout
// ────────────────────────────────────────────────
exports.createCheckoutSession = onCall(
  { secrets: [stripeSecretKey] },
  async (request) => {
    const { shopId, plan } = request.data;

    if (!shopId || !PLANS[plan]) {
      throw new Error("Invalid params: shopId and plan are required");
    }

    const Stripe = require("stripe");
    const stripe = Stripe(stripeSecretKey.value());
    const planConfig = PLANS[plan];

    const session = await stripe.checkout.sessions.create({
      payment_method_types: ["card", "promptpay", "truemoney"],
      line_items: [
        {
          price_data: {
            currency: "thb",
            product_data: { name: planConfig.label },
            unit_amount: planConfig.amount,
          },
          quantity: 1,
        },
      ],
      mode: "payment",
      success_url: SUCCESS_URL,
      cancel_url: CANCEL_URL,
      metadata: { shopId, plan, type: "subscription" },
      client_reference_id: shopId,
    });

    return { url: session.url };
  }
);

// ────────────────────────────────────────────────
// Online order checkout (เรียกจากหน้าเว็บลูกค้า)
// ────────────────────────────────────────────────
exports.createOrderCheckout = onRequest(
  { secrets: [stripeSecretKey], cors: true },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }

    const { shopId, customerName, customerPhone, items } = req.body;

    if (!shopId || !customerName || !customerPhone || !Array.isArray(items) || items.length === 0) {
      res.status(400).json({ error: "ข้อมูลไม่ครบ" });
      return;
    }

    const total = items.reduce((s, item) => s + item.price * item.quantity, 0);

    if (total < 20) {
      res.status(400).json({ error: "ยอดสั่งขั้นต่ำ ฿20" });
      return;
    }

    // สร้าง order doc ก่อน (status: pendingPayment)
    const orderRef = admin
      .firestore()
      .collection("shops")
      .doc(shopId)
      .collection("orders")
      .doc();

    await orderRef.set({
      customerName,
      customerPhone,
      items,
      total,
      status: "pendingPayment",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // สร้าง Stripe Checkout session
    const Stripe = require("stripe");
    const stripe = Stripe(stripeSecretKey.value());

    const session = await stripe.checkout.sessions.create({
      payment_method_types: ["card", "promptpay", "truemoney"],
      line_items: items.map((item) => ({
        price_data: {
          currency: "thb",
          product_data: { name: item.productName },
          unit_amount: Math.round(item.price * 100),
        },
        quantity: item.quantity,
      })),
      mode: "payment",
      success_url: `https://pok-pok.app/order/success/?order=${orderRef.id}`,
      cancel_url: `https://pok-pok.app/order/?shop=${shopId}`,
      metadata: { shopId, type: "order", orderId: orderRef.id },
      client_reference_id: orderRef.id,
    });

    res.json({ url: session.url, orderId: orderRef.id });
  }
);

// ────────────────────────────────────────────────
// PromptPay slip verification (Phase 3 — cross-platform fallback)
// ────────────────────────────────────────────────
// Customer transfers via mobile banking, downloads the slip image,
// uploads it from the order page. We:
//   1. Decode the QR embedded in the slip (every modern Thai bank slip
//      has one — it carries amount + tx ref in EMVCo TLV).
//   2. Verify the amount matches the pending order's finalAmount.
//   3. Use the QR payload as a unique transaction identifier so the
//      same slip can't be reused for two orders.
//   4. Persist the slip to Storage for audit and mark the order paid.
//
// This is the iOS-friendly alternative to the Android notification
// listener; Android shops can use either or both.
exports.verifyPromptPaySlip = onRequest(
  { cors: true, memory: "512MiB" },
  async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");
    res.set("X-Content-Type-Options", "nosniff");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }

    const { shopId, orderId, slipBase64 } = req.body || {};
    if (!shopId || !orderId || !slipBase64) {
      res.status(400).json({ error: "shopId, orderId, slipBase64 required" });
      return;
    }

    try {
      const orderRef = admin
        .firestore()
        .collection("shops").doc(shopId)
        .collection("orders").doc(orderId);
      const orderSnap = await orderRef.get();
      if (!orderSnap.exists) {
        res.status(404).json({ error: "Order not found" });
        return;
      }
      const order = orderSnap.data();
      if (order.status !== "pendingPayment") {
        res.json({ success: false, reason: "order already processed" });
        return;
      }

      // Strip data: prefix if present, then decode.
      const cleanBase64 = slipBase64.replace(/^data:image\/\w+;base64,/, "");
      const buf = Buffer.from(cleanBase64, "base64");

      // Decode QR from image.
      const Jimp = require("jimp");
      const jsQR = require("jsqr");
      const img = await Jimp.read(buf);
      const qr = jsQR(
        new Uint8ClampedArray(img.bitmap.data),
        img.bitmap.width,
        img.bitmap.height
      );
      if (!qr || !qr.data) {
        res.json({
          success: false,
          reason: "QR ในสลิปอ่านไม่ได้ — ลองถ่ายให้ชัดและตรงหน่อย",
        });
        return;
      }

      const slipAmount = parseEmvAmount(qr.data);
      if (slipAmount == null) {
        res.json({
          success: false,
          reason: "ไม่พบยอดเงินใน QR ของสลิป",
        });
        return;
      }

      const expected = Number(order.finalAmount || order.total);
      if (Math.abs(slipAmount - expected) > 0.01) {
        res.json({
          success: false,
          reason: `ยอดในสลิปไม่ตรง: สลิป ฿${slipAmount.toFixed(2)} vs ออเดอร์ ฿${expected.toFixed(2)}`,
        });
        return;
      }

      // Use entire QR payload as a tx identifier — collision-resistant
      // and provider-agnostic (each bank's slip embeds its own ref).
      const txKey = hashString(qr.data);
      const usedRef = admin
        .firestore()
        .collection("shops").doc(shopId)
        .collection("usedSlipRefs").doc(String(txKey));
      const usedSnap = await usedRef.get();
      if (usedSnap.exists) {
        res.json({
          success: false,
          reason: "สลิปนี้เคยใช้กับออเดอร์อื่นแล้ว",
        });
        return;
      }

      // Persist slip to Storage for audit + give shop owner a link.
      const fileName = `shops/${shopId}/orderSlips/${orderId}.jpg`;
      const file = admin.storage().bucket().file(fileName);
      await file.save(buf, {
        contentType: "image/jpeg",
        resumable: false,
      });
      // Make it readable via a long-lived signed URL.
      const [slipUrl] = await file.getSignedUrl({
        action: "read",
        expires: "2030-12-31",
      });

      // Mark paid + record txKey so the same slip can't be replayed.
      await orderRef.update({
        status: "paid",
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        paymentRef: `slip:${txKey}`,
        autoConfirmed: true,
        slipUrl,
      });
      await usedRef.set({
        orderId,
        amount: slipAmount,
        ts: admin.firestore.FieldValue.serverTimestamp(),
      });

      res.json({ success: true, txRef: txKey });
    } catch (e) {
      console.error("verifyPromptPaySlip error:", e);
      res.status(500).json({
        error: "verifyPromptPaySlip failed",
        message: String(e && e.message ? e.message : e).slice(0, 200),
      });
    }
  }
);

// Extract amount from an EMVCo PromptPay QR payload (tag "54" = amount).
function parseEmvAmount(payload) {
  let i = 0;
  while (i < payload.length - 4) {
    const tag = payload.slice(i, i + 2);
    const len = parseInt(payload.slice(i + 2, i + 4), 10);
    if (isNaN(len) || i + 4 + len > payload.length) return null;
    const value = payload.slice(i + 4, i + 4 + len);
    if (tag === "54") {
      const n = parseFloat(value);
      return isNaN(n) ? null : n;
    }
    i += 4 + len;
  }
  return null;
}

// ────────────────────────────────────────────────
// Online order via PromptPay (no Stripe — money goes straight to shop)
// ────────────────────────────────────────────────
exports.createPromptPayOrder = onRequest(
  { cors: true },
  async (req, res) => {
    // Explicit CORS + nosniff so Chrome's CORB doesn't drop the body
    // when the response is proxied through Firebase Hosting rewrites.
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");
    res.set("X-Content-Type-Options", "nosniff");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }

    const { shopId, customerName, customerPhone, items } = req.body;
    if (!shopId || !customerName || !customerPhone || !Array.isArray(items) || items.length === 0) {
      res.status(400).json({ error: "ข้อมูลไม่ครบ" });
      return;
    }

    const total = items.reduce((s, item) => s + item.price * item.quantity, 0);
    if (total < 20) {
      res.status(400).json({ error: "ยอดสั่งขั้นต่ำ ฿20" });
      return;
    }

    // Look up the shop's PromptPay settings
    const settingsSnap = await admin
      .firestore()
      .collection("shops").doc(shopId)
      .collection("settings").doc("shop")
      .get();
    const settings = settingsSnap.data() || {};
    const promptpayId = settings.promptpayId;
    const promptpayName = settings.promptpayName || "";

    if (!promptpayId) {
      res.status(400).json({
        error: "ร้านนี้ยังไม่ได้ตั้งค่า PromptPay กรุณาติดต่อร้านโดยตรง",
      });
      return;
    }

    // Create order doc first so its ID seeds the unique cents
    const orderRef = admin
      .firestore()
      .collection("shops").doc(shopId)
      .collection("orders").doc();

    // Unique cents per order: 1..99 satang. The server computes this
    // once and writes it to Firestore as finalAmount; both app and web
    // just read that value back, so the cents derivation only needs to
    // be deterministic per orderId — not identical across languages.
    const cents = (hashString(orderRef.id) % 99) + 1;
    const finalAmount = Math.round((total + cents / 100) * 100) / 100;

    await orderRef.set({
      customerName,
      customerPhone,
      items,
      total,
      finalAmount,
      paymentMethod: "promptpay",
      status: "pendingPayment",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({
      orderId: orderRef.id,
      total,
      finalAmount,
      promptpayId,
      promptpayName,
    });
  }
);

// Mirrors Dart's String.hashCode (DJB2-ish) closely enough for our use:
// we only need the same orderId → same cents mapping on both clients.
function hashString(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) - h + s.charCodeAt(i)) | 0;
  }
  return Math.abs(h);
}

// ────────────────────────────────────────────────
// Stripe webhook
// ────────────────────────────────────────────────
exports.stripeWebhook = onRequest(
  { secrets: [stripeSecretKey, stripeWebhookSecret], rawBody: true },
  async (req, res) => {
    const Stripe = require("stripe");
    const stripe = Stripe(stripeSecretKey.value());
    const sig = req.headers["stripe-signature"];

    let event;
    try {
      event = stripe.webhooks.constructEvent(
        req.rawBody,
        sig,
        stripeWebhookSecret.value().trim()
      );
    } catch (err) {
      console.error("Webhook signature verification failed:", err.message);
      res.status(400).send(`Webhook Error: ${err.message}`);
      return;
    }

    if (event.type === "checkout.session.completed") {
      const session = event.data.object;
      const { shopId, type, plan, orderId } = session.metadata;

      if (!shopId) {
        console.error("Missing shopId in metadata");
        res.json({ received: true });
        return;
      }

      if (type === "order") {
        // ── Online order payment ──
        if (!orderId) {
          console.error("Missing orderId in metadata");
          res.json({ received: true });
          return;
        }

        const orderRef = admin
          .firestore()
          .collection("shops")
          .doc(shopId)
          .collection("orders")
          .doc(orderId);

        const orderDoc = await orderRef.get();
        if (!orderDoc.exists) {
          console.error("Order not found:", orderId);
          res.json({ received: true });
          return;
        }

        // ลด stock สินค้าแต่ละชิ้น
        const orderData = orderDoc.data();
        const batch = admin.firestore().batch();
        for (const item of orderData.items) {
          const productRef = admin
            .firestore()
            .collection("shops")
            .doc(shopId)
            .collection("products")
            .doc(item.productId);
          batch.update(productRef, {
            stock: admin.firestore.FieldValue.increment(-item.quantity),
          });
        }
        await batch.commit();

        // อัพเดต order status → paid
        await orderRef.update({
          status: "paid",
          paidAt: admin.firestore.FieldValue.serverTimestamp(),
          stripeSessionId: session.id,
        });

        // สร้าง sale record เพื่อให้ขึ้นใน dashboard/report
        const saleRef = admin
          .firestore()
          .collection("shops")
          .doc(shopId)
          .collection("sales")
          .doc();

        await saleRef.set({
          items: orderData.items.map((item) => ({
            productId: item.productId,
            productName: item.productName,
            price: item.price,
            quantity: item.quantity,
            subtotal: item.price * item.quantity,
          })),
          total: orderData.total,
          discount: 0,
          paid: orderData.total,
          change: 0,
          paymentMethod: "online",
          isDebt: false,
          customerName: orderData.customerName,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          orderId: orderRef.id,
          stripePaymentIntentId: session.payment_intent || null,
        });

        // ส่ง FCM notification ไปยังเจ้าของร้าน
        const shopDoc = await admin.firestore().collection("shops").doc(shopId).get();
        const fcmToken = shopDoc.data()?.fcmToken;
        if (fcmToken) {
          const itemCount = orderData.items.reduce((s, i) => s + i.quantity, 0);
          await admin.messaging().send({
            token: fcmToken,
            notification: {
              title: "ออเดอร์ใหม่!",
              body: `${orderData.customerName} · ${itemCount} ชิ้น · ฿${orderData.total}`,
            },
            android: { notification: { channelId: "new_orders", priority: "high" } },
          });
        }

        // ส่ง LINE notification ถ้าเปิดใช้งาน
        const shopSettingDoc = await admin.firestore()
          .collection("shops").doc(shopId)
          .collection("settings").doc("shop").get();
        const lineUserId = shopSettingDoc.data()?.lineUserId;
        const lineEnabled = shopSettingDoc.data()?.lineNotifyEnabled !== false;
        if (lineUserId && lineEnabled) {
          const itemCount = orderData.items.reduce((s, i) => s + i.quantity, 0);
          await _linePush(lineChannelAccessToken.value(), lineUserId, [{
            type: "text",
            text: `🛒 ออเดอร์ใหม่!\nลูกค้า: ${orderData.customerName}\nสินค้า: ${itemCount} ชิ้น\nยอด: ฿${orderData.total}\nเปิดแอป Pokpok เพื่อยืนยัน`
          }]);
        }

        console.log(`Order ${orderId} paid for shop ${shopId}`);
      } else {
        // ── Subscription payment ──
        if (!PLANS[plan]) {
          console.error("Missing or invalid plan in metadata");
          res.json({ received: true });
          return;
        }

        const days = PLANS[plan].days;
        const shopRef = admin.firestore().collection("shops").doc(shopId);
        const shopDoc = await shopRef.get();

        let baseDate = new Date();
        if (shopDoc.exists) {
          const data = shopDoc.data();
          const existingEnd = data.subscriptionEndsAt?.toDate();
          if (existingEnd && existingEnd > baseDate) {
            baseDate = existingEnd;
          }
        }

        const newEndDate = new Date(
          baseDate.getTime() + days * 24 * 60 * 60 * 1000
        );

        await shopRef.set(
          {
            subscriptionStatus: "active",
            subscriptionEndsAt: admin.firestore.Timestamp.fromDate(newEndDate),
            plan,
            lastPaymentAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        console.log(`Subscription updated for shop ${shopId}: ${plan} until ${newEndDate.toISOString()}`);
      }
    }

    res.json({ received: true });
  }
);

// ────────────────────────────────────────────────
// Refund a sale (Stripe + Firestore)
// ────────────────────────────────────────────────
exports.createRefund = onCall(
  { secrets: [stripeSecretKey] },
  async (request) => {
    const { shopId, saleId, reason } = request.data;
    if (!shopId || !saleId) throw new Error("shopId and saleId required");

    const db = admin.firestore();
    const saleRef = db.collection("shops").doc(shopId).collection("sales").doc(saleId);
    const saleDoc = await saleRef.get();
    if (!saleDoc.exists) throw new Error("Sale not found");

    const saleData = saleDoc.data();
    if (saleData.isRefunded) throw new Error("Already refunded");

    let stripeRefundId = null;
    if (saleData.stripePaymentIntentId) {
      const Stripe = require("stripe");
      const stripe = Stripe(stripeSecretKey.value());
      const refund = await stripe.refunds.create({
        payment_intent: saleData.stripePaymentIntentId,
        reason: "requested_by_customer",
      });
      stripeRefundId = refund.id;
    }

    const batch = db.batch();
    batch.update(saleRef, {
      isRefunded: true,
      refundedAt: admin.firestore.FieldValue.serverTimestamp(),
      refundReason: reason || "",
      stripeRefundId,
    });

    for (const item of saleData.items) {
      const productRef = db.collection("shops").doc(shopId).collection("products").doc(item.productId);
      batch.update(productRef, { stock: admin.firestore.FieldValue.increment(item.quantity) });
    }

    if (saleData.isDebt) {
      const debtSnap = await db.collection("shops").doc(shopId).collection("debts")
        .where("saleId", "==", saleId).limit(1).get();
      for (const doc of debtSnap.docs) batch.delete(doc.reference);
    }

    await batch.commit();
    return { success: true, stripeRefundId };
  }
);

// ────────────────────────────────────────────────
// LINE Messaging API — helpers
// ────────────────────────────────────────────────
async function _linePush(token, to, messages) {
  const res = await fetch("https://api.line.me/v2/bot/message/push", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ to, messages }),
  });
  if (!res.ok) {
    const err = await res.text();
    console.error("LINE push error:", err);
  }
  return res.ok;
}

async function _lineReply(token, replyToken, messages) {
  const res = await fetch("https://api.line.me/v2/bot/message/reply", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ replyToken, messages }),
  });
  return res.ok;
}

function _verifyLineSignature(secret, rawBody, signature) {
  const crypto = require("crypto");
  const hash = crypto
    .createHmac("SHA256", secret)
    .update(Buffer.from(rawBody))
    .digest("base64");
  return hash === signature;
}

// ────────────────────────────────────────────────
// LINE Webhook — รับ events จาก LINE platform
// ────────────────────────────────────────────────
exports.lineWebhook = onRequest(
  { secrets: [lineChannelAccessToken, lineChannelSecret], rawBody: true },
  async (req, res) => {
    const signature = req.headers["x-line-signature"];
    if (!signature || !_verifyLineSignature(lineChannelSecret.value(), req.rawBody, signature)) {
      console.error("Invalid LINE signature");
      res.status(401).send("Unauthorized");
      return;
    }

    const events = req.body.events || [];
    const token = lineChannelAccessToken.value();

    for (const event of events) {
      const userId = event.source?.userId;
      if (!userId) continue;

      // เมื่อ user follow bot → ส่งข้อความต้อนรับ + วิธีเชื่อม
      if (event.type === "follow") {
        await _lineReply(token, event.replyToken, [{
          type: "text",
          text: `ยินดีต้อนรับสู่ Pokpok POS 🎉\n\nส่งข้อความใดก็ได้เพื่อรับ LINE User ID ของคุณ แล้วนำไปใส่ใน Settings → การแจ้งเตือน LINE ในแอป Pokpok`
        }]);
        continue;
      }

      // เมื่อ user ส่งข้อความ → ตอบ userId ให้ copy ไปใส่ settings
      if (event.type === "message" && event.message?.type === "text") {
        const text = event.message.text.trim().toLowerCase();

        // รองรับ command เชื่อม shop: "link:SHOP_ID"
        if (text.startsWith("link:")) {
          const shopId = text.replace("link:", "").trim();
          if (shopId) {
            await admin.firestore()
              .collection("shops").doc(shopId)
              .collection("settings").doc("shop")
              .set({ lineUserId: userId, lineNotifyEnabled: true }, { merge: true });

            await _lineReply(token, event.replyToken, [{
              type: "text",
              text: `✅ เชื่อมต่อสำเร็จ!\nร้านค้า ${shopId} จะได้รับแจ้งเตือนออเดอร์ใหม่ผ่าน LINE แล้ว`
            }]);
          }
          continue;
        }

        // ตอบ userId เพื่อให้ copy ไปใส่ settings
        await _lineReply(token, event.replyToken, [{
          type: "text",
          text: `LINE User ID ของคุณ:\n${userId}\n\nนำ ID นี้ไปใส่ใน Settings → การแจ้งเตือน LINE ในแอป Pokpok\n\nหรือส่ง "link:SHOP_ID" เพื่อเชื่อมอัตโนมัติ`
        }]);
      }
    }

    res.json({ status: "ok" });
  }
);

// ────────────────────────────────────────────────
// sendLineMessage — callable จาก Flutter app
// ────────────────────────────────────────────────
exports.sendLineMessage = onCall(
  { secrets: [lineChannelAccessToken] },
  async (request) => {
    const { shopId, message, messageType = "text" } = request.data;
    if (!shopId || !message) throw new Error("shopId and message required");

    const db = admin.firestore();
    const settingDoc = await db
      .collection("shops").doc(shopId)
      .collection("settings").doc("shop")
      .get();

    const data = settingDoc.data() || {};
    const lineUserId = data.lineUserId;
    const enabled = data.lineNotifyEnabled !== false;

    if (!lineUserId) throw new Error("LINE User ID not configured");
    if (!enabled) return { skipped: true, reason: "LINE notify disabled" };

    const messages = [{ type: "text", text: message }];
    const ok = await _linePush(lineChannelAccessToken.value(), lineUserId, messages);
    return { success: ok };
  }
);

// ────────────────────────────────────────────────
// AI chat proxy → Google Gemini Flash 8B
// ────────────────────────────────────────────────
// Why a proxy instead of calling Gemini from the client?
//   1. Shop owners never see / manage an API key — frictionless setup.
//   2. The single platform key stays server-side (no leakage into APKs).
//   3. We can gate by subscription + per-shop daily quota here.
//   4. Future tier switching (Gemini → OpenAI for paid plans) is one
//      function change, no client redeploy.
//
// Request:  { history: [{role:'user'|'assistant', content:string}], shopContext?: string }
// Response: { reply: string, usage: { dailyCount: number, dailyLimit: number } }
const AI_DAILY_LIMIT_PER_SHOP = 100;
// Google retired the 1.5 line in 2026; 2.5 Flash Lite is the current
// equivalent — same price tier, better Thai output, current SDK support.
const AI_MODEL = "gemini-2.5-flash-lite";

exports.aiChat = onCall(
  { secrets: [geminiApiKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required");
    }
    const shopId = request.auth.uid;
    const { history, shopContext } = request.data || {};
    if (!Array.isArray(history) || history.length === 0) {
      throw new HttpsError("invalid-argument", "history is required");
    }

    // Subscription gate — only trial-in-window or active-in-window shops
    // get to spend our Gemini budget.
    const shopSnap = await admin.firestore().collection("shops").doc(shopId).get();
    if (!shopSnap.exists) {
      throw new HttpsError("not-found", "Shop not found");
    }
    const shop = shopSnap.data();
    const now = new Date();
    const trialOk =
      shop.subscriptionStatus === "trial" &&
      shop.trialEndsAt &&
      shop.trialEndsAt.toDate() > now;
    const activeOk =
      shop.subscriptionStatus === "active" &&
      shop.subscriptionEndsAt &&
      shop.subscriptionEndsAt.toDate() > now;
    if (!trialOk && !activeOk) {
      throw new HttpsError(
        "failed-precondition",
        "Subscription not active — please renew to use AI"
      );
    }

    // Per-shop daily rate limit. Doc id = YYYY-MM-DD so it rolls over
    // automatically at midnight in the function's region.
    const today = now.toISOString().slice(0, 10);
    const usageRef = admin
      .firestore()
      .collection("shops").doc(shopId)
      .collection("aiUsage").doc(today);
    const usageSnap = await usageRef.get();
    const dailyCount = usageSnap.exists ? (usageSnap.data().count || 0) : 0;
    if (dailyCount >= AI_DAILY_LIMIT_PER_SHOP) {
      throw new HttpsError(
        "resource-exhausted",
        `ใช้ AI ครบ ${AI_DAILY_LIMIT_PER_SHOP} ครั้งในวันนี้แล้ว — เริ่มใหม่พรุ่งนี้`
      );
    }

    // Build Gemini request. Gemini uses 'model' instead of 'assistant'.
    const systemPrompt =
      "คุณเป็นผู้ช่วย AI สำหรับร้านค้าปลีกที่ใช้ระบบ Pokpok POS\n" +
      "ตอบเป็นภาษาไทย กระชับ ตรงประเด็น ช่วยวิเคราะห์ยอดขาย แนะนำการจัดการร้าน" +
      (shopContext ? "\n\nข้อมูลร้านวันนี้:\n" + shopContext : "");

    const contents = history.map((m) => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: String(m.content || "") }],
    }));

    const url =
      "https://generativelanguage.googleapis.com/v1beta/models/" +
      AI_MODEL +
      ":generateContent?key=" +
      geminiApiKey.value();
    const geminiRes = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemPrompt }] },
        contents,
        generationConfig: {
          maxOutputTokens: 1024,
          temperature: 0.7,
        },
      }),
    });

    if (!geminiRes.ok) {
      const errText = await geminiRes.text();
      console.error("Gemini API error:", geminiRes.status, errText);
      throw new HttpsError(
        "internal",
        `AI provider error (${geminiRes.status}): ${errText.slice(0, 200)}`
      );
    }
    const data = await geminiRes.json();
    const reply = data?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!reply) {
      console.error("Empty Gemini response:", JSON.stringify(data));
      throw new HttpsError("internal", "AI returned no content");
    }

    // Bump the daily counter only on a successful call so quota-exhausted
    // user attempts don't burn budget.
    await usageRef.set(
      {
        count: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      reply,
      usage: {
        dailyCount: dailyCount + 1,
        dailyLimit: AI_DAILY_LIMIT_PER_SHOP,
      },
    };
  }
);
