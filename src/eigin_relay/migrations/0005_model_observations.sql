-- Content-free operational observations, bounded per model by the writer.
CREATE TABLE model_observations (
    id BIGSERIAL PRIMARY KEY,
    model_id TEXT NOT NULL,
    source TEXT NOT NULL CHECK (source IN ('traffic', 'probe')),
    observed_at_ms BIGINT NOT NULL,
    outcome TEXT NOT NULL,
    ttft_ms DOUBLE PRECISION,
    tps DOUBLE PRECISION
);
CREATE INDEX model_observations_model_time ON model_observations (model_id, observed_at_ms DESC);

CREATE TABLE model_probe_slots (
    model_id TEXT PRIMARY KEY,
    claimed_slot BIGINT NOT NULL DEFAULT -1,
    last_traffic_ms BIGINT
);
