#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE2_ROOT}/../.." && pwd)"

RUN_ID="${1:-phase2-check-layer-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN_DIR="${PHASE2_ROOT}/runs/${RUN_ID}"
CHECKS_DIR="${RUN_DIR}/checks"

mkdir -p "${CHECKS_DIR}"

EXIT_STATUS="1"
cleanup() {
  printf '%s\n' "${EXIT_STATUS}" > "${RUN_DIR}/exit_code"
}
trap cleanup EXIT

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

PYTHON_BIN="${PHASE2_PYTHON_BIN:-python}"
if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "FAIL python runtime not found: ${PYTHON_BIN}" >&2
  exit 1
fi

cat > "${RUN_DIR}/run_meta.json" <<EOF
{
  "run_id": "${RUN_ID}",
  "generated_at": "${GENERATED_AT}",
  "profile": "check-layer-strict",
  "engine_mode": "external-check-layer",
  "evaluation_mode": "static-v1"
}
EOF

bash "${PHASE2_ROOT}/bin/preflight_wrong_root_scan.sh" "${REPO_ROOT}" "${RUN_DIR}"
"${PYTHON_BIN}" "${PHASE2_ROOT}/bin/validate_contracts.py" "${REPO_ROOT}" "${RUN_DIR}"
"${PYTHON_BIN}" "${PHASE2_ROOT}/bin/validate_policy.py" "${REPO_ROOT}" "${RUN_DIR}"
PHASE2_PYTHON_BIN="${PYTHON_BIN}" bash "${PHASE2_ROOT}/tests/run_fixture_smoke.sh" > "${CHECKS_DIR}/fixture_smoke.txt" 2>&1

EXIT_STATUS="0"
