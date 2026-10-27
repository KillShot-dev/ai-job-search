"""Stripe webhook handling: signature verification + fulfillment.

Verification follows Stripe's documented scheme (no SDK needed):
  - Header: Stripe-Signature: t=<unix timestamp>,v1=<hex hmac>,v1=<hex hmac>,...
  - Signed payload: "<t>.<raw request body bytes as text>"
  - Expected signature: HMAC-SHA256(secret, signed_payload), hex-encoded.
  - Compare with hmac.compare_digest against EACH v1 value.
  - Reject if the timestamp is more than 5 minutes from now in either
    direction (replay guard), unless the caller passes
    tolerance_seconds=None (tests only; never used by the server).

On a verified checkout.session.completed event:
  1. Extract buyer email from customer_details.email, falling back
     to customer_email (both are set by Checkout).
  2. Extract amount_total (cents); fall back to the session's
     display amount if absent (then to 0 -- recorded honestly, not guessed).
  3. Idempotency: if event id was already processed, return
     already_processed=True and create NO second serial.
  4. Otherwise generate a serial, store it (source='stripe'), and
     send the license email via the configured mailer (dry-run by default).

Any other event type is acknowledged (ignored=True) without fulfillment,
so Stripe does not retry it. Signature failures raise WebhookError
and must be answered HTTP 400 (see server.py).
"""
from __future__ import annotations

import hashlib
import hmac
import json
import threading
import time

from mailer import MailerError, send_license_email, validate_email
from serials import generate_serial
from store import Store

# Serializes webhook fulfillment in-process. Combined with the
# webhook_events primary key, this closes the race where two
# concurrent deliveries of the same event could both pass the
# "already seen" check before either finished fulfilling.
_webhook_lock = threading.Lock()


class WebhookError(Exception):
    pass


def verify_stripe_signature(payload: bytes, signature_header: str | None,
                            secret: str | None,
                            tolerance_seconds: int | None = 300) -> None:
    """Raise WebhookError unless the Stripe signature verifies."""
    if secret is None or secret == "":
        raise WebhookError("STRIPE_WEBHOOK_SECRET is not set; cannot verify webhook.")
    if not signature_header:
        raise WebhookError("Missing Stripe-Signature header.")
    timestamp = None
    signatures: list[str] = []
    for part in signature_header.split(","):
        part = part.strip()
        if part.startswith("t="):
            timestamp = part[2:]
        elif part.startswith("v1="):
            signatures.append(part[3:])
    if timestamp is None or not signatures:
        raise WebhookError("Malformed Stripe-Signature header.")
    if tolerance_seconds is not None:
        try:
            age = abs(time.time() - int(timestamp))
        except ValueError:
            raise WebhookError("Invalid webhook timestamp.") from None
        if age > tolerance_seconds:
            raise WebhookError("Webhook timestamp outside tolerance (possible replay).")
    signed = f"{timestamp}.".encode("utf-8") + payload
    expected = hmac.new(secret.encode("utf-8"), signed, hashlib.sha256).hexdigest()
    if not any(hmac.compare_digest(expected, sig) for sig in signatures):
        raise WebhookError("Webhook signature mismatch.")


def sign_test_payload(payload: bytes, secret: str, timestamp: int | None = None) -> str:
    """Build a Stripe-Signature header for a payload (tests / local tools only)."""
    ts = timestamp if timestamp is not None else int(time.time())
    signed = f"{ts}.".encode("utf-8") + payload
    sig = hmac.new(secret.encode("utf-8"), signed, hashlib.sha256).hexdigest()
    return f"t={ts},v1={sig}"


def handle_webhook_event(payload: bytes, signature_header: str | None, secret: str | None,
                         store: Store, mailer=None) -> dict:
    """Verify + fulfill one webhook delivery. Returns a result dict.

    Ordering matters for idempotency: the event is validated
    (event id, buyer email, amount) BEFORE its id is marked seen,
    so a malformed delivery never poisons the idempotency record.
    If fulfillment itself fails after marking (serial stored but
    email failed, serial collision, ...), the serial is removed and
    the mark is undone, so a Stripe retry can fulfill exactly once
    instead of returning already_processed for a failed delivery.
    """
    verify_stripe_signature(payload, signature_header, secret)
    try:
        event = json.loads(payload.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        raise WebhookError("Webhook body is not valid JSON.") from None
    if not isinstance(event, dict):
        raise WebhookError("Webhook body is not a JSON object.")
    event_type = event.get("type")
    if event_type != "checkout.session.completed":
        return {"received": True, "ignored": True, "type": event_type}
    event_id = event.get("id")
    if not event_id or not isinstance(event_id, str):
        raise WebhookError("checkout.session.completed has no event id.")
    session = (event.get("data") or {}).get("object") or {}
    if not isinstance(session, dict):
        raise WebhookError("checkout.session.completed has no session object.")
    details = session.get("customer_details") or {}
    if not isinstance(details, dict):
        details = {}
    raw_email = details.get("email") or session.get("customer_email")
    try:
        buyer_email = validate_email(raw_email)
    except MailerError:
        raise WebhookError("checkout.session.completed has no valid buyer email.") from None
    amount = session.get("amount_total")
    if amount is None:
        amount = 0
    if isinstance(amount, bool) or not isinstance(amount, int) or amount < 0:
        raise WebhookError("checkout.session.completed has an invalid amount_total.")
    with _webhook_lock:
        if not store.mark_event_seen(event_id):
            return {"received": True, "already_processed": True, "event_id": event_id}
        serial = None
        try:
            serial = generate_serial()
            record = store.create_serial(serial, buyer_email, amount, source="stripe")
            email_result = send_license_email(buyer_email, serial, amount, mailer=mailer)
        except Exception as exc:
            # Roll back so a retry fulfills exactly once. A
            # MailerError (or anything else) must not leave a
            # half-fulfilled delivery marked as processed.
            if serial is not None:
                try:
                    store.delete_serial(serial)
                except Exception:
                    pass
            try:
                store.unmark_event_seen(event_id)
            except Exception:
                pass
            if isinstance(exc, WebhookError):
                raise
            raise WebhookError("Webhook fulfillment failed.") from None
    return {
        "received": True,
        "fulfilled": True,
        "event_id": event_id,
        "serial": serial,
        "buyer_email": buyer_email,
        "price_paid_cents": amount,
        "email": email_result,
        "serial_id": record["id"],
    }
