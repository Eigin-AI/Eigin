-- Rolling-window usage quota, stored as daily counters.
-- One row per (key, UTC day) holds that day's total.
-- Backs the search community pool and the Apple Sandbox credit-issuance budget.
CREATE TABLE quota_buckets (
    key    TEXT   NOT NULL,
    bucket DATE   NOT NULL,
    used   BIGINT NOT NULL,
    PRIMARY KEY (key, bucket)
);
