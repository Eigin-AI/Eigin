CREATE TABLE users (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  gitlab_user_id bigint NOT NULL UNIQUE CHECK (gitlab_user_id > 0),
  gitlab_username text NOT NULL,
  display_name text NOT NULL
);
CREATE TABLE sessions (
  token_hash text PRIMARY KEY,
  user_id bigint NOT NULL REFERENCES users(id),
  expires_at timestamptz NOT NULL
);
CREATE TABLE oauth_attempts (
  binding_hash text PRIMARY KEY,
  state_hash text NOT NULL,
  verifier text NOT NULL,
  expires_at timestamptz NOT NULL
);
