#!/usr/bin/env bash
#
# Generate ios-frisfocus/FrisFocus/Config.swift from the template.
#
# Values come from the environment when present, otherwise from the
# placeholders in the template. A build with placeholders COMPILES but
# cannot reach the network — that is exactly what CI needs, and it is
# also enough to open the project and browse it locally.
#
# Usage:
#   scripts/bootstrap-config.sh              # placeholders (CI / offline)
#   FRISFOCUS_SUPABASE_URL=... scripts/bootstrap-config.sh
#
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="$repo_root/scripts/config/Config.example.swift"
target="$repo_root/ios-frisfocus/FrisFocus/Config.swift"

if [[ ! -f "$template" ]]; then
  echo "error: template not found at $template" >&2
  exit 1
fi

# Placeholders are only replaced when the matching variable is non-empty,
# so an unset variable leaves a visible __TOKEN__ rather than an empty
# string that would fail at runtime in a confusing way.
substitute() {
  local token="$1" value="${2:-}"
  if [[ -n "$value" ]]; then
    # Use a control character as the sed delimiter so URLs and keys
    # containing / & | are safe.
    python3 - "$token" "$value" "$target" <<'PY'
import sys
token, value, path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    text = f.read()
with open(path, "w") as f:
    f.write(text.replace(token, value))
PY
  fi
}

mkdir -p "$(dirname "$target")"
cp "$template" "$target"

substitute "__SUPABASE_URL__"      "${FRISFOCUS_SUPABASE_URL:-}"
substitute "__SUPABASE_ANON_KEY__" "${FRISFOCUS_SUPABASE_ANON_KEY:-}"
substitute "__RORK_AUTH_URL__"     "${FRISFOCUS_RORK_AUTH_URL:-}"
substitute "__RORK_APP_KEY__"      "${FRISFOCUS_RORK_APP_KEY:-}"
substitute "__PROJECT_ID__"        "${FRISFOCUS_PROJECT_ID:-}"

if grep -q "__[A-Z_]*__" "$target"; then
  echo "note: Config.swift written with placeholder values (offline build only)."
else
  echo "Config.swift written with environment values."
fi
echo "  -> $target"
