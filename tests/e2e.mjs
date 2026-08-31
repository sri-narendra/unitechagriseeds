// ============================================================================
// AgriStock end-to-end check — exercises the Supabase backend directly
// (the same calls the HTML pages make). Creates clearly-labelled "e2e-" data
// and cleans up after itself. Safe to re-run.
//
// Usage (Node 18+):
//   SUPABASE_URL=https://xxx.supabase.co \
//   SUPABASE_ANON_KEY=eyJ... \
//   ADMIN_EMAIL=… ADMIN_PASSWORD=… \
//   DEALER_EMAIL=dealer-001@agri.local DEALER_PASSWORD=… \
//   node tests/e2e.mjs
// ============================================================================

const BASE = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
if (!BASE || !ANON) {
  console.error("Set SUPABASE_URL and SUPABASE_ANON_KEY env vars.");
  process.exit(1);
}
let failures = 0;
function assert(cond, msg) {
  console.log((cond ? "PASS: " : "FAIL: ") + msg);
  if (!cond) failures++;
}

async function login(email, password) {
  const r = await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const j = await r.json();
  if (!r.ok || !j.access_token) throw new Error("login failed for " + email);
  return j.access_token;
}

async function rest(token, method, path, body) {
  const r = await fetch(BASE + path, {
    method,
    headers: { apikey: ANON, Authorization: "Bearer " + token, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const t = await r.text();
  return { status: r.status, ok: r.ok, body: t ? JSON.parse(t) : null };
}

async function rpc(token, fn, args) {
  return rest(token, "POST", `/rest/v1/rpc/${fn}`, args);
}

const admin = await login(process.env.ADMIN_EMAIL, process.env.ADMIN_PASSWORD);
const dealer = await login(process.env.DEALER_EMAIL, process.env.DEALER_PASSWORD);

const me = await fetch(`${BASE}/auth/v1/user`, {
  headers: { apikey: ANON, Authorization: "Bearer " + dealer },
}).then(r => r.json());
const dealerId = me.app_metadata && me.app_metadata.dealer_id;
assert(!!dealerId, "dealer token carries the dealer_id claim");
assert(me.app_metadata && me.app_metadata.role === "dealer", "dealer token has role=dealer");

// --- fixture: two e2e products (needed for multi-item sale test) ---
const pid = crypto.randomUUID();
const pid2 = crypto.randomUUID();
const ins = await rest(admin, "POST", "/rest/v1/products", { id: pid, name: "e2e product" });
const ins2 = await rest(admin, "POST", "/rest/v1/products", { id: pid2, name: "e2e product 2" });
assert(ins.ok && ins2.ok, "admin creates e2e products");

// --- allocate 50 each via multi-item RPC ---
const alloc = await rpc(admin, "allocate_stock", {
  p_dealer: dealerId, p_items: [{ product_id: pid, quantity: 50 }, { product_id: pid2, quantity: 50 }],
});
assert(alloc.ok, "allocate_stock accepts items[]");

// --- multi-item sale (5 of pid + 10 of pid2) in ONE atomic call ---
const ref = crypto.randomUUID();
const sale = await rpc(dealer, "record_sale", {
  p_items: [{ product_id: pid, quantity: 5 }, { product_id: pid2, quantity: 10 }],
  p_client_ref: ref,
});
assert(sale.ok && sale.body && sale.body.replayed === false, "record_sale accepts items[]");
assert(sale.body && Array.isArray(sale.body.items) && sale.body.items.length === 2
  && sale.body.items[0].quantity_before === 50 && sale.body.items[0].quantity_after === 45,
  "record_sale reports quantity_before/after");
const afterSale = (sale.body.items[1] || {}).quantity_after;
assert(afterSale === 40, "sale totals: pid2 50 - 10 = 40");

// --- replay with the same client_ref does NOT sell again ---
const replay = await rpc(dealer, "record_sale", {
  p_items: [{ product_id: pid, quantity: 100 }], p_client_ref: ref,
});
assert(replay.ok && replay.body && replay.body.replayed === true, "client_ref replay is a no-op");

// --- insufficient stock is rejected ---
const tooMuch = await rpc(dealer, "record_sale", {
  p_items: [{ product_id: pid, quantity: 9999 }], p_client_ref: crypto.randomUUID(),
});
assert(!tooMuch.ok && String(tooMuch.body?.message || "").includes("INSUFFICIENT_STOCK"),
  "over-selling is rejected with INSUFFICIENT_STOCK");

// --- dealer can read own stock via RLS (scoped to their rows) ---
const own = await rest(dealer, "GET", `/rest/v1/dealer_stock?dealer_id=eq.${dealerId}&product_id=eq.${pid}&select=quantity`);
assert(own.ok, "dealer can read own stock via RLS");

// --- order: create via RPC + admin approve (+qty) ---
const orderClientRef = crypto.randomUUID();
const orderResult = await rpc(dealer, "create_order", {
  p_items: [{ product_id: pid, quantity: 20 }],
  p_client_ref: orderClientRef,
});
assert(orderResult.ok, "dealer creates an order via create_order RPC");
const orderId = orderResult.body;
assert(!!orderId, "create_order returns order UUID");

const approved = await rpc(admin, "approve_order", { p_order: orderId });
assert(approved.ok, "admin approves the order");
const double = await rpc(admin, "approve_order", { p_order: orderId });
assert(!double.ok, "approving twice is refused (status guard)");

// --- return: create via RPC + admin accept (-qty) ---
const returnClientRef = crypto.randomUUID();
const returnResult = await rpc(dealer, "create_return", {
  p_items: [{ product_id: pid, quantity: 5 }],
  p_client_ref: returnClientRef,
});
assert(returnResult.ok, "dealer creates a return via create_return RPC");
const returnId = returnResult.body;
assert(!!returnId, "create_return returns return UUID");

const accepted = await rpc(admin, "accept_return", { p_return: returnId });
assert(accepted.ok, "admin accepts the return");

// --- expected final stock for pid: 45 + 20 - 5 = 60 ---
const stock = await rest(dealer, "GET",
  `/rest/v1/dealer_stock?dealer_id=eq.${dealerId}&product_id=eq.${pid}&select=quantity`);
const qty = Array.isArray(stock.body) && stock.body[0] ? stock.body[0].quantity : null;
assert(qty === 60, `final quantity is 60 (got ${qty})`);

// === NEGATIVE SECURITY TESTS ===
// Dealer should NOT be able to directly modify transactional tables.
// PostgREST returns 200 with empty [] when RLS blocks INSERT/UPDATE,
// so we verify the data didn't change rather than checking HTTP status.

// 1. dealer_stock UPDATE: check quantity unchanged
const dealerStockUpdate = await rest(dealer, "PATCH",
  `/rest/v1/dealer_stock?dealer_id=eq.${dealerId}&product_id=eq.${pid}`,
  { quantity: 99999 });
const postStockCheck = await rest(dealer, "GET",
  `/rest/v1/dealer_stock?dealer_id=eq.${dealerId}&product_id=eq.${pid}&select=quantity`);
const postStockQty = Array.isArray(postStockCheck.body) && postStockCheck.body[0] ? postStockCheck.body[0].quantity : null;
assert(postStockQty === 60, `SECURITY: dealer cannot directly update dealer_stock (still ${postStockQty})`);

// 2. sale_transactions INSERT: count before/after
const preSaleCount = (await rest(admin, "GET",
  `/rest/v1/sale_transactions?dealer_id=eq.${dealerId}&select=id`)).body?.length ?? -1;
await rest(dealer, "POST", "/rest/v1/sale_transactions", { dealer_id: dealerId });
const postSaleCount = (await rest(admin, "GET",
  `/rest/v1/sale_transactions?dealer_id=eq.${dealerId}&select=id`)).body?.length ?? -1;
assert(postSaleCount === preSaleCount, `SECURITY: dealer cannot directly insert sale_transactions (${preSaleCount} -> ${postSaleCount})`);

// 3. orders UPDATE: use Prefer:return=representation to see if RLS blocked it
const dealerOrderRes = await fetch(`${BASE}/rest/v1/orders?id=eq.${orderId}`, {
  method: "PATCH",
  headers: { apikey: ANON, Authorization: "Bearer " + dealer, "Content-Type": "application/json", Prefer: "return=representation" },
  body: JSON.stringify({ status: "sent" }),
});
const orderRows = await dealerOrderRes.json();
assert(Array.isArray(orderRows) && orderRows.length === 0,
  `SECURITY: dealer cannot directly update order status (got ${orderRows.length} rows)`);

// 4. returns UPDATE: use Prefer:return=representation to see if RLS blocked it
const dealerReturnRes = await fetch(`${BASE}/rest/v1/returns?id=eq.${returnId}`, {
  method: "PATCH",
  headers: { apikey: ANON, Authorization: "Bearer " + dealer, "Content-Type": "application/json", Prefer: "return=representation" },
  body: JSON.stringify({ status: "accepted" }),
});
const returnRows = await dealerReturnRes.json();
assert(Array.isArray(returnRows) && returnRows.length === 0,
  `SECURITY: dealer cannot directly update return status (got ${returnRows.length} rows)`);

// 5. stock_movements INSERT: count before/after
const preMovCount = (await rest(admin, "GET",
  `/rest/v1/stock_movements?product_id=eq.${pid}&select=id`)).body?.length ?? -1;
await rest(dealer, "POST", "/rest/v1/stock_movements",
  { dealer_id: dealerId, product_id: pid, quantity: 1000, movement_type: "ALLOCATION" });
const postMovCount = (await rest(admin, "GET",
  `/rest/v1/stock_movements?product_id=eq.${pid}&select=id`)).body?.length ?? -1;
assert(postMovCount === preMovCount, `SECURITY: dealer cannot directly insert stock_movements (${preMovCount} -> ${postMovCount})`);

// --- cleanup (order matters: children first) ---
try {
  for (const step of [
    ["DELETE", `/rest/v1/sale_items?transaction_id=in.(select id from sale_transactions where dealer_id='${dealerId}')`],
    ["DELETE", `/rest/v1/sale_transactions?dealer_id=eq.${dealerId}`],
    ["DELETE", `/rest/v1/stock_movements?product_id=eq.${pid}`],
    ["DELETE", `/rest/v1/stock_movements?product_id=eq.${pid2}`],
    ["DELETE", `/rest/v1/order_items?order_id=eq.${orderId}`],
    ["DELETE", `/rest/v1/orders?id=eq.${orderId}`],
    ["DELETE", `/rest/v1/return_items?return_id=eq.${returnId}`],
    ["DELETE", `/rest/v1/returns?id=eq.${returnId}`],
    ["DELETE", `/rest/v1/dealer_stock?product_id=eq.${pid}`],
    ["DELETE", `/rest/v1/dealer_stock?product_id=eq.${pid2}`],
    ["DELETE", `/rest/v1/products?id=eq.${pid}`],
    ["DELETE", `/rest/v1/products?id=eq.${pid2}`],
  ]) {
    await rest(admin, step[0], step[1]);
  }
} catch (e) {
  console.log("WARN: cleanup error (non-fatal): " + e.message);
}

console.log(failures === 0 ? "\nALL CHECKS PASSED" : `\n${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
