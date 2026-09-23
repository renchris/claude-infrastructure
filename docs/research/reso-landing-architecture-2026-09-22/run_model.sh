#!/usr/bin/env bash
# Re-derive every model table in ../reso-landing-architecture-2026-09-22.md (pure Python, no I/O, ~2 min).
set -euo pipefail
cd "$(dirname "$0")"
python3 landsim.py '{"hours":48,"seeds":3}'
python3 scenarios.py
