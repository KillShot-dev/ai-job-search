-- FileRadar licensing schema (SQLite).
-- Apply with: sqlite3 licenses.db < schema.sql
-- or let store.py create it automatically on first use.
-- All timestamps are ISO-8601 UTC strings (YYYY-MM-DDTHH:MM:SSZ).

CREATE TABLE IF NOT EXISTS serials (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    serial          TEXT NOT NULL UNIQUE,          -- FR-XXXX-XXXX-XXXX-XXXX
    buyer_email     TEXT NOT NULL,
    purchase_date   TEXT NOT NULL,                  -- ISO date or datetime
    price_paid_cents INTEGER NOT NULL,
    currency        TEXT NOT NULL DEFAULT 'usd',
    status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'deactivated')),
    source          TEXT NOT NULL DEFAULT 'stripe' CHECK (source IN ('stripe', 'demo')),
    created_at      TEXT NOT NULL,
    deactivated_at  TEXT
);

CREATE TABLE IF NOT EXISTS activations (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    serial_id       INTEGER NOT NULL REFERENCES serials(id),
    machine_hash    TEXT NOT NULL,                  -- hash of a machine identifier, never the raw identifier
    status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'deactivated')),
    activated_at    TEXT NOT NULL,
    deactivated_at  TEXT
);

CREATE INDEX IF NOT EXISTS idx_activations_serial_status
    ON activations (serial_id, status);

-- Enforced by the database, not just by application checks: at most
-- one ACTIVE activation per serial, even under concurrent requests.
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_activation
    ON activations (serial_id) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS webhook_events (
    event_id        TEXT PRIMARY KEY,              -- Stripe event id, for idempotency
    received_at     TEXT NOT NULL
);
