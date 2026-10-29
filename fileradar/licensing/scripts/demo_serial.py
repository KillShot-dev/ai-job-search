#!/usr/bin/env python3
"""Generate a demo/test serial for Mac app demo unlock -- no Stripe, no money.

Usage:
  python3 scripts/demo_serial.py [--email demo@test.local]

Prints the serial as JSON and stores it in the local SQLite database
with source='demo' and price_paid_cents=0. See cli.py demo-serial
for the same flow. Demo serials are test data, not paid licenses.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from cli import cmd_demo_serial  # noqa: E402

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate a FileRadar demo serial")
    parser.add_argument("--email", default="demo@test.local")
    args = parser.parse_args()
    cmd_demo_serial(args.email)
