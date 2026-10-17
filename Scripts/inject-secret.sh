#!/usr/bin/env bash
# Injects the license HMAC secret into Sources/ClipManagerCore/SecretConfig.swift
# at build time, from the CLIP_LICENSE_SECRET environment variable.
#
#   make build  -> injects $CLIP_LICENSE_SECRET (if set), otherwise resets to nil
#   --reset     -> always resets to nil (fail closed)
#
# The secret never lives in the repository: CI additionally verifies the
# checked-in file contains the nil template before building.
set -euo pipefail

FILE="Sources/ClipManagerCore/SecretConfig.swift"
RESET=0
if [ "${1:-}" = "--reset" ]; then RESET=1; fi

SECRET="${CLIP_LICENSE_SECRET:-}"

if [ "$RESET" = "1" ] || [ -z "$SECRET" ]; then
  LC_SECRET="" python3 - "$FILE" <<'PY'
import os, sys
path = sys.argv[1]
secret = os.environ.get("LC_SECRET", "")
if not secret:
    value = "nil"
else:
    def esc(ch):
        return {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\r": "\\r", "\t": "\\t"}.get(ch, ch)
    value = '"' + "".join(esc(c) for c in secret) + '"'
src = open(path, encoding="utf-8").read().splitlines(keepends=True)
out = []
found = False
for line in src:
    if "static let licenseSecret" in line:
        out.append("    public static let licenseSecret: String? = %s\n" % value)
        found = True
    else:
        out.append(line)
if not found:
    sys.exit("ERROR: could not find 'static let licenseSecret' in %s" % path)
open(path, "w", encoding="utf-8").writelines(out)
PY
  echo "SecretConfig: licenseSecret = nil (no CLIP_LICENSE_SECRET — app fails closed)"
else
  LC_SECRET="$SECRET" python3 - "$FILE" <<'PY'
import os, sys
path = sys.argv[1]
secret = os.environ["LC_SECRET"]
def esc(ch):
    return {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\r": "\\r", "\t": "\\t"}.get(ch, ch)
value = '"' + "".join(esc(c) for c in secret) + '"'
src = open(path, encoding="utf-8").read().splitlines(keepends=True)
out = []
found = False
for line in src:
    if "static let licenseSecret" in line:
        out.append("    public static let licenseSecret: String? = %s\n" % value)
        found = True
    else:
        out.append(line)
if not found:
    sys.exit("ERROR: could not find 'static let licenseSecret' in %s" % path)
open(path, "w", encoding="utf-8").writelines(out)
PY
  echo "SecretConfig: licenseSecret injected from CLIP_LICENSE_SECRET (not committed)"
fi
