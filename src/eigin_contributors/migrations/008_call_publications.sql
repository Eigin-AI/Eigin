CREATE TABLE call_publications (
  call_slug text PRIMARY KEY REFERENCES call_selections(call_slug),
  public_snapshot jsonb NOT NULL CHECK (jsonb_typeof(public_snapshot) = 'object'),
  snapshot_sha256 text NOT NULL,
  published_by_user_id bigint NOT NULL REFERENCES users(id),
  published_by_gitlab_id bigint NOT NULL,
  published_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  mode text NOT NULL CHECK (mode = 'rehearsal')
);
CREATE TABLE publication_confirmations (
  token_hash text PRIMARY KEY,
  call_slug text NOT NULL REFERENCES call_selections(call_slug),
  reviewer_user_id bigint NOT NULL REFERENCES users(id),
  session_hash text NOT NULL REFERENCES sessions(token_hash) ON DELETE CASCADE,
  snapshot_sha256 text NOT NULL,
  expires_at timestamptz NOT NULL,
  UNIQUE (call_slug, reviewer_user_id, session_hash)
);
CREATE INDEX publication_confirmation_expiry ON publication_confirmations(expires_at);
