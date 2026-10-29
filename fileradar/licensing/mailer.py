"""Email delivery for license emails, behind a provider interface.

Providers (selected by EMAIL_PROVIDER env var):
  - "ionos":  SMTP to smtp.ionos.com:587 with STARTTLS.
               Credentials: IONOS_SMTP_USER, IONOS_SMTP_PASS, IONOS_FROM.
  - "resend": HTTP POST to https://api.resend.com/emails.
               Credentials: RESEND_API_KEY, RESEND_FROM.

Dry run (default ON):
  When EMAIL_DRY_RUN is set to a truthy value (default "1"), NO email
  is sent by either provider. Instead the mailer logs the recipient,
  subject, and serial to stdout and returns {"dry_run": True, ...}.
  This is what makes end-to-end testing possible with zero real emails.
  Set EMAIL_DRY_RUN=0 only when real delivery is intended, with real
  credentials supplied by the user (see README, production section).

No credential is ever hardcoded here; all come from environment variables.
"""
from __future__ import annotations

import json
import os
import re
import smtplib
import sys
import urllib.request
from email.message import EmailMessage

SUPPORT_EMAIL = "support@metaphasic.net"

# Pragmatic buyer-email validation: one '@', no whitespace or
# control characters, a dotted domain. Accepts test domains such as
# buyer@test.local. This is a format gate before any send path, not
# proof that the mailbox exists.
_EMAIL_RE = re.compile(r"^[^@\s\x00-\x1f\x7f]{1,64}@[^@\s\x00-\x1f\x7f]+\.[^@\s\x00-\x1f\x7f]+$")


class MailerError(Exception):
    pass


def validate_email(address: str | None) -> str:
    """Return a stripped, validated email or raise MailerError.

    Also rejects CR/LF anywhere (header-injection guard) and
    over-long values. Used by every send path and by callers that
    accept a buyer email (server checkout, webhook fulfillment).
    """
    if not address or not isinstance(address, str):
        raise MailerError("a valid buyer email is required")
    value = address.strip()
    if len(value) > 254 or "\r" in value or "\n" in value:
        raise MailerError("a valid buyer email is required")
    if not _EMAIL_RE.match(value):
        raise MailerError("a valid buyer email is required")
    return value


def _check_header_value(name: str, value: str) -> None:
    if "\r" in value or "\n" in value:
        raise MailerError(f"invalid characters in {name}")
    if len(value) > 998:
        raise MailerError(f"{name} is too long")


def render_license_email(serial: str, price_paid_cents: int) -> tuple[str, str]:
    """Render (subject, plain-text body) from the template file if present.

    Falls back to the built-in copy (identical wording) if the template
    file is missing, so the mailer never fails on a missing template.
    Placeholders: {{SERIAL}}, {{PRICE}}, {{SUPPORT_EMAIL}}.
    No refund terms are stated anywhere in this copy (none were provided).
    """
    price = f"${price_paid_cents / 100:.2f}"
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        with open(os.path.join(here, "templates", "license_email.txt"), encoding="utf-8") as f:
            template = f.read()
    except OSError:
        template = (
            "Hello,\n\nThank you for purchasing FileRadar.\n\n"
            "Your license serial is:\n\n  {{SERIAL}}\n\n"
            "To activate: open FileRadar on your Mac, go to License, "
            "and enter this serial.\n\n"
            "This license covers one Mac at a time. To move to a new Mac, "
            "deactivate FileRadar on the old Mac first (or contact support), "
            "then activate on the new Mac.\n\n"
            "Questions? Contact {{SUPPORT_EMAIL}}.\n\n"
            "Price paid: {{PRICE}} (one-time purchase).\n"
        )
    body = (
        template.replace("{{SERIAL}}", serial)
        .replace("{{PRICE}}", price)
        .replace("{{SUPPORT_EMAIL}}", SUPPORT_EMAIL)
    )
    subject = "Your FileRadar license serial"
    return subject, body


class EmailProvider:
    def send(self, to_email: str, subject: str, body: str) -> dict:
        raise NotImplementedError


class IonosSmtpProvider(EmailProvider):
    HOST = "smtp.ionos.com"
    PORT = 587

    def send(self, to_email: str, subject: str, body: str) -> dict:
        to_email = validate_email(to_email)
        _check_header_value("subject", subject)
        user = os.environ.get("IONOS_SMTP_USER")
        password = os.environ.get("IONOS_SMTP_PASS")
        sender = os.environ.get("IONOS_FROM") or user
        if not user or not password or not sender:
            raise MailerError(
                "IONOS credentials missing: set IONOS_SMTP_USER, IONOS_SMTP_PASS, "
                "and IONOS_FROM in the environment."
            )
        _check_header_value("From", sender)
        msg = EmailMessage()
        msg["From"] = sender
        msg["To"] = to_email
        msg["Subject"] = subject
        msg.set_content(body)
        with smtplib.SMTP(self.HOST, self.PORT, timeout=30) as smtp:
            smtp.starttls()
            smtp.login(user, password)
            smtp.send_message(msg)
        return {"provider": "ionos", "to": to_email, "sent": True}


class ResendProvider(EmailProvider):
    ENDPOINT = "https://api.resend.com/emails"

    def send(self, to_email: str, subject: str, body: str) -> dict:
        to_email = validate_email(to_email)
        _check_header_value("subject", subject)
        api_key = os.environ.get("RESEND_API_KEY")
        sender = os.environ.get("RESEND_FROM")
        if not api_key or not sender:
            raise MailerError(
                "Resend credentials missing: set RESEND_API_KEY and RESEND_FROM "
                "in the environment."
            )
        _check_header_value("From", sender)
        payload = json.dumps(
            {"from": sender, "to": [to_email], "subject": subject, "text": body}
        ).encode("utf-8")
        req = urllib.request.Request(
            self.ENDPOINT, data=payload,
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read().decode("utf-8") or "{}")
        return {"provider": "resend", "to": to_email, "sent": True, "resend_id": result.get("id")}


class DryRunProvider(EmailProvider):
    """Wraps a real provider but never sends; logs only that a mail
    would have been sent. The recipient address and the serial are
    NOT written to logs: the address is buyer PII and the serial is
    a license credential. The return dict still carries them for the
    (already signature-authenticated) webhook caller, not for logs."""

    def __init__(self, inner: EmailProvider):
        self.inner = inner

    def send(self, to_email: str, subject: str, body: str) -> dict:
        to_email = validate_email(to_email)
        _check_header_value("subject", subject)
        serial_line = next((ln.strip() for ln in body.splitlines() if ln.strip().startswith("FR-")), "")
        print(f"[DRY RUN EMAIL] provider={type(self.inner).__name__} "
              f"subject={subject!r} (recipient and serial withheld from logs)",
              file=sys.stdout, flush=True)
        return {"provider": f"dry-run({type(self.inner).__name__})",
                "to": to_email, "dry_run": True, "serial": serial_line}


def get_mailer() -> EmailProvider:
    """Build the configured provider, wrapped in dry-run unless explicitly disabled."""
    import config

    provider_name = config.email_provider()
    inner: EmailProvider = IonosSmtpProvider() if provider_name == "ionos" else ResendProvider()
    if config.email_dry_run():
        return DryRunProvider(inner)
    return inner


def send_license_email(to_email: str, serial: str, price_paid_cents: int,
                       mailer: EmailProvider | None = None) -> dict:
    # Validate before rendering/sending so no provider (real or dry-run)
    # is ever reached with a malformed or injection-bearing address.
    to_email = validate_email(to_email)
    subject, body = render_license_email(serial, price_paid_cents)
    return (mailer or get_mailer()).send(to_email, subject, body)
