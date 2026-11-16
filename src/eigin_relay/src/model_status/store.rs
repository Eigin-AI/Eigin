//! Shared observation retention and atomic idle-probe claims.

use super::{Observation, Outcome, Source};
use async_trait::async_trait;
use sqlx::{PgPool, Row};
use std::collections::HashMap;
use tokio::sync::Mutex;

/// Storage boundary for content-free health observations.
#[async_trait]
pub trait StatusStore: Send + Sync {
    /// Record one terminal observation and bound retained history.
    async fn record(&self, observation: Observation) -> Result<(), sqlx::Error>;
    /// Read retained observations; aggregation excludes expired samples.
    async fn observations(&self, cutoff_ms: i64) -> Result<Vec<Observation>, sqlx::Error>;
    /// Reserve the current slot only when the model has no recent traffic.
    async fn claim_probe(&self, model: &str, interval_ms: i64) -> Result<bool, sqlx::Error>;
}

/// Process-local implementation for development and tests.
#[derive(Default)]
pub struct MemoryStatusStore(Mutex<MemoryState>);

#[derive(Default)]
struct MemoryState {
    samples: Vec<Observation>,
    slots: HashMap<String, i64>,
    traffic: HashMap<String, i64>,
}

/// Current UTC Unix milliseconds.
pub fn now_ms() -> i64 {
    (time::OffsetDateTime::now_utc().unix_timestamp_nanos() / 1_000_000) as i64
}

#[async_trait]
impl StatusStore for MemoryStatusStore {
    async fn record(&self, observation: Observation) -> Result<(), sqlx::Error> {
        let mut state = self.0.lock().await;
        if observation.source == Source::Traffic {
            let previous = state
                .traffic
                .entry(observation.model_id.clone())
                .or_default();
            *previous = (*previous).max(observation.observed_at_ms);
        }
        let model = observation.model_id.clone();
        let source = observation.source;
        state.samples.push(observation);
        state
            .samples
            .sort_by_key(|sample| std::cmp::Reverse(sample.observed_at_ms));
        let mut count = 0;
        state.samples.retain(|sample| {
            if sample.model_id != model || sample.source != source {
                return true;
            }
            count += 1;
            count <= if source == Source::Traffic { 128 } else { 1 }
        });
        Ok(())
    }

    async fn observations(&self, cutoff_ms: i64) -> Result<Vec<Observation>, sqlx::Error> {
        let mut state = self.0.lock().await;
        state
            .samples
            .retain(|sample| sample.observed_at_ms > cutoff_ms);
        Ok(state.samples.clone())
    }

    async fn claim_probe(&self, model: &str, interval_ms: i64) -> Result<bool, sqlx::Error> {
        let now = now_ms();
        let slot = now / interval_ms;
        let mut state = self.0.lock().await;
        if state
            .slots
            .get(model)
            .is_some_and(|previous| *previous >= slot)
            || state
                .traffic
                .get(model)
                .is_some_and(|last| *last > now - interval_ms)
        {
            return Ok(false);
        }
        state.slots.insert(model.into(), slot);
        Ok(true)
    }
}

/// Cross-replica observations and probe coordination using the shared pool.
pub struct PostgresStatusStore(pub PgPool);

#[async_trait]
impl StatusStore for PostgresStatusStore {
    async fn record(&self, sample: Observation) -> Result<(), sqlx::Error> {
        let mut tx = self.0.begin().await?;
        sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 413))")
            .bind(&sample.model_id)
            .execute(&mut *tx)
            .await?;
        let source = if sample.source == Source::Traffic {
            "traffic"
        } else {
            "probe"
        };
        let outcome = match sample.outcome {
            Outcome::Success => "success",
            Outcome::Timeout => "timeout",
            Outcome::Overloaded => "overloaded",
            Outcome::UpstreamFailure => "upstream_failure",
        };
        sqlx::query("INSERT INTO model_observations (model_id, source, observed_at_ms, outcome, ttft_ms, tps) VALUES ($1,$2,$3,$4,$5,$6)")
            .bind(&sample.model_id).bind(source).bind(sample.observed_at_ms).bind(outcome)
            .bind(sample.ttft_ms).bind(sample.tps).execute(&mut *tx).await?;
        sqlx::query("DELETE FROM model_observations WHERE id IN (SELECT id FROM model_observations WHERE model_id=$1 AND source=$2 ORDER BY observed_at_ms DESC, id DESC OFFSET $3)")
            .bind(&sample.model_id).bind(source).bind(if sample.source == Source::Traffic { 128_i64 } else { 1 })
            .execute(&mut *tx).await?;
        if sample.source == Source::Traffic {
            sqlx::query("INSERT INTO model_probe_slots (model_id, last_traffic_ms) VALUES ($1,$2) ON CONFLICT (model_id) DO UPDATE SET last_traffic_ms=GREATEST(model_probe_slots.last_traffic_ms, EXCLUDED.last_traffic_ms)")
                .bind(&sample.model_id).bind(sample.observed_at_ms).execute(&mut *tx).await?;
        }
        tx.commit().await
    }

    async fn observations(&self, cutoff_ms: i64) -> Result<Vec<Observation>, sqlx::Error> {
        sqlx::query("DELETE FROM model_observations WHERE observed_at_ms <= $1")
            .bind(cutoff_ms)
            .execute(&self.0)
            .await?;
        let rows = sqlx::query("SELECT model_id, source, observed_at_ms, outcome, ttft_ms, tps FROM model_observations WHERE observed_at_ms > $1")
            .bind(cutoff_ms).fetch_all(&self.0).await?;
        rows.into_iter()
            .map(|row| {
                Ok(Observation {
                    model_id: row.try_get("model_id")?,
                    source: if row.try_get::<String, _>("source")? == "traffic" {
                        Source::Traffic
                    } else {
                        Source::Probe
                    },
                    observed_at_ms: row.try_get("observed_at_ms")?,
                    outcome: match row.try_get::<String, _>("outcome")?.as_str() {
                        "success" => Outcome::Success,
                        "timeout" => Outcome::Timeout,
                        "overloaded" => Outcome::Overloaded,
                        _ => Outcome::UpstreamFailure,
                    },
                    ttft_ms: row.try_get("ttft_ms")?,
                    tps: row.try_get("tps")?,
                })
            })
            .collect()
    }

    async fn claim_probe(&self, model: &str, interval_ms: i64) -> Result<bool, sqlx::Error> {
        let mut tx = self.0.begin().await?;
        sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 413))")
            .bind(model)
            .execute(&mut *tx)
            .await?;
        let now: i64 =
            sqlx::query_scalar("SELECT (EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::bigint")
                .fetch_one(&mut *tx)
                .await?;
        let changed = sqlx::query("INSERT INTO model_probe_slots (model_id, claimed_slot) VALUES ($1,$2) ON CONFLICT (model_id) DO UPDATE SET claimed_slot=EXCLUDED.claimed_slot WHERE model_probe_slots.claimed_slot < EXCLUDED.claimed_slot AND (model_probe_slots.last_traffic_ms IS NULL OR model_probe_slots.last_traffic_ms <= $3)")
            .bind(model).bind(now / interval_ms).bind(now - interval_ms).execute(&mut *tx).await?.rows_affected();
        tx.commit().await?;
        Ok(changed == 1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn claims_are_shared_by_concurrent_callers() {
        let store = MemoryStatusStore::default();
        let (a, b) = tokio::join!(
            store.claim_probe("model", 900_000),
            store.claim_probe("model", 900_000)
        );
        assert_ne!(a.unwrap(), b.unwrap());
    }

    #[tokio::test]
    async fn recent_traffic_suppresses_probes() {
        let store = MemoryStatusStore::default();
        store
            .record(Observation {
                model_id: "model".into(),
                source: Source::Traffic,
                observed_at_ms: now_ms(),
                outcome: Outcome::Success,
                ttft_ms: None,
                tps: None,
            })
            .await
            .unwrap();
        assert!(!store.claim_probe("model", 900_000).await.unwrap());
    }
}

#[cfg(test)]
mod postgres_tests {
    use super::*;

    #[tokio::test]
    #[ignore = "requires disposable PostgreSQL via DATABASE_URL"]
    async fn shared_storage_bounds_history_and_coordinates_replica_claims() {
        let url = std::env::var("DATABASE_URL").expect("disposable database URL");
        let pool = crate::credits::postgres::connect_and_migrate(&url)
            .await
            .unwrap();
        let a = PostgresStatusStore(pool.clone());
        let b = PostgresStatusStore(pool.clone());
        let model = format!("test-{}", uuid::Uuid::new_v4());
        let (first, second) = tokio::join!(
            a.claim_probe(&model, 900_000),
            b.claim_probe(&model, 900_000)
        );
        assert_ne!(first.unwrap(), second.unwrap());
        let timestamp = now_ms();
        for i in 0..140 {
            a.record(Observation {
                model_id: model.clone(),
                source: Source::Traffic,
                observed_at_ms: timestamp - i,
                outcome: Outcome::Success,
                ttft_ms: Some(100.0),
                tps: None,
            })
            .await
            .unwrap();
        }
        let samples = b.observations(timestamp - 900_000).await.unwrap();
        assert_eq!(
            samples
                .iter()
                .filter(|sample| sample.model_id == model)
                .count(),
            128
        );
        assert!(!b.claim_probe(&model, 900_000).await.unwrap());
        a.record(Observation {
            model_id: model.clone(),
            source: Source::Probe,
            observed_at_ms: timestamp,
            outcome: Outcome::Timeout,
            ttft_ms: None,
            tps: None,
        })
        .await
        .unwrap();
        a.record(Observation {
            model_id: model.clone(),
            source: Source::Probe,
            observed_at_ms: timestamp + 1,
            outcome: Outcome::Success,
            ttft_ms: Some(100.0),
            tps: None,
        })
        .await
        .unwrap();
        let samples = b.observations(timestamp - 900_000).await.unwrap();
        assert_eq!(
            samples
                .iter()
                .filter(|sample| sample.model_id == model && sample.source == Source::Probe)
                .count(),
            1
        );
        assert!(
            b.observations(timestamp + 1)
                .await
                .unwrap()
                .iter()
                .all(|sample| sample.model_id != model)
        );
        pool.close().await;
    }
}
