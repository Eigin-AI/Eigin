CREATE TABLE call_contracts (
  slug text PRIMARY KEY,
  sha256 text NOT NULL,
  snapshot jsonb NOT NULL
);
CREATE TABLE agreement_snapshots (
  sha256 text PRIMARY KEY,
  version text NOT NULL,
  body text NOT NULL
);
CREATE TABLE submissions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  call_slug text NOT NULL REFERENCES call_contracts(slug),
  user_id bigint NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  current_revision_id bigint,
  UNIQUE(call_slug, user_id)
);
CREATE TABLE submission_revisions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  submission_id bigint NOT NULL REFERENCES submissions(id),
  markdown text NOT NULL,
  filename text NOT NULL,
  sha256 text NOT NULL,
  received_at timestamptz NOT NULL,
  contact_email text NOT NULL,
  author_name text NOT NULL,
  author_email text NOT NULL,
  cla_sha256 text NOT NULL REFERENCES agreement_snapshots(sha256),
  terms_sha256 text NOT NULL REFERENCES agreement_snapshots(sha256),
  consent jsonb NOT NULL,
  UNIQUE(submission_id, id)
);
ALTER TABLE submissions ADD CONSTRAINT current_revision_belongs_to_submission
  FOREIGN KEY (id, current_revision_id) REFERENCES submission_revisions(submission_id, id);
