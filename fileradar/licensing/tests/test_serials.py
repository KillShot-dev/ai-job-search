"""Serial generation + checksum validation, incl. tamper rejection."""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from serials import ALPHABET, checksum_char, generate_serial, is_valid_serial, normalize_serial

PATTERN = re.compile(r"^FR-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$")


class TestSerials(unittest.TestCase):
    def test_format_and_alphabet(self):
        for _ in range(50):
            s = generate_serial()
            self.assertRegex(s, PATTERN)
            body = s[3:].replace("-", "")
            self.assertTrue(all(ch in ALPHABET for ch in body))
            self.assertNotIn("0", body)
            self.assertNotIn("O", body)
            self.assertNotIn("1", body)
            self.assertNotIn("I", body)
            self.assertNotIn("L", body)

    def test_generated_serials_validate(self):
        for _ in range(100):
            self.assertTrue(is_valid_serial(generate_serial()))

    def test_uniqueness_sample(self):
        serials = {generate_serial() for _ in range(1000)}
        self.assertEqual(len(serials), 1000)

    def test_every_single_char_change_rejected(self):
        # 31 is prime, so every single-character payload change must fail.
        serial = generate_serial()
        body = normalize_serial(serial)
        for pos in range(16):
            for replacement in ALPHABET:
                if replacement == body[pos]:
                    continue
                tampered = body[:pos] + replacement + body[pos + 1:]
                self.assertFalse(is_valid_serial(tampered),
                                 f"tamper at {pos} with {replacement} passed for {serial}")

    def test_checksum_char_known_vector(self):
        # Hand-computed: payload of 15 'A's (index 0) sums to 0 -> 'A'.
        self.assertEqual(checksum_char("A" * 15), "A")
        # Payload 'B' + 14 'A's: sum = 1*1 = 1 -> 'B'.
        self.assertEqual(checksum_char("B" + "A" * 14), "B")

    def test_rejects_garbage(self):
        for bad in ["", "FR-0000-0000-0000-0000",
                    "FR-AAAA-AAAA-AAAA-AAAB", "not-a-serial", "FR-SHORT"]:
            self.assertFalse(is_valid_serial(bad), bad)

    def test_accepts_lowercase_and_no_prefix(self):
        s = generate_serial()
        self.assertTrue(is_valid_serial(s.lower()))
        self.assertTrue(is_valid_serial(s[3:].replace("-", "")))


if __name__ == "__main__":
    unittest.main()
