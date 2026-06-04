// One-off marketplace seed — creates sample suppliers + catalogs so the
// "สั่งของ" feature has data to show in Internal Testing.
//
// Writes via the Firestore REST API using a gcloud OAuth access token,
// which authenticates as the project owner and BYPASSES security rules
// (rules only apply to Firebase-Auth client tokens, not Google OAuth).
// No service-account key needed.
//
// Run from PowerShell:
//   $env:GCLOUD_TOKEN = (gcloud auth print-access-token)
//   node scripts/seed_suppliers.mjs
//
// Idempotent: uses PATCH on fixed document ids, so re-running updates
// rather than duplicating.

const PROJECT = 'shop-pos-89294';
const TOKEN = process.env.GCLOUD_TOKEN;
if (!TOKEN) {
  console.error('Missing GCLOUD_TOKEN env var');
  process.exit(1);
}

const BASE =
  `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const NOW = new Date().toISOString();

// ── Firestore REST typed-value helpers ──
const S = (v) => ({ stringValue: v });
const D = (v) => ({ doubleValue: v });
const I = (v) => ({ integerValue: String(v) });
const B = (v) => ({ booleanValue: v });
const T = (v) => ({ timestampValue: v });

async function patch(path, fields) {
  const res = await fetch(`${BASE}/${path}`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`PATCH ${path} → ${res.status}: ${body}`);
  }
}

// ── Sample suppliers (per GTM plan categories) ──
const suppliers = [
  {
    id: 'demo-veg',
    name: 'สวนผักลุงมา',
    category: 'ผัก · ผลไม้สด',
    area: '',
    deliveryDays: 'จ-ส',
    minOrder: 300,
    products: [
      { id: 'p1', name: 'ผักบุ้ง', unit: 'กก.', price: 25, moq: 2 },
      { id: 'p2', name: 'คะน้า', unit: 'กก.', price: 35, moq: 2 },
      { id: 'p3', name: 'พริกขี้หนู', unit: 'กก.', price: 80, moq: 1 },
      { id: 'p4', name: 'มะนาว', unit: 'กก.', price: 60, moq: 1 },
      { id: 'p5', name: 'หอมแดง', unit: 'กก.', price: 45, moq: 1 },
    ],
  },
  {
    id: 'demo-meat',
    name: 'เนื้อสดเจ๊ปุ๊',
    category: 'หมู · ไก่ · เนื้อ',
    area: '',
    deliveryDays: 'จ-ศ',
    minOrder: 500,
    products: [
      { id: 'p1', name: 'หมูสับ', unit: 'กก.', price: 130, moq: 1 },
      { id: 'p2', name: 'หมูสามชั้น', unit: 'กก.', price: 150, moq: 1 },
      { id: 'p3', name: 'อกไก่', unit: 'กก.', price: 75, moq: 2 },
      { id: 'p4', name: 'ไข่ไก่ เบอร์ 2', unit: 'แผง', price: 110, moq: 1 },
    ],
  },
  {
    id: 'demo-dry',
    name: 'ของแห้งส่ง พรชัย',
    category: 'ของแห้ง · เครื่องปรุง',
    area: '',
    deliveryDays: 'อ-พฤ-ส',
    minOrder: 0,
    products: [
      { id: 'p1', name: 'ข้าวหอมมะลิ', unit: 'กระสอบ 5กก.', price: 220, moq: 1 },
      { id: 'p2', name: 'น้ำมันพืช', unit: 'ลัง 12 ขวด', price: 580, moq: 1 },
      { id: 'p3', name: 'น้ำปลา', unit: 'ลัง', price: 360, moq: 1 },
      { id: 'p4', name: 'น้ำตาลทราย', unit: 'กระสอบ', price: 480, moq: 1 },
      { id: 'p5', name: 'ซีอิ๊วขาว', unit: 'ลัง', price: 320, moq: 1 },
    ],
  },
];

async function main() {
  for (const sup of suppliers) {
    await patch(`suppliers/${sup.id}`, {
      name: S(sup.name),
      category: S(sup.category),
      area: S(sup.area),
      deliveryDays: S(sup.deliveryDays),
      minOrder: D(sup.minOrder),
      active: B(true),
      createdAt: T(NOW),
    });
    console.log(`✓ supplier ${sup.name}`);

    for (const p of sup.products) {
      await patch(`suppliers/${sup.id}/products/${p.id}`, {
        name: S(p.name),
        unit: S(p.unit),
        price: D(p.price),
        moq: I(p.moq),
        available: B(true),
      });
    }
    console.log(`  ↳ ${sup.products.length} products`);
  }
  console.log('\nDone — marketplace seeded.');
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
