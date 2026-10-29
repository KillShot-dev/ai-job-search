"""Webhook handling with a locally constructed (fake) signed payload.

No real Stripe account is involved: the payload is built here and
signed with a test secret using the same HMAC scheme Stripe uses,
so this tests verification logic, not Stripe's servers.
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from mailer import DryRunProvider, EmailProvider
from store import Store
from webhook import WebhookError, handle_webhook_event, sign_test_payload, verify_stripe_signature

SECRET = "whsec_test_fake_secret_for_local_tests_only"


class CapturingMailer(EmailProvider):
    def __init__(self):
        self.sent = []

    def send(self, to_email, subject, body):
        self.sent.append({"to": to_email, "subject": subject, "body": body})
        return {"dry_run": True, "to": to_email}


def make_event(event_id="evt_test_123", email="buyer@test.local", amount=800):
    event = {
        "id": event_id,
        "type": "checkout.session.completed",
        "data": {"object": {
            "id": "cs_test_123",
            "customer_email": email,
            "customer_details": {"email": email},
            "amount_total": amount,
        }},
    }
    return json.dumps(event).encode("utf-8")


class TestWebhook(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Store(os.path.join(self.tmp.name, "test.db"))
        self.mailer = CapturingMailer()

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def test_valid_signature_fulfills(self):
        payload = make_event()
        header = sign_test_payload(payload, SECRET)
        result = handle_webhook_event(payload, header, SECRET, self.store, mailer=self.mailer)
        self.assertTrue(result["fulfilled"])
        self.assertEqual(result["buyer_email"], "buyer@test.local")
        self.assertEqual(result["price_paid_cents"], 800)
        self.assertTrue(result["serial"].startswith("FR-"))
        self.assertEqual(len(self.mailer.sent), 1)
        self.assertEqual(self.mailer.sent[0]["to"], "buyer@test.local")
        self.assertIn(result["serial"], self.mailer.sent[0]["body"])
        stored = self.store.get_serial(result["serial"])
        self.assertIsNotNone(stored)
        self.assertEqual(stored["status"], "active")

    def test_bad_signature_rejected(self):
        payload = make_event()
        header = sign_test_payload(payload, "whsec_wrong_secret")
        with self.assertRaises(WebhookError):
            handle_webhook_event(payload, header, SECRET, self.store, mailer=self.mailer)
        self.assertEqual(len(self.mailer.sent), 0)

    def test_tampered_payload_rejected(self):
        payload = make_event()
        header = sign_test_payload(payload, SECRET)
        tampered = payload.replace(b"800", b"190")
        with self.assertRaises(WebhookError):
            handle_webhook_event(tampered, header, SECRET, self.store, mailer=self.mailer)

    def test_missing_header_rejected(self):
        with self.assertRaises(WebhookError):
            handle_webhook_event(make_event(), None, SECRET, self.store, mailer=self.mailer)

    def test_duplicate_event_id_creates_no_second_serial(self):
        payload = make_event()
        header = sign_test_payload(payload, SECRET)
        first = handle_webhook_event(payload, header, SECRET, self.store, mailer=self.mailer)
        second = handle_webhook_event(payload, header, SECRET, self.store, mailer=self.mailer)
        self.assertTrue(second.get("already_processed"))
        self.assertEqual(len(self.mailer.sent), 1)

    def test_other_event_type_ignored(self):
        event = {"id": "evt_other", "type": "payment_intent.created", "data": {"object": {}}}
        payload = json.dumps(event).encode("utf-8")
        header = sign_test_payload(payload, SECRET)
        result = handle_webhook_event(payload, header, SECRET, self.store, mailer=self.mailer)
        self.assertTrue(result.get("ignored"))
        self.assertEqual(len(self.mailer.sent), 0)

    def test_dry_run_mailer_logs_not_sends(self):
        # DryRunProvider is the production default path; it must not
        # call through to a real provider.
        class Exploding(EmailProvider):
            def send(self, *a, **k):
                raise AssertionError("real provider must not be called in dry run")
        dry = DryRunProvider(Exploding())
        result = dry.send("buyer@test.local", "Your FileRadar license serial",
                          "Your license serial is:\n\n  FR-AAAA-AAAA-AAAA-AAAA\n")
        self.assertTrue(result["dry_run"])


if __name__ == "__main__":
    unittest.main()
