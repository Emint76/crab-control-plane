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

PHASE2_RUN_ID="phase3-run-dir-invariants-phase2-input"
PHASE2_RUN_DIR="${REPO_ROOT}/operations/harness-phase2/runs/${PHASE2_RUN_ID}"
VALID_RUN_ID="phase3-run-dir-test"
VALID_RUN_DIR="${PHASE3_ROOT}/runs/${VALID_RUN_ID}"
TARGET_JSON_DIR="${PHASE3_ROOT}/runs/${VALID_RUN_ID}-target"
TARGET_JSON="${TARGET_JSON_DIR}/execution_target.json"
EXTERNAL_PHASE2_RUN_DIR="${TMP_DIR}/phase2-run"
EXTERNAL_TARGET_JSON="${TMP_DIR}/execution_target.json"
EXTERNAL_PHASE2_RUN_ID="phase3-external-phase2"
EXTERNAL_TARGET_RUN_ID="phase3-external-target"

cleanup() {
  rm -rf \
    "${TMP_DIR}" \
    "${PHASE2_RUN_DIR}" \
    "${VALID_RUN_DIR}" \
    "${TARGET_JSON_DIR}" \
    "${PHASE3_ROOT}/runs/${EXTERNAL_PHASE2_RUN_ID}" \
    "${PHASE3_ROOT}/runs/${EXTERNAL_TARGET_RUN_ID}"
}

fail() {
  echo "FAIL $*" >&2
  exit 1
}

assert_absent() {
  local path="$1"
  [[ ! -e "${path}" ]] || fail "unexpected path exists: ${path}"
}

rm -rf \
  "${PHASE2_RUN_DIR}" \
  "${VALID_RUN_DIR}" \
  "${TARGET_JSON_DIR}" \
  "${PHASE3_ROOT}/runs/${EXTERNAL_PHASE2_RUN_ID}" \
  "${PHASE3_ROOT}/runs/${EXTERNAL_TARGET_RUN_ID}"
trap cleanup EXIT
mkdir -p "${TARGET_JSON_DIR}" "${EXTERNAL_PHASE2_RUN_DIR}"

bash "${REPO_ROOT}/operations/harness-phase2/bin/run_phase2_bundle.sh" "${PHASE2_RUN_ID}"

cat > "${TARGET_JSON}" <<EOF
{
  "target_runtime": "openclaw",
  "target_kind": "phase3_staging",
  "target_ref": "operations/harness-phase3/runs/${VALID_RUN_ID}/staging/runtime-ready-applied",
  "apply_mode": "staged",
  "approval_ref": "manual://phase3-run-dir-test",
  "invoked_by": "test://phase3-run-dir-invariants"
}
EOF

cat > "${EXTERNAL_TARGET_JSON}" <<EOF
{
  "target_runtime": "openclaw",
  "target_kind": "phase3_staging",
  "target_ref": "operations/harness-phase3/runs/${EXTERNAL_TARGET_RUN_ID}/staging/runtime-ready-applied",
  "apply_mode": "staged",
  "approval_ref": "manual://phase3-external-target",
  "invoked_by": "test://phase3-external-target"
}
EOF

bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
  --phase2-run-dir "${PHASE2_RUN_DIR}" \
  --execution-target-json "${TARGET_JSON}" \
  --run-id "${VALID_RUN_ID}"

[[ -f "${VALID_RUN_DIR}/run_meta.json" ]] || fail "missing run_meta.json"
[[ -f "${VALID_RUN_DIR}/checks/run_dir_invariants.json" ]] || fail "missing checks/run_dir_invariants.json"
[[ -f "${VALID_RUN_DIR}/report.json" ]] || fail "missing report.json"
[[ -f "${VALID_RUN_DIR}/exit_code" ]] || fail "missing exit_code"
[[ "$(tr -d '\r\n' < "${VALID_RUN_DIR}/exit_code")" == "0" ]] || fail "valid run exit_code must be 0"

"${PYTHON_BIN}" - "${VALID_RUN_DIR}/run_meta.json" "${VALID_RUN_DIR}/checks/run_dir_invariants.json" "${VALID_RUN_DIR}/report.json" <<'PY'
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


run_meta = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
invariants = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
report = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))

expected_run_id = "phase3-run-dir-test"
expected_run_dir = f"operations/harness-phase3/runs/{expected_run_id}"
expected_write_surface = f"{expected_run_dir}/"

assert run_meta["run_id"] == expected_run_id, run_meta
assert run_meta["profile"] == "canonical-execution-owner", run_meta
assert run_meta["canonical_run_dir"] == expected_run_dir, run_meta
assert run_meta["run_dir_identity_verified"] is True, run_meta
assert run_meta["write_surface"] == expected_write_surface, run_meta
unsafe_fields = [(path, value) for path, value in iter_strings(run_meta) if is_unsafe_host_path(value)]
assert unsafe_fields == [], unsafe_fields

assert invariants["status"] == "pass", invariants
assert invariants["run_id"] == expected_run_id, invariants
assert invariants["canonical_run_dir"] == expected_run_dir, invariants
assert invariants["run_dir_identity_verified"] is True, invariants
assert invariants["write_surface_verified"] is True, invariants
assert invariants["violations"] == [], invariants
assert report["summary"]["run_dir_invariants"] == "pass", report
PY

run_invalid() {
  local label="$1"
  local run_id="$2"
  shift 2
  local forbidden_paths=("$@")
  local log_path="${TMP_DIR}/invalid-${label}.log"

  for path in "${forbidden_paths[@]}"; do
    assert_absent "${path}"
  done

  set +e
  bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
    --phase2-run-dir "${PHASE2_RUN_DIR}" \
    --execution-target-json "${TARGET_JSON}" \
    --run-id "${run_id}" >"${log_path}" 2>&1
  local status=$?
  set -e

  [[ "${status}" -ne 0 ]] || fail "invalid run id unexpectedly passed: ${label}"

  for path in "${forbidden_paths[@]}"; do
    assert_absent "${path}"
  done

  echo "PASS invalid run id rejected: ${label}"
}

run_external_input_invalid() {
  local label="$1"
  local phase2_run_dir="$2"
  local execution_target_json="$3"
  local run_id="$4"
  local run_dir="${PHASE3_ROOT}/runs/${run_id}"
  local log_path="${TMP_DIR}/invalid-${label}.log"

  rm -rf "${run_dir}"

  set +e
  bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
    --phase2-run-dir "${phase2_run_dir}" \
    --execution-target-json "${execution_target_json}" \
    --run-id "${run_id}" >"${log_path}" 2>&1
  local status=$?
  set -e

  [[ "${status}" -ne 0 ]] || fail "external input unexpectedly passed: ${label}"
  [[ ! -f "${run_dir}/run_meta.json" ]] || fail "external input wrote run_meta.json: ${label}"

  echo "PASS external input rejected before run_meta: ${label}"
}

run_invalid "traversal" "../bad" "${PHASE3_ROOT}/bad"
run_invalid "forward-slash" "bad/run" "${PHASE3_ROOT}/runs/bad"
run_invalid "backslash" 'bad\run' "${PHASE3_ROOT}/runs/bad" "${PHASE3_ROOT}/runs/bad\\run"
run_invalid "absolute" "/tmp/bad" "${PHASE3_ROOT}/runs/tmp"
run_invalid "leading-whitespace" " bad" "${PHASE3_ROOT}/runs/ bad"
run_invalid "trailing-whitespace" "bad " "${PHASE3_ROOT}/runs/bad "
run_invalid "empty" "" \
  "${PHASE3_ROOT}/runs/input" \
  "${PHASE3_ROOT}/runs/checks" \
  "${PHASE3_ROOT}/runs/logs" \
  "${PHASE3_ROOT}/runs/staging" \
  "${PHASE3_ROOT}/runs/run_meta.json"

run_external_input_invalid "external-phase2-run-dir" "${EXTERNAL_PHASE2_RUN_DIR}" "${TARGET_JSON}" "${EXTERNAL_PHASE2_RUN_ID}"
run_external_input_invalid "external-execution-target-json" "${PHASE2_RUN_DIR}" "${EXTERNAL_TARGET_JSON}" "${EXTERNAL_TARGET_RUN_ID}"

echo "PASS valid run id phase3-run-dir-test"
echo "PASS Phase 3 run-dir invariants"
