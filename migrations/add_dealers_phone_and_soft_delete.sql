ALTER TABLE dealers ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE dealers ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
