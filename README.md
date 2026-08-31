# Unitech Agri Seeds — Dealer Stock Management & Distribution

Plain **HTML app on Vercel** + **Supabase** (Auth, PostgreSQL with RLS, Storage)
+ a few tiny **Vercel Functions**. No build step, no framework, no big server.

```text
public/   company website  (served at / via vercel.json rewrites)
dealer/   dealer portal    (/dealer/…)
admin/    admin portal     (/admin/…)
api/      Vercel Functions — /api/health, /api/bootstrap-admin, /api/create-dealer
supabase/ schema.sql — run once in the Supabase SQL editor
tests/    e2e.mjs — backend end-to-end check
docs/     blueprint.md · backendStack.md · UIUX.md
```

> There is **no money anywhere** in this system — products, quantities and
> stock movement only.

---

## 1 · Set up Supabase (once)

1. Create a project at [supabase.com](https://supabase.com).
2. **SQL Editor** → paste and run the whole of `supabase/schema.sql`
   (tables, indexes, RLS + storage policies, RPC functions, realtime pub).
3. **Storage** → New bucket → name `product-images` → **Public**.
4. **Do not create users manually** — the app does it (admin → "Create the
   first admin account"; dealer → admin Dealers → "+ Add dealer").

Full guide: `docs/backendStack.md` §5.8, §7.

## 2 · Run locally (`vercel dev`)

The app is static HTML **plus** the Vercel Functions in `/api`, so the correct
way to run locally is `vercel dev` — it serves both the pages **and** the
`/api` handlers (same origin, no CORS). The setup here is identical to what
production needs.

**Prereads:**
- [ ] Supabase project set up (§1) — tables reachable, `product-images` bucket exists.
- [ ] Node.js (>= 18) and the Vercel CLI:
  ```bash
  node -v                     # e.g. v24
  npm i -g vercel             # installs/updates the CLI
  vercel --version
  ```

**Step 1 — configure the `/api` functions.** Copy the sample and fill in real
Supabase values (`.gitignore` ignores `.env*`, so these never get committed):
```powershell
Copy-Item .env.example .env.local
# edit .env.local -> the four values below
```
| Var | Value |
|-----|-------|
| `SUPABASE_URL` | `https://<project>.supabase.co` |
| `SUPABASE_ANON_KEY` | your anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | your service-role key (**server-only**, never in HTML) |
| `LOGIN_DOMAIN` | `@dealers.example.com` |

`vercel dev` reads `.env.local` automatically.

**Step 2 — configure the pages.** Every HTML page's browser config block has two
`TODO` placeholders that must be real values for logins/data to work — follow
**§3 (Configure the pages)** below, then return here.

**Step 3 — run.**
```bash
vercel dev          # starts http://localhost:3000
```
The first run may ask you to log in to Vercel and / or link a project — it
serves locally either way. Then open **http://localhost:3000** and follow
**§5 (First login)**.

> **Local caveats**
> - The static pages are served from the filesystem at `/public/…`,
>   `/admin/…`, `/dealer/…`; some local `vercel dev` versions skip the
>   `vercel.json` rewrites/redirects, so the website's clean URLs (`/`, `/about`)
>   may not apply locally — they **do** apply after deployment. The portals are
>   unaffected (`/dealer/index.html`, `/admin/index.html`).
> - Everything that touches data requires a reachable Supabase project. Offline,
>   the public pages render but logins and data calls error.

## 3 · Configure the pages (2 minutes)

Every HTML page ends with the same config block containing two `TODO` values.
Use VS Code **Replace in Files** (`Ctrl+Shift+H`) across the repo:

| Find | Replace with |
|------|--------------|
| `https://xxxx.supabase.co` | your project URL (Settings → API) |
| `eyJ...` | your **anon** key (Settings → API — public by design) |

Optionally tune `LOGIN_DOMAIN`, `LOW_STOCK_MAX`, `EXCESS_TOTAL` in the same block.

## 4 · Deploy to Vercel

- **Dashboard:** push this folder to GitHub → [vercel.com/new](https://vercel.com/new) → import.
  Framework **Other** (auto), no build command.
- **CLI:** install `vercel`, run `vercel --prod` in this folder.
- Under **Project → Settings → Environment Variables**, add the values the
  `/api` Functions need (`docs/backendStack.md` §5.8):

| Var | Value |
|-----|-------|
| `SUPABASE_URL` | `https://<project>.supabase.co` |
| `SUPABASE_ANON_KEY` | your anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | your service-role key (**server-only**, never in HTML) |
| `LOGIN_DOMAIN` | `@dealers.example.com` |

The included `vercel.json` does the routing:
- the website is served at `/` (also `/about`, `/products`, `/contact`)
- the portals are at `/dealer/…` and `/admin/…`
- the Functions respond at `/api/health`, `/api/bootstrap-admin`, `/api/create-dealer`
- `/docs/*`, `/supabase/*`, `/tests/*` are redirected away (not part of the app)
- basic security headers are set

## 5 · First login

1. Open `/admin/index.html`, use **"Create the first admin account"** (works only while no admin exists).
2. Log in as admin.
3. **Products** → add a product.
4. **Dealers** → "+ Add dealer" → name, **Account ID**, **password**, optional
   **initial stock** → submit. The dealer can log in immediately.

## Optional · Run the E2E check

Requires real Supabase credentials and an existing admin + dealer (created via
the app, §5). Works from local or CI:

```bash
SUPABASE_URL=... SUPABASE_ANON_KEY=... \
ADMIN_EMAIL=... ADMIN_PASSWORD=... \
DEALER_EMAIL=dealer-001@dealers.example.com DEALER_PASSWORD=... \
node tests/e2e.mjs
```

(PowerShell: set each var with `$env:NAME="..."` first, then `node tests/e2e.mjs`.)

## URLs after deploy

| Path | Page |
|------|------|
| `/` | Company website home |
| `/about` · `/products` · `/contact` | Website pages |
| `/dealer/index.html` | Dealer login |
| `/admin/index.html` | Admin login |
| `/api/health` | Uptime probe |
