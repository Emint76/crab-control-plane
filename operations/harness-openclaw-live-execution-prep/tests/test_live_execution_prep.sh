#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PREP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${PREP_ROOT}/../.." && pwd -P)"
RUNS_ROOT="${PREP_ROOT}/runs"
PRECHECK_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-precheck/runs"

PYTHON_BIN="${LIVE_EXECUTION_PREP_TEST_PYTHON_BIN:-${LIVE_EXECUTION_PREP_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set LIVE_EXECUTION_PREP_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi
export LIVE_EXECUTION_PREP_PYTHON_BIN="${LIVE_EXECUTION_PREP_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_PRECHECK_PYTHON_BIN="${LIVE_PRECHECK_PYTHON_BIN:-${PYTHON_BIN}}"

VALID_RUN_ID="live-execution-prep-valid"
REPO_LOCAL_RUN_ID="live-execution-prep-repo-local-selector"
APPROVAL_REUSE_RUN_ID="live-execution-prep-approval-reuse"
ROLLBACK_MISMATCH_RUN_ID="live-execution-prep-rollback-mismatch"
INVALID_RUN_ID="../bad"

VALID_RUN_DIR="${RUNS_ROOT}/${VALID_RUN_ID}"
REPO_LOCAL_RUN_DIR="${RUNS_ROOT}/${REPO_LOCAL_RUN_ID}"
APPROVAL_REUSE_RUN_DIR="${RUNS_ROOT}/${APPROVAL_REUSE_RUN_ID}"
ROLLBACK_MISMATCH_RUN_DIR="${RUNS_ROOT}/${ROLLBACK_MISMATCH_RUN_ID}"

TMP_ROOT="$(mktemp -d)"
VALID_SELECTOR="${TMP_ROOT}/live-target-selector.json"
VALID_APPROVAL="${TMP_ROOT}/operator-approval.json"
VALID_ROLLBACK="${TMP_ROOT}/rollback-handoff.json"
REPO_LOCAL_SELECTOR="${SCRIPT_DIR}/repo-local-live-target-selector.tmp.json"
APPROVAL_REUSE_FILE="${TMP_ROOT}/operator-approval-reuse.json"
ROLLBACK_MISMATCH_FILE="${TMP_ROOT}/rollback-handoff-mismatch.json"

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
    print(f"refusing to delete outside generated runs: {target}", file=sys.stderr)
    raise SystemExit(1)

if len(relative.parts) != 1 or target.name != expected_name:
    print(f"refusing to delete non-direct generated run child: {target}", file=sys.stderr)
    raise SystemExit(1)
PY

  rm -rf -- "${target}"
}

cleanup_run_pair() {
  local run_id="$1"
  local run_dir="$2"
  safe_rm_generated_dir "${run_dir}" "${RUNS_ROOT}" "${run_id}"
  safe_rm_generated_dir "${PRECHECK_RUNS_ROOT}/${run_id}-precheck" "${PRECHECK_RUNS_ROOT}" "${run_id}-precheck"
}

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && "${TMP_ROOT}" == /tmp/* && -d "${TMP_ROOT}" ]]; then
    rm -rf -- "${TMP_ROOT}"
  fi
  rm -f -- "${REPO_LOCAL_SELECTOR}"
  cleanup_run_pair "${VALID_RUN_ID}" "${VALID_RUN_DIR}"
  cleanup_run_pair "${REPO_LOCAL_RUN_ID}" "${REPO_LOCAL_RUN_DIR}"
  cleanup_run_pair "${APPROVAL_REUSE_RUN_ID}" "${APPROVAL_REUSE_RUN_DIR}"
  cleanup_run_pair "${ROLLBACK_MISMATCH_RUN_ID}" "${ROLLBACK_MISMATCH_RUN_DIR}"
}

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
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

selector = {
    "selector_kind": "live-target-selector",
    "selector_label": selector_label,
    "target_class": "live",
    "target_instance_label": target_label,
    "workspace_root": str(tmp_root / "reviewed-live-workspace-root"),
    "state_root": str(tmp_root / "reviewed-live-state-root"),
    "runtime_root": str(tmp_root / "reviewed-live-runtime-root"),
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

run_prep_expect_fail() {
  local label="$1"
  local run_id="$2"
  local run_dir="$3"
  local expected_field="$4"
  shift 4
  cleanup_run_pair "${run_id}" "${run_dir}"

  set +e
  bash operations/harness-openclaw-live-execution-prep/bin/run_live_execution_prep.sh "$@" --run-id "${run_id}" >/dev/null 2>&1
  local status=$?
  set -e
  [[ "${status}" -ne 0 ]] || fail "negative live execution prep case unexpectedly passed: ${label}"
  assert_file "${run_dir}/execution_prep_report.json"
  assert_report_field "${run_dir}/execution_prep_report.json" "${expected_field}" "fail"
  echo "PASS live execution prep negative case rejected: ${label}"
}

cd "${REPO_ROOT}"
mkdir -p "${RUNS_ROOT}" "${PRECHECK_RUNS_ROOT}"
cleanup
trap cleanup EXIT

write_records "${VALID_SELECTOR}" "${VALID_APPROVAL}" "${VALID_ROLLBACK}" "reviewed-live-instance-a" "reviewed-live-selector-a" "execution-attempt-a"

bash operations/harness-openclaw-live-execution-prep/bin/run_live_execution_prep.sh \
  --selector-file "${VALID_SELECTOR}" \
  --approval-file "${VALID_APPROVAL}" \
  --rollback-file "${VALID_ROLLBACK}" \
  --run-id "${VALID_RUN_ID}"

assert_file "${VALID_RUN_DIR}/execution_prep_meta.json"
assert_file "${VALID_RUN_DIR}/execution_prep_report.json"
assert_file "${VALID_RUN_DIR}/selector_execution_record.json"
assert_file "${VALID_RUN_DIR}/approval_execution_record.json"
assert_file "${VALID_RUN_DIR}/rollback_execution_record.json"
assert_file "${VALID_RUN_DIR}/execution_prep_bundle.json"
assert_file "${VALID_RUN_DIR}/input_refs.json"
assert_file "${VALID_RUN_DIR}/checks/preexecution_gate_validation.json"
assert_file "${VALID_RUN_DIR}/checks/approval_record_validation.json"
assert_file "${VALID_RUN_DIR}/checks/rollback_record_validation.json"
assert_file "${VALID_RUN_DIR}/exit_code"
assert_file "${PRECHECK_RUNS_ROOT}/${VALID_RUN_ID}-precheck/gate_report.json"
assert_file_text_equals "${VALID_RUN_DIR}/exit_code" "0"

"${PYTHON_BIN}" - "${VALID_RUN_DIR}" "${PRECHECK_RUNS_ROOT}/${VALID_RUN_ID}-precheck" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
precheck_dir = Path(sys.argv[2])

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

meta = load(run_dir / "execution_prep_meta.json")
report = load(run_dir / "execution_prep_report.json")
selector = load(run_dir / "selector_execution_record.json")
approval = load(run_dir / "approval_execution_record.json")
rollback = load(run_dir / "rollback_execution_record.json")
bundle = load(run_dir / "execution_prep_bundle.json")
refs = load(run_dir / "input_refs.json")
precheck = load(run_dir / "checks" / "preexecution_gate_validation.json")
approval_check = load(run_dir / "checks" / "approval_record_validation.json")
rollback_check = load(run_dir / "checks" / "rollback_record_validation.json")
precheck_report = load(precheck_dir / "gate_report.json")

assert meta["surface_kind"] == "live-execution-prep", meta
assert meta["execution_prep_only"] is True, meta
assert meta["live_runtime_apply"] is False, meta
assert meta["live_wrapper"] is False, meta
assert meta["crab_approved"] is False, meta
assert meta["approval_granting"] is False, meta
assert meta["rollback_execution"] is False, meta

assert report["overall_status"] == "pass", report
assert report["preexecution_gate_validation"] == "pass", report
assert report["approval_record_validation"] == "pass", report
assert report["rollback_record_validation"] == "pass", report
assert report["execution_prep_only"] is True, report
assert report["live_runtime_apply"] is False, report
assert report["live_wrapper"] is False, report
assert report["crab_approved"] is False, report

assert precheck["status"] == "pass", precheck
assert precheck["precheck_run_id"] == "live-execution-prep-valid-precheck", precheck
assert precheck["overall_status"] == "pass", precheck
assert precheck_report["overall_status"] == "pass", precheck_report
assert approval_check["status"] == "pass", approval_check
assert rollback_check["status"] == "pass", rollback_check

assert selector["record_kind"] == "selector-execution-record", selector
assert selector["selector_label"] == "reviewed-live-selector-a", selector
assert selector["target_instance_label"] == "reviewed-live-instance-a", selector
assert selector["target_class"] == "live", selector
assert selector["is_disposable"] is False, selector
assert approval["record_kind"] == "approval-execution-record", approval
assert approval["approved_operation_class"] == "live-runtime-apply", approval
assert approval["selector_label"] == selector["selector_label"], approval
assert approval["target_instance_label"] == selector["target_instance_label"], approval
assert approval["execution_label"] == "execution-attempt-a", approval
assert approval["non_reusable"] is True, approval
assert rollback["record_kind"] == "rollback-execution-record", rollback
assert rollback["target_instance_label"] == selector["target_instance_label"], rollback
assert rollback["execution_label"] == approval["execution_label"], rollback
assert rollback["rollback_ready"] is True, rollback
assert rollback["decision_points"], rollback
assert bundle["bundle_kind"] == "live-execution-prep-bundle", bundle
assert bundle["execution_prep_only"] is True, bundle
assert bundle["live_runtime_apply"] is False, bundle
assert refs["precheck"]["precheck_run_dir"] == "operations/harness-openclaw-live-precheck/runs/live-execution-prep-valid-precheck", refs
assert refs["contains_secrets"] is False, refs
PY

cp "${VALID_SELECTOR}" "${REPO_LOCAL_SELECTOR}"
run_prep_expect_fail \
  "repo-local selector file" \
  "${REPO_LOCAL_RUN_ID}" \
  "${REPO_LOCAL_RUN_DIR}" \
  "preexecution_gate_validation" \
  --selector-file "${REPO_LOCAL_SELECTOR}" \
  --approval-file "${VALID_APPROVAL}" \
  --rollback-file "${VALID_ROLLBACK}"

cp "${VALID_APPROVAL}" "${APPROVAL_REUSE_FILE}"
"${PYTHON_BIN}" - "${APPROVAL_REUSE_FILE}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8-sig"))
payload["non_reusable"] = False
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
run_prep_expect_fail \
  "approval record not non-reusable" \
  "${APPROVAL_REUSE_RUN_ID}" \
  "${APPROVAL_REUSE_RUN_DIR}" \
  "approval_record_validation" \
  --selector-file "${VALID_SELECTOR}" \
  --approval-file "${APPROVAL_REUSE_FILE}" \
  --rollback-file "${VALID_ROLLBACK}"

cp "${VALID_ROLLBACK}" "${ROLLBACK_MISMATCH_FILE}"
"${PYTHON_BIN}" - "${ROLLBACK_MISMATCH_FILE}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8-sig"))
payload["execution_label"] = "different-execution-attempt"
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
run_prep_expect_fail \
  "rollback execution label mismatch" \
  "${ROLLBACK_MISMATCH_RUN_ID}" \
  "${ROLLBACK_MISMATCH_RUN_DIR}" \
  "rollback_record_validation" \
  --selector-file "${VALID_SELECTOR}" \
  --approval-file "${VALID_APPROVAL}" \
  --rollback-file "${ROLLBACK_MISMATCH_FILE}"

before_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
set +e
bash operations/harness-openclaw-live-execution-prep/bin/run_live_execution_prep.sh \
  --selector-file "${VALID_SELECTOR}" \
  --approval-file "${VALID_APPROVAL}" \
  --rollback-file "${VALID_ROLLBACK}" \
  --run-id "${INVALID_RUN_ID}" >/dev/null 2>&1
invalid_status=$?
set -e
[[ "${invalid_status}" -ne 0 ]] || fail "invalid run id unexpectedly passed"
after_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
[[ "${before_runs}" == "${after_runs}" ]] || fail "invalid run id created a live execution prep run dir"

echo "PASS live execution prep valid run"
echo "PASS live execution prep rejects invalid inputs"
