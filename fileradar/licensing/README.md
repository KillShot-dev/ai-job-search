# FileRadar Licensing Backend

Test-mode-only licensing backend for FileRadar (Finder alternative for Mac,
metaPhasic Group). One-time purchase, 1 Mac, USD. Support contact:
support@metaphasic.net. No personal information appears in this backend.

## Stack choice (and why)

**Python standard library + sqlite3, no third-party packages.**
Justification: the whole backend is HTTP + HMAC + SMTP/HTTP + SQLite,
all of which the stdlib covers; adding the Stripe SDK, Flask, or an
ORM would add install steps, version risk, and supply-chain surface
for no needed capability. It runs with one command (`python3 server.py`)
on any machine with Python 3.10+, which is also what the Mac app team
already has for tooling. Node was the alternative; it was not chosen
because it would still need an HTTP framework or raw `http` handling
plus a Stripe dependency for no benefit here.

## Architecture

```
create-checkout (Stripe Checkout Session, TEST mode)
        |
        v  buyer pays in Stripe Checkout (test mode)
webhook: checkout.session.completed  -- HMAC-SHA256 verified -->
        generate serial (FR-XXXX-XXXX-XXXX-XXXX, checksum, see serials.py)
        store serial in SQLite
        send license email (provider interface, dry-run by default)
        |
        v
Mac app: local checksum check (UX only, NOT authoritative)
         + server validate-serial / activate / deactivate
```

Files:

| File | Role |
|---|---|
| `server.py` | HTTP server (stdlib `http.server`), all endpoints |
| `cli.py` | CLI equivalents of every endpoint (`serve`, `create-checkout`, `demo-serial`, `validate-serial`, `activate`, `deactivate`, `deactivate-serial`) |
| `config.py` | Env-var config; `LAUNCH_DATE` parsing (never defaults to today) |
| `pricing.py` | Price schedule: $8 first 60 days after launch, then $19 |
| `serials.py` | Serial generation + checksum algorithm (precise spec for the app team) |
| `store.py` | SQLite storage + activation state machine (one active Mac) |
| `schema.sql` | Schema (also auto-created by `store.py`) |
| `stripe_client.py` | Stripe Checkout via stdlib `urllib` (test mode; mock fallback) |
| `webhook.py` | Stripe signature verification + fulfillment + idempotency |
| `mailer.py` | Provider interface: IONOS SMTP + Resend HTTP, dry-run wrapper |
| `templates/license_email.txt` | License email copy (no refund terms stated — none were provided) |
| `scripts/demo_serial.py` | Demo-serial generator for app testing (no Stripe, no money) |
| `tests/` | `unittest` suites (see Tests) |
| `.env.example` | Variable names only — NO real values |

## Serial format and checksum (for the Mac app team)

Full spec lives in `serials.py` (the docstring is the contract).
Summary: `FR-XXXX-XXXX-XXXX-XXXX`, 16 body characters from the
31-symbol alphabet `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (excludes
`0, O, 1, I, L`). The first 15 characters are random (`secrets`).
The 16th is a checksum: `ALPHABET[sum((i+1) * ALPHABET.index(payload[i])
for i in 0..14) mod 31]`. Validation: strip `FR`/hyphens/spaces,
uppercase, require 16 alphabet characters, recompute and compare.
Because 31 is prime, every single-character change is detected.
**Local checksum validation is a typo check only, not proof of
purchase** — anyone reading this spec can forge a checksum-valid
serial. Server-side `validate-serial` (serial exists in the database
and is `active`) is the authoritative check.

## Database

SQLite tables (`schema.sql`):

- `serials`: `serial` (unique), `buyer_email`, `purchase_date`,
  `price_paid_cents`, `currency` (`usd`), `status`
  (`active`/`deactivated`), `source` (`stripe`/`demo`), timestamps.
- `activations`: `serial_id`, `machine_hash` (a HASH of a machine
  identifier — the app must hash before sending; the server stores
  only what it receives), `status`, timestamps.
- `webhook_events`: Stripe event ids, for webhook idempotency.

State machine: a serial has at most ONE `active` activation.
Activating on a second Mac returns HTTP 409. To move Macs:
`POST /deactivate` (frees the current Mac; the serial stays
`active`), then `POST /activate` on the new Mac. Re-activating on
the same `machine_hash` is idempotent. `POST /deactivate-serial`
revokes the serial entirely (admin use, not the move flow).

## Setup (test mode)

No Stripe account, no mail credentials, no money needed:

```bash
cd ~/workspace/goals/fileradar/licensing
# No pip install needed (stdlib only). Set config in the environment:
export LAUNCH_DATE=YYYY-MM-DD        # YOUR launch date, e.g. the real one
export STRIPE_TEST_MODE=1            # default ON
export EMAIL_DRY_RUN=1               # default ON: mail is logged, never sent
export EMAIL_PROVIDER=ionos          # or resend
export STRIPE_WEBHOOK_SECRET=whsec_test_placeholder   # any test value for local signing
export LICENSING_PORT=8000
export LICENSING_ADMIN_TOKEN=<a-long-random-token>  # required for /deactivate-serial
python3 server.py
```

`.env.example` lists every variable (names only). This server does
not load `.env` files itself; export the variables (or
`set -a; source .env; set +a`) before starting it. Never commit a
real `.env` file, and never put a real key in any file in this repo.

## Run end-to-end in test mode (zero money, zero real email)

```bash
# 1. Start the server (terminal 1) as above.
# 2. Create a checkout (no Stripe key configured -> labelled mock session):
curl -X POST http://127.0.0.1:8000/create-checkout \
  -H 'Content-Type: application/json' -d '{"email":"buyer@test.local"}'
#    -> {"id": "cs_test_mock_...", "url": null, "amount_cents": 800, "mock": true, ...}
#    The amount is $8 (800) while within 60 days of LAUNCH_DATE, else $19 (1900).

# 3. Simulate Stripe's webhook with a locally signed payload:
python3 - <<'EOF'
import json, urllib.request, sys
sys.path.insert(0, '.')
from webhook import sign_test_payload
import os
secret = os.environ["STRIPE_WEBHOOK_SECRET"]
payload = json.dumps({"id": "evt_test_1", "type": "checkout.session.completed",
  "data": {"object": {"customer_email": "buyer@test.local",
    "customer_details": {"email": "buyer@test.local"}, "amount_total": 800}}}).encode()
req = urllib.request.Request("http://127.0.0.1:8000/webhook", data=payload,
    headers={"Stripe-Signature": sign_test_payload(payload, secret)}, method="POST")
print(urllib.request.urlopen(req).read().decode())
EOF
#    -> fulfilled, with a serial; the server prints a [DRY RUN EMAIL] line
#       (provider + subject only — recipient and serial are deliberately
#       withheld from logs) and sends nothing.

# 4. Validate / activate / move:
curl -X POST http://127.0.0.1:8000/validate-serial -d '{"serial":"FR-..."}'
curl -X POST http://127.0.0.1:8000/activate \
  -d '{"serial":"FR-...","machine_hash":"<sha256-of-machine-id>"}'
curl -X POST http://127.0.0.1:8000/activate \
  -d '{"serial":"FR-...","machine_hash":"<other-mac-hash>"}'   # -> HTTP 409
curl -X POST http://127.0.0.1:8000/deactivate -d '{"serial":"FR-..."}'
curl -X POST http://127.0.0.1:8000/activate \
  -d '{"serial":"FR-...","machine_hash":"<other-mac-hash>"}'   # now succeeds
# Revoke a serial (admin only — no token, or a wrong token, gets a
# generic 403 and changes nothing):
curl -X POST http://127.0.0.1:8000/deactivate-serial \
  -H "X-Admin-Token: $LICENSING_ADMIN_TOKEN" -d '{"serial":"FR-..."}'
```

CLI equivalents (no server): `python3 cli.py create-checkout --email
...`, `validate-serial`, `activate`, `deactivate`, `deactivate-serial`
— see `cli.py --help` per subcommand.

## Demo-license flow (Mac app testing, no Stripe)

```bash
python3 scripts/demo_serial.py [--email demo@test.local]
# or: python3 cli.py demo-serial [--email demo@test.local]
```

Prints a serial and stores it with `source='demo'`,
`price_paid_cents=0`. Use it to exercise the app's demo unlock.
Demo serials are test data: they are checksum-valid and locally
indistinguishable from paid serials, so never publish them and
never treat them as paid licenses. (Server-side, they are marked
by `source='demo'` in the `serials` table.)

## Email providers

Selected by `EMAIL_PROVIDER`: `ionos` (SMTP `smtp.ionos.com:587`,
STARTTLS; needs `IONOS_SMTP_USER`, `IONOS_SMTP_PASS`, `IONOS_FROM`)
or `resend` (HTTP `https://api.resend.com/emails`; needs
`RESEND_API_KEY`, `RESEND_FROM`). While `EMAIL_DRY_RUN=1` (default),
either provider is wrapped so it only LOGS recipient, subject, and
serial — no connection to IONOS or Resend is made. Real sending
requires `EMAIL_DRY_RUN=0` plus real credentials (see Production).

Email copy (`templates/license_email.txt`): serial, how to activate,
deactivate-to-move note, support contact support@metaphasic.net.
No refund terms are stated, because none were provided — do not
invent any.

## Switching to production LATER (user steps — nothing here is done yet)

All of the following are supplied by the user; no production value
is invented or stored in this repo:

1. In the Stripe Dashboard (a real Stripe account, created by the user):
   create the product/price OR keep using the server-computed amount
   (current code sends `price_data` with the computed cents — no
   dashboard price id is required), and create a webhook endpoint
   pointing at the deployed server's `/webhook` for
   `checkout.session.completed`.
2. Set `STRIPE_TEST_MODE=0`, `STRIPE_SECRET_KEY` to the real LIVE
   secret key, and `STRIPE_WEBHOOK_SECRET` to the real LIVE webhook
   signing secret. (While test mode is on, the server REFUSES live keys.)
3. Set `EMAIL_DRY_RUN=0` and supply real mail credentials for the
   chosen provider (`IONOS_*` or `RESEND_*`).
4. Set the real `LAUNCH_DATE` (YYYY-MM-DD). The $8/$19 switch follows it.
5. Deploy behind TLS with authenticated admin access before exposing
   it publicly (see "Security posture" and "Production checklist"
   below — admin auth, TLS termination, DB permissions, and live-key
   handling are all operator steps). Also run a real test purchase
   in Stripe TEST mode first (with a `sk_test_` key and a test
   webhook secret) before flipping to live.
6. Point the Mac app at the deployed `/validate-serial`, `/activate`,
   and `/deactivate` endpoints if server-side validation is adopted
   (currently the app validates locally only).

## Security posture (as hardened 2026-10-27; stdlib only, no new deps)

- **Admin auth — the only admin HTTP endpoint is
  `POST /deactivate-serial`.** It requires `LICENSING_ADMIN_TOKEN`
  (env var, name only — never a value — in `.env.example`), sent as
  `X-Admin-Token` or `Authorization: Bearer`. Comparison is
  constant-time (`hmac.compare_digest`); missing token, wrong token,
  and "no token configured" all return the identical generic
  `403 {"error": "forbidden"}`. If no token is configured, admin
  access is DENIED (fail closed), never open. Every other endpoint
  is part of the normal buyer/app flow and is authenticated by the
  serial itself — treat serials as credentials. The CLI's
  `deactivate-serial` is a local-operator command (it needs direct
  filesystem access to the same SQLite file), not an HTTP endpoint.
- **SQL: every query is parameterized** (including error/edge
  paths); the schema is a static string only. The one-active-Mac
  rule is additionally enforced by a partial unique DB index
  (`activations(serial_id) WHERE status='active'`), so concurrent
  activates cannot both succeed.
- **Webhook:** HMAC-SHA256 over the raw request body, constant-time
  compare against every `v1` value, ±5-minute timestamp tolerance
  (replay guard). Events are validated (event id, buyer email,
  amount) BEFORE the idempotency mark is written, and a failed
  fulfillment rolls its serial + mark back, so a Stripe retry
  fulfills exactly once instead of reporting `already_processed`
  for a failed delivery. Non-checkout events are ignored unmarked.
- **Rate limiting (in-process, per client IP, per 60 s):**
  `/create-checkout` 20, `/validate-serial` 60, `/activate` 30,
  `/deactivate` 30, `/deactivate-serial` 10, `/webhook` 120.
  Excess returns `429 {"error": "rate limit exceeded"}` with
  `Retry-After: 60`. Per-process only: a multi-process deployment
  needs a shared limiter at the proxy. `X-Forwarded-For` is never
  trusted for limiting (spoofable); the peer IP is used.
- **Stripe keys:** secrets come from the environment only and are
  never logged or returned in error bodies. While test mode is on,
  a `sk_live_` key is REFUSED (tested, including whitespace-padded
  keys); while test mode is off, a `sk_test_` key is likewise
  refused. Stripe API error bodies are never relayed to callers
  (generic `502 {"error": "payment provider error"}`).
- **Mailer:** buyer emails are format-validated and CR/LF-checked
  before ANY send path (checkout, webhook, dry-run, IONOS, Resend);
  subjects/senders are CR/LF-checked (header-injection guards).
  Dry-run (default) logs provider + subject only — never the buyer
  email (PII) or the serial (license credential).
- **Activation state machine:** second Mac → 409; deactivate →
  reactivate on a new Mac works; same-Mac re-activation is
  idempotent; revocation blocks new activations. Machine-hash
  comparison is constant-time.
- **Responses:** security headers on every response
  (`X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
  `Referrer-Policy: no-referrer`, `Cache-Control: no-store`,
  `Content-Security-Policy: default-src 'none'`); the `Server`
  header does not leak the Python version; error bodies are
  generic (no stack traces, no internal details, no secrets);
  request logs carry method + path only (query strings stripped),
  never headers or bodies. Request bodies are capped at 1 MB
  (413 above that).
- **Files:** the SQLite DB is created (and any pre-existing file
  is tightened) to mode `0600`. At-rest protection beyond file
  permissions is an operator requirement — host the DB on an
  encrypted volume. No custom crypto is implemented anywhere.
- **TLS:** this server serves plain HTTP only and never terminates
  TLS itself. See the production checklist: TLS termination in
  front of it is REQUIRED for real traffic.

## Production checklist (operator steps — none done by this repo)

1. **Admin token:** set a long random `LICENSING_ADMIN_TOKEN`.
   Verify `/deactivate-serial` without it returns 403.
2. **TLS termination:** put a TLS reverse proxy / load balancer in
   front of the server and set `LICENSING_TLS_TERMINATED=1` ONLY
   when that proxy really terminates TLS. Until then, with test
   mode off or a non-loopback host, the server logs a loud startup
   WARNING and `/health` reports `tls_warning: true`. Local test
   smoke runs (test mode on loopback) are unaffected.
3. **DB permissions + at-rest:** confirm the DB file is `0600`
   (the server enforces this on open), keep it on an encrypted
   volume, back it up, and `chmod 600` any real `.env` file.
4. **Stripe live keys:** set `STRIPE_TEST_MODE=0`, a real
   `sk_live_` secret, and the real live webhook secret — only after
   a real TEST-mode purchase succeeds. Never put a live key in a
   file, a log, or a test.
5. **Mail:** set `EMAIL_DRY_RUN=0` plus real provider credentials
   (`IONOS_*` or `RESEND_*`), and send a real test license email.
6. **Rate limiting at the edge:** if deploying multi-process or
   behind a proxy, add a shared rate limiter / WAF at the proxy;
   the in-process limiter does not span processes.
7. **Launch date:** set the real `LAUNCH_DATE` (the $8/$19 switch
   follows it: $8 for the first 60 days, then $19, one-time, 1 Mac).

## Tests

```bash
python3 -m unittest discover -s tests -v
```

Suites: `test_pricing.py` ($8 in window, $19 after, day-59/day-60
boundary), `test_serials.py` (format, alphabet, checksum, rejection
of EVERY single-character tamper, garbage rejection),
`test_webhook.py` (fake signed payload, bad/tampered signature,
duplicate event id, non-checkout event ignored, dry-run mailer),
`test_activations.py` (one-active-Mac state machine, move flow,
idempotent re-activation, revocation),
`test_security.py` (admin auth incl. fail-closed + generic 403,
rate limiting unit + HTTP 429, security headers, generic error
bodies, TLS health flags, SQL-injection-as-literal, DB 0600,
one-active-Mac DB index, webhook replay tolerance + idempotency
rollback, Stripe live/test key refusal, mailer validation +
header-injection guards, dry-run log redaction). Full suite:
59 tests, all passing as of the 2026-10-27 hardening pass.

## UNTESTED / placeholders — honest limits

- **No live Stripe account was connected.** No real Checkout Session
  was created and no real payment was taken. With no key configured,
  `/create-checkout` returns a clearly-labelled MOCK session
  (`mock: true`, `url: null`). The real-API code path in
  `stripe_client.py` (a `sk_test_` key calling Stripe) is written
  but NOT exercised.
- **No real email was sent.** All email paths were tested in dry-run
  (logged) mode only. IONOS SMTP login and the Resend HTTP call are
  implemented but NOT exercised against real providers.
- **Webhook signature verification was tested only with locally
  constructed payloads** signed with a fake test secret (see
  `test_webhook.py` and the smoke test). No webhook was ever received
  from Stripe's servers.
- **No production deployment exists.** TLS termination, a real
  admin token, an encrypted volume, a hosted database, and backups
  are all operator steps (see Production checklist). The SQLite
  file is local only, mode 0600. Rate limiting is in-process only
  and does not span processes.
- **The Mac app side is not implemented here** (local checksum check,
  machine-hash generation, License UI). The checksum spec in
  `serials.py` is written for that team to implement; it has not
  been verified against a Swift implementation.
- **No refund, tax, VAT, or invoicing terms** are implemented or
  stated anywhere, because none were provided. Stripe Checkout in
  test mode handles tax only if configured in the dashboard later.
