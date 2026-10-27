"""Price schedule tests: $8 in window, $19 after, boundary behavior."""
import os
import sys
import unittest
from datetime import date

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from pricing import get_price_cents

LAUNCH = date(2026, 1, 1)


class TestPricing(unittest.TestCase):
    def test_launch_day_is_8(self):
        self.assertEqual(get_price_cents(LAUNCH, date(2026, 1, 1)), 800)

    def test_day_59_is_8(self):
        # 2026-01-01 + 59 days = 2026-03-01
        self.assertEqual(get_price_cents(LAUNCH, date(2026, 3, 1)), 800)

    def test_day_60_is_19_boundary(self):
        # 2026-01-01 + 60 days = 2026-03-02 -- first $19 day
        self.assertEqual(get_price_cents(LAUNCH, date(2026, 3, 2)), 1900)

    def test_day_61_is_19(self):
        self.assertEqual(get_price_cents(LAUNCH, date(2026, 3, 3)), 1900)

    def test_far_future_is_19(self):
        self.assertEqual(get_price_cents(LAUNCH, date(2027, 1, 1)), 1900)

    def test_before_launch_is_8_documented(self):
        # Documented pre-launch branch (see pricing.py docstring).
        self.assertEqual(get_price_cents(LAUNCH, date(2025, 12, 31)), 800)


if __name__ == "__main__":
    unittest.main()
