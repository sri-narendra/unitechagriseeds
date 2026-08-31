-- Hard-delete prevention triggers for dealers and products
-- Idempotent: uses CREATE OR REPLACE / DROP TRIGGER IF EXISTS

CREATE OR REPLACE FUNCTION prevent_hard_delete()
RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'Hard deletes are not allowed on this table. Use soft delete (SET deleted_at).';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_dealer_hard_delete ON dealers;
CREATE TRIGGER trg_prevent_dealer_hard_delete
  BEFORE DELETE ON dealers
  FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();

DROP TRIGGER IF EXISTS trg_prevent_product_hard_delete ON products;
CREATE TRIGGER trg_prevent_product_hard_delete
  BEFORE DELETE ON products
  FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
