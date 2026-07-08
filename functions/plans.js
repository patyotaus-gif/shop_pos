// Plan-catalog helpers — pure CommonJS so index.js and the Node test
// script (scripts/test_functions_plans.mjs) can both load them.
//
// Prices are in สตางค์ (satang) to match the Stripe API. `days` is fixed
// per cycle (30/365) and NOT editable — entitlement math depends on it.
// The editable catalog lives in Firestore `config/plans`; these defaults
// are the zero-migration fallback when that doc doesn't exist yet.

const TIER_KEYS = ["solo", "lite", "full", "restaurant"];
const CYCLE_DAYS = { monthly: 30, yearly: 365 };

const DEFAULT_TIERS = {
  solo: {
    name: "Solo",
    desc: "ใช้มือถือ/แท็บเล็ตของตัวเอง POS + รายงาน + PromptPay",
    enabled: true,
    monthly: { amount: 19900, days: 30 },
    yearly: { amount: 199000, days: 365 },
  },
  lite: {
    name: "Lite",
    desc: "มีแท็บเล็ตแล้ว + ชุดพิมพ์ใบเสร็จ + จัดการสต็อก + ฐานลูกค้า",
    enabled: true,
    monthly: { amount: 39900, days: 30 },
    yearly: { amount: 399000, days: 365 },
  },
  full: {
    name: "Full",
    desc: "ครบชุดฮาร์ดแวร์ + 3 ผู้ใช้ + สะสมแต้ม + ซ่อมถึงที่",
    enabled: true,
    featured: true,
    monthly: { amount: 59900, days: 30 },
    yearly: { amount: 599000, days: 365 },
  },
  restaurant: {
    name: "Restaurant",
    desc: "ร้านอาหารหลายสาขา + ครัว + ผังโต๊ะ + แยกบิล",
    enabled: true,
    perLocation: true,
    monthly: { amount: 119900, days: 30 },
    yearly: { amount: 1199000, days: 365 },
  },
};

// Backward compatibility mirrors the legacy resolvePlanConfig: unknown
// tier → full (the historical ฿299 plan's closest equivalent), unknown
// cycle → monthly. Returns { amount, days, label } or null.
function resolvePlanConfig(tiers, tier, billingCycle) {
  const t = tiers[tier] || tiers.full;
  if (!t) return null;
  const cycle = billingCycle === "yearly" ? "yearly" : "monthly";
  const cfg = t[cycle] || t.monthly;
  if (!cfg) return null;
  return {
    amount: cfg.amount,
    days: cfg.days,
    label: `Pokpok ${t.name} ${cycle === "yearly" ? "รายปี" : "รายเดือน"}`,
  };
}

// Monthly-normalised recurring revenue in baht for one shop's plan.
// Yearly plans are divided by 12; restaurant is per-location. Used by the
// ops dashboard to sum MRR across paying shops.
function monthlyRevenueBaht(tiers, tier, billingCycle, locations) {
  const cfg = resolvePlanConfig(tiers, tier, billingCycle);
  if (!cfg) return 0;
  const locs = Math.max(1, parseInt(locations || 1));
  const perLoc = tiers[tier]?.perLocation === true;
  const amountSatang = perLoc ? cfg.amount * locs : cfg.amount;
  const baht = amountSatang / 100;
  return billingCycle === "yearly" ? baht / 12 : baht;
}

// Whitelist-sanitize an admin-submitted catalog. Throws Error (message in
// Thai, safe to surface) on any invalid input. Client cannot change tier
// keys, days, or perLocation — those are rebuilt from constants/defaults.
function validateTiers(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("รูปแบบข้อมูลแผนไม่ถูกต้อง");
  }
  for (const key of Object.keys(input)) {
    if (!TIER_KEYS.includes(key)) {
      throw new Error(`ไม่รู้จักแผน "${key}"`);
    }
  }
  const out = {};
  for (const key of TIER_KEYS) {
    const t = input[key];
    if (!t || typeof t !== "object") {
      throw new Error(`ข้อมูลแผน ${key} หายไป`);
    }
    const name = typeof t.name === "string" ? t.name.trim() : "";
    if (!name) throw new Error(`ชื่อแผน ${key} ห้ามว่าง`);
    const desc = typeof t.desc === "string" ? t.desc.trim() : "";

    const cycles = {};
    for (const cycle of ["monthly", "yearly"]) {
      const amount = t[cycle]?.amount;
      if (!Number.isInteger(amount) || amount <= 0) {
        throw new Error(`ราคาแผน ${key} (${cycle}) ต้องเป็นจำนวนเต็มสตางค์มากกว่า 0`);
      }
      cycles[cycle] = { amount, days: CYCLE_DAYS[cycle] };
    }

    out[key] = {
      name,
      desc,
      enabled: t.enabled !== false,
      ...(t.featured === true ? { featured: true } : {}),
      ...(DEFAULT_TIERS[key].perLocation === true ? { perLocation: true } : {}),
      monthly: cycles.monthly,
      yearly: cycles.yearly,
    };
  }
  return out;
}

module.exports = { TIER_KEYS, DEFAULT_TIERS, resolvePlanConfig, monthlyRevenueBaht, validateTiers };
