CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_hash TEXT NOT NULL UNIQUE,
    token_ciphertext TEXT NOT NULL,
    origin TEXT NOT NULL,
    fingerprint TEXT NOT NULL,
    product_id TEXT NOT NULL,
    initial_millicredits BIGINT NOT NULL,
    balance_millicredits BIGINT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (origin, fingerprint)
);
