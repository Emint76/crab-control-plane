#!/usr/bin/env bash
set -euo pipefail

PYTHON_BIN="${PHASE4_PYTHON_BIN:-${PHASE3_PYTHON_BIN:-${PYTHON:-python3}}}"
export PHASE4_PYTHON_BIN="${PYTHON_BIN}"
export PHASE3_PYTHON_BIN="${PHASE3_PYTHON_BIN:-${PYTHON_BIN}}"
export PHASE2_PYTHON_BIN="${PHASE2_PYTHON_BIN:-${PYTHON_BIN}}"

"${PYTHON_BIN}" operations/harness-phase4/tests/test_phase4_invocation_claim.py
