// POST /api/reset-dealer-password  (admin only)
// Updates a dealer's Supabase Auth password.
const { SERVICE_KEY, sbFetch, fail, ok, getAdminUser, handleCors } = require("./_supabase");

module.exports = async (req, res) => {
  if (handleCors(req, res)) return;
  if (req.method !== "POST") return fail(res, 405, "METHOD_NOT_ALLOWED", "POST only");
  const admin = await getAdminUser(req);
  if (!admin) return fail(res, 403, "FORBIDDEN", "Admin role required");

  const b = typeof req.body === "string" ? safeParse(req.body) : (req.body || {});
  const userId = String(b.user_id || "").trim();
  if (!userId) return fail(res, 422, "VALIDATION_ERROR", "user_id is required");

  const password = String(b.password || "");
  if (password.length < 10) return fail(res, 422, "VALIDATION_ERROR", "Password must be at least 10 characters");
  if (!/[a-z]/.test(password) || !/[A-Z]/.test(password) || !/[0-9]/.test(password)) {
    return fail(res, 422, "VALIDATION_ERROR", "Password must contain uppercase, lowercase, and a number");
  }

  const r = await sbFetch("/auth/v1/admin/users/" + userId, {
    method: "PUT", key: SERVICE_KEY, token: SERVICE_KEY,
    body: { password },
  });
  if (!r.ok) return fail(res, 500, "AUTH_UPDATE_FAILED", "Could not update password.");
  return ok(res, { user_id: userId });
};

function safeParse(t) { try { return JSON.parse(t); } catch (e) { return {}; } }
