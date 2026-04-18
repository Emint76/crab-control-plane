#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE2_ROOT}/../.." && pwd)"

RUN_ID="${1:-phase2-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN_DIR="${PHASE2_ROOT}/runs/${RUN_ID}"
CHECKS_DIR="${RUN_DIR}/checks"
OUTPUT_DIR="${RUN_DIR}/output/runtime-ready"

mkdir -p "${CHECKS_DIR}" "${OUTPUT_DIR}"

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
  "engine_mode": "scaffold",
  "evaluation_mode": "static-v1"
}
EOF

bash "${PHASE2_ROOT}/bin/preflight_wrong_root_scan.sh" "${REPO_ROOT}" "${RUN_DIR}"
"${PYTHON_BIN}" "${PHASE2_ROOT}/bin/validate_contracts.py" "${REPO_ROOT}" "${RUN_DIR}"
"${PYTHON_BIN}" "${PHASE2_ROOT}/bin/validate_policy.py" "${REPO_ROOT}" "${RUN_DIR}"
"${PYTHON_BIN}" "${PHASE2_ROOT}/bin/render_apply_plan.py" "${REPO_ROOT}" "${RUN_DIR}" "${RUN_ID}"

required_files=(
  "${RUN_DIR}/run_meta.json"
  "${RUN_DIR}/validation_report.json"
  "${RUN_DIR}/admission_decision.json"
  "${RUN_DIR}/placement_decision.json"
  "${RUN_DIR}/apply_plan.json"
  "${CHECKS_DIR}/wrong_root_preflight.txt"
  "${CHECKS_DIR}/contracts_validation.json"
  "${CHECKS_DIR}/policy_validation.json"
)

for f in "${required_files[@]}"; do
  [[ -f "${f}" ]] || { echo "FAIL missing required output: ${f}" >&2; exit 1; }
done

[[ -d "${OUTPUT_DIR}" ]] || { echo "FAIL missing runtime-ready output directory" >&2; exit 1; }

EXIT_STATUS="0"
