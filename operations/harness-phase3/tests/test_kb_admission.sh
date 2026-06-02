#!/usr/bin/env bash
set -euo pipefail

PYTHON_BIN="${PHASE3_PYTHON_BIN:-${PYTHON:-python3}}"
export PHASE3_PYTHON_BIN="${PYTHON_BIN}"

"${PYTHON_BIN}" operations/harness-phase3/tests/test_kb_admission.py
