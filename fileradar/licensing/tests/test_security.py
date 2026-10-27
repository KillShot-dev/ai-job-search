"""Security regression tests for the licensing-backend hardening pass.

Covers, one test per fix: admin-token auth on /deactivate-serial
(fail closed, constant-time, generic 403), per-IP rate limiting,
security headers, generic error bodies, TLS health/warning flags,
parameterized-SQL behaviour under injection input, DB 0600
permissions, the one-active-Mac DB index, webhook replay tolerance
and idempotency rollback, Stripe live/test key refusal, mailer
email validation + header-injection guards, and dry-run log
redaction (no buyer email or serial in logs).

HTTP tests spin up the real server on a loopback ephemeral port
with a temporary DB; env vars are set per test and restored after.
"""
import contextlib
import io
import json
import os
import stat
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import config
import server as server_mod
import stripe_client
from mailer import DryRunProvider, EmailProvider, MailerError, send_license_email, validate_email
from serials import generate_serial
from store import OneActiveMacError, SerialNotFound, Store
from webhook import WebhookError, handle_webhook_event, sign_test_payload

SECRET = "whsec_test_fake_secret_for_local_tests_only"
ADMIN_TOKEN = "test-admin-token-do-not-use-in-production"
MAC_A = "hash-of-mac-a-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
MAC_B = "hash-of-mac-b-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"


class CapturingMailer(EmailProvider):
    def __init__(self):
        self.sent = []

    def send(self, to_email, subject, body):
        self.sent.append({"to": to_email, "subject": subject, "body": body})
        return {"dry_run": True, "to": to_email}


class FailingThenWorkingMailer(EmailProvider):
    def __init__(self):
        self.calls = 0
        self.sent = []

    def send(self, to_email, subject, body):
        self.calls += 1
        if self.calls == 1:
            raise MailerError("simulated transient mail failure")
        self.sent.append(to_email)
        return {"dry_run": True, "to": to_email}


def make_event(event_id="evt_sec_1", email="buyer@test.local", amount=800,
               include_email=True):
    obj = {"id": "cs_test_123", "amount_total": amount}
    if include_email:
        obj["customer_email"] = email
        obj["customer_details"] = {"email": email}
    return json.dumps({"id": event_id, "type": "checkout.session.completed",
                       "data": {"object": obj}}).encode("utf-8")


class EnvGuard:
    """Save/restore a set of env vars around a test."""

    def __init__(self, *names):
        self.names = names
        self.saved = {}

    def __enter__(self):
        for name in self.names:
            self.saved[name] = os.environ.get(name)
        return self

    def __exit__(self, *exc):
        for name in self.names:
            if self.saved[name] is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = self.saved[name]
        return False


class TestAdminAuthHttp(unittest.TestCase):
    def setUp(self):
        self.env = EnvGuard("LICENSING_DB_PATH", "LAUNCH_DATE", "STRIPE_TEST_MODE",
                            "EMAIL_DRY_RUN", "STRIPE_WEBHOOK_SECRET",
                            "LICENSING_ADMIN_TOKEN")
        self.env.__enter__()
        self.tmp = tempfile.TemporaryDirectory()
        self.db = os.path.join(self.tmp.name, "test.db")
        os.environ["LICENSING_DB_PATH"] = self.db
        os.environ["LAUNCH_DATE"] = "2026-01-01"
        os.environ["STRIPE_TEST_MODE"] = "1"
        os.environ["EMAIL_DRY_RUN"] = "1"
        os.environ["STRIPE_WEBHOOK_SECRET"] = SECRET
        os.environ["LICENSING_ADMIN_TOKEN"] = ADMIN_TOKEN
        self.store = Store(self.db)
        self.serial = generate_serial()
        self.store.create_serial(self.serial, "buyer@test.local", 800)
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), server_mod.Handler)
        self.httpd.rate_limiter = server_mod.RateLimiter()
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.store.close()
        self.tmp.cleanup()
        self.env.__exit__()

    def post(self, path, obj, headers=None):
        data = json.dumps(obj).encode()
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", data=data,
                                     headers={"Content-Type": "application/json",
                                              **(headers or {})}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                return resp.status, dict(resp.headers), resp.read().decode()
        except urllib.error.HTTPError as exc:
            return exc.code, dict(exc.headers), exc.read().decode()

    def get(self, path):
        with urllib.request.urlopen(f"http://127.0.0.1:{self.port}{path}", timeout=10) as resp:
            return resp.status, dict(resp.headers), resp.read().decode()

    def test_deactivate_serial_requires_token(self):
        status, _, body = self.post("/deactivate-serial", {"serial": self.serial})
        self.assertEqual(status, 403)
        self.assertEqual(json.loads(body), {"error": "forbidden"})
        # Serial must NOT have been revoked by the denied request.
        self.assertEqual(self.store.get_serial(self.serial)["status"], "active")

    def test_deactivate_serial_wrong_token_same_generic_403(self):
        status, _, body = self.post("/deactivate-serial", {"serial": self.serial},
                                    headers={"X-Admin-Token": "wrong-token"})
        self.assertEqual(status, 403)
        self.assertEqual(json.loads(body), {"error": "forbidden"})
        self.assertEqual(self.store.get_serial(self.serial)["status"], "active")

    def test_deactivate_serial_missing_config_fails_closed(self):
        os.environ.pop("LICENSING_ADMIN_TOKEN", None)
        status, _, body = self.post("/deactivate-serial", {"serial": self.serial},
                                    headers={"X-Admin-Token": ADMIN_TOKEN})
        self.assertEqual(status, 403)
        self.assertEqual(json.loads(body), {"error": "forbidden"})

    def test_deactivate_serial_correct_token_header(self):
        status, _, body = self.post("/deactivate-serial", {"serial": self.serial},
                                    headers={"X-Admin-Token": ADMIN_TOKEN})
        self.assertEqual(status, 200)
        self.assertEqual(self.store.get_serial(self.serial)["status"], "deactivated")

    def test_deactivate_serial_bearer_token(self):
        status, _, _ = self.post("/deactivate-serial", {"serial": self.serial},
                                 headers={"Authorization": f"Bearer {ADMIN_TOKEN}"})
        self.assertEqual(status, 200)

    def test_security_headers_present(self):
        _, headers, _ = self.get("/health")
        lowered = {k.lower(): v for k, v in headers.items()}
        self.assertEqual(lowered.get("x-content-type-options"), "nosniff")
        self.assertEqual(lowered.get("x-frame-options"), "DENY")
        self.assertEqual(lowered.get("referrer-policy"), "no-referrer")
        self.assertEqual(lowered.get("cache-control"), "no-store")
        self.assertNotIn("python", lowered.get("server", "").lower())

    def test_health_tls_fields_local_test_mode_no_warning(self):
        _, _, body = self.get("/health")
        data = json.loads(body)
        self.assertFalse(data["tls_warning"])
        self.assertFalse(data["tls_terminated"])

    def test_health_tls_warning_when_test_mode_off(self):
        os.environ["STRIPE_TEST_MODE"] = "0"
        _, _, body = self.get("/health")
        self.assertTrue(json.loads(body)["tls_warning"])
        os.environ["LICENSING_TLS_TERMINATED"] = "1"
        try:
            _, _, body = self.get("/health")
            data = json.loads(body)
            self.assertFalse(data["tls_warning"])
            self.assertTrue(data["tls_terminated"])
        finally:
            os.environ.pop("LICENSING_TLS_TERMINATED", None)

    def test_webhook_bad_signature_generic_400(self):
        payload = make_event()
        header = sign_test_payload(payload, "whsec_wrong_secret")
        req = urllib.request.Request(
            f"http://127.0.0.1:{self.port}/webhook", data=payload,
            headers={"Stripe-Signature": header}, method="POST")
        try:
            urllib.request.urlopen(req, timeout=10)
            self.fail("expected HTTP 400")
        except urllib.error.HTTPError as exc:
            self.assertEqual(exc.code, 400)
            body = exc.read().decode()
            self.assertEqual(json.loads(body), {"error": "webhook verification failed"})
            self.assertNotIn("SECRET", body)
            self.assertNotIn("mismatch", body)

    def test_activate_second_mac_409_over_http(self):
        self.post("/activate", {"serial": self.serial, "machine_hash": MAC_A})
        status, _, body = self.post("/activate", {"serial": self.serial, "machine_hash": MAC_B})
        self.assertEqual(status, 409)
        self.assertNotIn("Traceback", body)

    def test_oversized_body_rejected_413(self):
        conn = HTTPConnection("127.0.0.1", self.port, timeout=10)
        conn.putrequest("POST", "/validate-serial")
        conn.putheader("Content-Type", "application/json")
        conn.putheader("Content-Length", str(server_mod.MAX_BODY_BYTES + 1))
        conn.endheaders()
        resp = conn.getresponse()
        self.assertEqual(resp.status, 413)
        resp.read()
        conn.close()

    def test_rate_limit_429_on_admin_endpoint(self):
        self.httpd.rate_limiter = server_mod.RateLimiter(
            limits={"/deactivate-serial": 2})
        headers = {"X-Admin-Token": ADMIN_TOKEN}
        # Unknown serials still count as hits (404), then the limit trips.
        s1, _, _ = self.post("/deactivate-serial", {"serial": "FR-AAAA-AAAA-AAAA-AAAA"}, headers)
        s2, _, _ = self.post("/deactivate-serial", {"serial": "FR-AAAA-AAAA-AAAA-AAAA"}, headers)
        s3, h3, b3 = self.post("/deactivate-serial", {"serial": "FR-AAAA-AAAA-AAAA-AAAA"}, headers)
        self.assertNotEqual(s1, 429)
        self.assertNotEqual(s2, 429)
        self.assertEqual(s3, 429)
        self.assertEqual(json.loads(b3), {"error": "rate limit exceeded"})
        lowered = {k.lower(): v for k, v in h3.items()}
        self.assertIn("retry-after", lowered)


class TestRateLimiterUnit(unittest.TestCase):
    def test_per_ip_window_and_separation(self):
        limiter = server_mod.RateLimiter(limits={"/validate-serial": 2}, window_seconds=60)
        self.assertTrue(limiter.allowed("1.2.3.4", "/validate-serial"))
        self.assertTrue(limiter.allowed("1.2.3.4", "/validate-serial"))
        self.assertFalse(limiter.allowed("1.2.3.4", "/validate-serial"))
        # A different IP has its own budget; unlisted paths are unlimited.
        self.assertTrue(limiter.allowed("5.6.7.8", "/validate-serial"))
        self.assertTrue(limiter.allowed("1.2.3.4", "/health"))


class TestStoreSecurity(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = os.path.join(self.tmp.name, "test.db")
        self.store = Store(self.db)

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def test_new_db_is_0600(self):
        self.assertEqual(stat.S_IMODE(os.stat(self.db).st_mode), 0o600)

    def test_preexisting_wide_db_is_tightened(self):
        self.store.close()
        os.chmod(self.db, 0o644)
        reopened = Store(self.db)
        try:
            self.assertEqual(stat.S_IMODE(os.stat(self.db).st_mode), 0o600)
        finally:
            reopened.close()

    def test_sql_injection_input_is_literal(self):
        serial = generate_serial()
        self.store.create_serial(serial, "buyer@test.local", 800)
        self.assertIsNone(self.store.get_serial("' OR '1'='1"))
        self.assertIsNone(self.store.get_serial("FR-AAAA-AAAA-AAAA-AAAA'; DROP TABLE serials; --"))
        with self.assertRaises(SerialNotFound):
            self.store.activate("' OR 1=1 --", MAC_A)
        # Table intact: the real serial is still there.
        self.assertIsNotNone(self.store.get_serial(serial))

    def test_one_active_mac_db_index(self):
        serial = generate_serial()
        record = self.store.create_serial(serial, "buyer@test.local", 800)
        self.store.activate(serial, MAC_A)
        import sqlite3
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.conn.execute(
                "INSERT INTO activations (serial_id, machine_hash, status, activated_at)"
                " VALUES (?, ?, 'active', ?)", (record["id"], MAC_B, "2026-01-01T00:00:00Z"))
        self.store.conn.rollback()
        with self.assertRaises(OneActiveMacError):
            self.store.activate(serial, MAC_B)


class TestWebhookSecurity(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Store(os.path.join(self.tmp.name, "test.db"))
        self.mailer = CapturingMailer()

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def test_replay_old_timestamp_rejected(self):
        payload = make_event()
        old = int(time.time()) - 3600
        header = sign_test_payload(payload, SECRET, timestamp=old)
        with self.assertRaises(WebhookError):
            handle_webhook_event(payload, header, SECRET, self.store, mailer=self.mailer)
        self.assertEqual(len(self.mailer.sent), 0)

    def test_replay_future_timestamp_rejected(self):
        payload = make_event()
        future = int(time.time()) + 3600
        header = sign_test_payload(payload, SECRET, timestamp=future)
        with self.assertRaises(WebhookError):
            handle_webhook_event(payload, header, SECRET, self.store, mailer=self.mailer)

    def test_missing_event_id_rejected(self):
        event = json.loads(make_event())
        del event["id"]
        payload = json.dumps(event).encode()
        header = sign_test_payload(payload, SECRET)
        with self.assertRaises(WebhookError):
            handle_webhook_event(payload, header, SECRET, self.store, mailer=self.mailer)

    def test_invalid_amount_rejected(self):
        for amount in ("800", 800.5, -1, True, None):
            # None is documented as "record 0"; every other non-int is rejected.
            if amount is None:
                continue
            event = json.loads(make_event(amount=800))
            event["data"]["object"]["amount_total"] = amount
            payload = json.dumps(event).encode()
            header = sign_test_payload(payload, SECRET)
            with self.assertRaises(WebhookError, msg=f"amount={amount!r}"):
                handle_webhook_event(payload, header, SECRET, self.store, mailer=self.mailer)

    def test_missing_email_does_not_poison_idempotency(self):
        bad = make_event(event_id="evt_poison", include_email=False)
        header = sign_test_payload(bad, SECRET)
        with self.assertRaises(WebhookError):
            handle_webhook_event(bad, header, SECRET, self.store, mailer=self.mailer)
        # Same event id, now with a valid email: must fulfill, not
        # report already_processed for the failed delivery.
        good = make_event(event_id="evt_poison")
        header = sign_test_payload(good, SECRET)
        result = handle_webhook_event(good, header, SECRET, self.store, mailer=self.mailer)
        self.assertTrue(result["fulfilled"])
        self.assertEqual(len(self.mailer.sent), 1)

    def test_mail_failure_rolls_back_and_retry_fulfills_once(self):
        flaky = FailingThenWorkingMailer()
        payload = make_event(event_id="evt_flaky")
        header = sign_test_payload(payload, SECRET)
        with self.assertRaises(WebhookError):
            handle_webhook_event(payload, header, SECRET, self.store, mailer=flaky)
        # Nothing left behind: no serial, no idempotency mark.
        self.assertEqual(self.store.conn.execute(
            "SELECT COUNT(*) FROM serials").fetchone()[0], 0)
        result = handle_webhook_event(payload, header, SECRET, self.store, mailer=flaky)
        self.assertTrue(result["fulfilled"])
        self.assertEqual(self.store.conn.execute(
            "SELECT COUNT(*) FROM serials").fetchone()[0], 1)
        self.assertEqual(len(flaky.sent), 1)

    def test_invalid_buyer_email_rejected_before_fulfillment(self):
        payload = make_event(email="not-an-email")
        header = sign_test_payload(payload, SECRET)
        with self.assertRaises(WebhookError):
            handle_webhook_event(payload, header, SECRET, self.store, mailer=self.mailer)
        self.assertEqual(len(self.mailer.sent), 0)


class TestStripeKeys(unittest.TestCase):
    # Keys are assembled at runtime so the repo never contains a full
    # sk_live_/sk_test_ literal (GitHub push protection treats those as secrets
    # even when they are clearly fake). Prefix + inert filler only.
    @staticmethod
    def _fake(kind: str) -> str:
        return "sk_" + kind + "_" + ("0" * 24)

    def test_live_key_refused_in_test_mode(self):
        from datetime import date
        with EnvGuard("STRIPE_TEST_MODE", "STRIPE_SECRET_KEY"):
            os.environ["STRIPE_TEST_MODE"] = "1"
            os.environ["STRIPE_SECRET_KEY"] = self._fake("live")
            with self.assertRaises(stripe_client.StripeError):
                stripe_client.create_checkout_session("buyer@test.local", date(2026, 1, 1))

    def test_test_key_refused_in_live_mode(self):
        from datetime import date
        with EnvGuard("STRIPE_TEST_MODE", "STRIPE_SECRET_KEY"):
            os.environ["STRIPE_TEST_MODE"] = "0"
            os.environ["STRIPE_SECRET_KEY"] = self._fake("test")
            with self.assertRaises(stripe_client.StripeError):
                stripe_client.create_checkout_session("buyer@test.local", date(2026, 1, 1))

    def test_live_key_with_whitespace_still_refused(self):
        from datetime import date
        with EnvGuard("STRIPE_TEST_MODE", "STRIPE_SECRET_KEY"):
            os.environ["STRIPE_TEST_MODE"] = "1"
            os.environ["STRIPE_SECRET_KEY"] = "  " + self._fake("live") + "\n"
            with self.assertRaises(stripe_client.StripeError):
                stripe_client.create_checkout_session("buyer@test.local", date(2026, 1, 1))


class TestMailerSecurity(unittest.TestCase):
    def test_validate_email_accepts_and_rejects(self):
        self.assertEqual(validate_email("buyer@test.local"), "buyer@test.local")
        for bad in ["", "no-at-sign", "a@b", "a b@test.local",
                    "buyer@test.local\r\nBcc: victim@test.local",
                    "buyer@test.local\nSubject: injected",
                    "x" * 250 + "@test.local"]:
            with self.assertRaises(MailerError, msg=bad):
                validate_email(bad)

    def test_header_injection_rejected_in_all_send_paths(self):
        class Exploding(EmailProvider):
            def send(self, *a, **k):
                raise AssertionError("provider must not be reached")
        dry = DryRunProvider(Exploding())
        with self.assertRaises(MailerError):
            dry.send("buyer@test.local", "Subject\r\nBcc: victim@test.local", "body")
        with self.assertRaises(MailerError):
            dry.send("buyer@test.local\r\nBcc: victim@test.local", "Subject", "body")
        with self.assertRaises(MailerError):
            send_license_email("not-an-email", generate_serial(), 800, mailer=Exploding())

    def test_dry_run_log_contains_no_email_or_serial(self):
        serial = generate_serial()
        body = f"Your license serial is:\n\n  {serial}\n"
        buf = io.StringIO()
        dry = DryRunProvider(EmailProvider())
        with contextlib.redirect_stdout(buf):
            result = dry.send("buyer@test.local", "Your FileRadar license serial", body)
        logged = buf.getvalue()
        self.assertNotIn("buyer@test.local", logged)
        self.assertNotIn(serial, logged)
        self.assertTrue(result["dry_run"])

    def test_config_admin_token_missing_is_none(self):
        with EnvGuard("LICENSING_ADMIN_TOKEN"):
            os.environ.pop("LICENSING_ADMIN_TOKEN", None)
            self.assertIsNone(config.admin_token())


if __name__ == "__main__":
    unittest.main()
