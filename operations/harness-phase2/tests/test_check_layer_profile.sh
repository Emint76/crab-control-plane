#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUN_ID="check-layer-profile-test"
RUN_DIR="${PHASE2_ROOT}/runs/${RUN_ID}"

fail() {
  printf 'FAIL %s\n' "$*" >&2
  exit 1
}

cleanup_run_dir() {
  if [[ -n "${RUN_DIR:-}" && -d "${RUN_DIR}" && "${RUN_DIR}" == "${PHASE2_ROOT}/runs/${RUN_ID}" ]]; then
    rm -rf "${RUN_DIR}"
  fi
}

trap cleanup_run_dir EXIT

cleanup_run_dir
bash "${PHASE2_ROOT}/bin/run_phase2_check_layer.sh" "${RUN_ID}"

required_files=(
  "${RUN_DIR}/run_meta.json"
  "${RUN_DIR}/exit_code"
  "${RUN_DIR}/checks/wrong_root_preflight.txt"
  "${RUN_DIR}/checks/contracts_validation.json"
  "${RUN_DIR}/checks/policy_validation.json"
  "${RUN_DIR}/checks/fixture_smoke.txt"
  "${RUN_DIR}/PHASE2_TREE.txt"
  "${RUN_DIR}/PREFLIGHT_RESULT.txt"
  "${RUN_DIR}/SMOKE_OUTPUT.txt"
  "${RUN_DIR}/CREATED_PATHS.txt"
  "${RUN_DIR}/FINAL_REPORT.md"
)

for required_file in "${required_files[@]}"; do
  [[ -f "${required_file}" ]] || fail "missing required strict profile output: ${required_file}"
done

forbidden_paths=(
  "${RUN_DIR}/apply_plan.json"
  "${RUN_DIR}/validation_report.json"
  "${RUN_DIR}/admission_decision.json"
  "${RUN_DIR}/placement_decision.json"
  "${RUN_DIR}/handoff_ready.json"
  "${RUN_DIR}/report.json"
  "${RUN_DIR}/report.md"
  "${RUN_DIR}/output/runtime-ready"
)

for forbidden_path in "${forbidden_paths[@]}"; do
  [[ ! -e "${forbidden_path}" ]] || fail "strict profile created scaffold output: ${forbidden_path}"
done

grep -Fq '"profile": "check-layer-strict"' "${RUN_DIR}/run_meta.json" || fail "run_meta.json missing check-layer-strict profile"
grep -Fxq '0' "${RUN_DIR}/exit_code" || fail "exit_code was not 0"
grep -Fq 'PASS valid task packet schema' "${RUN_DIR}/checks/fixture_smoke.txt" || fail "fixture_smoke.txt missing fixture smoke output"
grep -Fq 'status=PASS' "${RUN_DIR}/PREFLIGHT_RESULT.txt" || fail "PREFLIGHT_RESULT.txt missing status=PASS"
grep -Fq 'PASS valid task packet schema' "${RUN_DIR}/SMOKE_OUTPUT.txt" || fail "SMOKE_OUTPUT.txt missing fixture smoke output"
grep -Fq 'No OpenClaw runtime connection was implemented.' "${RUN_DIR}/FINAL_REPORT.md" || fail "FINAL_REPORT.md missing runtime connection statement"
grep -Fq 'No automatic runtime enforcement was implemented.' "${RUN_DIR}/FINAL_REPORT.md" || fail "FINAL_REPORT.md missing runtime enforcement statement"
grep -Fq 'No writes occurred outside the strict Phase 2 run directory.' "${RUN_DIR}/FINAL_REPORT.md" || fail "FINAL_REPORT.md missing write-surface statement"

expected_evidence_entries=(
  "run_meta.json"
  "exit_code"
  "checks/wrong_root_preflight.txt"
  "checks/contracts_validation.json"
  "checks/policy_validation.json"
  "checks/fixture_smoke.txt"
  "PHASE2_TREE.txt"
  "PREFLIGHT_RESULT.txt"
  "SMOKE_OUTPUT.txt"
  "CREATED_PATHS.txt"
  "FINAL_REPORT.md"
)

for expected_entry in "${expected_evidence_entries[@]}"; do
  grep -Fq "${expected_entry}" "${RUN_DIR}/PHASE2_TREE.txt" || fail "PHASE2_TREE.txt missing ${expected_entry}"
  grep -Fq "operations/harness-phase2/runs/${RUN_ID}/${expected_entry}" "${RUN_DIR}/CREATED_PATHS.txt" || fail "CREATED_PATHS.txt missing ${expected_entry}"
done

printf 'PASS check-layer profile separation\n'
