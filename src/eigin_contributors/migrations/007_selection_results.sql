CREATE TABLE selection_drafts (
  call_slug text PRIMARY KEY REFERENCES call_contracts(slug),
  version bigint NOT NULL CHECK (version > 0),
  selected_submission_id bigint NOT NULL,
  selected_revision_id bigint NOT NULL,
  runner_up_submission_id bigint NOT NULL,
  runner_up_revision_id bigint NOT NULL,
  copy jsonb NOT NULL CHECK (jsonb_typeof(copy) = 'object'),
  updated_by_gitlab_id bigint NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (selected_submission_id <> runner_up_submission_id),
  FOREIGN KEY (call_slug, selected_submission_id) REFERENCES submissions(call_slug, id),
  FOREIGN KEY (call_slug, runner_up_submission_id) REFERENCES submissions(call_slug, id),
  FOREIGN KEY (selected_submission_id, selected_revision_id) REFERENCES submission_revisions(submission_id, id),
  FOREIGN KEY (runner_up_submission_id, runner_up_revision_id) REFERENCES submission_revisions(submission_id, id)
);

-- Old temporary confirmations did not include results copy and must be reviewed again.
DELETE FROM selection_confirmations;
ALTER TABLE selection_confirmations ADD COLUMN draft_version bigint NOT NULL;
ALTER TABLE call_selections ADD COLUMN results_copy jsonb;
ALTER TABLE call_selections ADD COLUMN results_version bigint;
