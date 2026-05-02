#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WRAPPER_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${WRAPPER_ROOT}/../.." && pwd -P)"
RUNS_ROOT="${WRAPPER_ROOT}/runs"
PREP_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-execution-prep/runs"
PRECHECK_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-precheck/runs"
RETENTION_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-retention/runs"
INTAKE_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-wrapper-intake/runs"

PYTHON_BIN="${LIVE_WRAPPER_PREFLIGHT_TEST_PYTHON_BIN:-${LIVE_WRAPPER_PREFLIGHT_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set LIVE_WRAPPER_PREFLIGHT_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi
export LIVE_WRAPPER_PREFLIGHT_PYTHON_BIN="${LIVE_WRAPPER_PREFLIGHT_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_WRAPPER_INTAKE_PYTHON_BIN="${LIVE_WRAPPER_INTAKE_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_EXECUTION_PREP_PYTHON_BIN="${LIVE_EXECUTION_PREP_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_PRECHECK_PYTHON_BIN="${LIVE_PRECHECK_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_RETENTION_PYTHON_BIN="${LIVE_RETENTION_PYTHON_BIN:-${PYTHON_BIN}}"

VALID_WRAPPER_RUN_ID="live-wrapper-preflight-valid"
BAD_ROOT_RUN_ID="live-wrapper-preflight-bad-intake-root"
FAILED_INPUT_RUN_ID="live-wrapper-preflight-failed-intake-input"
INVALID_RUN_ID="../bad"

VALID_PREP_RUN_ID="live-wrapper-preflight-valid-prep"
VALID_RETENTION_RUN_ID="live-wrapper-preflight-valid-retention"
VALID_INTAKE_RUN_ID="live-wrapper-preflight-valid-intake"
FAILED_INTAKE_RUN_ID="live-wrapper-preflight-failed-intake"

VALID_WRAPPER_RUN_DIR="${RUNS_ROOT}/${VALID_WRAPPER_RUN_ID}"
BAD_ROOT_RUN_DIR="${RUNS_ROOT}/${BAD_ROOT_RUN_ID}"
FAILED_INPUT_RUN_DIR="${RUNS_ROOT}/${FAILED_INPUT_RUN_ID}"
VALID_PREP_RUN_DIR="${PREP_RUNS_ROOT}/${VALID_PREP_RUN_ID}"
VALID_RETENTION_RUN_DIR="${RETENTION_RUNS_ROOT}/${VALID_RETENTION_RUN_ID}"
VALID_INTAKE_RUN_DIR="${INTAKE_RUNS_ROOT}/${VALID_INTAKE_RUN_ID}"
FAILED_INTAKE_RUN_DIR="${INTAKE_RUNS_ROOT}/${FAILED_INTAKE_RUN_ID}"

TMP_ROOT="$(mktemp -d)"
VALID_SELECTOR="${TMP_ROOT}/live-target-selector.json"
VALID_APPROVAL="${TMP_ROOT}/operator-approval.json"
VALID_ROLLBACK="${TMP_ROOT}/rollback-handoff.json"
DECLARATION_FILE="${TMP_ROOT}/source-declaration.json"
CANDIDATE_DIR="${TMP_ROOT}/candidate-evidence"
BAD_ROOT_DIR="${SCRIPT_DIR}/repo-local-invalid-root.tmp"

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

cleanup_prep_pair() {
  local run_id="$1"
  local run_dir="$2"
  safe_rm_generated_dir "${run_dir}" "${PREP_RUNS_ROOT}" "${run_id}"
  safe_rm_generated_dir "${PRECHECK_RUNS_ROOT}/${run_id}-precheck" "${PRECHECK_RUNS_ROOT}" "${run_id}-precheck"
}

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && "${TMP_ROOT}" == /tmp/* && -d "${TMP_ROOT}" ]]; then
    rm -rf -- "${TMP_ROOT}"
  fi
  rm -rf -- "${BAD_ROOT_DIR}"
  safe_rm_generated_dir "${VALID_WRAPPER_RUN_DIR}" "${RUNS_ROOT}" "${VALID_WRAPPER_RUN_ID}"
  safe_rm_generated_dir "${BAD_ROOT_RUN_DIR}" "${RUNS_ROOT}" "${BAD_ROOT_RUN_ID}"
  safe_rm_generated_dir "${FAILED_INPUT_RUN_DIR}" "${RUNS_ROOT}" "${FAILED_INPUT_RUN_ID}"
  cleanup_prep_pair "${VALID_PREP_RUN_ID}" "${VALID_PREP_RUN_DIR}"
  safe_rm_generated_dir "${VALID_RETENTION_RUN_DIR}" "${RETENTION_RUNS_ROOT}" "${VALID_RETENTION_RUN_ID}"
  safe_rm_generated_dir "${VALID_INTAKE_RUN_DIR}" "${INTAKE_RUNS_ROOT}" "${VALID_INTAKE_RUN_ID}"
  safe_rm_generated_dir "${FAILED_INTAKE_RUN_DIR}" "${INTAKE_RUNS_ROOT}" "${FAILED_INTAKE_RUN_ID}"
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

write_declaration() {
  local path="$1"
  "${PYTHON_BIN}" - "${path}" "${TMP_ROOT}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
tmp_root = Path(sys.argv[2])
payload = {
    "declaration_kind": "secret-material-source-declaration",
    "declaration_label": "reviewed-live-material-source",
    "execution_label": "wrapper-preflight-execution-a",
    "local_only": True,
    "outside_git": True,
    "sources": [
        {
            "source_label": "reviewed-provider-config",
            "source_class": "outside-git-local-material",
            "source_path": str(tmp_root / "reviewed-material-root"),
            "contains_raw_secrets": True,
        }
    ],
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

write_candidate_evidence() {
  local dir="$1"
  "${PYTHON_BIN}" - "${dir}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.mkdir(parents=True, exist_ok=True)
(path / "event.json").write_text(
    json.dumps(
        {
            "event": "candidate-wrapper-preflight-evidence",
            "nested": {
                "api_key": "json-clear-value",
                "oauth": "json-oauth-value",
            },
            "plain": "kept",
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
(path / "operator.log").write_text(
    "\n".join(
        [
            "token=clear-token-value",
            "Authorization: Bearer clear-bearer-value",
            "credential=clear-credential-value",
            "safe_line=kept",
        ]
    )
    + "\n",
    encoding="utf-8",
)
PY
}

run_preflight_expect_fail() {
  local label="$1"
  local run_id="$2"
  local run_dir="$3"
  shift 3
  safe_rm_generated_dir "${run_dir}" "${RUNS_ROOT}" "${run_id}"

  set +e
  bash operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_preflight.sh "$@" --run-id "${run_id}" >/dev/null 2>&1
  local status=$?
  set -e
  [[ "${status}" -ne 0 ]] || fail "negative live wrapper preflight case unexpectedly passed: ${label}"
  assert_file "${run_dir}/wrapper_report.json"
  assert_report_field "${run_dir}/wrapper_report.json" "wrapper_intake_validation" "fail"
  echo "PASS live wrapper preflight negative case rejected: ${label}"
}

cd "${REPO_ROOT}"
mkdir -p "${RUNS_ROOT}" "${PREP_RUNS_ROOT}" "${RETENTION_RUNS_ROOT}" "${INTAKE_RUNS_ROOT}" "${PRECHECK_RUNS_ROOT}"
cleanup
trap cleanup EXIT

write_records "${VALID_SELECTOR}" "${VALID_APPROVAL}" "${VALID_ROLLBACK}" "reviewed-live-instance-a" "reviewed-live-selector-a" "execution-attempt-a"
write_declaration "${DECLARATION_FILE}"
write_candidate_evidence "${CANDIDATE_DIR}"

bash operations/harness-openclaw-live-retention/bin/run_secret_retention_surface.sh \
  --source-declaration-file "${DECLARATION_FILE}" \
  --candidate-evidence-dir "${CANDIDATE_DIR}" \
  --run-id "${VALID_RETENTION_RUN_ID}"

bash operations/harness-openclaw-live-execution-prep/bin/run_live_execution_prep.sh \
  --selector-file "${VALID_SELECTOR}" \
  --approval-file "${VALID_APPROVAL}" \
  --rollback-file "${VALID_ROLLBACK}" \
  --run-id "${VALID_PREP_RUN_ID}"

bash operations/harness-openclaw-live-wrapper-intake/bin/run_live_wrapper_intake.sh \
  --execution-prep-run-dir "operations/harness-openclaw-live-execution-prep/runs/${VALID_PREP_RUN_ID}" \
  --retention-run-dir "operations/harness-openclaw-live-retention/runs/${VALID_RETENTION_RUN_ID}" \
  --run-id "${VALID_INTAKE_RUN_ID}"

bash operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_preflight.sh \
  --wrapper-intake-run-dir "operations/harness-openclaw-live-wrapper-intake/runs/${VALID_INTAKE_RUN_ID}" \
  --run-id "${VALID_WRAPPER_RUN_ID}"

assert_file "${VALID_WRAPPER_RUN_DIR}/wrapper_meta.json"
assert_file "${VALID_WRAPPER_RUN_DIR}/wrapper_report.json"
assert_file "${VALID_WRAPPER_RUN_DIR}/wrapper_input_refs.json"
assert_file "${VALID_WRAPPER_RUN_DIR}/execution_plan_stub.json"
assert_file "${VALID_WRAPPER_RUN_DIR}/checks/wrapper_intake_validation.json"
assert_file "${VALID_WRAPPER_RUN_DIR}/checks/preflight_boundary_validation.json"
assert_file "${VALID_WRAPPER_RUN_DIR}/exit_code"
assert_file_text_equals "${VALID_WRAPPER_RUN_DIR}/exit_code" "0"

"${PYTHON_BIN}" - "${VALID_WRAPPER_RUN_DIR}" "${VALID_INTAKE_RUN_DIR}" "${VALID_RETENTION_RUN_DIR}/retained" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
intake_dir = Path(sys.argv[2])
retained_dir = Path(sys.argv[3])

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

meta = load(run_dir / "wrapper_meta.json")
report = load(run_dir / "wrapper_report.json")
refs = load(run_dir / "wrapper_input_refs.json")
plan = load(run_dir / "execution_plan_stub.json")
intake_check = load(run_dir / "checks" / "wrapper_intake_validation.json")
boundary_check = load(run_dir / "checks" / "preflight_boundary_validation.json")

assert meta["surface_kind"] == "live-wrapper-preflight", meta
assert meta["preflight_only"] is True, meta
assert meta["live_runtime_apply"] is False, meta
assert meta["live_wrapper"] is False, meta
assert meta["crab_approved"] is False, meta
assert meta["approval_granting"] is False, meta
assert meta["rollback_execution"] is False, meta
assert meta["real_secret_loading"] is False, meta
assert meta["target_mutation"] is False, meta

assert report["overall_status"] == "pass", report
assert report["wrapper_intake_validation"] == "pass", report
assert report["preflight_boundary_validation"] == "pass", report
assert report["preflight_only"] is True, report
assert report["live_runtime_apply"] is False, report
assert report["live_wrapper"] is False, report
assert report["crab_approved"] is False, report

assert intake_check["status"] == "pass", intake_check
assert boundary_check["status"] == "pass", boundary_check
for value in boundary_check["flags"].values():
    assert value is False, boundary_check

assert plan["plan_kind"] == "live-wrapper-preflight-stub", plan
assert plan["preflight_only"] is True, plan
assert plan["live_runtime_apply"] is False, plan
assert plan["live_wrapper"] is False, plan
assert plan["crab_approved"] is False, plan
assert plan["approval_granting"] is False, plan
assert plan["rollback_execution"] is False, plan
assert plan["real_secret_loading"] is False, plan
assert plan["target_identity"]["target_instance_label"] == "reviewed-live-instance-a", plan
assert plan["target_identity"]["execution_label"] == "execution-attempt-a", plan
assert plan["inputs"]["wrapper_intake_run_dir"].endswith("/live-wrapper-preflight-valid-intake"), plan
assert plan["inputs"]["execution_input_bundle"].endswith("/execution_input_bundle.json"), plan
assert plan["future_steps"] == [
    "real secret loading",
    "wrapper-integrated redaction",
    "live runtime apply",
], plan
assert plan["contains_retained_contents"] is False, plan
assert plan["contains_source_declaration_body"] is False, plan
assert plan["contains_target_mutation_commands"] is False, plan

assert refs["wrapper_intake_run_dir"].endswith("/live-wrapper-preflight-valid-intake"), refs
assert refs["execution_input_bundle"].endswith("/execution_input_bundle.json"), refs
assert refs["selector_execution_record"].endswith("/selector_execution_record.json"), refs
assert refs["approval_execution_record"].endswith("/approval_execution_record.json"), refs
assert refs["rollback_execution_record"].endswith("/rollback_execution_record.json"), refs
assert refs["retained_evidence_dir"].endswith("/retained"), refs
assert refs["contains_file_contents"] is False, refs
assert refs["contains_source_declaration_body"] is False, refs

plan_text = json.dumps(plan, sort_keys=True)
refs_text = json.dumps(refs, sort_keys=True)
for retained_file in retained_dir.rglob("*"):
    if retained_file.is_file():
        retained_content = retained_file.read_text(encoding="utf-8-sig").strip()
        assert retained_content not in plan_text, retained_file
        assert retained_content not in refs_text, retained_file
assert "json-clear-value" not in plan_text, plan_text
assert "clear-token-value" not in plan_text, plan_text
assert "clear-bearer-value" not in plan_text, plan_text
assert "clear-credential-value" not in plan_text, plan_text
assert str(intake_dir / "input_refs.json") not in plan_text, plan_text
PY

mkdir -p "${BAD_ROOT_DIR}"
run_preflight_expect_fail \
  "invalid wrapper-intake run dir root" \
  "${BAD_ROOT_RUN_ID}" \
  "${BAD_ROOT_RUN_DIR}" \
  --wrapper-intake-run-dir "operations/harness-openclaw-live-wrapper/tests/repo-local-invalid-root.tmp"

set +e
bash operations/harness-openclaw-live-wrapper-intake/bin/run_live_wrapper_intake.sh \
  --execution-prep-run-dir "operations/harness-openclaw-live-wrapper/tests/repo-local-invalid-root.tmp" \
  --retention-run-dir "operations/harness-openclaw-live-retention/runs/${VALID_RETENTION_RUN_ID}" \
  --run-id "${FAILED_INTAKE_RUN_ID}" >/dev/null 2>&1
failed_intake_status=$?
set -e
[[ "${failed_intake_status}" -ne 0 ]] || fail "expected failed wrapper-intake input to fail"

run_preflight_expect_fail \
  "failed wrapper-intake input" \
  "${FAILED_INPUT_RUN_ID}" \
  "${FAILED_INPUT_RUN_DIR}" \
  --wrapper-intake-run-dir "operations/harness-openclaw-live-wrapper-intake/runs/${FAILED_INTAKE_RUN_ID}"

before_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
set +e
bash operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_preflight.sh \
  --wrapper-intake-run-dir "operations/harness-openclaw-live-wrapper-intake/runs/${VALID_INTAKE_RUN_ID}" \
  --run-id "${INVALID_RUN_ID}" >/dev/null 2>&1
invalid_status=$?
set -e
[[ "${invalid_status}" -ne 0 ]] || fail "invalid run id unexpectedly passed"
after_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
[[ "${before_runs}" == "${after_runs}" ]] || fail "invalid run id created a live wrapper preflight run dir"

echo "PASS live wrapper preflight valid run"
echo "PASS live wrapper preflight rejects invalid inputs"
