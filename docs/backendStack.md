# Backend Stack — Vercel (static) + Supabase

Engineering reference for the Agriculture Dealer Stock Management system.
One rule drives everything: **keep it simple** — three folders of plain HTML
files on Vercel, one Supabase project behind them, nothing else.

## 1. Stack at a glance

| Concern | Handled by |
|---------|-----------|
| Hosting all pages | **Vercel** (static hosting, no build step) |
| Login (dealer + admin) | **Supabase Auth** (JWT in browser) |
| Data (single source of truth) | **Supabase PostgreSQL** |
| Business logic / stock math | **Postgres functions (RPCs)** |
| Access control | **Row Level Security (RLS)** |
| Product images | **Supabase Storage** (bucket `product-images`) |
| Live updates | **Supabase Realtime** (dealer Stock Stats page) |
| Privileged tasks (create dealer login, first admin, health) | **Vercel Functions** in `/api` (§5.8) |

**Deliberately removed (no Cloudflare):** no Cloudflare Worker fallback, no R2,
no Cloudflare DNS/CDN/WAF, no wrangler config. There is also **no Node/Next.js
API layer** — the browser calls Supabase directly; the old `API_CONTRACTS.md`
endpoints are replaced by the RPC contract in §5. The only exceptions are the
three **Vercel Functions** in `/api` (§5.8): creating a dealer login and the
first admin need the privileged **service-role key**, which can never run in a
browser, so they live in tiny serverless handlers instead.

## 2. Folder & page structure (HTML files only)

```text
project-root/
├── public/
│   ├── index.html        # home
│   ├── about.html
│   ├── products.html     # product list (public read of products table)
│   └── contact.html
├── dealer/
│   ├── index.html        # login
│   ├── stock.html        # Stock Stats (landing after login)
│   ├── sale.html
│   ├── order.html        # catalogue + cart + My Orders list
│   └── return.html       # return form + My Returns list
├── admin/
│   ├── index.html        # login
│   ├── dashboard.html    # totals, low/excess dealers, redistribute, movement
│   ├── products.html     # add/edit/remove products, upload image, product stats
│   ├── dealers.html      # add/edit dealers, dealer detail (activity + allocate)
│   ├── orders.html       # order queue (approve/reject)
│   └── returns.html      # return queue (accept/reject)
├── supabase/
│   └── schema.sql        # tables + RPCs + policies (§4–§6) — DB config, not app code
├── api/                  # Vercel Functions: health, bootstrap-admin, create-dealer (§5.8)
│   ├── _supabase.js      # shared fetch helpers + JWT check (service-role key lives ONLY here)
│   ├── health.js
│   ├── bootstrap-admin.js
│   └── create-dealer.js
├── tests/
│   └── e2e.mjs           # backend end-to-end check (node tests/e2e.mjs)
├── docs/                 # blueprint.md, backendStack.md, UIUX.md
├── vercel.json           # routing: website at /, hides docs/supabase, security headers
└── README.md             # 3-step deployment guide
```

Rules:
- The three app folders (`public/`, `admin/`, `dealer/`) contain **only
  `.html` files**. CSS lives in a `<style>` block inside each page; JS lives in
  a `<script>` block inside each page. No external `.css`/`.js` files of our own.
- The **only external script** allowed is the Supabase JS client from a CDN
  (§3).
- Page filenames are lowercase; URLs are `/<folder>/<page>.html`
  (e.g. `/admin/dashboard.html`).
- Shared markup (header/nav) is deliberately duplicated per page — simple beats
  clever. Keep pages byte-consistent by copying the snippets in §3 and
  `UIUX.md` §9.

## 3. Per-page config block (paste into every page)

Every page starts its `<body>`-end script area with the same two blocks:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script>
  // ---- shared config (identical in every page) -------------------------
  const SUPABASE_URL  = "https://xxxx.supabase.co";
  const SUPABASE_ANON_KEY = "eyJ...";            // public by design; RLS protects data
  const LOGIN_DOMAIN  = "@dealers.example.com";  // dealer Account ID -> login email
  const LOW_STOCK_MAX = 0;                       // dealer total <= this = low stock
  const EXCESS_TOTAL  = 1000;                    // dealer total >= this = excess stock
  const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  // ----------------------------------------------------------------------
</script>
```

- `SUPABASE_URL` and `SUPABASE_ANON_KEY` are safe to ship to the browser — the
  anon key is scoped by RLS. **Never** place the service-role key in any HTML
  file; it lives only in Vercel env vars, used by the `/api` Functions (§5.8).
- **Account ID normalization:** "Dealer 001" is normalized to `dealer-001`
  (lowercase, spaces → hyphens, trimmed) on both login and dealer-creation, so
  the login email always matches. See `normalizeAccountId()` in the pages and
  `api/_supabase.js`.
- Dealer login: the dealer types their Account ID (e.g. `dealer01`); the page
  normalizes it, appends `LOGIN_DOMAIN`, and signs in with
  `supabase.auth.signInWithPassword`. Admins sign in with their real email.
- Session helpers: `await supabase.auth.getSession()` on page load (redirect to
  the folder's `index.html` if missing), `supabase.auth.onAuthStateChange` for
  expiry, `supabase.auth.signOut()` for the logout button.

---

## 4. Database schema (run `supabase/schema.sql` in the Supabase SQL editor)

PostgreSQL on Supabase is the single source of truth. Auth is handled by
**Supabase Auth** (`auth.users`); roles (`dealer` / `admin`) are carried as JWT
`app_metadata` claims and enforced by **RLS** (§6). There is **no
`company_stock` table** — the company warehouse is tracked manually outside the
system. There is **no money field anywhere** (the old legacy `credit_limit` was
removed on purpose).

```sql
create table dealers (
  id            uuid primary key default gen_random_uuid(),
  shop_name     text,
  dealer_name   text,
  village       text,
  mandal        text,
  district      text,
  account_details text,                          -- informational only (no payments)
  account_id    text not null unique,            -- login Account ID (admin-issued)
  auth_user_id  uuid unique references auth.users(id) on delete set null,
  is_active     boolean not null default true,   -- soft delete / deactivate
  created_at    timestamptz not null default now()
);

create table admins (
  id           uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete cascade,
  full_name    text,
  email        text unique,
  created_at   timestamptz not null default now()
);

create table products (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  image_url  text,                               -- Supabase Storage public URL
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table dealer_stock (
  dealer_id  uuid not null references dealers(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  quantity   integer not null default 0 check (quantity >= 0),
  updated_at timestamptz not null default now(),
  primary key (dealer_id, product_id)
);

create table sales (
  id         uuid primary key default gen_random_uuid(),
  dealer_id  uuid not null references dealers(id) on delete cascade,
  product_id uuid not null references products(id),
  quantity   integer not null check (quantity > 0),
  client_ref uuid unique,                        -- replay-safe double-click guard (§5)
  created_at timestamptz not null default now()
);

create table orders (
  id           uuid primary key default gen_random_uuid(),
  dealer_id    uuid not null references dealers(id) on delete cascade,
  status       text not null default 'pending'
                 check (status in ('pending','sent','rejected')),
  requested_at timestamptz not null default now(),
  approved_at  timestamptz,
  fulfilled_at timestamptz,
  created_at   timestamptz not null default now()
);

create table order_items (
  order_id   uuid not null references orders(id) on delete cascade,
  product_id uuid not null references products(id),
  quantity   integer not null check (quantity > 0),
  primary key (order_id, product_id)
);

create table returns (
  id           uuid primary key default gen_random_uuid(),
  dealer_id    uuid not null references dealers(id) on delete cascade,
  status       text not null default 'pending'
                 check (status in ('pending','accepted','rejected')),
  submitted_at timestamptz not null default now(),
  accepted_at  timestamptz,
  created_at   timestamptz not null default now()
);

create table return_items (
  return_id  uuid not null references returns(id) on delete cascade,
  product_id uuid not null references products(id),
  quantity   integer not null check (quantity > 0),
  primary key (return_id, product_id)
);

create table stock_movements (
  id            uuid primary key default gen_random_uuid(),
  dealer_id     uuid not null references dealers(id) on delete cascade,
  product_id    uuid not null references products(id),
  quantity      integer not null,               -- signed: + in, - out
  movement_type text not null check (movement_type in
                  ('ALLOCATION','ORDER','SALE','RETURN','REDISTRIBUTE')),
  reference_id  uuid,                           -- order_id / return_id / sale id
  created_at    timestamptz not null default now()
);
-- ALLOCATION + / ORDER + : dealer received from company
-- SALE - : dealer sold to customer
-- RETURN - : dealer sent back to company
-- REDISTRIBUTE +/- : dealer -> dealer
```

Indexes for the common query paths:

```sql
create index idx_dealer_stock_product    on dealer_stock(product_id);
create index idx_orders_status           on orders(status);
create index idx_returns_status          on returns(status);
create index idx_sales_dealer            on sales(dealer_id, created_at desc);
create index idx_orders_dealer           on orders(dealer_id, created_at desc);
create index idx_returns_dealer          on returns(dealer_id, created_at desc);
create index idx_stock_movements_dealer  on stock_movements(dealer_id, created_at desc);
create index idx_stock_movements_product on stock_movements(product_id);
```

Notes:
- The old `idempotency_keys` table is **not needed** in this architecture:
  replay-safety comes from the `client_ref` unique column on `sales` (§5) and
  from status guards inside the RPCs (an `approve_order` on an already-`sent`
  order is refused, not re-applied).
- All stock mutation happens in the RPCs of §5 — the tables above are never
  updated directly by page JS (except order/return creation, which is plain
  `insert` under RLS).

---

## 5. Business logic = Postgres functions (the "API")

**Principle:** the browser never computes stock. Every mutation is one RPC call
that runs atomically inside Postgres — check, update, and audit-log in a single
transaction. If any step fails, everything rolls back.

Page JS calls them like:

```js
const { data, error } = await supabase.rpc("record_sale", {
  p_product: productId,
  p_quantity: qty,
  p_client_ref: crypto.randomUUID(),   // replay-safe double-click guard
});
```

### 5.1 `record_sale(p_items jsonb, p_client_ref uuid)` — dealer Sale (multi-item)
One atomic transaction for **all items** in the sale. `p_items` is an array of
`{ product_id, quantity }`. Each row is checked (the post-failure read
disambiguates `409 CONCURRENT_MODIFICATION` from `422 INSUFFICIENT_STOCK`),
decremented, and audit-logged; per-item `quantity_before/after` are returned.
Replaying the same `p_client_ref` is a no-op (`replayed: true`).

Page call:
```js
const { data, error } = await supabase.rpc("record_sale", {
  p_items: [{ product_id, quantity }, …],
  p_client_ref: crypto.randomUUID(),   // replay-safe double-click guard
});
// data = { replayed: false, items: [{ product_id, quantity_before, quantity_after }, …] }
```
```sql
-- pseudo-structure (full SQL in supabase/schema.sql):
if p_items empty -> raise VALIDATION_ERROR
if p_client_ref already used -> return { replayed: true }
for item in p_items:
  read quantity_before                                   -- post-failure disambiguation
  update dealer_stock set quantity = quantity - n
   where dealer_id = v_dealer and product_id = item
     and quantity >= n
  if not found:
     raise INSUFFICIENT_STOCK   (if before < n)  else  raise CONCURRENT_MODIFICATION
  insert sales (client_ref = p_client_ref)
  insert stock_movements (SALE, -n)
return { replayed: false, items: [{quantity_before, quantity_after}, …] }
```
The dealer id comes from the JWT claim, so a dealer can only ever touch their
own stock — even though the function runs with elevated rights.

### 5.2 `approve_order(p_order)` — admin sends stock (Order queue)
Guarded by role + status (replay-safe: only a `pending` order is processed):

```sql
-- inside the function:
if (auth.jwt() -> 'app_metadata' ->> 'role') <> 'admin' then
  raise exception 'FORBIDDEN';
end if;
update orders set status='sent', approved_at=now(), fulfilled_at=now()
 where id = p_order and status = 'pending';
if not found then raise exception 'ORDER_NOT_PENDING'; end if;
-- then, for each row in order_items of this order:
--   upsert dealer_stock + r.quantity  (on conflict do update)
--   insert stock_movements (dealer_id, r.product_id, +r.quantity, 'ORDER', p_order)
```

### 5.3 `accept_return(p_return)` / `reject_return(p_return)` — Return queue
`accept_return`: role guard → `returns.status: pending → accepted` → for each
`return_items` row run the conditional
`update dealer_stock set quantity = quantity - r.quantity ... and quantity >= r.quantity`
→ any `not found` raises `INSUFFICIENT_STOCK` and the whole transaction rolls
back → insert `RETURN` movements (negative). `reject_return`: role guard →
status `pending → rejected`; no stock movement.

### 5.4 `allocate_stock(p_dealer, p_items jsonb)` — direct allocation (multi-item)
Role guard (admin) → for each `{ product_id, quantity }` upsert
`dealer_stock + qty` and write one `ALLOCATION` movement — one transaction.
Company side is manual, so nothing is decremented.

### 5.5 `redistribute_stock(p_from_dealer, p_to_dealer, p_items jsonb)`
Role guard → for each item: subtract from source with the `quantity >=` guard
(failure = `INSUFFICIENT_STOCK`, full rollback) → add to target via upsert →
write a **paired** `REDISTRIBUTE` movement (`-qty` source, `+qty` target)
sharing one `reference_id`, so each move is reconstructable in the audit trail.
Rejects `from === to`.

### 5.6 Order / Return creation (no RPC needed)
Creating an order or return is plain inserts the dealer makes from their own
pages — RLS forces `dealer_id` to equal the caller's claim. Both carry a
`client_ref` so a retried submit can't create duplicates (the unique column is
the guard):

```js
// dealerId was read once from the JWT claim after login:
const { data: session } = await supabase.auth.getSession();
const dealerId = session.user.app_metadata.dealer_id;

const { data: order, error } = await supabase
  .from("orders")
  .insert({ dealer_id: dealerId, client_ref: crypto.randomUUID() })
  .select()
  .single();

await supabase.from("order_items").insert(
  cart.map(item => ({
    order_id: order.id,
    product_id: item.productId,
    quantity: item.quantity,      // positive integers; the DB re-checks
  }))
);
```
Same pattern for `returns` + `return_items`. Return/sale items can be multiple
products in one request (multi-item carts on the dealer pages).

### 5.7 Error mapping (client side)

| RPC exception / error | Meaning | UI response |
|---|---|---|
| `VALIDATION_ERROR` | bad input | inline field error; no retry needed |
| `INSUFFICIENT_STOCK` | genuinely not enough stock | toast + refresh stats; do **not** auto-retry |
| `CONCURRENT_MODIFICATION` | another write took the stock first | toast + refresh stats; retry with a **new** idempotency key |
| `ORDER_NOT_PENDING` / `RETURN_NOT_PENDING` | already processed (double-click / stale list) | info toast + refresh list |
| `FORBIDDEN` | role/ownership mismatch | redirect to login |
| `NOT_FOUND` | stale row id | refresh list |
| `invalid login credentials` (Auth) | wrong Account ID / password | inline "Wrong Account ID or password" |
| network error | offline / Supabase down | toast "Network problem — try again"; same payload may be safely resent (guards above prevent double-apply) |

Show the friendly message from this table — never raw Postgres errors.

### 5.8 Vercel Functions: privileged tasks + health
Three tiny Node functions in `/api` (Vercel serves them automatically; they are
the only place the **service-role key** is used, and it is read from Vercel env
vars, never from a page). Shared helpers live in `api/_supabase.js`.

| Function | Purpose | Guard |
|----------|---------|-------|
| `POST /api/create-dealer` | Creates a dealer login end-to-end: Supabase Auth user + `role="dealer"`/`dealer_id` claims + `dealers` row (+ optional `initial_stock`). Called by admin **Dealers → Add Dealer.** | Verifies the caller's JWT and requires `app_metadata.role = admin`. Normalizes the Account ID. |
| `POST /api/bootstrap-admin` | Creates the **first** admin (email-based). Called from the admin login screen's "Create the first admin account". | **Refuses** (`409 ADMIN_EXISTS`) if any admin already exists — safe to expose. |
| `GET /api/health` | Uptime probe; reports Supabase reachability. | public |

Required Vercel environment variables — set **Project → Settings → Environment
Variables** (same values as your Supabase project, **not** in any HTML file):

```
SUPABASE_URL            https://<project>.supabase.co
SUPABASE_ANON_KEY       <anon key>
SUPABASE_SERVICE_ROLE_KEY  <service-role key>   # server-only
LOGIN_DOMAIN            @dealers.example.com
```

**Security notes**
- The service-role key bypasses RLS, so the functions are the **only** caller
  allowed to touch `auth.admin.*`. `create-dealer` verifies the caller is an
  admin (via the anon-key `/auth/v1/user` check) before using it.
- Initial stock written by `create-dealer` could also go through the normal
  `allocate_stock` RPC; writing it directly is a build convenience — it is
  admin-authorized either way.
- Keep `/api/*` on the same Vercel project/domain as the app so the pages can
  `fetch("/api/...")` without CORS setup.

---

## 6. Security: RLS + Storage policies

RLS is the security wall, since the anon key ships to the browser. Roles come
from JWT `app_metadata` claims set when the user is created (§7):
`role = 'dealer'` with `dealer_id`, or `role = 'admin'`.

```sql
-- enable RLS everywhere
alter table dealers           enable row level security;
alter table admins            enable row level security;
alter table products          enable row level security;
alter table dealer_stock      enable row level security;
alter table sales             enable row level security;
alter table orders            enable row level security;
alter table order_items       enable row level security;
alter table returns           enable row level security;
alter table return_items      enable row level security;
alter table stock_movements   enable row level security;

-- dealers see/mutate only their own rows (same pattern for sales, orders,
-- returns, stock_movements)
create policy dealer_stock_own on dealer_stock for all
  using (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid);

-- admin sees/mutates everything (same pattern on every table)
create policy dealer_stock_admin on dealer_stock for all
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- products: readable by everyone (public website + dealer catalogue);
-- writes admin-only
create policy products_read on products for select using (true);
create policy products_admin_write on products for all
  using      ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- dealers table: admin manages; a dealer may read their own row
create policy dealers_admin_all on dealers for all
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy dealers_own_read on dealers for select
  using (id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid);
```

Storage (bucket `product-images`, created as **public**):

```sql
create policy "images public read" on storage.objects for select
  using (bucket_id = 'product-images');
create policy "images admin write" on storage.objects for insert
  with check (bucket_id = 'product-images'
              and (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
```

Hard rules:
- The **service-role key is never used in any HTML file** — it lives only in
  Vercel **environment variables**, used by the `/api` Functions (§5.8). It is
  also available in the Supabase Dashboard (SQL editor), but the app never
  needs it in the browser.
- Admin pages double-check `role = 'admin'` in JS after login and hide/redirect,
  but RLS remains the real enforcement.
- Keep every policy above in place; do not weaken them for convenience.

## 7. Account bootstrap (no manual Dashboard steps)

Logins are created **from the app** via the `/api` Functions (§5.8), so there
is no manual user-provisioning:

1. **First admin** (`/admin/index.html` → "Create the first admin account"):
   enter an email + password. `POST /api/bootstrap-admin` creates the admin
   user with `app_metadata.role = "admin"`. It **refuses if an admin already
   exists**, so it's safe to leave exposed. (Alternatively, create the first
   user in the Supabase Dashboard with `{ "role": "admin" }` App Metadata.)
2. **Each dealer** (`/admin/dealers.html` → "+ Add dealer"): fill the fields +
   password (+ optional **initial stock** items). `POST /api/create-dealer`:
   - normalizes the Account ID (`"Dealer 001"` → `dealer-001`)
   - creates the Supabase Auth user `dealer-001@dealers.example.com`
   - sets `app_metadata = { "role": "dealer", "dealer_id": "<user id>" }`
   - inserts the `dealers` row (id = the auth user id)
   - optionally seeds the initial `dealer_stock`

The dealer then signs in at `/dealer/index.html` by typing only their Account
ID — the page normalizes it and appends `LOGIN_DOMAIN` (§3). Passwords are
stored by Supabase Auth (never in the DB).

## 8. State transitions & validation

| Entity | Allowed transitions | Stock effect |
|--------|--------------------|--------------|
| orders | `pending` → `sent` (approve) / `rejected` | `+qty` on `sent` only |
| returns | `pending` → `accepted` (on physical receipt) / `rejected` | `-qty` on `accepted` only |
| dealers | `is_active` true ↔ false (deactivate/reactivate) | none |

Database-level guarantees: `dealer_stock.quantity >= 0`, positive-integer
quantities on `sales`/`order_items`/`return_items`, status + `movement_type`
enums, unique `account_id`, unique `(dealer_id, product_id)`, unique
`sales.client_ref`, unique `orders.client_ref`, unique `returns.client_ref`.

Application-level (page JS, mirrors §5.7): validate quantities are positive
integers and required fields are present *before* calling Supabase; the DB is
the final gate either way.

---

## 9. Coding standards (static-HTML edition)

- **Structure:** only `.html` files inside `public/`, `admin/`, `dealer/` —
  every page carries its own `<style>` and `<script>` (`UIUX.md` §9 tokens,
  §3 config block). `supabase/schema.sql` is the DB source of truth; the small
  `/api` Functions (`_supabase.js`, `health.js`, `bootstrap-admin.js`,
  `create-dealer.js`) handle privileged server tasks (§5.8).
- **Reject-input lists:** sale, return, allocate and redistribute all submit
  **multi-item** arrays in one atomic call; the DB rolls back fully if any item
  fails.
- **Naming:** pages lowercase (`stock.html`); ids/classes `kebab-case`;
  DB objects `snake_case`; status values `pending`/`sent`/`accepted`/
  `rejected`; `movement_type` `UPPER_SNAKE` (`ALLOCATION`, `ORDER`, `SALE`,
  `RETURN`, `REDISTRIBUTE`); error codes `UPPER_SNAKE`
  (`INSUFFICIENT_STOCK`, …). Never abbreviate domain words: `quantity`, `dealer`.
- **JS style:** `const`/`let` only; `async/await` — every call `await`ed or
  returned (no floating promises); scripts at the end of `<body>`; one logical
  block per concern (config → auth guard → load → handlers).
- **Concurrency rules:** never read-then-write stock in JS — all stock math is
  in RPCs (§5); quantities are integers; generate `client_ref` with
  `crypto.randomUUID()` on every sale submit; disable the submit button while a
  write is in flight.
- **Validation:** check input in JS (positive integer quantities, required
  fields), then let DB constraints/RPC guards be the final gate. Never trust
  another dealer's/admin's data arriving in the page — render only what
  Supabase returns for the signed-in user.
- **Errors:** map `error.message`/codes through the §5.7 table; show friendly
  toasts/messages; never dump raw errors to the UI.
- **No money:** no price/cost/currency field, variable, or formatted number
  anywhere.

## 10. Deployment (Vercel + Supabase only)

**Supabase (once):**
1. Create the project; run `supabase/schema.sql` (§4 + §5 + §6) in the SQL editor.
2. Create the public Storage bucket `product-images` + the §6 storage policies.
   Do **not** manually create users — the app provisions them (§5.8, §7).

**Vercel:**
1. Import the repo (or `vercel` CLI / drag-and-drop) — the included
   `vercel.json` and `README.md` make this a 3-step job.
2. Framework preset **Other**; **no build command**; output = repo root
   (static). Portals are served at `/dealer/…` and `/admin/…`. The `/api`
   folder becomes Vercel Functions automatically.
3. Set the Functions' environment variables (§5.8): `SUPABASE_URL`,
   `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `LOGIN_DOMAIN`.
4. The shipped `vercel.json` handles routing (no changes needed):
   - rewrites serve the company website at `/` (plus `/about`, `/products`,
     `/contact`, with or without the `.html` suffix)
   - redirects keep `/docs/*`, `/supabase/*` and `/tests/*` off the deployed site
   - sets basic security headers (nosniff, DENY framing, referrer policy)
5. Custom domain: point DNS from any registrar straight to Vercel — **no
   Cloudflare account needed anywhere**.
6. The page-level config still lives in the HTML (§3) — if the Supabase
   URL/anon key change, update it in every page (README §2 shows the
   find-and-replace). The Functions read their own values from env vars.

## 11. Live updates (Realtime) + monitoring

Implemented on the dealer **Stock Stats** page (`dealer/stock.html`): the page
subscribes to `dealer_stock` changes and re-renders its cards and the recent
movement feed the moment stock changes — no manual refresh. RLS applies to
Realtime too, so a dealer only ever receives events for their own rows.

The publication step ships at the end of `supabase/schema.sql` (§6):

```sql
do $$
begin
  alter publication supabase_realtime add table dealer_stock;
exception
  when duplicate_object then null;   -- already added (safe to re-run)
  when undefined_object then null;   -- no realtime publication (non-Supabase host)
end $$;
```

Page-side subscription (already in `dealer/stock.html`):

```js
supabase.channel("dealer-stock-live")
  .on("postgres_changes",
      { event: "*", schema: "public", table: "dealer_stock" },
      () => { loadStock(); loadMoves(); })
  .subscribe();
```

Monitoring stays inside the two dashboards: **Supabase → Reports** (DB size,
egress, auth, API latency) and **Vercel → Analytics** (traffic). No extra
infrastructure.

## 12. Scope reminder

Inventory only — products, quantities, stock movement. No prices, costs,
payments, invoicing, or money anywhere (`blueprint.md` §8).