-- ============================================================================
-- Agriculture Dealer Stock Management & Distribution System — Supabase schema
-- Run once: Supabase Dashboard → SQL Editor
-- Contents: 1) tables  2) indexes  3) RLS policies  4) storage policies  5) RPCs
-- Matches docs/backendStack.md §4 (schema), §5 (RPCs), §6 (security).
-- Inventory only — no money fields anywhere.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Tables
-- ----------------------------------------------------------------------------

create table if not exists dealers (
  id            uuid primary key default gen_random_uuid(),
  shop_name     text,
  dealer_name   text,
  phone         text,
  village       text,
  mandal        text,
  district      text,
  account_details text,
  account_id    text not null unique,
  auth_user_id  uuid unique references auth.users(id) on delete set null,
  is_active     boolean not null default true,
  deleted_at    timestamptz,
  created_at    timestamptz not null default now()
);

create table if not exists admins (
  id           uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete cascade,
  full_name    text,
  email        text unique,
  created_at   timestamptz not null default now()
);

create table if not exists products (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  image_url  text,
  is_active  boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists dealer_stock (
  dealer_id  uuid not null references dealers(id) on delete restrict,
  product_id uuid not null references products(id) on delete restrict,
  quantity   integer not null default 0 check (quantity >= 0),
  updated_at timestamptz not null default now(),
  primary key (dealer_id, product_id)
);

-- Transaction header for sales (holds client_ref for idempotency)
create table if not exists sale_transactions (
  id         uuid primary key default gen_random_uuid(),
  dealer_id  uuid not null references dealers(id) on delete restrict,
  client_ref uuid unique,
  created_at timestamptz not null default now()
);

-- Individual sale lines (one per product in a transaction)
create table if not exists sale_items (
  transaction_id uuid not null references sale_transactions(id) on delete restrict,
  product_id     uuid not null references products(id) on delete restrict,
  quantity       integer not null check (quantity > 0),
  primary key (transaction_id, product_id)
);

create table if not exists orders (
  id           uuid primary key default gen_random_uuid(),
  dealer_id    uuid not null references dealers(id) on delete restrict,
  client_ref   uuid unique,
  status       text not null default 'pending'
                 check (status in ('pending','sent','rejected')),
  requested_at timestamptz not null default now(),
  approved_at  timestamptz,
  fulfilled_at timestamptz,
  created_at   timestamptz not null default now()
);

create table if not exists order_items (
  order_id   uuid not null references orders(id) on delete restrict,
  product_id uuid not null references products(id) on delete restrict,
  quantity   integer not null check (quantity > 0),
  primary key (order_id, product_id)
);

create table if not exists returns (
  id           uuid primary key default gen_random_uuid(),
  dealer_id    uuid not null references dealers(id) on delete restrict,
  client_ref   uuid unique,
  status       text not null default 'pending'
                 check (status in ('pending','accepted','rejected')),
  submitted_at timestamptz not null default now(),
  accepted_at  timestamptz,
  created_at   timestamptz not null default now()
);

create table if not exists return_items (
  return_id  uuid not null references returns(id) on delete restrict,
  product_id uuid not null references products(id) on delete restrict,
  quantity   integer not null check (quantity > 0),
  primary key (return_id, product_id)
);

create table if not exists stock_movements (
  id            uuid primary key default gen_random_uuid(),
  dealer_id     uuid not null references dealers(id) on delete restrict,
  product_id    uuid not null references products(id) on delete restrict,
  quantity      integer not null check (quantity <> 0),
  movement_type text not null check (movement_type in
                  ('ALLOCATION','ORDER','SALE','RETURN','REDISTRIBUTE')),
  reference_id  uuid,
  actor_user_id uuid,
  created_at    timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 2. Indexes
-- ----------------------------------------------------------------------------

create index if not exists idx_dealer_stock_product    on dealer_stock(product_id);
create index if not exists idx_orders_status           on orders(status);
create index if not exists idx_returns_status          on returns(status);
create index if not exists idx_sales_dealer            on sale_transactions(dealer_id, created_at desc);
create index if not exists idx_orders_dealer           on orders(dealer_id, created_at desc);
create index if not exists idx_returns_dealer          on returns(dealer_id, created_at desc);
create index if not exists idx_stock_movements_dealer  on stock_movements(dealer_id, created_at desc);
create index if not exists idx_stock_movements_product on stock_movements(product_id);

-- ----------------------------------------------------------------------------
-- 3. Row Level Security
-- Roles come from JWT app_metadata claims (set in Dashboard → Authentication
-- → Users → Edit user → App metadata):
--   dealer: { "role": "dealer", "dealer_id": "<dealers.id>" }
--   admin : { "role": "admin" }
-- ----------------------------------------------------------------------------

alter table dealers           enable row level security;
alter table admins            enable row level security;
alter table products          enable row level security;
alter table dealer_stock      enable row level security;
alter table sale_transactions enable row level security;
alter table sale_items        enable row level security;
-- (sales table was renamed to sale_transactions above)
alter table orders            enable row level security;
alter table order_items       enable row level security;
alter table returns           enable row level security;
alter table return_items      enable row level security;
alter table stock_movements   enable row level security;

-- === DEALERS ===
-- Dealer: SELECT own row (only if active)
drop policy if exists dealers_own_read on dealers;
create policy dealers_own_read on dealers for select
  using (id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid
         and is_active = true);
-- Admin: full CRUD
drop policy if exists dealers_admin_all on dealers;
create policy dealers_admin_all on dealers for all
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- === ADMINS ===
-- Dealer: no access
-- Admin: full CRUD
drop policy if exists admins_admin_all on admins;
create policy admins_admin_all on admins for all
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- === PRODUCTS ===
-- Everyone: SELECT (public read — excludes soft-deleted products)
drop policy if exists products_public_read on products;
create policy products_public_read on products for select
  using (deleted_at is null or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
-- Admin: full CRUD
drop policy if exists products_admin_all on products;
create policy products_admin_all on products for all
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- === DEALER_STOCK ===
-- Dealer: SELECT own rows only (NO direct writes — stock changes via RPCs only)
drop policy if exists dealer_stock_own_read on dealer_stock;
create policy dealer_stock_own_read on dealer_stock for select
  using (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid);
-- Admin: full CRUD (admin may directly adjust stock for exceptional cases)
drop policy if exists dealer_stock_admin on dealer_stock;
create policy dealer_stock_admin on dealer_stock for all
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- === SALE_TRANSACTIONS ===
-- Dealer: SELECT own rows only
drop policy if exists sale_transactions_own on sale_transactions;
create policy sale_transactions_own on sale_transactions for select
  using (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid);
-- Admin: SELECT all
drop policy if exists sale_transactions_admin on sale_transactions;
create policy sale_transactions_admin on sale_transactions for select
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
-- Inserts are done via RPC (security definer)

-- === SALE_ITEMS ===
-- Dealer: SELECT own via transaction
drop policy if exists sale_items_own on sale_items;
create policy sale_items_own on sale_items for select
  using (exists (select 1 from sale_transactions st where st.id = transaction_id
          and st.dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid));
-- Admin: SELECT all
drop policy if exists sale_items_admin on sale_items;
create policy sale_items_admin on sale_items for select
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
-- Inserts are done via RPC (security definer)

-- === ORDERS ===
-- Dealer: SELECT own, INSERT pending only (no UPDATE/DELETE — status changes via RPC)
drop policy if exists orders_own_select on orders;
create policy orders_own_select on orders for select
  using (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid);
drop policy if exists orders_own_insert on orders;
create policy orders_own_insert on orders for insert
  with check (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid
              and status = 'pending');
-- Admin: SELECT all, no direct writes (approve/reject via RPC)
drop policy if exists orders_admin_select on orders;
create policy orders_admin_select on orders for select
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- === ORDER_ITEMS ===
-- Dealer: SELECT own via order, INSERT own pending order items
drop policy if exists order_items_own_select on order_items;
create policy order_items_own_select on order_items for select
  using (exists (select 1 from orders o where o.id = order_id
          and o.dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid));
drop policy if exists order_items_own_insert on order_items;
create policy order_items_own_insert on order_items for insert
  with check (exists (select 1 from orders o where o.id = order_id
              and o.dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid
              and o.status = 'pending'));
-- Admin: SELECT all
drop policy if exists order_items_admin_select on order_items;
create policy order_items_admin_select on order_items for select
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- === RETURNS ===
-- Dealer: SELECT own, INSERT pending only (no UPDATE/DELETE)
drop policy if exists returns_own_select on returns;
create policy returns_own_select on returns for select
  using (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid);
drop policy if exists returns_own_insert on returns;
create policy returns_own_insert on returns for insert
  with check (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid
              and status = 'pending');
-- Admin: SELECT all
drop policy if exists returns_admin_select on returns;
create policy returns_admin_select on returns for select
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- === RETURN_ITEMS ===
-- Dealer: SELECT own via return, INSERT own pending return items
drop policy if exists return_items_own_select on return_items;
create policy return_items_own_select on return_items for select
  using (exists (select 1 from returns r where r.id = return_id
          and r.dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid));
drop policy if exists return_items_own_insert on return_items;
create policy return_items_own_insert on return_items for insert
  with check (exists (select 1 from returns r where r.id = return_id
              and r.dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid
              and r.status = 'pending'));
-- Admin: SELECT all
drop policy if exists return_items_admin_select on return_items;
create policy return_items_admin_select on return_items for select
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- === STOCK_MOVEMENTS ===
-- Dealer: SELECT own rows only (append-only, created by RPCs)
drop policy if exists stock_movements_own_read on stock_movements;
create policy stock_movements_own_read on stock_movements for select
  using (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid);
-- Admin: SELECT all
drop policy if exists stock_movements_admin_select on stock_movements;
create policy stock_movements_admin_select on stock_movements for select
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
-- Inserts are done via RPCs (security definer)

-- ----------------------------------------------------------------------------
-- 4. Storage policies — create a PUBLIC bucket named "product-images" first
--    (Dashboard → Storage → New bucket → name: product-images → Public)
-- ----------------------------------------------------------------------------

do $$ begin
  drop policy if exists "product images public read" on storage.objects;
  drop policy if exists "product images admin insert" on storage.objects;
  drop policy if exists "product images admin update" on storage.objects;
  drop policy if exists "product images admin delete" on storage.objects;
exception when undefined_object then null; end $$;

create policy "product images public read" on storage.objects for select
  using (bucket_id = 'product-images');
create policy "product images admin insert" on storage.objects for insert
  with check (bucket_id = 'product-images'
              and (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy "product images admin update" on storage.objects for update
  using (bucket_id = 'product-images'
         and (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy "product images admin delete" on storage.objects for delete
  using (bucket_id = 'product-images'
         and (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- ----------------------------------------------------------------------------
-- 5. RPCs — all stock math lives here (atomic, one transaction each).
-- Browser pages call: supabase.rpc("<name>", { p_... })
-- ----------------------------------------------------------------------------

-- Dealer records a sale: ONE atomic transaction for ALL items.
-- Uses sale_transactions + sale_items instead of flat sales rows.
-- p_items: '[{"product_id":"<uuid>","quantity":3}, …]'
-- Dealer identity comes from the JWT claim, so a dealer can only ever touch
-- their own stock. Replaying the same p_client_ref does nothing (replay flag).
drop function if exists record_sale(jsonb, uuid);
create or replace function record_sale(p_items jsonb, p_client_ref uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_dealer uuid := (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid;
  item     jsonb;
  v_before int;
  v_txn    uuid;
  v_items  jsonb := '[]'::jsonb;
begin
  if v_dealer is null then
    raise exception 'FORBIDDEN: no dealer_id in JWT';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'VALIDATION_ERROR: items must be a non-empty array';
  end if;

  -- Replay guard: if this client_ref was already processed, return early
  if p_client_ref is not null then
    select id into v_txn from sale_transactions where client_ref = p_client_ref;
    if v_txn is not null then
      return jsonb_build_object('replayed', true);
    end if;
  end if;

  -- Create transaction header
  insert into sale_transactions (dealer_id, client_ref)
    values (v_dealer, p_client_ref)
    returning id into v_txn;

  for item in select * from jsonb_array_elements(p_items)
  loop
    if coalesce((item->>'quantity')::int, 0) <= 0 then
      raise exception 'VALIDATION_ERROR: quantity must be a positive integer';
    end if;
    if (item->>'quantity')::int > 10000 then
      raise exception 'VALIDATION_ERROR: quantity exceeds maximum of 10000 per item';
    end if;

    -- Validate product exists and is active
    if not exists (select 1 from products where id = (item->>'product_id')::uuid and is_active = true) then
      raise exception 'VALIDATION_ERROR: product % is inactive or does not exist', item->>'product_id';
    end if;

    select quantity into v_before from dealer_stock
     where dealer_id = v_dealer and product_id = (item->>'product_id')::uuid;
    v_before := coalesce(v_before, 0);

    update dealer_stock
       set quantity = quantity - (item->>'quantity')::int, updated_at = now()
     where dealer_id = v_dealer and product_id = (item->>'product_id')::uuid
       and quantity >= (item->>'quantity')::int;
    if not found then
      if v_before < (item->>'quantity')::int then
        raise exception 'INSUFFICIENT_STOCK: product % has only % units', (item->>'product_id'), v_before;
      end if;
      raise exception 'CONCURRENT_MODIFICATION';
    end if;

    insert into sale_items (transaction_id, product_id, quantity)
      values (v_txn, (item->>'product_id')::uuid, (item->>'quantity')::int);

    insert into stock_movements (dealer_id, product_id, quantity, movement_type, reference_id, actor_user_id)
      values (v_dealer, (item->>'product_id')::uuid, -(item->>'quantity')::int, 'SALE', v_txn, auth.uid());

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'product_id', item->>'product_id',
      'quantity_before', v_before,
      'quantity_after', v_before - (item->>'quantity')::int));
  end loop;

  return jsonb_build_object('replayed', false, 'items', v_items);
end $$;

-- Dealer creates an order atomically: order + items in one transaction.
-- p_items: '[{"product_id":"<uuid>","quantity":3}, …]'
drop function if exists create_order(jsonb, uuid);
create or replace function create_order(p_items jsonb, p_client_ref uuid default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_dealer uuid := (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid;
  v_order  uuid;
  item     jsonb;
begin
  if v_dealer is null then
    raise exception 'FORBIDDEN: no dealer_id in JWT';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'VALIDATION_ERROR: items must be a non-empty array';
  end if;

  -- Auto-generate client_ref if null (prevents unlimited idempotency bypass)
  if p_client_ref is null then
    p_client_ref := gen_random_uuid();
  end if;

  -- Replay guard
  if p_client_ref is not null and exists (select 1 from orders where client_ref = p_client_ref) then
    select id into v_order from orders where client_ref = p_client_ref;
    return v_order;
  end if;

  insert into orders (dealer_id, client_ref, status)
    values (v_dealer, p_client_ref, 'pending')
    returning id into v_order;

  for item in select * from jsonb_array_elements(p_items)
  loop
    if coalesce((item->>'quantity')::int, 0) <= 0 then
      raise exception 'VALIDATION_ERROR: quantity must be a positive integer';
    end if;
    if (item->>'quantity')::int > 10000 then
      raise exception 'VALIDATION_ERROR: quantity exceeds maximum of 10000 per item';
    end if;
    if not exists (select 1 from products where id = (item->>'product_id')::uuid and is_active = true) then
      raise exception 'VALIDATION_ERROR: product % is inactive or does not exist', item->>'product_id';
    end if;
    insert into order_items (order_id, product_id, quantity)
      values (v_order, (item->>'product_id')::uuid, (item->>'quantity')::int);
  end loop;

  return v_order;
end $$;

-- Dealer creates a return atomically: return + items in one transaction.
-- p_items: '[{"product_id":"<uuid>","quantity":3}, …]'
drop function if exists create_return(jsonb, uuid);
create or replace function create_return(p_items jsonb, p_client_ref uuid default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_dealer uuid := (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid;
  v_return uuid;
  item     jsonb;
begin
  if v_dealer is null then
    raise exception 'FORBIDDEN: no dealer_id in JWT';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'VALIDATION_ERROR: items must be a non-empty array';
  end if;

  -- Auto-generate client_ref if null (prevents unlimited idempotency bypass)
  if p_client_ref is null then
    p_client_ref := gen_random_uuid();
  end if;

  -- Replay guard
  if p_client_ref is not null and exists (select 1 from returns where client_ref = p_client_ref) then
    select id into v_return from returns where client_ref = p_client_ref;
    return v_return;
  end if;

  insert into returns (dealer_id, client_ref, status)
    values (v_dealer, p_client_ref, 'pending')
    returning id into v_return;

  for item in select * from jsonb_array_elements(p_items)
  loop
    if coalesce((item->>'quantity')::int, 0) <= 0 then
      raise exception 'VALIDATION_ERROR: quantity must be a positive integer';
    end if;
    if (item->>'quantity')::int > 10000 then
      raise exception 'VALIDATION_ERROR: quantity exceeds maximum of 10000 per item';
    end if;
    if not exists (select 1 from products where id = (item->>'product_id')::uuid and is_active = true) then
      raise exception 'VALIDATION_ERROR: product % is inactive or does not exist', item->>'product_id';
    end if;
    -- Verify dealer actually holds this product before allowing return
    if not exists (select 1 from dealer_stock where dealer_id = v_dealer and product_id = (item->>'product_id')::uuid and quantity >= (item->>'quantity')::int) then
      raise exception 'INSUFFICIENT_STOCK: dealer does not hold enough of product %', item->>'product_id';
    end if;
    insert into return_items (return_id, product_id, quantity)
      values (v_return, (item->>'product_id')::uuid, (item->>'quantity')::int);
  end loop;

  return v_return;
end $$;

-- Admin approves an order: order pending -> sent, dealer stock += items.
drop function if exists approve_order(uuid);
create or replace function approve_order(p_order uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  r        record;
  v_dealer uuid;
  v_actor  uuid := auth.uid();
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') is distinct from 'admin' then
    raise exception 'FORBIDDEN';
  end if;

  select dealer_id into v_dealer from orders where id = p_order;
  if v_dealer is null then
    raise exception 'NOT_FOUND';
  end if;

  update orders set status = 'sent', approved_at = now(), fulfilled_at = now()
   where id = p_order and status = 'pending';
  if not found then
    raise exception 'ORDER_NOT_PENDING';
  end if;

  for r in select product_id, quantity from order_items where order_id = p_order
  loop
    insert into dealer_stock (dealer_id, product_id, quantity)
      values (v_dealer, r.product_id, r.quantity)
    on conflict (dealer_id, product_id)
      do update set quantity = dealer_stock.quantity + excluded.quantity,
                    updated_at = now();

    insert into stock_movements (dealer_id, product_id, quantity, movement_type, reference_id, actor_user_id)
      values (v_dealer, r.product_id, r.quantity, 'ORDER', p_order, v_actor);
  end loop;
end $$;

-- Admin rejects a pending order (no stock movement).
drop function if exists reject_order(uuid);
create or replace function reject_order(p_order uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') is distinct from 'admin' then
    raise exception 'FORBIDDEN';
  end if;
  update orders set status = 'rejected'
   where id = p_order and status = 'pending';
  if not found then
    raise exception 'ORDER_NOT_PENDING';
  end if;
end $$;

-- Admin accepts a return after physical receipt: dealer stock -= items.
drop function if exists accept_return(uuid);
create or replace function accept_return(p_return uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  r        record;
  v_dealer uuid;
  v_actor  uuid := auth.uid();
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') is distinct from 'admin' then
    raise exception 'FORBIDDEN';
  end if;

  select dealer_id into v_dealer from returns where id = p_return;
  if v_dealer is null then
    raise exception 'NOT_FOUND';
  end if;

  update returns set status = 'accepted', accepted_at = now()
   where id = p_return and status = 'pending';
  if not found then
    raise exception 'RETURN_NOT_PENDING';
  end if;

  for r in select product_id, quantity from return_items where return_id = p_return
  loop
    update dealer_stock
       set quantity = quantity - r.quantity, updated_at = now()
     where dealer_id = v_dealer and product_id = r.product_id
       and quantity >= r.quantity;
    if not found then
      raise exception 'INSUFFICIENT_STOCK';
    end if;

    insert into stock_movements (dealer_id, product_id, quantity, movement_type, reference_id, actor_user_id)
      values (v_dealer, r.product_id, -r.quantity, 'RETURN', p_return, v_actor);
  end loop;
end $$;

-- Admin rejects a pending return (no stock movement).
drop function if exists reject_return(uuid);
create or replace function reject_return(p_return uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') is distinct from 'admin' then
    raise exception 'FORBIDDEN';
  end if;
  update returns set status = 'rejected'
   where id = p_return and status = 'pending';
  if not found then
    raise exception 'RETURN_NOT_PENDING';
  end if;
end $$;

-- Admin directly allocates stock to a dealer (no request needed).
-- p_items: '[{"product_id":"<uuid>","quantity":3}, …]' — one transaction.
drop function if exists allocate_stock(uuid, jsonb);
create or replace function allocate_stock(p_dealer uuid, p_items jsonb)
returns int
language plpgsql security definer set search_path = public as $$
declare
  item   jsonb;
  n      int := 0;
  v_actor uuid := auth.uid();
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') is distinct from 'admin' then
    raise exception 'FORBIDDEN';
  end if;
  if not exists (select 1 from dealers where id = p_dealer and deleted_at is null and is_active = true) then
    raise exception 'VALIDATION_ERROR: dealer not found or inactive';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'VALIDATION_ERROR: items must be a non-empty array';
  end if;

  for item in select * from jsonb_array_elements(p_items)
  loop
    if coalesce((item->>'quantity')::int, 0) <= 0 then
      raise exception 'VALIDATION_ERROR: quantity must be a positive integer';
    end if;
    if (item->>'quantity')::int > 10000 then
      raise exception 'VALIDATION_ERROR: quantity exceeds maximum of 10000 per item';
    end if;

    insert into dealer_stock (dealer_id, product_id, quantity)
      values (p_dealer, (item->>'product_id')::uuid, (item->>'quantity')::int)
    on conflict (dealer_id, product_id)
      do update set quantity = dealer_stock.quantity + excluded.quantity,
                    updated_at = now();

    insert into stock_movements (dealer_id, product_id, quantity, movement_type, actor_user_id)
      values (p_dealer, (item->>'product_id')::uuid, (item->>'quantity')::int, 'ALLOCATION', v_actor);
    n := n + 1;
  end loop;
  return n;
end $$;

-- Admin moves stock between dealers (single transaction: subtract source,
-- add target, paired REDISTRIBUTE movements sharing one reference id;
-- any failure rolls back all items).
-- p_items: '[{"product_id":"<uuid>","quantity":3}, …]'
drop function if exists redistribute_stock(uuid, uuid, jsonb);
create or replace function redistribute_stock(p_from_dealer uuid, p_to_dealer uuid, p_items jsonb)
returns int
language plpgsql security definer set search_path = public as $$
declare
  item      jsonb;
  n         int := 0;
  redist_id uuid := gen_random_uuid();
  v_actor   uuid := auth.uid();
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') is distinct from 'admin' then
    raise exception 'FORBIDDEN';
  end if;
  if p_from_dealer = p_to_dealer then
    raise exception 'VALIDATION_ERROR: dealers must differ';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'VALIDATION_ERROR: items must be a non-empty array';
  end if;

  for item in select * from jsonb_array_elements(p_items)
  loop
    if coalesce((item->>'quantity')::int, 0) <= 0 then
      raise exception 'VALIDATION_ERROR: quantity must be a positive integer';
    end if;
    if (item->>'quantity')::int > 10000 then
      raise exception 'VALIDATION_ERROR: quantity exceeds maximum of 10000 per item';
    end if;

    update dealer_stock
       set quantity = quantity - (item->>'quantity')::int, updated_at = now()
     where dealer_id = p_from_dealer and product_id = (item->>'product_id')::uuid
       and quantity >= (item->>'quantity')::int;
    if not found then
      raise exception 'INSUFFICIENT_STOCK';
    end if;

    insert into dealer_stock (dealer_id, product_id, quantity)
      values (p_to_dealer, (item->>'product_id')::uuid, (item->>'quantity')::int)
    on conflict (dealer_id, product_id)
      do update set quantity = dealer_stock.quantity + excluded.quantity,
                    updated_at = now();

    insert into stock_movements (dealer_id, product_id, quantity, movement_type, reference_id, actor_user_id)
      values (p_from_dealer, (item->>'product_id')::uuid, -(item->>'quantity')::int, 'REDISTRIBUTE', redist_id, v_actor),
             (p_to_dealer,   (item->>'product_id')::uuid,  (item->>'quantity')::int, 'REDISTRIBUTE', redist_id, v_actor);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ----------------------------------------------------------------------------
-- 7. Hard-delete prevention triggers
-- Prevents direct DELETE on tables that have soft-delete (deleted_at column).
-- Forces application to use soft-delete instead.
-- ----------------------------------------------------------------------------

create or replace function prevent_hard_delete() returns trigger as $$
begin
  raise exception 'HARD_DELETE_BLOCKED: use soft-delete (SET deleted_at = now()) instead of DELETE on %', TG_TABLE_NAME;
  return null;
end $$;

drop trigger if exists trg_prevent_dealer_hard_delete on dealers;
create trigger trg_prevent_dealer_hard_delete
  before delete on dealers
  for each row execute function prevent_hard_delete();

drop trigger if exists trg_prevent_product_hard_delete on products;
create trigger trg_prevent_product_hard_delete
  before delete on products
  for each row execute function prevent_hard_delete();

do $$
begin
  alter publication supabase_realtime add table dealer_stock;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
