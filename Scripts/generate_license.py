#!/usr/bin/env python3
"""ClipManager license serial generator / verifier.

This script EXACTLY mirrors the app's offline verification
(Sources/ClipManagerCore/License.swift): same format, same alphabet,
same HMAC, same canonical installId form. The Swift test suite runs it
with a build-time secret and verifies the "golden" serial it produces —
so the two implementations can never drift apart.

Serial format:  {PREFIX}-{PLAN}-{EXPIRY YYYYMMDD}-{PAYLOAD 20}-{CHECK 8}
  PAYLOAD  20 random chars from A-Z (no I, O) + 23456789
  CHECK    first 8 hex chars of HMAC-SHA256(secret, "installId|plan|expiry|payload")
           where installId is the canonical lower-case hyphenated UUID.

Usage:
  # generate (secret from --secret or $CLIP_LICENSE_SECRET)
  python3 Scripts/generate_license.py --install-id <uuid> --plan solo --expiry 20261231

  # verify
  python3 Scripts/generate_license.py --verify --serial <serial> --install-id <uuid>

Exit codes: 0 = ok / valid, 1 = invalid, 2 = usage error.
"""

import argparse
import hashlib
import hmac
import os
import random
import re
import sys
import uuid
from datetime import date, datetime

PREFIX = "CLIP"
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # A-Z without I, O + 23456789
PLANS = ("SOLO", "TEAM", "FIRMA")
PAYLOAD_LEN = 20
CHECK_LEN = 8
SERIAL_RE = re.compile(
    r"^(?P<prefix>CLIP)"
    r"-(?P<plan>SOLO|TEAM|FIRMA)"
    r"-(?P<expiry>\d{8})"
    r"-(?P<payload>[A-HJKLMNP-Z2-9]{20})"
    r"-(?P<check>[0-9a-fA-F]{8})$"
)


def fail(msg: str) -> None:
    print(f"invalid: {msg}", file=sys.stderr)
    sys.exit(1)


def norm_install_id(raw: str) -> str:
    """Canonical form: lower-case, hyphenated — matches Swift's normalizedInstallId."""
    try:
        return str(uuid.UUID(raw))
    except (ValueError, AttributeError, TypeError):
        fail(f"installId is not a valid UUID: {raw!r}")


def hmac_check(secret: str, install_id: str, plan: str, expiry: str, payload: str) -> str:
    msg = f"{install_id}|{plan}|{expiry}|{payload}"
    return hmac.new(secret.encode("utf-8"), msg.encode("utf-8"), hashlib.sha256).hexdigest()[:8]


def valid_expiry(expiry: str) -> bool:
    try:
        datetime.strptime(expiry, "%Y%m%d")
        return True
    except ValueError:
        return False


def generate(secret: str, install_id: str, plan: str, expiry: str, payload: str | None = None) -> str:
    if len(secret) == 0:
        fail("missing secret (use --secret or $CLIP_LICENSE_SECRET)")
    if plan not in PLANS:
        fail(f"plan must be one of {PLANS}")
    if not valid_expiry(expiry):
        fail(f"expiry must be YYYYMMDD: {expiry!r}")
    canonical_id = norm_install_id(install_id)
    if payload is None:
        payload = "".join(random.SystemRandom().choice(ALPHABET) for _ in range(PAYLOAD_LEN))
    if len(payload) != PAYLOAD_LEN or any(c not in ALPHABET for c in payload):
        fail(f"payload must be {PAYLOAD_LEN} chars from the license alphabet")
    check = hmac_check(secret, canonical_id, plan, expiry, payload)
    return f"{PREFIX}-{plan}-{expiry}-{payload}-{check}"


def verify(serial: str, secret: str, install_id: str, now: datetime | None = None) -> None:
    """Exit 0 if valid, else exit 1 with a reason (mirrors LicenseSerial.verify)."""
    if len(secret) == 0:
        fail("missing secret (use --secret or $CLIP_LICENSE_SECRET)")

    m = SERIAL_RE.match(serial.strip().upper())
    if not m:
        fail("bad format")
    plan, expiry, payload, check = m.group("plan"), m.group("expiry"), m.group("payload"), m.group("check").lower()

    if not valid_expiry(expiry):
        fail(f"bad expiry date: {expiry}")

    canonical_id = norm_install_id(install_id)

    # Expiry first (mirrors the app: an expired serial is rejected).
    now = now or datetime.now()
    exp_date = datetime.strptime(expiry, "%Y%m%d")
    if now >= exp_date.replace(hour=23, minute=59, second=59, microsecond=999999):
        fail(f"expired on {expiry}")

    expected = hmac_check(secret, canonical_id, plan, expiry, payload)
    if not hmac.compare_digest(expected, check):
        fail("checksum mismatch (wrong secret, corrupted serial, or bound to another installId)")

    print("valid")
    sys.exit(0)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate / verify ClipManager license serials.")
    parser.add_argument("--secret", default=os.environ.get("CLIP_LICENSE_SECRET", ""),
                        help="HMAC secret (or set $CLIP_LICENSE_SECRET)")
    parser.add_argument("--install-id", help="installation UUID (generate mode)")
    parser.add_argument("--plan", choices=[p.lower() for p in PLANS], help="plan (generate mode)")
    parser.add_argument("--expiry", help="expiry date YYYYMMDD (generate mode)")
    parser.add_argument("--payload", help=f"fixed {PAYLOAD_LEN}-char payload (generate mode, for tests)")
    parser.add_argument("--verify", action="store_true", help="verify a serial instead of generating")
    parser.add_argument("--serial", help="serial to verify (verify mode)")
    args = parser.parse_args()

    if args.verify:
        if not args.serial or not args.install_id:
            parser.error("--verify requires --serial and --install-id")
        verify(args.serial, args.secret, args.install_id)
        return

    if not args.install_id or not args.plan or not args.expiry:
        parser.error("generate mode requires --install-id, --plan and --expiry")
    print(generate(args.secret, args.install_id, args.plan.upper(), args.expiry, args.payload))


if __name__ == "__main__":
    main()
