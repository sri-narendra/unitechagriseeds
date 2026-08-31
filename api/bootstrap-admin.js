// POST /api/bootstrap-admin
// Creates the FIRST admin account (email + password). Safe by construction:
// if any admin already exists the request is refused (409 ADMIN_EXISTS), so
// this endpoint cannot be abused once the system is set up.
// Uses the admins table as source of truth (not paginated Auth user listing).
// Rate-limited to 3 attempts per 10 minutes per IP.
const { SERVICE_KEY, sbFetch, fail, ok, handleCors } = require("./_supabase");

// ponytail: in-memory rate limiter — works for single instance, fine for bootstrap
const attempts = new Map();
function isRateLimited(ip) {
  const now = Date.now();
  const window = 10 * 60 * 1000; // 10 minutes
  const maxAttempts = 3;
  const record = attempts.get(ip) || [];
  const recent = record.filter(t => now - t < window);
  attempts.set(ip, recent);
  return recent.length >= maxAttempts;
}
function recordAttempt(ip) {
  const now = Date.now();
  const record = attempts.get(ip) || [];
  record.push(now);
  attempts.set(ip, record);
}

module.exports = async (req, res) => {
  if (handleCors(req, res)) return;
  if (req.method !== "POST") return fail(res, 405, "METHOD_NOT_ALLOWED", "POST only");

  const ip = req.headers["x-forwarded-for"] || "unknown";
  if (isRateLimited(ip)) {
    return fail(res, 429, "RATE_LIMITED", "Too many attempts. Try again in 10 minutes.");
  }
  recordAttempt(ip);

  const b = typeof req.body === "string" ? safeParse(req.body) : (req.body || {});
  const email = String(b.email || "").trim().toLowerCase();
  const password = String(b.password || "");
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return fail(res, 422, "VALIDATION_ERROR", "A valid email is required");
  if (password.length < 10) return fail(res, 422, "VALIDATION_ERROR", "Password must be at least 10 characters");
  if (!/[a-z]/.test(password) || !/[A-Z]/.test(password) || !/[0-9]/.test(password)) {
    return fail(res, 422, "VALIDATION_ERROR", "Password must contain uppercase, lowercase, and a number");
  }

  // Check admins table (source of truth) — not paginated Auth listing
  const existing = await sbFetch("/rest/v1/admins?select=id&limit=1", {
    key: SERVICE_KEY, token: SERVICE_KEY,
  });
  if (existing.ok && existing.json && existing.json.length > 0) {
    return fail(res, 409, "ADMIN_EXISTS", "An admin account already exists. Just log in.");
  }

  // Also check Auth users as backup (handles case where admins row wasn't created)
  const list = await sbFetch("/auth/v1/admin/users?per_page=200", { key: SERVICE_KEY, token: SERVICE_KEY });
  const users = (list.json && list.json.users) || [];
  if (users.some(u => u.app_metadata && u.app_metadata.role === "admin")) {
    return fail(res, 409, "ADMIN_EXISTS", "An admin account already exists. Just log in.");
  }

  // Create Auth user
  const created = await sbFetch("/auth/v1/admin/users", {
    method: "POST", key: SERVICE_KEY, token: SERVICE_KEY,
    body: { email, password, email_confirm: true, app_metadata: { role: "admin" } },
  });
  if (!created.ok) {
    console.error("bootstrap-admin failed:", created.json);
    return fail(res, 500, "ADMIN_BOOTSTRAP_FAILED", "Could not create the admin account. Check server logs for details.");
  }
  const userId = created.json.id;

  // Insert into admins table
  const adminRow = await sbFetch("/rest/v1/admins", {
    method: "POST", key: SERVICE_KEY, token: SERVICE_KEY,
    body: {
      auth_user_id: userId,
      full_name: b.full_name || null,
      email: email,
    },
  });
  if (!adminRow.ok) {
    console.error("bootstrap-admin admins row failed:", adminRow.json);
  }

  return ok(res, { email });
};

function safeParse(t) { try { return JSON.parse(t); } catch (e) { return {}; } }
