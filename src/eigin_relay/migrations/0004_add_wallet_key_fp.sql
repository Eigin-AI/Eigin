-- Records which encryption key each wallet's token_ciphertext is under, so a key
-- rotation can find rows still on an old key and confirm a sweep has drained.
-- The value is a short fingerprint of the key (hex of the first 8 bytes of its
-- SHA-256), not the key itself. Nullable: existing rows are stamped by a one-time
-- backfill on relay startup, and new rows set it on insert.
ALTER TABLE wallets ADD COLUMN key_fp TEXT;
