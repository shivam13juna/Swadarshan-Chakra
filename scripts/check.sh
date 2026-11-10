#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
python3 scripts/verify-assets.py
swift run CoreChecks
swift build --product SwadarshanChakra
