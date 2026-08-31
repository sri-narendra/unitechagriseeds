// Shared helpers for the Vercel Functions in /api (Node 18+, zero dependencies).
// The service-role key lives ONLY in Vercel environment variables — never in
// any HTML page (docs/backendStack.md §5.8).
const SUPABASE_URL = process.env.SUPABASE_URL || "";
const ANON_KEY = process.env.SUPABASE_ANON_KEY || "";
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || "";
const LOGIN_DOMAIN = process.env.LOGIN_DOMAIN || "@agri.local";

// M-1: Dynamic CORS — validate origin against allowlist (no more wildcard *)
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || "").split(",").filter(Boolean);
function corsHeaders(req) {
  const origin = req.headers.origin || "";
  const isDev = /localhost|127\.0\.0\.1/.test(origin);
  const allowed = isDev || ALLOWED_ORIGINS.length === 0 || ALLOWED_ORIGINS.includes(origin);
  return {
    "Access-Control-Allow-Origin": allowed ? (ALLOWED_ORIGINS.length ? origin : "*") : "null",
    "Vary": "Origin",
  };
}
function handleCors(req, res) {
  const h = corsHeaders(req);
  Object.entries(h).forEach(([k, v]) => res.setHeader(k, v));
  if (req.method === "OPTIONS") { res.status(204).end(); return true; }
  return false;
}

async function sbFetch(path, { method = "GET", body, key, token, prefer } = {}) {
  const headers = { apikey: key || ANON_KEY, "Content-Type": "application/json" };
  if (token) headers.Authorization = "Bearer " + token;
  if (prefer) headers.Prefer = prefer;
  const res = await fetch(SUPABASE_URL + path, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch (e) { json = { raw: text }; }
  return { status: res.status, ok: res.ok, json };
}

function fail(res, status, code, message) {
  res.status(status).json({ ok: false, error: { code, message } });
}
function ok(res, data, status = 200) {
  res.status(status).json({ ok: true, data });
}

// Verifies the caller's Supabase JWT (via /auth/v1/user) and requires the
// admin role claim. Returns the user object or null.
async function getAdminUser(req) {
  const m = String(req.headers.authorization || "").match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  const r = await sbFetch("/auth/v1/user", { key: ANON_KEY, token: m[1] });
  if (!r.ok || !r.json || !r.json.app_metadata) return null;
  return r.json.app_metadata.role === "admin" ? r.json : null;
}

// "Dealer 001" -> "dealer-001" (authoritative version; pages pre-normalize).
function normalizeAccountId(raw) {
  return String(raw || "").trim().toLowerCase()
    .replace(/[^a-z0-9-]+/g, "-")
    .replace(/-{2,}/g, "-")
    .replace(/^-+|-+$/g, "");
}

module.exports = { SUPABASE_URL, ANON_KEY, SERVICE_KEY, LOGIN_DOMAIN, sbFetch, fail, ok, getAdminUser, normalizeAccountId, handleCors };
