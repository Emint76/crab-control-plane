#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMISSION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PYTHON_BIN="${ADMISSION_PYTHON_BIN:-${PYTHON:-python3}}"
if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "FAIL python runtime not found: ${PYTHON_BIN}" >&2
  exit 1
fi

exec "${PYTHON_BIN}" "${ADMISSION_ROOT}/lib/admission_cli.py" "$@"
