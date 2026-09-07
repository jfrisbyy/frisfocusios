#!/usr/bin/env bash
#
# Deploy the Supabase edge functions.
#
# This exists because deploying is the one step in this repo that has no
# safe remote path. The functions live here; the only lossless way to get
# them onto the project is the Supabase CLI reading them off disk. Doing
# it by hand — pasting file contents into an API call — risks silently
# dropping a paragraph of a 130-line system prompt, which still compiles,
# still deploys, and quietly makes the product worse in a way nothing
# catches.
#
#   ./scripts/deploy-functions.sh                # every function
#   ./scripts/deploy-functions.sh season-setup   # just one
#
# Requires: supabase CLI, and `supabase login` once.

set -euo pipefail

PROJECT_REF="pgrsrgctuclcmbhqnlqo"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FUNCTIONS_DIR="$ROOT/backend/functions"

if ! command -v supabase >/dev/null 2>&1; then
  echo "supabase CLI not found. Install it:" >&2
  echo "  brew install supabase/tap/supabase   # or see supabase.com/docs/guides/cli" >&2
  exit 1
fi

# The CLI expects functions under supabase/functions/. This repo keeps
# them under backend/functions/, so point the CLI at a temporary tree
# rather than reorganising the repo around one tool's convention.
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/supabase"
cp -R "$FUNCTIONS_DIR" "$WORKDIR/supabase/functions"

if [ $# -gt 0 ]; then
  TARGETS=("$@")
else
  TARGETS=()
  for dir in "$FUNCTIONS_DIR"/*/; do
    name="$(basename "$dir")"
    # _shared is imported by the others, never deployed on its own.
    [ "$name" = "_shared" ] && continue
    TARGETS+=("$name")
  done
fi

echo "Deploying ${#TARGETS[@]} function(s) to $PROJECT_REF"
for name in "${TARGETS[@]}"; do
  echo "  → $name"
  ( cd "$WORKDIR" && supabase functions deploy "$name" --project-ref "$PROJECT_REF" )
done
echo "Done."
