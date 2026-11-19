ALTER TABLE submissions ADD CONSTRAINT submission_call_id UNIQUE (call_slug, id);

CREATE TABLE call_selections (
  call_slug text PRIMARY KEY REFERENCES call_contracts(slug),
  contract_sha256 text NOT NULL,
  selected_submission_id bigint NOT NULL,
  selected_revision_id bigint NOT NULL,
  runner_up_submission_id bigint NOT NULL,
  runner_up_revision_id bigint NOT NULL,
  selected_amount_minor bigint NOT NULL CHECK (selected_amount_minor > 0),
  runner_up_amount_minor bigint NOT NULL CHECK (runner_up_amount_minor > 0),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  mode text NOT NULL CHECK (mode = 'rehearsal'),
  confirmed_by_user_id bigint NOT NULL REFERENCES users(id),
  confirmed_by_gitlab_id bigint NOT NULL,
  confirmed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (selected_submission_id <> runner_up_submission_id),
  FOREIGN KEY (call_slug, selected_submission_id) REFERENCES submissions(call_slug, id),
  FOREIGN KEY (call_slug, runner_up_submission_id) REFERENCES submissions(call_slug, id),
  FOREIGN KEY (selected_submission_id, selected_revision_id) REFERENCES submission_revisions(submission_id, id),
  FOREIGN KEY (runner_up_submission_id, runner_up_revision_id) REFERENCES submission_revisions(submission_id, id)
);

CREATE TABLE selection_confirmations (
  token_hash text PRIMARY KEY,
  call_slug text NOT NULL REFERENCES call_contracts(slug),
  reviewer_user_id bigint NOT NULL REFERENCES users(id),
  session_hash text NOT NULL REFERENCES sessions(token_hash) ON DELETE CASCADE,
  contract_sha256 text NOT NULL,
  selected_submission_id bigint NOT NULL,
  selected_revision_id bigint NOT NULL,
  runner_up_submission_id bigint NOT NULL,
  runner_up_revision_id bigint NOT NULL,
  expires_at timestamptz NOT NULL,
  UNIQUE (call_slug, reviewer_user_id, session_hash),
  CHECK (selected_submission_id <> runner_up_submission_id),
  FOREIGN KEY (call_slug, selected_submission_id) REFERENCES submissions(call_slug, id),
  FOREIGN KEY (call_slug, runner_up_submission_id) REFERENCES submissions(call_slug, id),
  FOREIGN KEY (selected_submission_id, selected_revision_id) REFERENCES submission_revisions(submission_id, id),
  FOREIGN KEY (runner_up_submission_id, runner_up_revision_id) REFERENCES submission_revisions(submission_id, id)
);
CREATE INDEX selection_confirmation_expiry ON selection_confirmations(expires_at);
