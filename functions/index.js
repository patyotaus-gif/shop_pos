const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
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

// ────────────────────────────────────────────────
// 4-tier pricing (Pokpok GTM plan)
// ────────────────────────────────────────────────
// amounts are in สตางค์ (Stripe API). Restaurant is priced per location
// — the checkout multiplies amount × locations at session create.
const PLANS = {
  solo: {
    monthly: { amount:  19900, days:  30, label: "Pokpok Solo รายเดือน" },
    yearly:  { amount: 199000, days: 365, label: "Pokpok Solo รายปี" },
  },
  lite: {
    monthly: { amount:  39900, days:  30, label: "Pokpok Lite รายเดือน" },
    yearly:  { amount: 399000, days: 365, label: "Pokpok Lite รายปี" },
    // Hardware peripheral bundle (printer + drawer + stand). One-off
    // up-front charge OR financed across 24 months — Phase D will wire
    // the financed option through Stripe Subscriptions.
    hardwareUpfront: 400000,
  },
  full: {
    monthly: { amount:  59900, days:  30, label: "Pokpok Full รายเดือน" },
    yearly:  { amount: 599000, days: 365, label: "Pokpok Full รายปี" },
    // Hardware-as-a-service: ฿1,000 deposit (refundable), 36-month term
    deposit: 100000,
    termMonths: 36,
  },
  restaurant: {
    // Priced per location — Cloud Function multiplies by `locations`
    monthly: { amount: 119900, days:  30, label: "Pokpok Restaurant รายเดือน" },
    yearly:  { amount: 1199000, days: 365, label: "Pokpok Restaurant รายปี" },
    depositPerLocation: 200000,
    perLocation: true,
  },
};

// Backward compatibility: older clients still send plan='monthly' or
// 'yearly' without a tier. Default them to Full (Tier 3 was the closest
// equivalent to the historical ฿299 plan they came from).
function resolvePlanConfig(tier, billingCycle) {
  const tierConfig = PLANS[tier] || PLANS.full;
  return tierConfig[billingCycle] || tierConfig.monthly;
}

// Monthly-normalised recurring revenue in baht for one shop's plan.
// Yearly plans are divided by 12; restaurant is per-location. Used by the
// ops dashboard to sum MRR across paying shops.
function monthlyRevenueBaht(tier, billingCycle, locations) {
  const cfg = resolvePlanConfig(tier, billingCycle);
  if (!cfg) return 0;
  const locs = Math.max(1, parseInt(locations || 1));
  const perLoc = PLANS[tier]?.perLocation === true;
  const amountSatang = perLoc ? cfg.amount * locs : cfg.amount;
  const baht = amountSatang / 100;
  return billingCycle === "yearly" ? baht / 12 : baht;
}

const MARKETPLACE_TAKE_RATE = 0.025; // 2.5% — applied at marketplace order

const SUCCESS_URL = "https://pok-pok.app/payment/success";
const CANCEL_URL  = "https://pok-pok.app/payment/cancel";

// ────────────────────────────────────────────────
// Subscription checkout
// ────────────────────────────────────────────────
exports.createCheckoutSession = onCall(
  { secrets: [stripeSecretKey] },
  async (request) => {
    const {
      shopId,
      // New params (Phase A onwards)
      tier,           // 'solo' | 'lite' | 'full' | 'restaurant'
      billingCycle,   // 'monthly' | 'yearly'
      locations,      // restaurant only — defaults to 1
      // Legacy fallback — older clients sent { plan: 'monthly' | 'yearly' }
      plan,
    } = request.data;

    if (!shopId) {
      throw new Error("shopId is required");
    }
    // Only the signed-in owner may start a checkout for their own shop —
    // the callable is invoked from the web /subscribe page after login.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required");
    }
    if (request.auth.uid !== shopId) {
      throw new HttpsError("permission-denied", "shopId mismatch");
    }

    // Resolve which plan to bill. If a tier is sent, use the new path;
    // otherwise treat the legacy `plan` as a billingCycle on the Full tier.
    const resolvedTier = tier || "full";
    const resolvedCycle = billingCycle || plan || "monthly";
    const planConfig = resolvePlanConfig(resolvedTier, resolvedCycle);

    if (!planConfig) {
      throw new Error(`Invalid plan: tier=${resolvedTier}, cycle=${resolvedCycle}`);
    }

    // Restaurant is per-location — multiply.
    const locs = Math.max(1, parseInt(locations || 1));
    const isPerLocation = PLANS[resolvedTier]?.perLocation === true;
    const unitAmount = isPerLocation ? planConfig.amount * locs : planConfig.amount;
    const labelSuffix = isPerLocation && locs > 1 ? ` × ${locs} สาขา` : "";

    const Stripe = require("stripe");
    const stripe = Stripe(stripeSecretKey.value());

    const session = await stripe.checkout.sessions.create({
      payment_method_types: ["card", "promptpay", "truemoney"],
      line_items: [
        {
          price_data: {
            currency: "thb",
            product_data: { name: planConfig.label + labelSuffix },
            unit_amount: unitAmount,
          },
          quantity: 1,
        },
      ],
      mode: "payment",
      success_url: SUCCESS_URL,
      cancel_url: CANCEL_URL,
      metadata: {
        shopId,
        tier: resolvedTier,
        billingCycle: resolvedCycle,
        locations: String(locs),
        type: "subscription",
      },
      client_reference_id: shopId,
    });

    return { url: session.url };
  }
);

// ────────────────────────────────────────────────
// Public shop info for the customer order page. The shop doc is locked to
// its owner (it holds the owner's email + subscription state), so the order
// page asks this endpoint instead — it returns only the non-PII display
// fields. No backfill needed since it reads the live shop doc.
// ────────────────────────────────────────────────
exports.getShopPublic = onRequest({ cors: true }, async (req, res) => {
  const shopId = String(req.query.shop || "").trim();
  if (!shopId) {
    res.status(400).json({ error: "shop required" });
    return;
  }
  const db = admin.firestore();
  const shopSnap = await db.collection("shops").doc(shopId).get();
  if (!shopSnap.exists) {
    res.status(404).json({ error: "not found" });
    return;
  }
  const shop = shopSnap.data() || {};

  // Products served here too so the order page makes no public Firestore
  // reads (App-Check-enforceable later). Whitelist display fields only —
  // never leak cost price or other internal fields to a customer.
  const prodSnap = await db
    .collection("shops")
    .doc(shopId)
    .collection("products")
    .limit(300)
    .get();
  const products = [];
  for (const doc of prodSnap.docs) {
    const p = doc.data() || {};
    if (typeof p.stock !== "number") continue;
    products.push({
      id: doc.id,
      name: p.name || "",
      price: Number(p.price || 0),
      stock: p.stock,
      category: p.category || "",
      imageUrl: p.imageUrl || "",
    });
  }

  res.json({ name: shop.name || "ร้านค้า", products });
});

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
      const { shopId, type, plan, orderId, tier, billingCycle, locations } =
        session.metadata;

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
        // Resolve tier + billingCycle from metadata. New checkouts send
        // both; legacy checkouts only send `plan` (which was a billing
        // cycle on the old flat-price model) — treat those as Full tier.
        const resolvedTier = tier || "full";
        const resolvedCycle = billingCycle || plan || "monthly";
        const planConfig = resolvePlanConfig(resolvedTier, resolvedCycle);

        if (!planConfig) {
          console.error(
            `Invalid plan in metadata: tier=${resolvedTier}, cycle=${resolvedCycle}`
          );
          res.json({ received: true });
          return;
        }

        const days = planConfig.days;
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
            tier: resolvedTier,
            plan: resolvedCycle, // billing cycle — keep as plan for legacy
            locations: Math.max(1, parseInt(locations || 1)),
            lastPaymentAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        console.log(
          `Subscription updated for shop ${shopId}: tier=${resolvedTier} cycle=${resolvedCycle} until ${newEndDate.toISOString()}`
        );
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

      // เมื่อ user follow bot → ส่งข้อความต้อนรับ
      if (event.type === "follow") {
        await _lineReply(token, event.replyToken, [{
          type: "text",
          text:
            "ยินดีต้อนรับสู่ Pokpok 🎉\n\n" +
            "• ร้านค้า/ซัพพลายเออร์ที่ต้องการรับแจ้งเตือนออเดอร์ผ่าน LINE — พิมพ์ \"ID\" เพื่อรับ LINE User ID ของคุณ\n" +
            "• มีคำถามอื่น ๆ ทักได้เลย ทีมงานจะตอบกลับโดยเร็ว"
        }]);
        continue;
      }

      // เมื่อ user ส่งข้อความ → ตอบ userId ให้ copy ไปใส่ settings
      if (event.type === "message" && event.message?.type === "text") {
        const text = event.message.text.trim().toLowerCase();

        // NOTE: เคยมีคำสั่ง "link:SHOP_ID" ที่เขียน lineUserId ลงร้านโดยตรง
        // แต่ถอดออกเพราะไม่ได้ยืนยันความเป็นเจ้าของ — ใครรู้ shopId (หลุดจาก
        // URL หน้าสั่งของ) ก็แย่งการแจ้งเตือนออเดอร์ของร้านอื่นได้. การเชื่อม
        // LINE ทำผ่านเจ้าของเท่านั้น: พิมพ์ "ID" รับ User ID แล้วเอาไปวางใน
        // แอป (ตั้งค่า) / พอร์ทัลซัพพลายเออร์ ซึ่งเขียนได้เฉพาะเจ้าของ.

        // คีย์เวิร์ดขอ User ID — ตอบเฉพาะเมื่อถามตรง ๆ เท่านั้น เพื่อไม่ให้
        // ลูกค้าทั่วไปที่ทักมาถามได้ User ID งง ๆ กลับไป
        const idKeywords =
          ["id", "ไอดี", "รหัส", "userid", "user id", "myid", "my id"];
        if (idKeywords.includes(text)) {
          await _lineReply(token, event.replyToken, [{
            type: "text",
            text:
              `LINE User ID ของคุณ:\n${userId}\n\n` +
              "นำ ID นี้ไปวางใน:\n" +
              "• แอป Pokpok → ตั้งค่า → การแจ้งเตือน LINE (ร้านค้า)\n" +
              "• พอร์ทัลซัพพลายเออร์ → แก้ไขร้าน (ซัพพลายเออร์)\n" +
              "เพื่อรับแจ้งเตือนออเดอร์ใหม่ผ่าน LINE"
          }]);
          continue;
        }

        // ข้อความทั่วไป → ตอบสุภาพ + บอกวิธีขอ User ID
        await _lineReply(token, event.replyToken, [{
          type: "text",
          text:
            "ขอบคุณที่ติดต่อ Pokpok 🙏\nทีมงานจะตอบกลับโดยเร็วที่สุด\n\n" +
            "(อยากรับแจ้งเตือนออเดอร์ผ่าน LINE? พิมพ์ \"ID\" เพื่อรับ LINE User ID ของคุณ)"
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

// ────────────────────────────────────────────────
// Referral — redeem a code at signup
// ────────────────────────────────────────────────
// Runs as admin so it can extend BOTH shops' trials (a client can only
// write its own shop doc). Idempotent: a shop that already has
// `referredBy` set can't claim a second reward.
const REFERRAL_BONUS_DAYS = 30;

exports.applyReferral = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login required");
  }
  const shopId = request.auth.uid;
  const code = String(request.data?.code || "").trim().toUpperCase();
  if (!code) {
    throw new HttpsError("invalid-argument", "code is required");
  }

  const db = admin.firestore();
  const selfRef = db.collection("shops").doc(shopId);
  const selfSnap = await selfRef.get();
  if (!selfSnap.exists) {
    throw new HttpsError("not-found", "Shop not found");
  }
  // Already claimed a referral — no double-dipping.
  if (selfSnap.data().referredBy) {
    return { applied: false, reason: "already-referred" };
  }
  // Can't refer yourself.
  if (selfSnap.data().referralCode === code) {
    return { applied: false, reason: "self" };
  }

  // Find the referrer by code.
  const referrerQuery = await db
    .collection("shops")
    .where("referralCode", "==", code)
    .limit(1)
    .get();
  if (referrerQuery.empty) {
    return { applied: false, reason: "code-not-found" };
  }
  const referrerRef = referrerQuery.docs[0].ref;

  // Extend both trials by REFERRAL_BONUS_DAYS from their current end (or
  // from now if already lapsed). Only meaningful while a shop is still on
  // trial; for an active paid shop we extend the trial end harmlessly but
  // it won't affect their paid subscriptionEndsAt.
  const bonusMs = REFERRAL_BONUS_DAYS * 24 * 60 * 60 * 1000;
  function extend(snap) {
    const cur = snap.data().trialEndsAt?.toDate();
    const base = cur && cur > new Date() ? cur : new Date();
    return admin.firestore.Timestamp.fromDate(
      new Date(base.getTime() + bonusMs)
    );
  }

  const referrerSnap = referrerQuery.docs[0];
  const batch = db.batch();
  batch.update(selfRef, {
    referredBy: code,
    trialEndsAt: extend(selfSnap),
  });
  batch.update(referrerRef, {
    trialEndsAt: extend(referrerSnap),
  });
  await batch.commit();

  return { applied: true, bonusDays: REFERRAL_BONUS_DAYS };
});

// ────────────────────────────────────────────────
// Ops dashboard — founder-only business metrics
// ────────────────────────────────────────────────
// Aggregates across ALL shops (admin SDK bypasses Firestore rules), so it
// is locked to the founder's account by an email allowlist. No shop owner
// can call it, and the client never reads other shops directly — rules
// stay per-owner.
const FOUNDER_EMAILS = ["patyotaus@gmail.com"];

// Throws unless the caller is signed in as a founder. Every admin/ops
// callable funnels through here so the allowlist lives in one place.
function assertFounder(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login required");
  }
  const email = String(request.auth.token.email || "").toLowerCase();
  if (!FOUNDER_EMAILS.includes(email)) {
    throw new HttpsError("permission-denied", "Founder only");
  }
}

exports.opsMetrics = onCall(async (request) => {
  assertFounder(request);

  const db = admin.firestore();
  const snap = await db.collection("shops").get();
  const now = new Date();
  const day = 24 * 60 * 60 * 1000;

  let total = 0;
  let active = 0; // paying, still in window
  let trialing = 0; // on trial, still in window
  let expired = 0; // lapsed trial or lapsed subscription
  let mrr = 0;
  let new7 = 0;
  let new30 = 0;
  let trialsEndingSoon = 0; // trialing & ends within 7 days
  let referredCount = 0;
  const tierAll = { solo: 0, lite: 0, full: 0, restaurant: 0 };
  const tierPaid = { solo: 0, lite: 0, full: 0, restaurant: 0 };

  snap.forEach((doc) => {
    const d = doc.data();
    total++;
    const tier =
      d.tier || (d.shopType === "restaurant" ? "restaurant" : "full");
    if (tierAll[tier] !== undefined) tierAll[tier]++;

    const status = d.subscriptionStatus || "trial";
    const trialEnd = d.trialEndsAt?.toDate?.() || null;
    const subEnd = d.subscriptionEndsAt?.toDate?.() || null;
    const createdAt = d.createdAt?.toDate?.() || null;

    const isActive = status === "active" && subEnd && subEnd > now;
    const isTrialing = status === "trial" && trialEnd && trialEnd > now;

    if (isActive) {
      active++;
      if (tierPaid[tier] !== undefined) tierPaid[tier]++;
      mrr += monthlyRevenueBaht(tier, d.plan || "monthly", d.locations || 1);
    } else if (isTrialing) {
      trialing++;
      if (trialEnd.getTime() - now.getTime() <= 7 * day) trialsEndingSoon++;
    } else {
      expired++;
    }

    if (createdAt) {
      const age = now.getTime() - createdAt.getTime();
      if (age <= 7 * day) new7++;
      if (age <= 30 * day) new30++;
    }
    if (d.referredBy) referredCount++;
  });

  // Rough conversion proxy: of shops that have finished their trial
  // (now either paying or expired), what fraction are paying. Without a
  // historical event log this is an approximation, not a cohort metric.
  const finishedTrial = active + expired;
  const conversionRate = finishedTrial > 0 ? (active / finishedTrial) * 100 : 0;

  return {
    generatedAt: now.toISOString(),
    totals: { total, active, trialing, expired },
    mrr: Math.round(mrr),
    arr: Math.round(mrr * 12),
    arpa: active > 0 ? Math.round(mrr / active) : 0, // avg revenue per account
    growth: { new7, new30 },
    trials: { trialing, endingSoon: trialsEndingSoon },
    conversionRate: Math.round(conversionRate * 10) / 10, // percent, 1 dp
    referredCount,
    tierAll,
    tierPaid,
  };
});

// ────────────────────────────────────────────────
// Founder admin console — cross-shop management
// ────────────────────────────────────────────────
// All callables below are founder-gated (assertFounder) and run with the
// admin SDK, which bypasses Firestore rules. This is the only place that
// writes to other shops' docs or to the top-level supplier catalog, so
// client rules stay locked to per-owner access.

const ADMIN_TIERS = ["solo", "lite", "full", "restaurant"];
const ADMIN_CYCLES = ["monthly", "yearly"];

// List every shop with the fields the console needs (subscription state +
// its hardware requests). Sorted newest-first.
exports.adminListShops = onCall(async (request) => {
  assertFounder(request);
  const db = admin.firestore();
  const snap = await db.collection("shops").orderBy("createdAt", "desc").get();

  const shops = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    // Pull this shop's hardware requests (usually 0-1).
    const hwSnap = await doc.ref
      .collection("hardware")
      .orderBy("createdAt", "desc")
      .get();
    const hardware = hwSnap.docs.map((h) => {
      const hd = h.data();
      return {
        id: h.id,
        kit: hd.kit || "none",
        status: hd.status || "requested",
        serialNumber: hd.serialNumber || null,
        note: hd.note || null,
      };
    });

    shops.push({
      id: doc.id,
      name: d.name || "",
      email: d.email || "",
      tier: d.tier || (d.shopType === "restaurant" ? "restaurant" : "full"),
      plan: d.plan || "monthly",
      locations: d.locations || 1,
      subscriptionStatus: d.subscriptionStatus || "trial",
      trialEndsAt: d.trialEndsAt?.toDate?.()?.toISOString() || null,
      subscriptionEndsAt:
        d.subscriptionEndsAt?.toDate?.()?.toISOString() || null,
      createdAt: d.createdAt?.toDate?.()?.toISOString() || null,
      referredBy: d.referredBy || null,
      hardware,
    });
  }
  return { shops };
});

// Manually change a shop's subscription. Ops:
//   extendTrial  — push trialEndsAt out by `days` (from current end or now)
//   activate     — mark paid for `days`, optionally set tier/cycle/locations
//   expire       — force-expire immediately
exports.adminSetSubscription = onCall(async (request) => {
  assertFounder(request);
  const { shopId, op } = request.data || {};
  if (!shopId || !op) {
    throw new HttpsError("invalid-argument", "shopId and op are required");
  }

  const db = admin.firestore();
  const ref = db.collection("shops").doc(shopId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Shop not found");
  }
  const data = snap.data();
  const now = new Date();
  const dayMs = 24 * 60 * 60 * 1000;

  if (op === "extendTrial") {
    const days = Math.max(1, parseInt(request.data.days || 0));
    if (!days) throw new HttpsError("invalid-argument", "days required");
    const cur = data.trialEndsAt?.toDate?.();
    const base = cur && cur > now ? cur : now;
    await ref.set(
      {
        subscriptionStatus: "trial",
        trialEndsAt: admin.firestore.Timestamp.fromDate(
          new Date(base.getTime() + days * dayMs)
        ),
      },
      { merge: true }
    );
    return { ok: true };
  }

  if (op === "activate") {
    const days = Math.max(1, parseInt(request.data.days || 0));
    if (!days) throw new HttpsError("invalid-argument", "days required");
    const tier = ADMIN_TIERS.includes(request.data.tier)
      ? request.data.tier
      : data.tier || "full";
    const cycle = ADMIN_CYCLES.includes(request.data.billingCycle)
      ? request.data.billingCycle
      : data.plan || "monthly";
    const locations = Math.max(1, parseInt(request.data.locations || data.locations || 1));
    const curEnd = data.subscriptionEndsAt?.toDate?.();
    const base = curEnd && curEnd > now ? curEnd : now;
    await ref.set(
      {
        subscriptionStatus: "active",
        subscriptionEndsAt: admin.firestore.Timestamp.fromDate(
          new Date(base.getTime() + days * dayMs)
        ),
        tier,
        plan: cycle,
        locations,
      },
      { merge: true }
    );
    return { ok: true };
  }

  if (op === "expire") {
    await ref.set(
      {
        subscriptionStatus: "expired",
        subscriptionEndsAt: admin.firestore.Timestamp.fromDate(now),
      },
      { merge: true }
    );
    return { ok: true };
  }

  throw new HttpsError("invalid-argument", `Unknown op: ${op}`);
});

// Advance (or annotate) a shop's hardware shipment. The owner sees the
// status mirror in Settings; only the founder moves it forward.
exports.adminSetHardwareStatus = onCall(async (request) => {
  assertFounder(request);
  const { shopId, requestId, status } = request.data || {};
  if (!shopId || !requestId) {
    throw new HttpsError("invalid-argument", "shopId and requestId required");
  }
  const VALID = ["requested", "preparing", "shipped", "delivered", "returned"];
  if (status && !VALID.includes(status)) {
    throw new HttpsError("invalid-argument", `Invalid status: ${status}`);
  }

  const ref = admin
    .firestore()
    .collection("shops")
    .doc(shopId)
    .collection("hardware")
    .doc(requestId);
  if (!(await ref.get()).exists) {
    throw new HttpsError("not-found", "Hardware request not found");
  }

  const update = {};
  if (status) {
    update.status = status;
    if (status === "delivered") {
      update.deliveredAt = admin.firestore.FieldValue.serverTimestamp();
    }
  }
  if (typeof request.data.note === "string") update.note = request.data.note;
  if (typeof request.data.serialNumber === "string") {
    update.serialNumber = request.data.serialNumber;
  }
  if (Object.keys(update).length === 0) {
    throw new HttpsError("invalid-argument", "Nothing to update");
  }
  await ref.set(update, { merge: true });
  return { ok: true };
});

// Create or update a top-level supplier. Pass supplierId to update an
// existing one; omit it to create with an auto id.
exports.adminUpsertSupplier = onCall(async (request) => {
  assertFounder(request);
  const d = request.data || {};
  if (!d.name) {
    throw new HttpsError("invalid-argument", "name is required");
  }
  const db = admin.firestore();
  const ref = d.supplierId
    ? db.collection("suppliers").doc(String(d.supplierId))
    : db.collection("suppliers").doc();

  const fields = {
    name: String(d.name),
    category: String(d.category || ""),
    area: d.area != null ? String(d.area) : "",
    deliveryDays: d.deliveryDays != null ? String(d.deliveryDays) : "",
    minOrder: Number(d.minOrder || 0),
    active: d.active !== false,
  };
  // Only stamp createdAt on first create.
  if (!(await ref.get()).exists) {
    fields.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }
  await ref.set(fields, { merge: true });
  return { ok: true, supplierId: ref.id };
});

// Create or update one catalog line under a supplier.
exports.adminUpsertSupplierProduct = onCall(async (request) => {
  assertFounder(request);
  const d = request.data || {};
  if (!d.supplierId || !d.name) {
    throw new HttpsError("invalid-argument", "supplierId and name required");
  }
  const db = admin.firestore();
  const col = db
    .collection("suppliers")
    .doc(String(d.supplierId))
    .collection("products");
  const ref = d.productId ? col.doc(String(d.productId)) : col.doc();

  await ref.set(
    {
      name: String(d.name),
      unit: String(d.unit || "ชิ้น"),
      price: Number(d.price || 0),
      moq: Math.max(1, parseInt(d.moq || 1)),
      available: d.available !== false,
    },
    { merge: true }
  );
  return { ok: true, productId: ref.id };
});

// Create a login-enabled supplier: a Firebase Auth account + a supplier
// doc whose id IS that account's uid (so security rules can match
// request.auth.uid == supplierId). The supplier then signs into the web
// portal to manage their own catalog + orders. Founder-only.
exports.adminCreateSupplierAccount = onCall(async (request) => {
  assertFounder(request);
  const d = request.data || {};
  const email = String(d.email || "").trim().toLowerCase();
  const password = String(d.password || "");
  if (!email || password.length < 6) {
    throw new HttpsError(
      "invalid-argument",
      "email and a password (>=6 chars) are required"
    );
  }
  if (!d.name) {
    throw new HttpsError("invalid-argument", "name is required");
  }

  // Create (or reuse) the auth account.
  let uid;
  try {
    const user = await admin.auth().createUser({
      email,
      password,
      displayName: String(d.name),
    });
    uid = user.uid;
  } catch (e) {
    if (e.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "อีเมลนี้มีบัญชีอยู่แล้ว");
    }
    throw new HttpsError("internal", e.message || "createUser failed");
  }

  await admin
    .firestore()
    .collection("suppliers")
    .doc(uid)
    .set({
      name: String(d.name),
      email,
      category: String(d.category || ""),
      area: d.area != null ? String(d.area) : "",
      deliveryDays: d.deliveryDays != null ? String(d.deliveryDays) : "",
      minOrder: Number(d.minOrder || 0),
      lineUserId: d.lineUserId != null ? String(d.lineUserId) : "",
      active: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  return { ok: true, supplierId: uid };
});

// Supplier updates one of their incoming orders (accept / ship / cancel)
// from the web portal. Mirrors the new status to the shop's copy so both
// sides stay in sync. Caller must own the order (auth.uid == supplierId).
exports.supplierSetOrderStatus = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login required");
  }
  const uid = request.auth.uid;
  const orderId = String(request.data?.orderId || "");
  const status = String(request.data?.status || "");
  const ALLOWED = ["accepted", "shipped", "cancelled"];
  if (!orderId || !ALLOWED.includes(status)) {
    throw new HttpsError(
      "invalid-argument",
      "orderId + valid status required"
    );
  }

  const db = admin.firestore();
  const supRef = db
    .collection("suppliers")
    .doc(uid)
    .collection("orders")
    .doc(orderId);
  const supSnap = await supRef.get();
  if (!supSnap.exists) {
    throw new HttpsError("not-found", "Order not found");
  }
  const order = supSnap.data();
  if (order.status === "delivered" || order.status === "cancelled") {
    throw new HttpsError("failed-precondition", "ออเดอร์ปิดแล้ว");
  }

  const patch = { status };
  const batch = db.batch();
  batch.set(supRef, patch, { merge: true });
  if (order.shopId) {
    batch.set(
      db
        .collection("shops")
        .doc(order.shopId)
        .collection("marketplaceOrders")
        .doc(orderId),
      patch,
      { merge: true }
    );
  }
  await batch.commit();
  return { ok: true };
});

// ────────────────────────────────────────────────
// Notify a supplier on LINE when a shop places a new order. Fires on the
// supplier-side copy created by the app's dual-write. Opt-in: the supplier
// pastes their LINE User ID into the web portal (lineUserId) and can mute
// with lineNotifyEnabled. Best-effort — a LINE failure never blocks the
// order, which is already committed by the time this runs.
// ────────────────────────────────────────────────
exports.notifySupplierNewOrder = onDocumentCreated(
  {
    document: "suppliers/{supplierId}/orders/{orderId}",
    secrets: [lineChannelAccessToken],
  },
  async (event) => {
    const order = event.data?.data();
    if (!order) return;
    // Only the initial "placed" write — ignore any re-creates.
    if (order.status && order.status !== "placed") return;

    const supplierId = event.params.supplierId;
    const supSnap = await admin
      .firestore()
      .collection("suppliers")
      .doc(supplierId)
      .get();
    const sup = supSnap.data() || {};
    const lineUserId = sup.lineUserId;
    if (!lineUserId || sup.lineNotifyEnabled === false) return;

    const items = Array.isArray(order.items) ? order.items : [];
    const itemCount = items.reduce((s, i) => s + (i.quantity || 0), 0);
    const subtotal = items.reduce(
      (s, i) => s + (i.price || 0) * (i.quantity || 0),
      0
    );
    const lines = items
      .slice(0, 10)
      .map((i) => `• ${i.name} × ${i.quantity} ${i.unit || ""}`.trim())
      .join("\n");
    const more =
      items.length > 10 ? `\n…และอีก ${items.length - 10} รายการ` : "";

    await _linePush(lineChannelAccessToken.value(), lineUserId, [
      {
        type: "text",
        text:
          `🛒 ออเดอร์ใหม่จาก ${order.shopName || "ร้านค้า"}\n\n` +
          `${lines}${more}\n\n` +
          `รวม ${itemCount} รายการ · ฿${Math.round(subtotal).toLocaleString("th-TH")}\n\n` +
          `เปิดพอร์ทัลเพื่อรับออเดอร์:\nhttps://pok-pok.app/supplier`,
      },
    ]);
  }
);

// ── Subscription renewal reminders (reduce churn) ──────────────────────────
// Runs once a day and nudges shops whose free trial or paid plan is about to
// lapse (or just lapsed) on a fixed set of day-out buckets. Each shop is
// notified at most once per (end date, bucket) thanks to a stored dedup key,
// so scheduler retries or a re-run never double-notify.
const RENEWAL_BUCKETS = [7, 3, 1, 0]; // days before end (0 = expiry day)

exports.sendRenewalReminders = onSchedule(
  {
    schedule: "every day 09:00",
    timeZone: "Asia/Bangkok",
    secrets: [lineChannelAccessToken],
  },
  async () => {
    const db = admin.firestore();
    const now = new Date();
    const startOfToday = new Date(
      now.getFullYear(), now.getMonth(), now.getDate()
    );

    // Only trial/active shops can be "ending soon"; expired ones already lapsed.
    const snaps = await Promise.all([
      db.collection("shops").where("subscriptionStatus", "==", "trial").get(),
      db.collection("shops").where("subscriptionStatus", "==", "active").get(),
    ]);

    let sent = 0;
    for (const snap of snaps) {
      for (const doc of snap.docs) {
        const shop = doc.data();
        const isTrial = shop.subscriptionStatus === "trial";
        const endsAt = isTrial
          ? shop.trialEndsAt?.toDate?.()
          : shop.subscriptionEndsAt?.toDate?.();
        if (!endsAt) continue;

        // Whole-day countdown from local midnight, so "1 day left" is stable
        // no matter what time of day the job happens to run.
        const endDay = new Date(
          endsAt.getFullYear(), endsAt.getMonth(), endsAt.getDate()
        );
        const daysLeft = Math.round((endDay - startOfToday) / 86400000);
        if (!RENEWAL_BUCKETS.includes(daysLeft)) continue;

        // The key changes when the owner renews (endsAt moves) or a new bucket
        // is reached, so a given reminder fires exactly once.
        const key = `${endsAt.getTime()}:${daysLeft}`;
        if (shop.lastRenewalReminderKey === key) continue;

        const { title, body } = renewalMessage(isTrial, daysLeft);

        // FCM — reuse the existing `new_orders` channel so the push displays on
        // every installed app version (a brand-new channel would be missing on
        // older installs and silently dropped on Android 8+).
        if (shop.fcmToken) {
          try {
            await admin.messaging().send({
              token: shop.fcmToken,
              notification: { title, body },
              android: {
                notification: { channelId: "new_orders", priority: "high" },
              },
            });
          } catch (e) {
            console.error(`renewal FCM failed for ${doc.id}:`, e.message);
          }
        }

        // LINE — same opt-in switch as order notifications.
        try {
          const setDoc = await db
            .collection("shops").doc(doc.id)
            .collection("settings").doc("shop").get();
          const lineUserId = setDoc.data()?.lineUserId;
          const lineEnabled = setDoc.data()?.lineNotifyEnabled !== false;
          if (lineUserId && lineEnabled) {
            await _linePush(lineChannelAccessToken.value(), lineUserId, [{
              type: "text",
              text: `${title}\n${body}\n\nต่ออายุที่นี่:\nhttps://pok-pok.app/subscribe`,
            }]);
          }
        } catch (e) {
          console.error(`renewal LINE failed for ${doc.id}:`, e.message);
        }

        await doc.ref.update({ lastRenewalReminderKey: key });
        sent++;
      }
    }
    console.log(`Renewal reminders sent: ${sent}`);
  }
);

// Builds the title/body for a renewal nudge. Tone stays gentle — these go to
// paying customers and people still on the free trial.
function renewalMessage(isTrial, daysLeft) {
  if (daysLeft === 0) {
    return isTrial
      ? {
          title: "ช่วงทดลองใช้หมดวันนี้",
          body: "สมัครแพ็กเกจวันนี้เพื่อใช้ Pokpok ต่อได้ไม่สะดุด",
        }
      : {
          title: "แพ็กเกจหมดอายุวันนี้",
          body: "ต่ออายุวันนี้เพื่อใช้งานต่อเนื่อง",
        };
  }
  const when = daysLeft === 1 ? "พรุ่งนี้" : `อีก ${daysLeft} วัน`;
  return isTrial
    ? {
        title: `ทดลองใช้ฟรีเหลือ ${daysLeft} วัน`,
        body: `ช่วงทดลองจะหมด${when} — สมัครต่อเพื่อใช้งานต่อเนื่อง`,
      }
    : {
        title: `แพ็กเกจจะหมดอายุ${when}`,
        body: `ต่ออายุก่อนหมด${when} เพื่อใช้งานไม่สะดุด`,
      };
}
