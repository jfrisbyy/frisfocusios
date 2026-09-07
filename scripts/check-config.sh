#!/usr/bin/env bash
#
# Fail loudly when the committed Config.swift carries no real values.
#
# Config.swift used to be git-ignored and generated at build time. It is
# now tracked, because the platform that builds this app syncs the
# repository verbatim and a missing file is a compile error there. That
# fixes one failure and opens a worse one: a Config whose properties are
# empty strings COMPILES, so the app ships, signs nobody in, and reaches
# no backend, with nothing anywhere announcing why. A build that cannot
# work should not go quiet — it should stop here.
#
# Set ALLOW_PLACEHOLDER_CONFIG=1 for an offline build where that is fine.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-$repo_root/ios-frisfocus/FrisFocus/Config.swift}"

if [[ ! -f "$target" ]]; then
  echo "error: $target does not exist; every build needs it." >&2
  exit 1
fi

python3 - "$target" "${ALLOW_PLACEHOLDER_CONFIG:-0}" <<'PY'
import re, sys

path, allow = sys.argv[1], sys.argv[2] == "1"
text = open(path).read()

KEYS = [
    "EXPO_PUBLIC_SUPABASE_URL",
    "EXPO_PUBLIC_SUPABASE_ANON_KEY",
    "EXPO_PUBLIC_RORK_AUTH_URL",
    "EXPO_PUBLIC_RORK_APP_KEY",
    "EXPO_PUBLIC_PROJECT_ID",
]

bad = []
for key in KEYS:
    match = re.search(key + r'\s*(?::\s*String\s*)?=\s*"([^"]*)"', text)
    if match is None:
        bad.append((key, "missing"))
    elif not match.group(1).strip():
        bad.append((key, "empty"))
    elif re.fullmatch(r"__[A-Z_]+__", match.group(1)):
        bad.append((key, "placeholder"))

if not bad:
    print("Config.swift carries real values for all %d properties." % len(KEYS))
    sys.exit(0)

for key, why in bad:
    print("  %-34s %s" % (key, why))

if allow:
    print("note: placeholder Config accepted (ALLOW_PLACEHOLDER_CONFIG=1).")
    sys.exit(0)

print(
    "\nerror: Config.swift would compile and then silently do nothing.\n"
    "       Commit the real values, or set ALLOW_PLACEHOLDER_CONFIG=1 for\n"
    "       an offline build that is never meant to reach the network.",
    file=sys.stderr,
)
sys.exit(1)
PY
