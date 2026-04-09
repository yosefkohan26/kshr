#!/bin/bash
# Rebuild and restart kshr app

set -e

cd "$(dirname "$0")/.."

# Kill existing app if running
pkill -9 -f "kshr" 2>/dev/null || true

# Build
swift build

# Copy to app bundle
cp .build/debug/kshr .build/debug/kshr.app/Contents/MacOS/

# Open the app
open .build/debug/kshr.app
