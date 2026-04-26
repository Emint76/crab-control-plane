#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE4_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE4_ROOT}/../.." && pwd)"

PYTHON_BIN="${PHASE4_PYTHON_BIN:-${PHASE3_PYTHON_BIN:-python}}"
export PHASE4_PYTHON_BIN="${PYTHON_BIN}"
export PHASE3_PYTHON_BIN="${PHASE3_PYTHON_BIN:-${PYTHON_BIN}}"
export PHASE2_PYTHON_BIN="${PHASE2_PYTHON_BIN:-${PYTHON_BIN}}"

PHASE2_RUN_ID="phase4-wrapper-phase2-input"
PHASE2_RUN_DIR="${REPO_ROOT}/operations/harness-phase2/runs/${PHASE2_RUN_ID}"

VALID_PHASE3_RUN_ID="phase4-wrapper-phase3-valid"
VALID_WRAPPER_RUN_ID="phase4-wrapper-valid"
VALID_TARGET_DIR="${PHASE4_ROOT}/runs/phase4-wrapper-test-target"
VALID_TARGET_JSON="${VALID_TARGET_DIR}/execution_target.json"
VALID_WRAPPER_RUN_DIR="${PHASE4_ROOT}/runs/${VALID_WRAPPER_RUN_ID}"
VALID_PHASE3_RUN_DIR="${REPO_ROOT}/operations/harness-phase3/runs/${VALID_PHASE3_RUN_ID}"

BAD_OPERATOR_PHASE3_RUN_ID="phase4-wrapper-phase3-invalid-operator"
BAD_OPERATOR_WRAPPER_RUN_ID="phase4-wrapper-invalid-operator"
BAD_OPERATOR_TARGET_DIR="${PHASE4_ROOT}/runs/phase4-wrapper-invalid-operator-target"
BAD_OPERATOR_TARGET_JSON="${BAD_OPERATOR_TARGET_DIR}/execution_target.json"
BAD_OPERATOR_WRAPPER_RUN_DIR="${PHASE4_ROOT}/runs/${BAD_OPERATOR_WRAPPER_RUN_ID}"
BAD_OPERATOR_PHASE3_RUN_DIR="${REPO_ROOT}/operations/harness-phase3/runs/${BAD_OPERATOR_PHASE3_RUN_ID}"

PHASE3_FAIL_RUN_ID="phase4-wrapper-phase3-fail"
PHASE3_FAIL_WRAPPER_RUN_ID="phase4-wrapper-phase3-failure"
PHASE3_FAIL_TARGET_DIR="${PHASE4_ROOT}/runs/phase4-wrapper-phase3-failure-target"
PHASE3_FAIL_TARGET_JSON="${PHASE3_FAIL_TARGET_DIR}/execution_target.json"
PHASE3_FAIL_WRAPPER_RUN_DIR="${PHASE4_ROOT}/runs/${PHASE3_FAIL_WRAPPER_RUN_ID}"
PHASE3_FAIL_RUN_DIR="${REPO_ROOT}/operations/harness-phase3/runs/${PHASE3_FAIL_RUN_ID}"

fail() {
  echo "FAIL $*" >&2
  exit 1
}

cleanup() {
  rm -rf \
    "${PHASE2_RUN_DIR}" \
    "${VALID_TARGET_DIR}" \
    "${VALID_WRAPPER_RUN_DIR}" \
    "${VALID_PHASE3_RUN_DIR}" \
    "${BAD_OPERATOR_TARGET_DIR}" \
    "${BAD_OPERATOR_WRAPPER_RUN_DIR}" \
    "${BAD_OPERATOR_PHASE3_RUN_DIR}" \
    "${PHASE3_FAIL_TARGET_DIR}" \
    "${PHASE3_FAIL_WRAPPER_RUN_DIR}" \
    "${PHASE3_FAIL_RUN_DIR}"
}

write_target_json() {
  local path="$1"
  local run_id="$2"
  local target_ref="$3"
  mkdir -p "$(dirname "${path}")"
  cat > "${path}" <<EOF
{
  "target_runtime": "openclaw",
  "target_kind": "phase3_staging",
  "target_ref": "${target_ref}",
  "apply_mode": "staged",
  "approval_ref": "manual://${run_id}",
  "invoked_by": "test://phase4-wrapper"
}
EOF
}

assert_absent() {
  local path="$1"
  [[ ! -e "${path}" ]] || fail "unexpected path exists: ${path}"
}

assert_wrapper_forbidden_outputs_absent() {
  local run_dir="$1"
  assert_absent "${run_dir}/report.json"
  assert_absent "${run_dir}/report.md"
  assert_absent "${run_dir}/exit_code"
  assert_absent "${run_dir}/execution_result.json"
}

rm -rf \
  "${PHASE2_RUN_DIR}" \
  "${VALID_TARGET_DIR}" \
  "${VALID_WRAPPER_RUN_DIR}" \
  "${VALID_PHASE3_RUN_DIR}" \
  "${BAD_OPERATOR_TARGET_DIR}" \
  "${BAD_OPERATOR_WRAPPER_RUN_DIR}" \
  "${BAD_OPERATOR_PHASE3_RUN_DIR}" \
  "${PHASE3_FAIL_TARGET_DIR}" \
  "${PHASE3_FAIL_WRAPPER_RUN_DIR}" \
  "${PHASE3_FAIL_RUN_DIR}"
trap cleanup EXIT

bash "${REPO_ROOT}/operations/harness-phase2/bin/run_phase2_bundle.sh" "${PHASE2_RUN_ID}"

write_target_json \
  "${VALID_TARGET_JSON}" \
  "${VALID_PHASE3_RUN_ID}" \
  "operations/harness-phase3/runs/${VALID_PHASE3_RUN_ID}/staging/runtime-ready-applied"

bash "${PHASE4_ROOT}/bin/run_phase4_wrapper.sh" \
  --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
  --execution-target-json "operations/harness-phase4/runs/phase4-wrapper-test-target/execution_target.json" \
  --phase3-run-id "${VALID_PHASE3_RUN_ID}" \
  --operator test-operator \
  --wrapper-run-id "${VALID_WRAPPER_RUN_ID}"

[[ -f "${VALID_WRAPPER_RUN_DIR}/wrapper_meta.json" ]] || fail "missing wrapper_meta.json"
[[ -f "${VALID_WRAPPER_RUN_DIR}/preflight.json" ]] || fail "missing preflight.json"
[[ -f "${VALID_WRAPPER_RUN_DIR}/phase3_invocation.json" ]] || fail "missing phase3_invocation.json"
[[ -f "${VALID_WRAPPER_RUN_DIR}/wrapper_summary.md" ]] || fail "missing wrapper_summary.md"
[[ -f "${VALID_WRAPPER_RUN_DIR}/wrapper_exit_code" ]] || fail "missing wrapper_exit_code"
[[ "$(tr -d '\r\n' < "${VALID_WRAPPER_RUN_DIR}/wrapper_exit_code")" == "0" ]] || fail "wrapper_exit_code must be 0"

[[ -f "${VALID_PHASE3_RUN_DIR}/report.json" ]] || fail "missing Phase 3 report.json"
[[ -f "${VALID_PHASE3_RUN_DIR}/report.md" ]] || fail "missing Phase 3 report.md"
[[ -f "${VALID_PHASE3_RUN_DIR}/exit_code" ]] || fail "missing Phase 3 exit_code"
assert_wrapper_forbidden_outputs_absent "${VALID_WRAPPER_RUN_DIR}"

"${PYTHON_BIN}" - \
  "${VALID_WRAPPER_RUN_DIR}/wrapper_meta.json" \
  "${VALID_WRAPPER_RUN_DIR}/preflight.json" \
  "${VALID_WRAPPER_RUN_DIR}/phase3_invocation.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

wrapper_meta = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
preflight = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8-sig"))
invocation = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8-sig"))

assert wrapper_meta["profile"] == "thin-wrapper", wrapper_meta
assert wrapper_meta["runtime_statement"]["phase4_is_canonical_execution_owner"] is False, wrapper_meta
assert wrapper_meta["runtime_statement"]["phase4_created_canonical_outputs"] is False, wrapper_meta
assert preflight["status"] == "pass", preflight
assert invocation["phase3_invoked"] is True, invocation
assert invocation["phase3_exit_status"] == 0, invocation
PY

write_target_json \
  "${BAD_OPERATOR_TARGET_JSON}" \
  "${BAD_OPERATOR_PHASE3_RUN_ID}" \
  "operations/harness-phase3/runs/${BAD_OPERATOR_PHASE3_RUN_ID}/staging/runtime-ready-applied"

set +e
bash "${PHASE4_ROOT}/bin/run_phase4_wrapper.sh" \
  --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
  --execution-target-json "operations/harness-phase4/runs/phase4-wrapper-invalid-operator-target/execution_target.json" \
  --phase3-run-id "${BAD_OPERATOR_PHASE3_RUN_ID}" \
  --operator "bad operator" \
  --wrapper-run-id "${BAD_OPERATOR_WRAPPER_RUN_ID}" >/dev/null 2>&1
bad_operator_status=$?
set -e
[[ "${bad_operator_status}" -ne 0 ]] || fail "invalid operator unexpectedly passed"
assert_absent "${BAD_OPERATOR_PHASE3_RUN_DIR}"
[[ -f "${BAD_OPERATOR_WRAPPER_RUN_DIR}/preflight.json" ]] || fail "missing invalid-operator preflight"
[[ "$(tr -d '\r\n' < "${BAD_OPERATOR_WRAPPER_RUN_DIR}/wrapper_exit_code")" != "0" ]] || fail "invalid-operator wrapper_exit_code must be non-zero"
assert_wrapper_forbidden_outputs_absent "${BAD_OPERATOR_WRAPPER_RUN_DIR}"
"${PYTHON_BIN}" - "${BAD_OPERATOR_WRAPPER_RUN_DIR}/preflight.json" "${BAD_OPERATOR_WRAPPER_RUN_DIR}/phase3_invocation.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

preflight = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
invocation = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8-sig"))
assert preflight["status"] == "fail", preflight
assert invocation["phase3_invoked"] is False, invocation
assert invocation["reason"] == "preflight_failed", invocation
PY

write_target_json \
  "${PHASE3_FAIL_TARGET_JSON}" \
  "${PHASE3_FAIL_RUN_ID}" \
  "operations/harness-phase3/runs/wrong-run/staging/runtime-ready-applied"

set +e
bash "${PHASE4_ROOT}/bin/run_phase4_wrapper.sh" \
  --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
  --execution-target-json "operations/harness-phase4/runs/phase4-wrapper-phase3-failure-target/execution_target.json" \
  --phase3-run-id "${PHASE3_FAIL_RUN_ID}" \
  --operator test-operator \
  --wrapper-run-id "${PHASE3_FAIL_WRAPPER_RUN_ID}" >/dev/null 2>&1
phase3_failure_status=$?
set -e
[[ "${phase3_failure_status}" -ne 0 ]] || fail "Phase 3 failure was masked as wrapper success"
[[ -d "${PHASE3_FAIL_RUN_DIR}" ]] || fail "missing Phase 3 failure run dir"
[[ -f "${PHASE3_FAIL_RUN_DIR}/report.json" ]] || fail "missing Phase 3 failure report.json"
[[ "$(tr -d '\r\n' < "${PHASE3_FAIL_WRAPPER_RUN_DIR}/wrapper_exit_code")" != "0" ]] || fail "Phase 3 failure wrapper_exit_code must be non-zero"
assert_wrapper_forbidden_outputs_absent "${PHASE3_FAIL_WRAPPER_RUN_DIR}"
"${PYTHON_BIN}" - "${PHASE3_FAIL_RUN_DIR}/report.json" "${PHASE3_FAIL_WRAPPER_RUN_DIR}/phase3_invocation.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
invocation = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8-sig"))
assert report["overall_status"] == "fail", report
assert invocation["phase3_invoked"] is True, invocation
assert invocation["phase3_exit_status"] != 0, invocation
PY

echo "PASS Phase 4 wrapper valid run"
echo "PASS Phase 4 wrapper rejects invalid operator without invoking Phase 3"
echo "PASS Phase 4 wrapper propagates Phase 3 failure"
