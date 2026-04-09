#!/usr/bin/env bash
set -euo pipefail

URL="${1:-https://example.com/form}"
SURFACE="${2:-surface:1}"

kshr browser "$SURFACE" goto "$URL"
kshr browser "$SURFACE" get url
kshr browser "$SURFACE" wait --load-state complete --timeout-ms 15000
kshr browser "$SURFACE" snapshot --interactive

echo "Now run fill/click commands using refs from the snapshot above."
