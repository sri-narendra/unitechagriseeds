// GET /api/health — uptime probe (same contract as the reference /api/health).
const { handleCors } = require("./_supabase");

module.exports = async (req, res) => {
  if (handleCors(req, res)) return;
  let supabase = "unconfigured";
  if (process.env.SUPABASE_URL && process.env.SUPABASE_ANON_KEY) {
    try {
      const r = await fetch(process.env.SUPABASE_URL + "/rest/v1/", {
        headers: { apikey: process.env.SUPABASE_ANON_KEY },
      });
      supabase = r.ok ? "ok" : "error " + r.status;
    } catch (e) {
      supabase = "unreachable";
    }
  }
  res.status(200).json({ status: "ok" });
};
