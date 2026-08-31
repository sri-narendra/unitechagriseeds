-- Fix stale RLS policies that allow dealer direct writes.
-- The schema.sql drop policy if exists only drops by exact name.
-- Old policies with different names survived. This script drops ALL
-- policies on affected tables and recreates the correct ones.
-- Run in: Supabase Dashboard -> SQL Editor

-- === ORDERS: drop ALL policies, recreate correct ones ===
DO $$ DECLARE r RECORD; BEGIN
  FOR r SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='orders' LOOP
    EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON orders';
  END LOOP;
END $$;

-- Dealer: SELECT own rows
CREATE POLICY orders_own_select ON orders FOR select
  USING (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid);
-- Dealer: INSERT pending only (no UPDATE/DELETE)
CREATE POLICY orders_own_insert ON orders FOR insert
  WITH CHECK (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid
              AND status = 'pending');
-- Admin: SELECT all
CREATE POLICY orders_admin_select ON orders FOR select
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- === SALE_TRANSACTIONS: drop ALL policies, recreate correct ones ===
DO $$ DECLARE r RECORD; BEGIN
  FOR r SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='sale_transactions' LOOP
    EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON sale_transactions';
  END LOOP;
END $$;

-- Dealer: SELECT own rows only
CREATE POLICY sale_transactions_own ON sale_transactions FOR select
  USING (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid);
-- Admin: SELECT all
CREATE POLICY sale_transactions_admin ON sale_transactions FOR select
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
-- Inserts are done via RPC (security definer) — no INSERT policy for dealers

-- === SALE_ITEMS: drop ALL policies, recreate correct ones ===
DO $$ DECLARE r RECORD; BEGIN
  FOR r SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='sale_items' LOOP
    EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON sale_items';
  END LOOP;
END $$;

-- Dealer: SELECT own via transaction
CREATE POLICY sale_items_own ON sale_items FOR select
  USING (exists (select 1 from sale_transactions st where st.id = transaction_id
          and st.dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid));
-- Admin: SELECT all
CREATE POLICY sale_items_admin ON sale_items FOR select
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- === STOCK_MOVEMENTS: drop ALL policies, recreate correct ones ===
DO $$ DECLARE r RECORD; BEGIN
  FOR r SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='stock_movements' LOOP
    EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON stock_movements';
  END LOOP;
END $$;

-- Dealer: SELECT own rows only
CREATE POLICY stock_movements_own_read ON stock_movements FOR select
  USING (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid);
-- Admin: SELECT all
CREATE POLICY stock_movements_admin_select ON stock_movements FOR select
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
-- Inserts are done via RPCs (security definer) — no INSERT policy for dealers

-- === DEALER_STOCK: drop ALL policies, recreate correct ones ===
DO $$ DECLARE r RECORD; BEGIN
  FOR r SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='dealer_stock' LOOP
    EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON dealer_stock';
  END LOOP;
END $$;

-- Dealer: SELECT own rows only (NO direct writes)
CREATE POLICY dealer_stock_own_read ON dealer_stock FOR select
  USING (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid);
-- Admin: full CRUD
CREATE POLICY dealer_stock_admin ON dealer_stock FOR all
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- === RETURNS: drop ALL policies, recreate correct ones ===
DO $$ DECLARE r RECORD; BEGIN
  FOR r SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='returns' LOOP
    EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON returns';
  END LOOP;
END $$;

-- Dealer: SELECT own, INSERT pending only (no UPDATE/DELETE)
CREATE POLICY returns_own_select ON returns FOR select
  USING (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid);
CREATE POLICY returns_own_insert ON returns FOR insert
  WITH CHECK (dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid
              AND status = 'pending');
-- Admin: SELECT all
CREATE POLICY returns_admin_select ON returns FOR select
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- === RETURN_ITEMS: drop ALL policies, recreate correct ones ===
DO $$ DECLARE r RECORD; BEGIN
  FOR r SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='return_items' LOOP
    EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON return_items';
  END LOOP;
END $$;

-- Dealer: SELECT own via return, INSERT own pending return items
CREATE POLICY return_items_own_select ON return_items FOR select
  USING (exists (select 1 from returns r where r.id = return_id
          and r.dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid));
CREATE POLICY return_items_own_insert ON return_items FOR insert
  WITH CHECK (exists (select 1 from returns r where r.id = return_id
              and r.dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid
              and r.status = 'pending'));
-- Admin: SELECT all
CREATE POLICY return_items_admin_select ON return_items FOR select
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- === ORDER_ITEMS: drop ALL policies, recreate correct ones ===
DO $$ DECLARE r RECORD; BEGIN
  FOR r SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='order_items' LOOP
    EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON order_items';
  END LOOP;
END $$;

-- Dealer: SELECT own via order, INSERT own pending order items
CREATE POLICY order_items_own_select ON order_items FOR select
  USING (exists (select 1 from orders o where o.id = order_id
          and o.dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid));
CREATE POLICY order_items_own_insert ON order_items FOR insert
  WITH CHECK (exists (select 1 from orders o where o.id = order_id
              and o.dealer_id = (auth.jwt() -> 'app_metadata' ->> 'dealer_id')::uuid
              and o.status = 'pending'));
-- Admin: SELECT all
CREATE POLICY order_items_admin_select ON order_items FOR select
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- Verify: show all policies on affected tables
SELECT tablename, policyname, cmd, qual IS NOT NULL as has_using, with_check IS NOT NULL as has_check
FROM pg_policies
WHERE schemaname='public'
  AND tablename IN ('orders','sale_transactions','sale_items','stock_movements','dealer_stock','returns','return_items','order_items')
ORDER BY tablename, policyname;
