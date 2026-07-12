// Pure helpers for recipe/ingredient inventory — CommonJS so index.js and
// scripts/test_functions_inventory.mjs share them.

// Weighted-average cost on receiving goods. Negative/zero starting stock
// (recount signal — sales never block on ingredients) is treated as zero
// for costing so one bad count can't poison the average forever.
function applyPurchase(stock, avgCost, qty, totalPrice) {
  const base = Math.max(0, Number(stock) || 0);
  const value = base * (Number(avgCost) || 0) + Number(totalPrice);
  const newStock = (Number(stock) || 0) + Number(qty);
  const denom = base + Number(qty);
  return {
    stock: newStock,
    avgCost: denom > 0 ? value / denom : 0,
  };
}

// Total ingredient usage for one sale. items = sale items
// [{productId, quantity, modifiers?: [{groupId, optionId}]}].
// - stockMode "recipe" products consume their recipe × quantity
// - every modifier consumes its option's ingredientUsage × quantity
//   (works on count-mode products too — e.g. a topping on a counted item)
// Unknown products/groups/options are tolerated: deduct what we can.
function computeUsage(items, productsById, groupsById) {
  const usage = {};
  const add = (ingredientId, qty) => {
    if (!ingredientId || !(qty > 0)) return;
    usage[ingredientId] = (usage[ingredientId] || 0) + qty;
  };

  for (const item of items || []) {
    const qty = Number(item.quantity) || 0;
    if (qty <= 0) continue;
    const product = productsById[item.productId];

    if (product?.stockMode === "recipe") {
      for (const line of product.recipe || []) {
        add(line.ingredientId, (Number(line.qty) || 0) * qty);
      }
    }

    for (const m of item.modifiers || []) {
      const group = groupsById[m.groupId];
      const option = (group?.options || []).find((o) => o.id === m.optionId);
      for (const u of option?.ingredientUsage || []) {
        add(u.ingredientId, (Number(u.qty) || 0) * qty);
      }
    }
  }
  return usage;
}

module.exports = { applyPurchase, computeUsage };
