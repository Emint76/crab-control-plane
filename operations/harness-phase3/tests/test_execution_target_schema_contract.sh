#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE3_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE3_ROOT}/../.." && pwd)"
TMP_DIR="$(mktemp -d)"

PHASE3_PYTHON_BIN="${PHASE3_PYTHON_BIN:-python}"
export PHASE3_PYTHON_BIN
PYTHON_BIN="${PHASE3_PYTHON_BIN}"
export PHASE2_PYTHON_BIN="${PHASE2_PYTHON_BIN:-${PYTHON_BIN}}"

PHASE2_RUN_ID="phase3-schema-contract-phase2-input"
PHASE2_RUN_DIR="${REPO_ROOT}/operations/harness-phase2/runs/${PHASE2_RUN_ID}"

RUN_IDS=(
  "phase3-schema-contract-valid"
  "phase3-schema-missing-approval"
  "phase3-schema-additional-field"
  "phase3-schema-wrong-runtime"
  "phase3-schema-semantic-target-ref"
)

TARGET_DIRS=(
  "${PHASE3_ROOT}/runs/phase3-schema-contract-valid-target"
  "${PHASE3_ROOT}/runs/phase3-schema-missing-approval-target"
  "${PHASE3_ROOT}/runs/phase3-schema-additional-field-target"
  "${PHASE3_ROOT}/runs/phase3-schema-wrong-runtime-target"
  "${PHASE3_ROOT}/runs/phase3-schema-semantic-target-ref-target"
)

cleanup() {
  rm -rf "${TMP_DIR}" "${PHASE2_RUN_DIR}"
  for run_id in "${RUN_IDS[@]}"; do
    rm -rf "${PHASE3_ROOT}/runs/${run_id}"
  done
  for target_dir in "${TARGET_DIRS[@]}"; do
    rm -rf "${target_dir}"
  done
}

fail() {
  echo "FAIL $*" >&2
  exit 1
}

write_target_json() {
  local path="$1"
  local run_id="$2"
  local target_runtime="$3"
  local target_ref="$4"
  local include_approval="$5"
  local include_extra="$6"
  mkdir -p "$(dirname "${path}")"
  cat > "${path}" <<EOF
{
  "target_runtime": "${target_runtime}",
  "target_kind": "phase3_staging",
  "target_ref": "${target_ref}",
  "apply_mode": "staged"$(if [[ "${include_approval}" == "yes" ]]; then printf ',\n  "approval_ref": "manual://%s"' "${run_id}"; fi)$(if [[ "${include_extra}" == "yes" ]]; then printf ',\n  "unexpected_field": "bad"'; fi),
  "invoked_by": "test://phase3-schema-contract"
}
EOF
}

run_phase3_expect_failure() {
  local run_id="$1"
  local target_json="$2"
  local log_path="${TMP_DIR}/${run_id}.log"

  set +e
  bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
    --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
    --execution-target-json "${target_json}" \
    --run-id "${run_id}" >"${log_path}" 2>&1
  local status=$?
  set -e

  [[ "${status}" -ne 0 ]] || fail "${run_id} unexpectedly passed"
}

assert_exit_code_one() {
  local run_dir="$1"
  [[ -f "${run_dir}/exit_code" ]] || fail "missing exit_code: ${run_dir}"
  [[ "$(tr -d '\r\n' < "${run_dir}/exit_code")" == "1" ]] || fail "exit_code must be 1: ${run_dir}"
}

assert_no_execution_surfaces() {
  local run_dir="$1"
  [[ ! -d "${run_dir}/staging/runtime-ready-applied" ]] || fail "staging target must be absent: ${run_dir}"
  [[ ! -f "${run_dir}/logs/apply.log" ]] || fail "apply.log must be absent: ${run_dir}"
  [[ ! -f "${run_dir}/execution_result.json" ]] || fail "execution_result.json must be absent: ${run_dir}"
}

assert_schema_failure() {
  local run_dir="$1"
  [[ -f "${run_dir}/checks/execution_target_validation.json" ]] || fail "missing execution_target_validation.json: ${run_dir}"
  assert_exit_code_one "${run_dir}"
  assert_no_execution_surfaces "${run_dir}"
  "${PYTHON_BIN}" - "${run_dir}/checks/execution_target_validation.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
checks = {item["name"]: item["status"] for item in payload["checks"]}
assert payload["status"] == "fail", payload
assert checks["execution_target.parse"] == "pass", payload
assert checks["execution_target.schema"] == "fail", payload
assert any(item.startswith("schema.") or item == "execution_target.schema" for item in payload["violations"]), payload
PY
}

rm -rf "${PHASE2_RUN_DIR}"
for run_id in "${RUN_IDS[@]}"; do
  rm -rf "${PHASE3_ROOT}/runs/${run_id}"
done
for target_dir in "${TARGET_DIRS[@]}"; do
  rm -rf "${target_dir}"
done
trap cleanup EXIT

bash "${REPO_ROOT}/operations/harness-phase2/bin/run_phase2_bundle.sh" "${PHASE2_RUN_ID}"

VALID_RUN_ID="phase3-schema-contract-valid"
VALID_TARGET_JSON="${PHASE3_ROOT}/runs/phase3-schema-contract-valid-target/execution_target.json"
VALID_RUN_DIR="${PHASE3_ROOT}/runs/${VALID_RUN_ID}"
write_target_json \
  "${VALID_TARGET_JSON}" \
  "${VALID_RUN_ID}" \
  "openclaw" \
  "operations/harness-phase3/runs/${VALID_RUN_ID}/staging/runtime-ready-applied" \
  "yes" \
  "no"

bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
  --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
  --execution-target-json "operations/harness-phase3/runs/phase3-schema-contract-valid-target/execution_target.json" \
  --run-id "${VALID_RUN_ID}"

[[ -f "${VALID_RUN_DIR}/exit_code" ]] || fail "missing valid exit_code"
[[ "$(tr -d '\r\n' < "${VALID_RUN_DIR}/exit_code")" == "0" ]] || fail "valid exit_code must be 0"
"${PYTHON_BIN}" - "${VALID_RUN_DIR}/checks/execution_target_validation.json" "${VALID_RUN_DIR}/report.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

check = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
report = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8-sig"))
checks = {item["name"]: item["status"] for item in check["checks"]}
assert check["status"] == "pass", check
assert checks["execution_target.schema"] == "pass", check
assert report["overall_status"] == "pass", report
PY

MISSING_RUN_ID="phase3-schema-missing-approval"
MISSING_TARGET_JSON="${PHASE3_ROOT}/runs/phase3-schema-missing-approval-target/execution_target.json"
MISSING_RUN_DIR="${PHASE3_ROOT}/runs/${MISSING_RUN_ID}"
write_target_json \
  "${MISSING_TARGET_JSON}" \
  "${MISSING_RUN_ID}" \
  "openclaw" \
  "operations/harness-phase3/runs/${MISSING_RUN_ID}/staging/runtime-ready-applied" \
  "no" \
  "no"
run_phase3_expect_failure "${MISSING_RUN_ID}" "operations/harness-phase3/runs/phase3-schema-missing-approval-target/execution_target.json"
assert_schema_failure "${MISSING_RUN_DIR}"

ADDITIONAL_RUN_ID="phase3-schema-additional-field"
ADDITIONAL_TARGET_JSON="${PHASE3_ROOT}/runs/phase3-schema-additional-field-target/execution_target.json"
ADDITIONAL_RUN_DIR="${PHASE3_ROOT}/runs/${ADDITIONAL_RUN_ID}"
write_target_json \
  "${ADDITIONAL_TARGET_JSON}" \
  "${ADDITIONAL_RUN_ID}" \
  "openclaw" \
  "operations/harness-phase3/runs/${ADDITIONAL_RUN_ID}/staging/runtime-ready-applied" \
  "yes" \
  "yes"
run_phase3_expect_failure "${ADDITIONAL_RUN_ID}" "operations/harness-phase3/runs/phase3-schema-additional-field-target/execution_target.json"
assert_schema_failure "${ADDITIONAL_RUN_DIR}"

WRONG_RUNTIME_RUN_ID="phase3-schema-wrong-runtime"
WRONG_RUNTIME_TARGET_JSON="${PHASE3_ROOT}/runs/phase3-schema-wrong-runtime-target/execution_target.json"
WRONG_RUNTIME_RUN_DIR="${PHASE3_ROOT}/runs/${WRONG_RUNTIME_RUN_ID}"
write_target_json \
  "${WRONG_RUNTIME_TARGET_JSON}" \
  "${WRONG_RUNTIME_RUN_ID}" \
  "other-runtime" \
  "operations/harness-phase3/runs/${WRONG_RUNTIME_RUN_ID}/staging/runtime-ready-applied" \
  "yes" \
  "no"
run_phase3_expect_failure "${WRONG_RUNTIME_RUN_ID}" "operations/harness-phase3/runs/phase3-schema-wrong-runtime-target/execution_target.json"
assert_schema_failure "${WRONG_RUNTIME_RUN_DIR}"

SEMANTIC_RUN_ID="phase3-schema-semantic-target-ref"
SEMANTIC_TARGET_JSON="${PHASE3_ROOT}/runs/phase3-schema-semantic-target-ref-target/execution_target.json"
SEMANTIC_RUN_DIR="${PHASE3_ROOT}/runs/${SEMANTIC_RUN_ID}"
write_target_json \
  "${SEMANTIC_TARGET_JSON}" \
  "${SEMANTIC_RUN_ID}" \
  "openclaw" \
  "operations/harness-phase3/runs/wrong-run/staging/runtime-ready-applied" \
  "yes" \
  "no"
run_phase3_expect_failure "${SEMANTIC_RUN_ID}" "operations/harness-phase3/runs/phase3-schema-semantic-target-ref-target/execution_target.json"
assert_exit_code_one "${SEMANTIC_RUN_DIR}"
assert_no_execution_surfaces "${SEMANTIC_RUN_DIR}"
"${PYTHON_BIN}" - "${SEMANTIC_RUN_DIR}/checks/execution_target_validation.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
checks = {item["name"]: item["status"] for item in payload["checks"]}
assert payload["status"] == "fail", payload
assert checks["execution_target.schema"] == "pass", payload
assert checks["target_ref"] == "fail", payload
PY

echo "PASS execution target schema valid case"
echo "PASS execution target schema rejects missing required field"
echo "PASS execution target schema rejects additional field"
echo "PASS execution target schema rejects wrong constant"
echo "PASS execution target semantic validation still fails closed"
