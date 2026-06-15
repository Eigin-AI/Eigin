CREATE TABLE processed_notifications (
    notification_uuid TEXT PRIMARY KEY,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
