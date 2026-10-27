"""SQLite storage for FileRadar licenses and activations.

State machine (the rule the whole product depends on):
  - A serial is 'active' (usable) or 'deactivated' (revoked; no new
    activations, existing activations no longer count as valid).
  - A serial may have AT MOST ONE 'active' activation at a time.
    Activating on a second Mac while one is active is rejected
    with OneActiveMacError. To move Macs: deactivate the current
    activation first (the /deactivate endpoint), then activate
    on the new Mac. The serial itself stays 'active' through a move.
  - Re-activating on the SAME machine_hash while it is already
    active is idempotent (returns the existing activation).
  - Deactivating an already-deactivated / unknown machine is a
    no-op that reports 0 deactivated, not an error.
"""
from __future__ import annotations

import hmac
import os
import sqlite3
import stat
from datetime import datetime, timezone

SCHEMA = """
CREATE TABLE IF NOT EXISTS serials (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    serial          TEXT NOT NULL UNIQUE,
    buyer_email     TEXT NOT NULL,
    purchase_date   TEXT NOT NULL,
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
    machine_hash    TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'deactivated')),
    activated_at    TEXT NOT NULL,
    deactivated_at  TEXT
);
CREATE INDEX IF NOT EXISTS idx_activations_serial_status
    ON activations (serial_id, status);
-- At most one ACTIVE activation per serial, enforced by the database
-- itself (not just by application checks), so two concurrent activate
-- requests cannot both succeed. Deactivated rows are unconstrained.
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_activation
    ON activations (serial_id) WHERE status = 'active';
CREATE TABLE IF NOT EXISTS webhook_events (
    event_id        TEXT PRIMARY KEY,
    received_at     TEXT NOT NULL
);
"""


def utcnow() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class StoreError(Exception):
    pass


class SerialNotFound(StoreError):
    pass


class SerialDeactivated(StoreError):
    pass


class OneActiveMacError(StoreError):
    pass


def _ensure_private_file(path: str) -> None:
    """Create (if missing) or tighten a state file to mode 0600.

    Pre-creating with 0600 before sqlite opens it closes the window
    where a fresh DB would exist at the process umask's permissions.
    Existing files are tightened to 0600 as well. ':memory:' is skipped.
    """
    if not path or path == ":memory:" or path.startswith("file:"):
        return
    if not os.path.exists(path):
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(fd)
    try:
        mode = stat.S_IMODE(os.stat(path).st_mode)
    except OSError:
        return
    if mode != 0o600:
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass


class Store:
    def __init__(self, path: str):
        self.path = path
        _ensure_private_file(path)
        self.conn = sqlite3.connect(path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.conn.executescript(SCHEMA)
        self.conn.commit()
        # Re-tighten after creation: sqlite may have created -journal
        # files, and the DB file itself must end up 0600 regardless
        # of the umask in effect when the connection was opened.
        _ensure_private_file(path)

    def close(self):
        self.conn.close()

    # -- serials ------------------------------------------------------
    def create_serial(self, serial: str, buyer_email: str, price_paid_cents: int,
                      purchase_date: str | None = None, source: str = "stripe") -> dict:
        now = utcnow()
        cur = self.conn.execute(
            "INSERT INTO serials (serial, buyer_email, purchase_date, price_paid_cents,"
            " currency, status, source, created_at) VALUES (?, ?, ?, ?, 'usd', 'active', ?, ?)",
            (serial, buyer_email, purchase_date or now, price_paid_cents, source, now),
        )
        self.conn.commit()
        return self.get_serial_by_id(cur.lastrowid)

    def get_serial(self, serial: str) -> dict | None:
        row = self.conn.execute("SELECT * FROM serials WHERE serial = ?", (serial,)).fetchone()
        return dict(row) if row else None

    def get_serial_by_id(self, serial_id: int) -> dict:
        row = self.conn.execute("SELECT * FROM serials WHERE id = ?", (serial_id,)).fetchone()
        if row is None:
            raise StoreError(f"serial id {serial_id} not found")
        return dict(row)

    def delete_serial(self, serial: str) -> bool:
        """Remove a serial and its activations. Rollback use only
        (webhook fulfillment failure): never exposed as an endpoint."""
        row = self.get_serial(serial)
        if row is None:
            return False
        self.conn.execute("DELETE FROM activations WHERE serial_id=?", (row["id"],))
        self.conn.execute("DELETE FROM serials WHERE id=?", (row["id"],))
        self.conn.commit()
        return True

    def deactivate_serial(self, serial: str) -> bool:
        """Revoke a serial entirely. Also deactivates its active activations."""
        row = self.get_serial(serial)
        if row is None:
            raise SerialNotFound(serial)
        now = utcnow()
        self.conn.execute("UPDATE serials SET status='deactivated', deactivated_at=? WHERE id=?",
                          (now, row["id"]))
        self.conn.execute("UPDATE activations SET status='deactivated', deactivated_at=? "
                          "WHERE serial_id=? AND status='active'", (now, row["id"]))
        self.conn.commit()
        return True

    # -- activations --------------------------------------------------
    def active_activation(self, serial_id: int) -> dict | None:
        row = self.conn.execute(
            "SELECT * FROM activations WHERE serial_id=? AND status='active' ORDER BY id LIMIT 1",
            (serial_id,)).fetchone()
        return dict(row) if row else None

    def activate(self, serial: str, machine_hash: str) -> dict:
        row = self.get_serial(serial)
        if row is None:
            raise SerialNotFound(serial)
        if row["status"] != "active":
            raise SerialDeactivated(serial)
        existing = self.active_activation(row["id"])
        if existing is not None:
            if hmac.compare_digest(existing["machine_hash"], machine_hash):
                return existing  # idempotent re-activation on same Mac
            raise OneActiveMacError(
                "This license is already active on another Mac. "
                "Deactivate it there (or via /deactivate) before activating here."
            )
        now = utcnow()
        try:
            cur = self.conn.execute(
                "INSERT INTO activations (serial_id, machine_hash, status, activated_at)"
                " VALUES (?, ?, 'active', ?)", (row["id"], machine_hash, now))
            self.conn.commit()
        except sqlite3.IntegrityError:
            # Lost a race with a concurrent activation: the partial
            # unique index rejected the second active row. Re-check
            # under the same rules instead of leaking a DB error.
            self.conn.rollback()
            raced = self.active_activation(row["id"])
            if raced is not None and hmac.compare_digest(raced["machine_hash"], machine_hash):
                return raced
            raise OneActiveMacError(
                "This license is already active on another Mac. "
                "Deactivate it there (or via /deactivate) before activating here."
            ) from None
        act = self.conn.execute("SELECT * FROM activations WHERE id=?", (cur.lastrowid,)).fetchone()
        return dict(act)

    def deactivate(self, serial: str, machine_hash: str | None = None) -> int:
        """Deactivate the active activation(s) for a serial (move-Macs flow).

        The serial itself stays 'active' so it can be activated on a new Mac.
        Returns the number of activations deactivated.
        """
        row = self.get_serial(serial)
        if row is None:
            raise SerialNotFound(serial)
        now = utcnow()
        if machine_hash is None:
            cur = self.conn.execute(
                "UPDATE activations SET status='deactivated', deactivated_at=? "
                "WHERE serial_id=? AND status='active'", (now, row["id"]))
        else:
            cur = self.conn.execute(
                "UPDATE activations SET status='deactivated', deactivated_at=? "
                "WHERE serial_id=? AND status='active' AND machine_hash=?",
                (now, row["id"], machine_hash))
        self.conn.commit()
        return cur.rowcount

    def list_activations(self, serial: str) -> list[dict]:
        row = self.get_serial(serial)
        if row is None:
            raise SerialNotFound(serial)
        rows = self.conn.execute(
            "SELECT * FROM activations WHERE serial_id=? ORDER BY id", (row["id"],)).fetchall()
        return [dict(r) for r in rows]

    # -- webhook idempotency -------------------------------------------
    def mark_event_seen(self, event_id: str) -> bool:
        """Return True if this event is new, False if already processed."""
        try:
            self.conn.execute("INSERT INTO webhook_events (event_id, received_at) VALUES (?, ?)",
                              (event_id, utcnow()))
            self.conn.commit()
            return True
        except sqlite3.IntegrityError:
            self.conn.rollback()
            return False

    def unmark_event_seen(self, event_id: str) -> None:
        """Remove an idempotency mark (rollback use only: a fulfillment
        that failed before completing must be retryable by Stripe)."""
        self.conn.execute("DELETE FROM webhook_events WHERE event_id=?", (event_id,))
        self.conn.commit()
