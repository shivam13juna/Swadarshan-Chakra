#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
python3 scripts/verify-assets.py
swift run CoreChecks
# The web version's port of the engine (web/engine.js), when Node is installed.
if command -v node >/dev/null 2>&1; then node Tests/web/engine-checks.mjs; fi
swift build --product SwadarshanChakra
