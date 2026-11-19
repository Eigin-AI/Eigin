CREATE TABLE call_contract_history (
  call_slug text NOT NULL REFERENCES call_contracts(slug),
  sha256 text NOT NULL,
  snapshot jsonb NOT NULL,
  superseded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (call_slug, sha256)
);
