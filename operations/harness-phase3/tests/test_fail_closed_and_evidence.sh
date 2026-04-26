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

PHASE2_RUN_ID="phase3-fail-closed-phase2-input"
PHASE2_RUN_DIR="${REPO_ROOT}/operations/harness-phase2/runs/${PHASE2_RUN_ID}"

VALID_RUN_ID="phase3-fail-closed-valid"
MISSING_PHASE2_RUN_ID="phase3-missing-phase2-input"
INVALID_TARGET_RUN_ID="phase3-invalid-target-ref"
UNSAFE_TARGET_RUN_ID="phase3-unsafe-target-ref"

VALID_RUN_DIR="${PHASE3_ROOT}/runs/${VALID_RUN_ID}"
MISSING_PHASE2_RUN_DIR="${PHASE3_ROOT}/runs/${MISSING_PHASE2_RUN_ID}"
INVALID_TARGET_RUN_DIR="${PHASE3_ROOT}/runs/${INVALID_TARGET_RUN_ID}"
UNSAFE_TARGET_RUN_DIR="${PHASE3_ROOT}/runs/${UNSAFE_TARGET_RUN_ID}"

VALID_TARGET_DIR="${PHASE3_ROOT}/runs/${VALID_RUN_ID}-target"
MISSING_PHASE2_TARGET_DIR="${PHASE3_ROOT}/runs/${MISSING_PHASE2_RUN_ID}-target"
INVALID_TARGET_DIR="${PHASE3_ROOT}/runs/${INVALID_TARGET_RUN_ID}-target"
UNSAFE_TARGET_DIR="${PHASE3_ROOT}/runs/${UNSAFE_TARGET_RUN_ID}-target"

VALID_TARGET_JSON="${VALID_TARGET_DIR}/execution_target.json"
MISSING_PHASE2_TARGET_JSON="${MISSING_PHASE2_TARGET_DIR}/execution_target.json"
INVALID_TARGET_JSON="${INVALID_TARGET_DIR}/execution_target.json"
UNSAFE_TARGET_JSON="${UNSAFE_TARGET_DIR}/execution_target.json"

cleanup() {
  rm -rf \
    "${TMP_DIR}" \
    "${PHASE2_RUN_DIR}" \
    "${REPO_ROOT}/operations/harness-phase2/runs/missing-phase2-input" \
    "${VALID_RUN_DIR}" \
    "${MISSING_PHASE2_RUN_DIR}" \
    "${INVALID_TARGET_RUN_DIR}" \
    "${UNSAFE_TARGET_RUN_DIR}" \
    "${VALID_TARGET_DIR}" \
    "${MISSING_PHASE2_TARGET_DIR}" \
    "${INVALID_TARGET_DIR}" \
    "${UNSAFE_TARGET_DIR}"
}

fail() {
  echo "FAIL $*" >&2
  exit 1
}

write_target_json() {
  local path="$1"
  local run_id="$2"
  local target_ref="$3"
  local invoked_by="$4"
  mkdir -p "$(dirname "${path}")"
  cat > "${path}" <<EOF
{
  "target_runtime": "openclaw",
  "target_kind": "phase3_staging",
  "target_ref": "${target_ref}",
  "apply_mode": "staged",
  "approval_ref": "manual://${run_id}",
  "invoked_by": "${invoked_by}"
}
EOF
}

run_phase3_expect_failure() {
  local run_id="$1"
  local phase2_run_dir="$2"
  local target_json="$3"
  local log_path="${TMP_DIR}/${run_id}.log"

  set +e
  bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
    --phase2-run-dir "${phase2_run_dir}" \
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

assert_no_host_paths_in_run_meta() {
  local run_meta_path="$1"
  "${PYTHON_BIN}" - "${run_meta_path}" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


def iter_strings(value: Any, path: str = ""):
    if isinstance(value, str):
        yield path, value
    elif isinstance(value, dict):
        for key, item in value.items():
            child = str(key) if not path else f"{path}.{key}"
            yield from iter_strings(item, child)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from iter_strings(item, f"{path}[{index}]")


def is_unsafe_host_path(value: str) -> bool:
    if value.startswith("/"):
        return True
    if re.match(r"^[A-Za-z]:[\\/]", value):
        return True
    if "\\" in value:
        return True
    return any(token in value for token in ("/tmp/", "/home/", "/Users/", "/mnt/"))


payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
unsafe = [(path, value) for path, value in iter_strings(payload) if is_unsafe_host_path(value)]
assert unsafe == [], unsafe
PY
}

rm -rf \
  "${PHASE2_RUN_DIR}" \
  "${REPO_ROOT}/operations/harness-phase2/runs/missing-phase2-input" \
  "${VALID_RUN_DIR}" \
  "${MISSING_PHASE2_RUN_DIR}" \
  "${INVALID_TARGET_RUN_DIR}" \
  "${UNSAFE_TARGET_RUN_DIR}" \
  "${VALID_TARGET_DIR}" \
  "${MISSING_PHASE2_TARGET_DIR}" \
  "${INVALID_TARGET_DIR}" \
  "${UNSAFE_TARGET_DIR}"
trap cleanup EXIT

bash "${REPO_ROOT}/operations/harness-phase2/bin/run_phase2_bundle.sh" "${PHASE2_RUN_ID}"

write_target_json \
  "${VALID_TARGET_JSON}" \
  "${VALID_RUN_ID}" \
  "operations/harness-phase3/runs/${VALID_RUN_ID}/staging/runtime-ready-applied" \
  "test://phase3-fail-closed-valid"

bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
  --phase2-run-dir "${PHASE2_RUN_DIR}" \
  --execution-target-json "${VALID_TARGET_JSON}" \
  --run-id "${VALID_RUN_ID}"

[[ -f "${VALID_RUN_DIR}/exit_code" ]] || fail "missing valid exit_code"
[[ "$(tr -d '\r\n' < "${VALID_RUN_DIR}/exit_code")" == "0" ]] || fail "valid run exit_code must be 0"
"${PYTHON_BIN}" - "${VALID_RUN_DIR}/checks/execution_target_validation.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["status"] == "pass", payload
PY

write_target_json \
  "${MISSING_PHASE2_TARGET_JSON}" \
  "${MISSING_PHASE2_RUN_ID}" \
  "operations/harness-phase3/runs/${MISSING_PHASE2_RUN_ID}/staging/runtime-ready-applied" \
  "test://phase3-missing-phase2-input"

run_phase3_expect_failure \
  "${MISSING_PHASE2_RUN_ID}" \
  "operations/harness-phase2/runs/missing-phase2-input" \
  "${MISSING_PHASE2_TARGET_JSON}"

[[ -d "${MISSING_PHASE2_RUN_DIR}" ]] || fail "missing Phase 3 run dir for missing Phase 2 input"
assert_exit_code_one "${MISSING_PHASE2_RUN_DIR}"
[[ -f "${MISSING_PHASE2_RUN_DIR}/report.json" ]] || fail "missing report.json for missing Phase 2 input"
[[ -f "${MISSING_PHASE2_RUN_DIR}/report.md" ]] || fail "missing report.md for missing Phase 2 input"
[[ ! -f "${MISSING_PHASE2_RUN_DIR}/execution_result.json" ]] || fail "missing Phase 2 input must not emit execution_result.json"
[[ ! -d "${MISSING_PHASE2_RUN_DIR}/staging/runtime-ready-applied" ]] || fail "missing Phase 2 input must not stage"

write_target_json \
  "${INVALID_TARGET_JSON}" \
  "${INVALID_TARGET_RUN_ID}" \
  "operations/harness-phase3/runs/wrong-run/staging/runtime-ready-applied" \
  "test://phase3-invalid-target-ref"

run_phase3_expect_failure \
  "${INVALID_TARGET_RUN_ID}" \
  "${PHASE2_RUN_DIR}" \
  "${INVALID_TARGET_JSON}"

assert_exit_code_one "${INVALID_TARGET_RUN_DIR}"
assert_no_execution_surfaces "${INVALID_TARGET_RUN_DIR}"
"${PYTHON_BIN}" - \
  "${INVALID_TARGET_RUN_DIR}/checks/execution_target_validation.json" \
  "${INVALID_TARGET_RUN_DIR}/report.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

check = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert check["status"] == "fail", check
assert report["overall_status"] == "fail", report
assert report["summary"]["execution_target_validation"] == "fail", report
assert any("execution_target_validation" in item for item in report["blockers"]), report
PY

write_target_json \
  "${UNSAFE_TARGET_JSON}" \
  "${UNSAFE_TARGET_RUN_ID}" \
  "/tmp/bad-target" \
  "test://phase3-unsafe-target-ref"

run_phase3_expect_failure \
  "${UNSAFE_TARGET_RUN_ID}" \
  "${PHASE2_RUN_DIR}" \
  "${UNSAFE_TARGET_JSON}"

assert_exit_code_one "${UNSAFE_TARGET_RUN_DIR}"
assert_no_execution_surfaces "${UNSAFE_TARGET_RUN_DIR}"
[[ -f "${UNSAFE_TARGET_RUN_DIR}/checks/execution_target_validation.json" ]] || fail "missing unsafe target validation report"
"${PYTHON_BIN}" - "${UNSAFE_TARGET_RUN_DIR}/checks/execution_target_validation.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["status"] == "fail", payload
assert "target_ref.safe_path_value" in payload["violations"], payload
PY
assert_no_host_paths_in_run_meta "${UNSAFE_TARGET_RUN_DIR}/run_meta.json"

echo "PASS valid Phase 3 run"
echo "PASS missing Phase 2 input fails closed"
echo "PASS invalid target_ref fails closed before staging/apply"
echo "PASS unsafe absolute target_ref fails closed without run_meta host path"
