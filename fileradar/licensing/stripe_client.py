"""Stripe Checkout session creation (TEST MODE ONLY by default).

Uses only the Python standard library (urllib) to call the Stripe
REST API directly -- no Stripe SDK dependency, so there is nothing
to install. This keeps the backend to stdlib + sqlite3.

Safety rules enforced here:
  - If STRIPE_TEST_MODE is on (the default) and STRIPE_SECRET_KEY
    starts with "sk_live_", creation is REFUSED. Live keys must
    never be used while test mode is on.
  - If no secret key is set at all while test mode is on, a MOCK
    test session is returned (id "cs_test_mock_...") so the full
    local flow (checkout -> webhook -> serial -> dry-run email) can
    be exercised with no Stripe account and no money. The mock is
    clearly labelled and can never be mistaken for a real session:
    its checkout URL is None. This is documented in the README as
    a placeholder, not a live payment flow.
  - If a real test key (sk_test_...) is set, a real TEST-mode
    Checkout Session is created via the live Stripe API. That path
    has NOT been exercised in this build (no Stripe account was
    connected); see README "UNTESTED".
"""
from __future__ import annotations

import json
import os
import urllib.parse
import urllib.request
from datetime import date

import config
import pricing


class StripeError(Exception):
    pass


def create_checkout_session(buyer_email: str, launch: date, on: date | None = None) -> dict:
    """Create a Checkout Session for one FileRadar license.

    Returns a dict with at least: id, url (None for mock sessions),
    amount_cents, currency, mode, test_mode, mock (bool).
    """
    from mailer import MailerError, validate_email

    try:
        buyer_email = validate_email(buyer_email)
    except MailerError as exc:
        raise StripeError("a valid buyer email is required") from exc
    amount = pricing.get_price_cents(launch, on)
    test_mode = config.stripe_test_mode()
    secret = config.stripe_secret_key()

    if secret and secret.startswith("sk_live_") and test_mode:
        raise StripeError(
            "Refusing to use a live Stripe secret key while STRIPE_TEST_MODE is on. "
            "Set STRIPE_TEST_MODE=0 only for a deliberate production switch (see README)."
        )
    if secret and secret.startswith("sk_test_") and not test_mode:
        raise StripeError(
            "Refusing to use a test Stripe secret key while STRIPE_TEST_MODE is off. "
            "Production requires a live key (see README)."
        )

    if not secret:
        if not test_mode:
            raise StripeError("STRIPE_SECRET_KEY is not set, but STRIPE_TEST_MODE is off.")
        # Mock test session: no Stripe account, no money, clearly labelled.
        return {
            "id": "cs_test_mock_000000000000000000000000",
            "url": None,
            "amount_cents": amount,
            "currency": pricing.CURRENCY,
            "mode": "payment",
            "test_mode": True,
            "mock": True,
            "buyer_email": buyer_email,
            "note": "Mock session: no Stripe key configured. "
                    "Set a real sk_test_ key to create a real TEST-mode session.",
        }

    # Real API call (test key expected; live key only if test mode was
    # explicitly switched off by the operator -- see refusal above).
    form = {
        "mode": "payment",
        "success_url": config.stripe_success_url(),
        "cancel_url": config.stripe_cancel_url(),
        "customer_email": buyer_email,
        "line_items[0][quantity]": "1",
        "line_items[0][price_data][currency]": pricing.CURRENCY,
        "line_items[0][price_data][unit_amount]": str(amount),
        "line_items[0][price_data][product_data][name]": "FileRadar License (1 Mac, one-time)",
    }
    data = urllib.parse.urlencode(form).encode("utf-8")
    req = urllib.request.Request(
        "https://api.stripe.com/v1/checkout/sessions", data=data, method="POST",
        headers={"Authorization": f"Bearer {secret}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:  # type: ignore[attr-defined]
        body = exc.read().decode("utf-8", "replace")
        raise StripeError(f"Stripe API error {exc.code}: {body}") from None
    return {
        "id": payload.get("id"),
        "url": payload.get("url"),
        "amount_cents": amount,
        "currency": pricing.CURRENCY,
        "mode": "payment",
        "test_mode": test_mode,
        "mock": False,
        "buyer_email": buyer_email,
    }
