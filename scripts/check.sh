#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
python3 scripts/verify-assets.py
swift run CoreChecks
# The web version's ports of the engine and the practice history, when Node is installed. The history
# checks read the same fixture as the core checks, so the Mac and the web read each other's backups.
if command -v node >/dev/null 2>&1; then
  node Tests/web/engine-checks.mjs
  node Tests/web/history-checks.mjs
fi
swift build --product SwadarshanChakra
