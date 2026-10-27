"""Serial-number generation and validation for FileRadar.

Format: FR-XXXX-XXXX-XXXX-XXXX  (16 characters in 4 groups of 4,
plus the "FR-" prefix; the prefix is not part of the checksum.)

Alphabet (31 characters, ambiguous characters excluded):
    ABCDEFGHJKMNPQRSTUVWXYZ23456789
Excluded: 0, O, 1, I, L  (0/O, 1/I/L confusion).
Alphabet order below is significant: it defines the checksum.
Index (authoritative order is the ALPHABET string in code):
A=0, B=1, C=2, D=3, E=4, F=5, G=6, H=7, J=8, K=9, M=10,
N=11, P=12, Q=13, R=14, S=15, T=16, U=17, V=18, W=19, X=20,
Y=21, Z=22, 2=23, 3=24, 4=25, 5=26, 6=27, 7=28, 8=29, 9=30.

Checksum algorithm (precise, so the Mac app can implement it identically):
  1. Generate 15 payload characters, each drawn uniformly at random
     from ALPHABET (use a CSPRNG: secrets.choice).
  2. checksum_index = sum( (i + 1) * ALPHABET.index(payload[i])
                           for i in 0..14 ) mod 31
     where i is the 0-based position in the payload (so the weight
     of the first character is 1, the second is 2, ..., the 15th is 15).
  3. checksum_char = ALPHABET[checksum_index]
  4. full = payload (15 chars) + checksum_char (1 char) = 16 chars.
  5. Display as FR- + full[0:4] + "-" + full[4:8] + "-" +
     full[8:12] + "-" + full[12:16].

Validation (local, offline, same algorithm):
  1. Strip whitespace, uppercase, remove hyphens. Optionally strip a
     leading "FR" prefix (with or without hyphen).
  2. The remaining string must be exactly 16 characters, all in ALPHABET.
  3. Recompute the checksum from the first 15 characters as above
     and require it to equal the 16th character.
  4. Anything else -> invalid. A single changed character in the
     payload changes the weighted sum mod 31 (see note below), so
     the recomputed checksum differs and the serial is rejected.

  Note on strength: this is a typo/tamper check, NOT cryptographic
  authentication. It catches every single-character change: 31 is
  prime, and for a single changed character the weighted sum changes
  by weight * delta, where weight is 1..15 and delta (the index
  difference) is 1..30 -- neither factor is divisible by 31, so
  their product is never 0 mod 31. It does NOT prove a serial was
  issued by metaPhasic Group: anyone who reads this document can
  forge a checksum-valid serial. That is why the app currently
  validates locally for UX only, and server-side validation
  (validate-serial endpoint, checking the serial exists in the
  database) is the authoritative check for any future enforcement.
  Do not present local checksum validation as piracy protection.

Swift sketch for the app team (same algorithm):
  let alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789" // 31 chars
  // payload = first 15 chars of the de-hyphenated, uppercased serial
  // sum = payload.enumerated().reduce(0) { $0 + ($1.offset + 1) *
  //         alphabet.firstIndex(of: $1.element)! (as integer offset) }
  // valid = (alphabet[sum % 31] == 16th char)
"""
from __future__ import annotations

import re
import secrets

ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
# Sanity: 31 symbols, no ambiguous chars.
assert len(ALPHABET) == 31
assert not set(ALPHABET) & set("01IOL")
assert len(set(ALPHABET)) == 31

PAYLOAD_LENGTH = 15
FULL_LENGTH = 16


def checksum_char(payload: str) -> str:
    """Compute the checksum character for a 15-char payload."""
    if len(payload) != PAYLOAD_LENGTH:
        raise ValueError(f"payload must be {PAYLOAD_LENGTH} chars, got {len(payload)}")
    total = 0
    for i, ch in enumerate(payload):
        try:
            idx = ALPHABET.index(ch)
        except ValueError:
            raise ValueError(f"character {ch!r} not in serial alphabet") from None
        total += (i + 1) * idx
    return ALPHABET[total % 31]


def generate_serial() -> str:
    """Generate a new random serial in FR-XXXX-XXXX-XXXX-XXXX form."""
    payload = "".join(secrets.choice(ALPHABET) for _ in range(PAYLOAD_LENGTH))
    full = payload + checksum_char(payload)
    groups = [full[i : i + 4] for i in range(0, FULL_LENGTH, 4)]
    return "FR-" + "-".join(groups)


def normalize_serial(raw: str) -> str | None:
    """Normalize user input to the 16-char body, or None if malformed.

    Accepts optional FR/FR- prefix, hyphens, spaces, lowercase.
    Returns None only for wrong length / illegal characters here;
    checksum is checked separately by is_valid_serial().
    """
    if raw is None:
        return None
    s = raw.strip().upper().replace("-", "").replace(" ", "")
    if s.startswith("FR"):
        s = s[2:]
    if len(s) != FULL_LENGTH:
        return None
    if any(ch not in ALPHABET for ch in s):
        return None
    return s


def is_valid_serial(raw: str) -> bool:
    """True iff the serial is well-formed AND its checksum matches."""
    body = normalize_serial(raw)
    if body is None:
        return False
    try:
        return checksum_char(body[:PAYLOAD_LENGTH]) == body[PAYLOAD_LENGTH]
    except ValueError:
        return False


def format_serial(body16: str) -> str:
    groups = [body16[i : i + 4] for i in range(0, FULL_LENGTH, 4)]
    return "FR-" + "-".join(groups)
