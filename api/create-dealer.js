// POST /api/create-dealer  (admin only)
// Creates the dealer login (Supabase Auth user + role/dealer_id claims), the
// dealers row and optional initial stock in one call — replaces the manual
// Dashboard steps (docs/backendStack.md §5.8, §7).
// Rollback: if any step fails after Auth user creation, the Auth user is deleted.
const { SERVICE_KEY, LOGIN_DOMAIN, sbFetch, fail, ok, getAdminUser, normalizeAccountId, handleCors } = require("./_supabase");

module.exports = async (req, res) => {
  if (handleCors(req, res)) return;
  if (req.method !== "POST") return fail(res, 405, "METHOD_NOT_ALLOWED", "POST only");
  const admin = await getAdminUser(req);
  if (!admin) return fail(res, 403, "FORBIDDEN", "Admin role required");

  const b = typeof req.body === "string" ? safeParse(req.body) : (req.body || {});
  const accountId = normalizeAccountId(b.account_id);
  if (!accountId || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(accountId)) {
    return fail(res, 422, "INVALID_ACCOUNT_ID", "Account ID must contain letters or digits");
  }
  const password = String(b.password || "");
  if (password.length < 10) return fail(res, 422, "VALIDATION_ERROR", "Password must be at least 10 characters");
  if (!/[a-z]/.test(password) || !/[A-Z]/.test(password) || !/[0-9]/.test(password)) {
    return fail(res, 422, "VALIDATION_ERROR", "Password must contain uppercase, lowercase, and a number");
  }
  const email = accountId + LOGIN_DOMAIN;

  // M-4: Input length limits
  const MAX_LEN = { shop_name: 200, dealer_name: 200, village: 200, mandal: 200, district: 200, account_details: 1000 };
  for (const [field, max] of Object.entries(MAX_LEN)) {
    if (b[field] && String(b[field]).length > max) {
      return fail(res, 422, "VALIDATION_ERROR", field + " must be " + max + " characters or fewer");
    }
  }

  // 1. Create Auth user
  const created = await sbFetch("/auth/v1/admin/users", {
    method: "POST", key: SERVICE_KEY, token: SERVICE_KEY,
    body: { email, password, email_confirm: true, app_metadata: { role: "dealer" } },
  });
  if (!created.ok) {
    const msg = errMsg(created);
    if (/already/i.test(msg)) return fail(res, 409, "ACCOUNT_EXISTS", "That Account ID already has a login.");
    return fail(res, 500, "AUTH_CREATE_FAILED", "Could not create the login user.");
  }
  const userId = created.json.id;

  // 2. Set dealer claims (including dealer_id = Auth user id)
  const claimed = await sbFetch("/auth/v1/admin/users/" + userId, {
    method: "PUT", key: SERVICE_KEY, token: SERVICE_KEY,
    body: { app_metadata: { role: "dealer", dealer_id: userId } },
  });
  if (!claimed.ok) {
    await sbFetch("/auth/v1/admin/users/" + userId, { method: "DELETE", key: SERVICE_KEY, token: SERVICE_KEY });
    return fail(res, 500, "AUTH_CREATE_FAILED", "Could not set the dealer claims.");
  }

  // 3. Create dealer row (with auth_user_id set)
  const row = await sbFetch("/rest/v1/dealers?on_conflict=id", {
    method: "POST", key: SERVICE_KEY, token: SERVICE_KEY,
    prefer: "resolution=merge-duplicates,return=representation",
    body: {
      id: userId,
      auth_user_id: userId,
      account_id: accountId,
      shop_name: b.shop_name || null,
      dealer_name: b.dealer_name || null,
      village: b.village || null,
      mandal: b.mandal || null,
      district: b.district || null,
      account_details: b.account_details || null,
      is_active: true,
    },
  });
  if (!row.ok) {
    await sbFetch("/auth/v1/admin/users/" + userId, { method: "DELETE", key: SERVICE_KEY, token: SERVICE_KEY });
    console.error("create-dealer DB_ERROR (dealer row):", errMsg(row));
    return fail(res, 500, "DB_ERROR", "Login created but the dealer row failed. Check server logs for details.");
  }

  // 4. Initial stock + audit movement
  const items = Array.isArray(b.initial_stock) ? b.initial_stock : [];
  const validItems = items.filter(i => i && i.product_id && Number(i.quantity) > 0);
  if (validItems.length) {
    // Validate products exist and are active
    const productIds = validItems.map(i => i.product_id);
    const prods = await sbFetch("/rest/v1/products?id=in.(" + productIds.join(",") + ")&select=id,is_active", {
      key: SERVICE_KEY, token: SERVICE_KEY,
    });
    if (prods.ok && prods.json) {
      const inactive = prods.json.filter(p => !p.is_active).map(p => p.id);
      if (inactive.length) {
        await sbFetch("/auth/v1/admin/users/" + userId, { method: "DELETE", key: SERVICE_KEY, token: SERVICE_KEY });
        return fail(res, 422, "VALIDATION_ERROR", inactive.length + " selected product(s) are inactive.");
      }
    }

    const stockRows = validItems.map(i => ({
      dealer_id: userId, product_id: i.product_id, quantity: Math.floor(Number(i.quantity)),
    }));
    const up = await sbFetch("/rest/v1/dealer_stock?on_conflict=dealer_id,product_id", {
      method: "POST", key: SERVICE_KEY, token: SERVICE_KEY,
      prefer: "resolution=merge-duplicates",
      body: stockRows,
    });
    if (!up.ok) {
      await sbFetch("/auth/v1/admin/users/" + userId, { method: "DELETE", key: SERVICE_KEY, token: SERVICE_KEY });
      console.error("create-dealer DB_ERROR (initial stock):", errMsg(up));
      return fail(res, 500, "DB_ERROR", "Dealer created but initial stock failed. Check server logs for details.");
    }

    // Create audit movements for initial stock
    const movements = validItems.map(i => ({
      dealer_id: userId,
      product_id: i.product_id,
      quantity: Math.floor(Number(i.quantity)),
      movement_type: "ALLOCATION",
      actor_user_id: admin.id || null,
    }));
    await sbFetch("/rest/v1/stock_movements", {
      method: "POST", key: SERVICE_KEY, token: SERVICE_KEY,
      body: movements,
    });
  }

  return ok(res, { dealer_id: userId, account_id: accountId, initial_stock: validItems.length });
};

function errMsg(r) {
  return (r.json && (r.json.message || r.json.error_description || r.json.hint || r.json.raw)) || ("HTTP " + r.status);
}
function safeParse(t) { try { return JSON.parse(t); } catch (e) { return {}; } }
