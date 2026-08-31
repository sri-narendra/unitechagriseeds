-- Run this in Supabase Dashboard → SQL Editor
-- Adds soft-delete support: product "delete" sets deleted_at instead of removing the row.
-- History (dealer_stock, sale_items, order_items, return_items) stays intact.

ALTER TABLE products ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
