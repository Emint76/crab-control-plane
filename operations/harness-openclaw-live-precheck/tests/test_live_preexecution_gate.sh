#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${GATE_ROOT}/../.." && pwd -P)"
RUNS_ROOT="${GATE_ROOT}/runs"

PYTHON_BIN="${LIVE_PRECHECK_TEST_PYTHON_BIN:-${LIVE_PRECHECK_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set LIVE_PRECHECK_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi
export LIVE_PRECHECK_PYTHON_BIN="${LIVE_PRECHECK_PYTHON_BIN:-${PYTHON_BIN}}"

VALID_RUN_ID="live-preexecution-gate-valid"
REPO_LOCAL_RUN_ID="live-preexecution-gate-repo-local-input"
TARGET_MISMATCH_RUN_ID="live-preexecution-gate-target-mismatch"
SECRET_KEY_RUN_ID="live-preexecution-gate-secret-key"
INVALID_RUN_ID="../bad"

VALID_RUN_DIR="${RUNS_ROOT}/${VALID_RUN_ID}"
REPO_LOCAL_RUN_DIR="${RUNS_ROOT}/${REPO_LOCAL_RUN_ID}"
TARGET_MISMATCH_RUN_DIR="${RUNS_ROOT}/${TARGET_MISMATCH_RUN_ID}"
SECRET_KEY_RUN_DIR="${RUNS_ROOT}/${SECRET_KEY_RUN_ID}"

TMP_ROOT="$(mktemp -d)"
VALID_SELECTOR="${TMP_ROOT}/live-target-selector.json"
VALID_APPROVAL="${TMP_ROOT}/operator-approval.json"
VALID_ROLLBACK="${TMP_ROOT}/rollback-handoff.json"
REPO_LOCAL_SELECTOR="${SCRIPT_DIR}/repo-local-live-target-selector.tmp.json"
TARGET_MISMATCH_APPROVAL="${TMP_ROOT}/operator-approval-target-mismatch.json"
SECRET_KEY_SELECTOR="${TMP_ROOT}/live-target-selector-secret-key.json"

fail() {
  echo "FAIL $*" >&2
  exit 1
}

safe_rm_generated_dir() {
  local target="$1"
  local approved_root="$2"
  local expected_name="$3"

  "${PYTHON_BIN}" - "${target}" "${approved_root}" "${expected_name}" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

target = Path(sys.argv[1]).resolve(strict=False)
approved_root = Path(sys.argv[2]).resolve(strict=False)
expected_name = sys.argv[3]

try:
    relative = target.relative_to(approved_root)
except ValueError:
    print(f"refusing to delete outside live precheck runs: {target}", file=sys.stderr)
    raise SystemExit(1)

if len(relative.parts) != 1 or target.name != expected_name:
    print(f"refusing to delete non-direct live precheck run child: {target}", file=sys.stderr)
    raise SystemExit(1)
PY

  rm -rf -- "${target}"
}

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && "${TMP_ROOT}" == /tmp/* && -d "${TMP_ROOT}" ]]; then
    rm -rf -- "${TMP_ROOT}"
  fi
  rm -f -- "${REPO_LOCAL_SELECTOR}"
  safe_rm_generated_dir "${VALID_RUN_DIR}" "${RUNS_ROOT}" "${VALID_RUN_ID}"
  safe_rm_generated_dir "${REPO_LOCAL_RUN_DIR}" "${RUNS_ROOT}" "${REPO_LOCAL_RUN_ID}"
  safe_rm_generated_dir "${TARGET_MISMATCH_RUN_DIR}" "${RUNS_ROOT}" "${TARGET_MISMATCH_RUN_ID}"
  safe_rm_generated_dir "${SECRET_KEY_RUN_DIR}" "${RUNS_ROOT}" "${SECRET_KEY_RUN_ID}"
}

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
}

assert_absent() {
  local path="$1"
  [[ ! -e "${path}" ]] || fail "unexpected path exists: ${path}"
}

assert_file_text_equals() {
  local path="$1"
  local expected="$2"
  assert_file "${path}"
  local actual
  actual="$(tr -d '\r\n' < "${path}")"
  [[ "${actual}" == "${expected}" ]] || fail "${path} expected ${expected}, got ${actual}"
}

write_records() {
  local selector_path="$1"
  local approval_path="$2"
  local rollback_path="$3"
  local target_label="$4"
  local selector_label="$5"
  local execution_label="$6"

  "${PYTHON_BIN}" - \
    "${selector_path}" \
    "${approval_path}" \
    "${rollback_path}" \
    "${TMP_ROOT}" \
    "${target_label}" \
    "${selector_label}" \
    "${execution_label}" <<'PY'
import json
import sys
from pathlib import Path

selector_path = Path(sys.argv[1])
approval_path = Path(sys.argv[2])
rollback_path = Path(sys.argv[3])
tmp_root = Path(sys.argv[4])
target_label = sys.argv[5]
selector_label = sys.argv[6]
execution_label = sys.argv[7]

workspace_root = tmp_root / "reviewed-live-workspace-root"
state_root = tmp_root / "reviewed-live-state-root"
runtime_root = tmp_root / "reviewed-live-runtime-root"

selector = {
    "selector_kind": "live-target-selector",
    "selector_label": selector_label,
    "target_class": "live",
    "target_instance_label": target_label,
    "workspace_root": str(workspace_root),
    "state_root": str(state_root),
    "runtime_root": str(runtime_root),
    "is_disposable": False,
}
approval = {
    "approval_kind": "operator-approval",
    "approval_label": "reviewed-operator-approval",
    "approved_operation_class": "live-runtime-apply",
    "target_instance_label": target_label,
    "selector_label": selector_label,
    "execution_label": execution_label,
    "non_reusable": True,
    "approved_by": "reviewed-human-operator",
}
rollback = {
    "rollback_kind": "rollback-handoff",
    "rollback_label": "reviewed-rollback-handoff",
    "target_instance_label": target_label,
    "execution_label": execution_label,
    "rollback_ready": True,
    "rollback_boundary": "reviewed rollback boundary for this exact attempt",
    "decision_points": [
        "abort before mutation if prechecks fail",
        "operator decides rollback after post-mutation validation failure"
    ],
}

for path, payload in (
    (selector_path, selector),
    (approval_path, approval),
    (rollback_path, rollback),
):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

assert_report_field() {
  local report_path="$1"
  local field="$2"
  local expected="$3"
  "${PYTHON_BIN}" - "${report_path}" "${field}" "${expected}" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
field = sys.argv[2]
expected_raw = sys.argv[3]
if expected_raw == "true":
    expected = True
elif expected_raw == "false":
    expected = False
else:
    expected = expected_raw
actual = report[field]
assert actual == expected, (field, actual, expected, report)
PY
}

run_gate_expect_fail() {
  local label="$1"
  local run_id="$2"
  local run_dir="$3"
  local expected_field="$4"
  shift 4
  safe_rm_generated_dir "${run_dir}" "${RUNS_ROOT}" "${run_id}"

  set +e
  bash operations/harness-openclaw-live-precheck/bin/run_live_preexecution_gate.sh "$@" --run-id "${run_id}" >/dev/null 2>&1
  local status=$?
  set -e
  [[ "${status}" -ne 0 ]] || fail "negative live preexecution case unexpectedly passed: ${label}"
  assert_file "${run_dir}/gate_report.json"
  assert_report_field "${run_dir}/gate_report.json" "${expected_field}" "fail"
  echo "PASS live preexecution negative case rejected: ${label}"
}

cd "${REPO_ROOT}"
mkdir -p "${RUNS_ROOT}"
cleanup
trap cleanup EXIT

write_records "${VALID_SELECTOR}" "${VALID_APPROVAL}" "${VALID_ROLLBACK}" "reviewed-live-instance-a" "reviewed-live-selector-a" "execution-attempt-a"

bash operations/harness-openclaw-live-precheck/bin/run_live_preexecution_gate.sh \
  --selector-file "${VALID_SELECTOR}" \
  --approval-file "${VALID_APPROVAL}" \
  --rollback-file "${VALID_ROLLBACK}" \
  --run-id "${VALID_RUN_ID}"

assert_file "${VALID_RUN_DIR}/gate_meta.json"
assert_file "${VALID_RUN_DIR}/gate_report.json"
assert_file "${VALID_RUN_DIR}/checks/input_file_validation.json"
assert_file "${VALID_RUN_DIR}/checks/schema_validation.json"
assert_file "${VALID_RUN_DIR}/checks/cross_binding_validation.json"
assert_file "${VALID_RUN_DIR}/checks/non_secret_input_validation.json"
assert_file "${VALID_RUN_DIR}/exit_code"
assert_file_text_equals "${VALID_RUN_DIR}/exit_code" "0"

"${PYTHON_BIN}" - "${VALID_RUN_DIR}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])

def load(name: str):
    return json.loads((run_dir / name).read_text(encoding="utf-8-sig"))

meta = load("gate_meta.json")
report = load("gate_report.json")
input_check = load("checks/input_file_validation.json")
schema_check = load("checks/schema_validation.json")
cross_check = load("checks/cross_binding_validation.json")
non_secret_check = load("checks/non_secret_input_validation.json")

assert meta["gate_kind"] == "live-preexecution-gate", meta
assert meta["validation_only"] is True, meta
assert meta["live_runtime_apply"] is False, meta
assert meta["live_wrapper"] is False, meta
assert meta["crab_approved"] is False, meta
assert meta["approval_granted"] is False, meta
assert meta["rollback_executed"] is False, meta

assert report["overall_status"] == "pass", report
assert report["input_location_validation"] == "pass", report
assert report["schema_validation"] == "pass", report
assert report["cross_binding_validation"] == "pass", report
assert report["non_secret_input_validation"] == "pass", report
assert report["validation_only"] is True, report
assert report["live_runtime_apply"] is False, report
assert report["crab_approved"] is False, report

for check in (input_check, schema_check, cross_check, non_secret_check):
    assert check["status"] == "pass", check
    assert check["validation_only"] is True, check
    assert check["live_runtime_apply"] is False, check
PY

cp "${VALID_SELECTOR}" "${REPO_LOCAL_SELECTOR}"
run_gate_expect_fail \
  "repo-local input path" \
  "${REPO_LOCAL_RUN_ID}" \
  "${REPO_LOCAL_RUN_DIR}" \
  "input_location_validation" \
  --selector-file "${REPO_LOCAL_SELECTOR}" \
  --approval-file "${VALID_APPROVAL}" \
  --rollback-file "${VALID_ROLLBACK}"

cp "${VALID_APPROVAL}" "${TARGET_MISMATCH_APPROVAL}"
"${PYTHON_BIN}" - "${TARGET_MISMATCH_APPROVAL}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8-sig"))
payload["target_instance_label"] = "different-reviewed-live-instance"
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
run_gate_expect_fail \
  "target mismatch" \
  "${TARGET_MISMATCH_RUN_ID}" \
  "${TARGET_MISMATCH_RUN_DIR}" \
  "cross_binding_validation" \
  --selector-file "${VALID_SELECTOR}" \
  --approval-file "${TARGET_MISMATCH_APPROVAL}" \
  --rollback-file "${VALID_ROLLBACK}"

cp "${VALID_SELECTOR}" "${SECRET_KEY_SELECTOR}"
"${PYTHON_BIN}" - "${SECRET_KEY_SELECTOR}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8-sig"))
payload["api_key"] = "should-not-be-carried-here"
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
run_gate_expect_fail \
  "secret-like key" \
  "${SECRET_KEY_RUN_ID}" \
  "${SECRET_KEY_RUN_DIR}" \
  "non_secret_input_validation" \
  --selector-file "${SECRET_KEY_SELECTOR}" \
  --approval-file "${VALID_APPROVAL}" \
  --rollback-file "${VALID_ROLLBACK}"

before_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
set +e
bash operations/harness-openclaw-live-precheck/bin/run_live_preexecution_gate.sh \
  --selector-file "${VALID_SELECTOR}" \
  --approval-file "${VALID_APPROVAL}" \
  --rollback-file "${VALID_ROLLBACK}" \
  --run-id "${INVALID_RUN_ID}" >/dev/null 2>&1
invalid_status=$?
set -e
[[ "${invalid_status}" -ne 0 ]] || fail "invalid run id unexpectedly passed"
after_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
[[ "${before_runs}" == "${after_runs}" ]] || fail "invalid run id created a live precheck run dir"

echo "PASS live preexecution gate valid run"
echo "PASS live preexecution gate rejects invalid inputs"
