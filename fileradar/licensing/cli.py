"""CLI equivalents of the licensing endpoints (no server needed).

Usage (from this directory):
  python3 cli.py serve
  python3 cli.py create-checkout --email buyer@example.com
  python3 cli.py demo-serial [--email demo@example.com]
  python3 cli.py validate-serial --serial FR-XXXX-XXXX-XXXX-XXXX
  python3 cli.py activate --serial FR-... --machine-hash <sha256>
  python3 cli.py deactivate --serial FR-... [--machine-hash <sha256>]
  python3 cli.py deactivate-serial --serial FR-...

demo-serial: generates a test serial locally and stores it with
source='demo' and price_paid_cents=0, so the Mac app demo unlock can
be exercised WITHOUT Stripe, WITHOUT money, and WITHOUT email.
Demo serials are marked in the database and must not be shipped
as paid licenses. The app team can distinguish them via source
only if they query this server; locally, a demo serial is
indistinguishable from a paid one by checksum alone -- treat
demo serials as test data and never publish them.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import config  # noqa: E402
import serials  # noqa: E402
import stripe_client  # noqa: E402
from store import Store  # noqa: E402


def _store() -> Store:
    return Store(config.db_path())


def cmd_demo_serial(email: str) -> dict:
    serial = serials.generate_serial()
    store = _store()
    try:
        record = store.create_serial(serial, email, 0, source="demo")
    finally:
        store.close()
    print(json.dumps({"serial": serial, "source": "demo", "record": record}, indent=2))
    return record


def main(argv=None):
    parser = argparse.ArgumentParser(description="FileRadar licensing CLI")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("serve", help="Start the HTTP server (see server.py)")
    p = sub.add_parser("create-checkout"); p.add_argument("--email", required=True)
    p = sub.add_parser("demo-serial"); p.add_argument("--email", default="demo@test.local")
    p = sub.add_parser("validate-serial"); p.add_argument("--serial", required=True)
    p = sub.add_parser("activate"); p.add_argument("--serial", required=True); p.add_argument("--machine-hash", required=True)
    p = sub.add_parser("deactivate"); p.add_argument("--serial", required=True); p.add_argument("--machine-hash")
    p = sub.add_parser("deactivate-serial"); p.add_argument("--serial", required=True)

    args = parser.parse_args(argv)
    if args.command == "serve":
        import server
        server.main()
        return
    if args.command == "create-checkout":
        print(json.dumps(stripe_client.create_checkout_session(args.email, config.launch_date()), indent=2))
        return
    if args.command == "demo-serial":
        cmd_demo_serial(args.email)
        return
    # Serial-accepting commands: normalize to canonical FR- form first.
    canonical = serials.format_serial(serials.normalize_serial(args.serial)) \
        if serials.normalize_serial(args.serial) else args.serial
    store = _store()
    try:
        if args.command == "validate-serial":
            known = store.get_serial(canonical)
            active = store.active_activation(known["id"]) if known else None
            print(json.dumps({
                "valid_checksum": serials.is_valid_serial(args.serial),
                "known": known is not None,
                "status": known["status"] if known else None,
                "active_machine": active is not None,
            }, indent=2))
        elif args.command == "activate":
            print(json.dumps(store.activate(canonical, args.machine_hash), indent=2))
        elif args.command == "deactivate":
            print(json.dumps({"deactivated": store.deactivate(canonical, args.machine_hash)}, indent=2))
        elif args.command == "deactivate-serial":
            store.deactivate_serial(canonical)
            print(json.dumps({"deactivated_serial": True}, indent=2))
    finally:
        store.close()


if __name__ == "__main__":
    main()
