"""Configuration for the FileRadar licensing backend.

All secrets and deployment-specific values come from environment variables.
Nothing secret is hardcoded here. See .env.example for variable names.

LAUNCH_DATE is a config value, deliberately NOT derived from today's date.
The price schedule is computed from it (see pricing.py).
"""
from __future__ import annotations

import os
from datetime import date


class ConfigError(ValueError):
    pass


def _env(name: str, default: str | None = None) -> str | None:
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return value


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


def parse_launch_date(raw: str | None) -> date:
    """Parse a YYYY-MM-DD launch date. Raises ConfigError if missing/invalid."""
    if not raw:
        raise ConfigError(
            "LAUNCH_DATE is not set. Set it to a YYYY-MM-DD date, e.g. "
            "LAUNCH_DATE=YYYY-MM-DD (see .env.example). "
            "The price schedule is computed from this value, not from today."
        )
    try:
        parts = raw.strip().split("-")
        if len(parts) != 3:
            raise ValueError
        return date(int(parts[0]), int(parts[1]), int(parts[2]))
    except ValueError:
        raise ConfigError(f"LAUNCH_DATE must be YYYY-MM-DD, got: {raw!r}") from None


def launch_date() -> date:
    return parse_launch_date(_env("LAUNCH_DATE"))


def stripe_test_mode() -> bool:
    # Default ON: safe by default. Production requires explicitly setting "0".
    return _env_bool("STRIPE_TEST_MODE", True)


def email_dry_run() -> bool:
    # Default ON: safe by default. No real email is sent unless explicitly "0".
    return _env_bool("EMAIL_DRY_RUN", True)


def email_provider() -> str:
    provider = (_env("EMAIL_PROVIDER", "ionos") or "ionos").strip().lower()
    if provider not in ("ionos", "resend"):
        raise ConfigError(f"EMAIL_PROVIDER must be 'ionos' or 'resend', got: {provider!r}")
    return provider


def db_path() -> str:
    return _env("LICENSING_DB_PATH", "licenses.db") or "licenses.db"


def stripe_secret_key() -> str | None:
    value = _env("STRIPE_SECRET_KEY")
    return value.strip() if value else value


def stripe_webhook_secret() -> str | None:
    value = _env("STRIPE_WEBHOOK_SECRET")
    return value.strip() if value else value


def admin_token() -> str | None:
    """Admin token for admin HTTP endpoints (LICENSING_ADMIN_TOKEN).

    Returns None when unset/empty. Callers must treat a missing token
    as "admin access denied" (fail closed) -- never as "no auth needed".
    The value itself is never logged or returned in any response.
    """
    value = _env("LICENSING_ADMIN_TOKEN")
    return value.strip() if value else None


def tls_terminated() -> bool:
    """True only when the operator confirms TLS terminates in front of us.

    This server itself serves plain HTTP only. Set
    LICENSING_TLS_TERMINATED=1 only when a reverse proxy / load balancer
    in front of it actually terminates TLS for real traffic.
    """
    return _env_bool("LICENSING_TLS_TERMINATED", False)


def tls_warning_active() -> bool:
    """True when real (non-test or non-loopback) traffic would arrive
    without TLS termination. Local test smoke runs (test mode on a
    loopback host, no TLS flag) do NOT trigger this warning."""
    host = server_host()
    loopback = host in ("127.0.0.1", "::1", "localhost")
    real_traffic = (not stripe_test_mode()) or (not loopback)
    return real_traffic and not tls_terminated()


def stripe_success_url() -> str:
    return _env("STRIPE_SUCCESS_URL", "http://localhost:8000/success?session_id={CHECKOUT_SESSION_ID}") or ""


def stripe_cancel_url() -> str:
    return _env("STRIPE_CANCEL_URL", "http://localhost:8000/cancel") or ""


def server_host() -> str:
    return _env("LICENSING_HOST", "127.0.0.1") or "127.0.0.1"


def server_port() -> int:
    try:
        return int(_env("LICENSING_PORT", "8000") or "8000")
    except ValueError:
        raise ConfigError("LICENSING_PORT must be an integer") from None
