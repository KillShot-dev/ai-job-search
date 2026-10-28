"""HTTP server for the FileRadar licensing backend (Python stdlib only).

Run:  python3 server.py
      (from this directory; env vars per .env.example)

Endpoints (all JSON except /webhook, which takes Stripe's raw body):
  GET  /health
    -> {"ok": true, "test_mode": ..., "email_dry_run": ...,
        "tls_terminated": ..., "tls_warning": ...}
  POST /create-checkout   {"email": "..."}
    -> Stripe Checkout Session (real TEST-mode session if a sk_test_
       key is configured, otherwise a clearly-labelled mock session).
       Price is computed from LAUNCH_DATE for today's date.
  POST /webhook           (raw Stripe body, Stripe-Signature header)
    -> verifies signature, fulfills checkout.session.completed.
       400 on bad signature, 200 otherwise. The 400 body is generic
       on purpose: it never repeats the verification failure detail.
  POST /validate-serial  {"serial": "FR-..."}
    -> {"valid_checksum": bool, "known": bool, "status": ...,
        "active_machine": bool}  (server-side check; the app's local
       checksum check is separate and is NOT authoritative.)
  POST /activate         {"serial": "FR-...", "machine_hash": "..."}
    -> activates on one Mac; 409 if already active on another Mac.
  POST /deactivate       {"serial": "FR-...", "machine_hash": "..."}
    -> deactivates the active activation (move-Macs flow). The serial
       stays active. machine_hash optional: omit to deactivate
       whatever Mac is currently active.
  POST /deactivate-serial {"serial": "FR-..."}
    -> revokes the serial entirely. ADMIN ONLY: requires the
       LICENSING_ADMIN_TOKEN (see below). This is the only admin
       HTTP endpoint; every other endpoint is part of the normal
       buyer/app flow and is authenticated by the serial itself
       (which is why serials must be treated as credentials).

Admin authentication
  /deactivate-serial requires an admin token from the environment
  (LICENSING_ADMIN_TOKEN), sent as either header
  "X-Admin-Token: <token>" or "Authorization: Bearer <token>".
  Comparison is constant-time (hmac.compare_digest). Missing token,
  wrong token, and "no token configured" all return the same generic
  403 {"error": "forbidden"} so a caller cannot learn which part
  failed or whether a token is configured at all. If no token is
  configured, admin access is DENIED (fail closed), never open.
  The CLI's deactivate-serial is a local-operator command (it needs
  direct filesystem access to the same SQLite file), not an HTTP
  endpoint, so it is outside this HTTP auth boundary.

Rate limiting (in-process, stdlib only, per client IP, per minute):
  /create-checkout: 20, /validate-serial: 60, /activate: 30,
  /deactivate: 30, /deactivate-serial: 10, /webhook: 120.
  Exceeding a limit returns 429 {"error": "rate limit exceeded"}
  with a Retry-After header. Limits are per process: a multi-process
  deployment needs a shared limiter at the proxy (see README).

TLS: this server serves plain HTTP only. Production traffic MUST be
terminated at a TLS reverse proxy in front of it, with
LICENSING_TLS_TERMINATED=1 set only when that proxy really does
terminate TLS. When the server is configured for real traffic
(test mode off, or bound to a non-loopback host) without TLS
termination, it logs a loud startup warning and /health reports
tls_warning=true. Local test smoke runs (test mode on loopback)
are unaffected.

Security headers are set on every JSON response, and error
responses are generic: no stack traces, no internal details, no
secrets, and no request bodies are ever returned or logged.
Request logs contain method + path only (query strings stripped),
never headers or bodies.

machine_hash: the app must send a HASH of its machine identifier,
never the raw identifier (e.g. SHA-256 of the hardware UUID).
The server stores only what it is given; hashing is the app's job.
"""
from __future__ import annotations

import hmac
import json
import os
import sys
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import config  # noqa: E402
import serials  # noqa: E402
import stripe_client  # noqa: E402
from mailer import MailerError, validate_email, get_mailer  # noqa: E402
from store import OneActiveMacError, SerialDeactivated, SerialNotFound, Store  # noqa: E402
from webhook import WebhookError, handle_webhook_event  # noqa: E402

MAX_BODY_BYTES = 1_000_000

# Per-IP, per-endpoint requests allowed per 60-second window.
RATE_LIMITS = {
    "/create-checkout": 20,
    "/validate-serial": 60,
    "/activate": 30,
    "/deactivate": 30,
    "/deactivate-serial": 10,
    "/webhook": 120,
}

# The one admin HTTP endpoint. Anything added here must also get the
# admin-token check in do_POST; see _require_admin().
ADMIN_ENDPOINTS = ("/deactivate-serial",)


class BodyTooLarge(Exception):
    pass


class RateLimiter:
    """Fixed-window, per-IP rate limiter (stdlib only, thread-safe)."""

    def __init__(self, limits: dict | None = None, window_seconds: int = 60,
                 max_keys: int = 10_000):
        self.limits = dict(limits or RATE_LIMITS)
        self.window = window_seconds
        self.max_keys = max_keys
        self._lock = threading.Lock()
        self._hits: dict[tuple[str, str], deque] = {}

    def allowed(self, client_ip: str, path: str) -> bool:
        limit = self.limits.get(path)
        if limit is None:
            return True
        now = time.monotonic()
        key = (client_ip, path)
        with self._lock:
            self._evict_locked(now)
            queue = self._hits.setdefault(key, deque())
            while queue and queue[0] <= now - self.window:
                queue.popleft()
            if not queue and key in self._hits and len(queue) == 0:
                # Keep the key for this check; empty keys are evicted next pass.
                pass
            if len(queue) >= limit:
                return False
            queue.append(now)
            return True

    def _evict_locked(self, now: float) -> None:
        """Drop empty / fully-expired keys so the map cannot grow without bound."""
        stale = [k for k, q in self._hits.items()
                 if not q or q[-1] <= now - self.window]
        for k in stale:
            del self._hits[k]
        if len(self._hits) <= self.max_keys:
            return
        # Bound worst-case growth: drop oldest-by-last-hit until under cap.
        ordered = sorted(self._hits.items(), key=lambda kv: kv[1][-1] if kv[1] else 0)
        overflow = len(self._hits) - self.max_keys
        for k, _ in ordered[:overflow]:
            self._hits.pop(k, None)


_DEFAULT_LIMITER = RateLimiter()


def _store() -> Store:
    return Store(config.db_path())


def _limiter_for(handler) -> RateLimiter:
    return getattr(handler.server, "rate_limiter", None) or _DEFAULT_LIMITER


def _admin_authorized(handler) -> bool:
    """Constant-time admin-token check. Generic caller: see docstring.

    Accepts X-Admin-Token or Authorization: Bearer. A missing
    configured token fails closed; a dummy comparison keeps the
    timing indistinguishable from a wrong-token comparison.
    """
    expected = config.admin_token()
    provided = handler.headers.get("X-Admin-Token")
    if provided is None:
        auth = handler.headers.get("Authorization") or ""
        if auth.lower().startswith("bearer "):
            provided = auth[7:].strip()
    if expected is None or provided is None:
        # Dummy constant-time comparison; result is always deny.
        hmac.compare_digest(provided or "", "0" * 32)
        return False
    return hmac.compare_digest(expected, provided)


class Handler(BaseHTTPRequestHandler):
    server_version = "FileRadarLicensing/1.0"

    def version_string(self) -> str:
        # Do not leak the Python version in the Server header.
        return "FileRadarLicensing"

    def log_message(self, fmt, *args):  # quieter than default, still visible
        # Log method + path only, query strings stripped: a query
        # string could carry a token/session id in some future route.
        # Never log headers or bodies here.
        try:
            message = fmt % args
        except Exception:
            message = fmt
        parts = message.split(" ", 2)
        if len(parts) >= 2 and parts[1].startswith("/"):
            parts[1] = urlsplit(parts[1]).path
            message = " ".join(parts)
        sys.stderr.write("[server] " + message + "\n")

    # -- helpers ------------------------------------------------------
    def _send_json(self, status: int, obj: dict, extra_headers: dict | None = None):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        # Security headers on every response.
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy", "default-src 'none'")
        self.send_header("Access-Control-Allow-Origin", "*")
        if extra_headers:
            for key, value in extra_headers.items():
                self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _content_length(self) -> int:
        raw = self.headers.get("Content-Length")
        if raw is None:
            return 0
        try:
            length = int(raw)
        except ValueError:
            raise BodyTooLarge("invalid Content-Length") from None
        if length < 0 or length > MAX_BODY_BYTES:
            raise BodyTooLarge("request body too large")
        return length

    def _read_json(self) -> dict:
        length = self._content_length()
        raw = self.rfile.read(length) if length else b"{}"
        try:
            parsed = json.loads(raw.decode("utf-8") or "{}")
        except ValueError:
            return {}
        return parsed if isinstance(parsed, dict) else {}

    def _read_raw(self) -> bytes:
        length = self._content_length()
        return self.rfile.read(length) if length else b""

    def _client_ip(self) -> str:
        # Peer IP only. X-Forwarded-For is NOT trusted (spoofable);
        # a proxy deployment must rate-limit at the proxy (README).
        return self.client_address[0] if self.client_address else "unknown"

    # -- routing ------------------------------------------------------

    def do_OPTIONS(self):
        # CORS preflight for browser-based admin/tools. Credentials are never
        # reflected; allowlist is methods + content-type / admin headers only.
        path = urlsplit(self.path).path
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers",
                         "Content-Type, X-Admin-Token, Authorization, Stripe-Signature")
        self.send_header("Access-Control-Max-Age", "600")
        self.send_header("Content-Length", "0")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        _ = path  # path reserved for future per-route allowlists

    def do_GET(self):
        try:
            path = urlsplit(self.path).path
            if path in ("/health", "/"):
                self._send_json(200, {
                    "ok": True,
                    "test_mode": config.stripe_test_mode(),
                    "email_dry_run": config.email_dry_run(),
                    "email_provider": config.email_provider(),
                    "tls_terminated": config.tls_terminated(),
                    "tls_warning": config.tls_warning_active(),
                })
            else:
                self._send_json(404, {"error": "not found"})
        except Exception:
            sys.stderr.write("[server] internal error handling GET (details withheld)\n")
            try:
                self._send_json(500, {"error": "internal error"})
            except Exception:
                pass

    def do_POST(self):
        path = urlsplit(self.path).path
        # Rate-limit BEFORE opening the store so a flood never touches SQLite.
        if path in RATE_LIMITS and not _limiter_for(self).allowed(self._client_ip(), path):
            self._send_json(429, {"error": "rate limit exceeded"},
                            extra_headers={"Retry-After": "60"})
            return
        store = _store()
        try:
            if path in ADMIN_ENDPOINTS and not _admin_authorized(self):
                # Generic 403: identical whether the token is missing,
                # wrong, or simply not configured server-side.
                self._send_json(403, {"error": "forbidden"})
                return

            if path == "/webhook":
                raw = self._read_raw()
                try:
                    result = handle_webhook_event(
                        raw, self.headers.get("Stripe-Signature"),
                        config.stripe_webhook_secret(), store, mailer=get_mailer())
                except WebhookError:
                    # Generic on purpose: never repeat the verification
                    # detail (e.g. whether the secret is unset) to the caller.
                    self._send_json(400, {"error": "webhook verification failed"})
                    return
                self._send_json(200, result)
                return

            body = self._read_json()
            if path == "/create-checkout":
                try:
                    email = validate_email(body.get("email"))
                except MailerError:
                    self._send_json(400, {"error": "a valid 'email' is required"})
                    return
                try:
                    launch = config.launch_date()
                except config.ConfigError:
                    self._send_json(500, {"error": "configuration error"})
                    return
                try:
                    session = stripe_client.create_checkout_session(email, launch)
                except stripe_client.StripeError:
                    # Generic: Stripe API error bodies are never
                    # relayed to the caller.
                    self._send_json(502, {"error": "payment provider error"})
                    return
                self._send_json(200, session)
                return

            if path == "/validate-serial":
                raw_serial = body.get("serial") or ""
                if not isinstance(raw_serial, str):
                    raw_serial = ""
                normalized = serials.normalize_serial(raw_serial)
                canonical = serials.format_serial(normalized) if normalized else raw_serial
                known = store.get_serial(canonical)
                active = None
                if known is not None:
                    active = store.active_activation(known["id"])
                self._send_json(200, {
                    "valid_checksum": serials.is_valid_serial(raw_serial),
                    "known": known is not None,
                    "status": known["status"] if known else None,
                    "active_machine": active is not None,
                    "price_paid_cents": known["price_paid_cents"] if known else None,
                })
                return

            if path == "/activate":
                serial_raw, machine = body.get("serial") or "", body.get("machine_hash") or ""
                if not isinstance(serial_raw, str) or not isinstance(machine, str):
                    self._send_json(400, {"error": "'serial' and 'machine_hash' are required"})
                    return
                if not serial_raw or not machine or len(machine) > 512:
                    self._send_json(400, {"error": "'serial' and 'machine_hash' are required"})
                    return
                serial = serials.format_serial(serials.normalize_serial(serial_raw)) \
                    if serials.normalize_serial(serial_raw) else serial_raw
                try:
                    act = store.activate(serial, machine)
                except SerialNotFound:
                    self._send_json(404, {"error": "serial not found"})
                    return
                except SerialDeactivated:
                    self._send_json(403, {"error": "serial is deactivated"})
                    return
                except OneActiveMacError:
                    self._send_json(409, {"error": "serial already active on another Mac"})
                    return
                self._send_json(200, {"activated": True, "activation": act})
                return

            if path == "/deactivate":
                serial_raw = body.get("serial") or ""
                machine = body.get("machine_hash") or None
                if not isinstance(serial_raw, str) or (machine is not None and not isinstance(machine, str)):
                    self._send_json(400, {"error": "'serial' is required"})
                    return
                if not serial_raw:
                    self._send_json(400, {"error": "'serial' is required"})
                    return
                serial = serials.format_serial(serials.normalize_serial(serial_raw)) \
                    if serials.normalize_serial(serial_raw) else serial_raw
                try:
                    count = store.deactivate(serial, machine)
                except SerialNotFound:
                    self._send_json(404, {"error": "serial not found"})
                    return
                self._send_json(200, {"deactivated": count})
                return

            if path == "/deactivate-serial":
                # Admin token already checked above, before any state change.
                serial_raw = body.get("serial") or ""
                if not isinstance(serial_raw, str) or not serial_raw:
                    self._send_json(400, {"error": "'serial' is required"})
                    return
                serial = serials.format_serial(serials.normalize_serial(serial_raw)) \
                    if serials.normalize_serial(serial_raw) else serial_raw
                try:
                    store.deactivate_serial(serial)
                except SerialNotFound:
                    self._send_json(404, {"error": "serial not found"})
                    return
                self._send_json(200, {"deactivated_serial": True})
                return

            self._send_json(404, {"error": "not found"})
        except BodyTooLarge:
            try:
                self._send_json(413, {"error": "request body too large"})
            except Exception:
                pass
        except Exception:
            # Generic 500: no stack trace, no exception text, no body.
            sys.stderr.write("[server] internal error handling POST (details withheld)\n")
            try:
                self._send_json(500, {"error": "internal error"})
            except Exception:
                pass
        finally:
            store.close()


def tls_startup_warning() -> str | None:
    if config.tls_warning_active():
        return (
            "WARNING: FileRadar licensing server is configured for real "
            "traffic WITHOUT TLS termination (STRIPE_TEST_MODE is off "
            "and/or the host is non-loopback, and LICENSING_TLS_TERMINATED "
            "is not set). Do NOT expose this server publicly until TLS "
            "terminates in front of it (see README production checklist)."
        )
    return None


def main():
    host, port = config.server_host(), config.server_port()
    warning = tls_startup_warning()
    if warning:
        print(warning, file=sys.stderr, flush=True)
    print(f"FileRadar licensing server on http://{host}:{port} "
          f"(test_mode={config.stripe_test_mode()}, "
          f"email_dry_run={config.email_dry_run()}, "
          f"db={config.db_path()})", flush=True)
    if warning:
        print(warning, flush=True)
    httpd = ThreadingHTTPServer((host, port), Handler)
    httpd.rate_limiter = RateLimiter()
    httpd.serve_forever()


if __name__ == "__main__":
    main()
