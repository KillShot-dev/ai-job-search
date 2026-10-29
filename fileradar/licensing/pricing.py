"""Price schedule for a FileRadar license.

Product: one-time purchase, 1 Mac, USD.
  - Launch price:  $8  (800 cents) for the first 60 days after launch.
  - Regular price: $19 (1900 cents) from day 60 onward.

Definition of the window (calendar dates, not datetimes):
  days = (on_date - launch_date).days
  price = $8  if days < 60
  price = $19 if days >= 60

So launch day itself is day 0 ($8), day 59 is the last $8 day,
and day 60 is the first $19 day. Dates before launch (days < 0)
also fall in the $8 branch; that is intentional for pre-launch
testing and is documented here rather than hidden in code.

LAUNCH_DATE is supplied by the caller (from config), never
defaulted to today inside this module, so the schedule is
testable and does not silently change when the code is run later.
"""
from __future__ import annotations

from datetime import date

LAUNCH_PRICE_CENTS = 800
REGULAR_PRICE_CENTS = 1900
LAUNCH_WINDOW_DAYS = 60
CURRENCY = "usd"


def get_price_cents(launch: date, on: date | None = None) -> int:
    """Return the price in cents for `on` given `launch` (both dates)."""
    if on is None:
        on = date.today()
    days = (on - launch).days
    if days < LAUNCH_WINDOW_DAYS:
        return LAUNCH_PRICE_CENTS
    return REGULAR_PRICE_CENTS


def price_for_launch_date_string(launch_raw: str, on: date | None = None) -> int:
    """Convenience wrapper taking a YYYY-MM-DD launch string."""
    from config import parse_launch_date

    return get_price_cents(parse_launch_date(launch_raw), on)
