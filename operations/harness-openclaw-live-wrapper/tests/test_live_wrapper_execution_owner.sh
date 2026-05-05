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
MATERIAL_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-material-resolution/runs"
SESSION_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-secret-session/runs"

PYTHON_BIN="${LIVE_WRAPPER_EXECUTION_OWNER_TEST_PYTHON_BIN:-${LIVE_WRAPPER_EXECUTION_OWNER_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set LIVE_WRAPPER_EXECUTION_OWNER_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi
export LIVE_WRAPPER_EXECUTION_OWNER_PYTHON_BIN="${LIVE_WRAPPER_EXECUTION_OWNER_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_SECRET_SESSION_PYTHON_BIN="${LIVE_SECRET_SESSION_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_MATERIAL_RESOLUTION_PYTHON_BIN="${LIVE_MATERIAL_RESOLUTION_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_WRAPPER_PREFLIGHT_PYTHON_BIN="${LIVE_WRAPPER_PREFLIGHT_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_WRAPPER_INTAKE_PYTHON_BIN="${LIVE_WRAPPER_INTAKE_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_EXECUTION_PREP_PYTHON_BIN="${LIVE_EXECUTION_PREP_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_PRECHECK_PYTHON_BIN="${LIVE_PRECHECK_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_RETENTION_PYTHON_BIN="${LIVE_RETENTION_PYTHON_BIN:-${PYTHON_BIN}}"

VALID_RUN_ID="live-wrapper-execution-owner-valid"
BAD_SESSION_ROOT_RUN_ID="live-wrapper-execution-owner-bad-session-root"
FAILED_SESSION_INPUT_RUN_ID="live-wrapper-execution-owner-failed-session-input"
BROKEN_OBSERVATION_RUN_ID="live-wrapper-execution-owner-broken-observation"
INVALID_RUN_ID="../bad"

BASE_PREP_RUN_ID="live-wrapper-execution-owner-valid-prep"
BASE_RETENTION_RUN_ID="live-wrapper-execution-owner-valid-retention"
BASE_INTAKE_RUN_ID="live-wrapper-execution-owner-valid-intake"
BASE_WRAPPER_PREFLIGHT_RUN_ID="live-wrapper-execution-owner-valid-wrapper-preflight"
BASE_MATERIAL_RUN_ID="live-wrapper-execution-owner-valid-material"
VALID_SESSION_RUN_ID="live-wrapper-execution-owner-valid-session"
FAILED_SESSION_RUN_ID="live-wrapper-execution-owner-failed-session"
BROKEN_SESSION_RUN_ID="live-wrapper-execution-owner-broken-session"

VALID_RUN_DIR="${RUNS_ROOT}/${VALID_RUN_ID}"
BAD_SESSION_ROOT_RUN_DIR="${RUNS_ROOT}/${BAD_SESSION_ROOT_RUN_ID}"
FAILED_SESSION_INPUT_RUN_DIR="${RUNS_ROOT}/${FAILED_SESSION_INPUT_RUN_ID}"
BROKEN_OBSERVATION_RUN_DIR="${RUNS_ROOT}/${BROKEN_OBSERVATION_RUN_ID}"

BASE_PREP_RUN_DIR="${PREP_RUNS_ROOT}/${BASE_PREP_RUN_ID}"
BASE_RETENTION_RUN_DIR="${RETENTION_RUNS_ROOT}/${BASE_RETENTION_RUN_ID}"
BASE_INTAKE_RUN_DIR="${INTAKE_RUNS_ROOT}/${BASE_INTAKE_RUN_ID}"
BASE_WRAPPER_PREFLIGHT_RUN_DIR="${RUNS_ROOT}/${BASE_WRAPPER_PREFLIGHT_RUN_ID}"
BASE_MATERIAL_RUN_DIR="${MATERIAL_RUNS_ROOT}/${BASE_MATERIAL_RUN_ID}"
VALID_SESSION_RUN_DIR="${SESSION_RUNS_ROOT}/${VALID_SESSION_RUN_ID}"
FAILED_SESSION_RUN_DIR="${SESSION_RUNS_ROOT}/${FAILED_SESSION_RUN_ID}"
BROKEN_SESSION_RUN_DIR="${SESSION_RUNS_ROOT}/${BROKEN_SESSION_RUN_ID}"

TMP_ROOT="$(mktemp -d)"
VALID_SELECTOR="${TMP_ROOT}/live-target-selector.json"
VALID_APPROVAL="${TMP_ROOT}/operator-approval.json"
VALID_ROLLBACK="${TMP_ROOT}/rollback-handoff.json"
DECLARATION_FILE="${TMP_ROOT}/source-declaration.json"
CANDIDATE_DIR="${TMP_ROOT}/candidate-evidence"
MATERIAL_FILE="${TMP_ROOT}/reviewed-material-root/material.txt"
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
  safe_rm_generated_dir "${VALID_RUN_DIR}" "${RUNS_ROOT}" "${VALID_RUN_ID}"
  safe_rm_generated_dir "${BAD_SESSION_ROOT_RUN_DIR}" "${RUNS_ROOT}" "${BAD_SESSION_ROOT_RUN_ID}"
  safe_rm_generated_dir "${FAILED_SESSION_INPUT_RUN_DIR}" "${RUNS_ROOT}" "${FAILED_SESSION_INPUT_RUN_ID}"
  safe_rm_generated_dir "${BROKEN_OBSERVATION_RUN_DIR}" "${RUNS_ROOT}" "${BROKEN_OBSERVATION_RUN_ID}"
  cleanup_prep_pair "${BASE_PREP_RUN_ID}" "${BASE_PREP_RUN_DIR}"
  safe_rm_generated_dir "${BASE_RETENTION_RUN_DIR}" "${RETENTION_RUNS_ROOT}" "${BASE_RETENTION_RUN_ID}"
  safe_rm_generated_dir "${BASE_INTAKE_RUN_DIR}" "${INTAKE_RUNS_ROOT}" "${BASE_INTAKE_RUN_ID}"
  safe_rm_generated_dir "${BASE_WRAPPER_PREFLIGHT_RUN_DIR}" "${RUNS_ROOT}" "${BASE_WRAPPER_PREFLIGHT_RUN_ID}"
  safe_rm_generated_dir "${BASE_MATERIAL_RUN_DIR}" "${MATERIAL_RUNS_ROOT}" "${BASE_MATERIAL_RUN_ID}"
  safe_rm_generated_dir "${VALID_SESSION_RUN_DIR}" "${SESSION_RUNS_ROOT}" "${VALID_SESSION_RUN_ID}"
  safe_rm_generated_dir "${FAILED_SESSION_RUN_DIR}" "${SESSION_RUNS_ROOT}" "${FAILED_SESSION_RUN_ID}"
  safe_rm_generated_dir "${BROKEN_SESSION_RUN_DIR}" "${SESSION_RUNS_ROOT}" "${BROKEN_SESSION_RUN_ID}"
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
  "${PYTHON_BIN}" - "${VALID_SELECTOR}" "${VALID_APPROVAL}" "${VALID_ROLLBACK}" "${TMP_ROOT}" <<'PY'
import json
import sys
from pathlib import Path

selector_path = Path(sys.argv[1])
approval_path = Path(sys.argv[2])
rollback_path = Path(sys.argv[3])
tmp_root = Path(sys.argv[4])

selector = {
    "selector_kind": "live-target-selector",
    "selector_label": "reviewed-live-selector-a",
    "target_class": "live",
    "target_instance_label": "reviewed-live-instance-a",
    "workspace_root": str(tmp_root / "reviewed-live-workspace-root"),
    "state_root": str(tmp_root / "reviewed-live-state-root"),
    "runtime_root": str(tmp_root / "reviewed-live-runtime-root"),
    "is_disposable": False,
}
approval = {
    "approval_kind": "operator-approval",
    "approval_label": "reviewed-operator-approval",
    "approved_operation_class": "live-runtime-apply",
    "target_instance_label": "reviewed-live-instance-a",
    "selector_label": "reviewed-live-selector-a",
    "execution_label": "execution-attempt-a",
    "non_reusable": True,
    "approved_by": "reviewed-human-operator",
}
rollback = {
    "rollback_kind": "rollback-handoff",
    "rollback_label": "reviewed-rollback-handoff",
    "target_instance_label": "reviewed-live-instance-a",
    "execution_label": "execution-attempt-a",
    "rollback_ready": True,
    "rollback_boundary": "reviewed rollback boundary for this exact attempt",
    "decision_points": [
        "abort before mutation if prechecks fail",
        "operator decides rollback after post-mutation validation failure",
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
  "${PYTHON_BIN}" - "${DECLARATION_FILE}" "${MATERIAL_FILE}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
source_path = sys.argv[2]
payload = {
    "declaration_kind": "secret-material-source-declaration",
    "declaration_label": "reviewed-live-material-source",
    "execution_label": "execution-owner-execution-a",
    "local_only": True,
    "outside_git": True,
    "sources": [
        {
            "source_label": "reviewed-provider-config",
            "source_class": "outside-git-local-material",
            "source_path": source_path,
            "contains_raw_secrets": True,
        }
    ],
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

write_candidate_evidence() {
  "${PYTHON_BIN}" - "${CANDIDATE_DIR}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.mkdir(parents=True, exist_ok=True)
(path / "event.json").write_text(
    json.dumps(
        {
            "event": "candidate-wrapper-execution-owner-evidence",
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

write_secret_material_file() {
  "${PYTHON_BIN}" - "${MATERIAL_FILE}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(
    "\n".join(
        [
            "token=material-token-value",
            "pass" + "word=material-pass-value",
            "Authorization: Bearer material-bearer-value",
            "api_key=material-api-key-value",
            "credential=material-credential-value",
        ]
    )
    + "\n",
    encoding="utf-8",
)
PY
}

run_execution_owner_expect_fail() {
  local label="$1"
  local run_id="$2"
  local run_dir="$3"
  local expected_field="$4"
  shift 4
  safe_rm_generated_dir "${run_dir}" "${RUNS_ROOT}" "${run_id}"

  set +e
  bash operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_execution_owner.sh "$@" --run-id "${run_id}" >/dev/null 2>&1
  local status=$?
  set -e
  [[ "${status}" -ne 0 ]] || fail "negative live wrapper execution-owner case unexpectedly passed: ${label}"
  assert_file "${run_dir}/wrapper_execution_report.json"
  assert_report_field "${run_dir}/wrapper_execution_report.json" "${expected_field}" "fail"
  echo "PASS live wrapper execution-owner negative case rejected: ${label}"
}

cd "${REPO_ROOT}"
mkdir -p \
  "${RUNS_ROOT}" \
  "${PREP_RUNS_ROOT}" \
  "${PRECHECK_RUNS_ROOT}" \
  "${RETENTION_RUNS_ROOT}" \
  "${INTAKE_RUNS_ROOT}" \
  "${MATERIAL_RUNS_ROOT}" \
  "${SESSION_RUNS_ROOT}"
cleanup
trap cleanup EXIT

write_records
write_declaration
write_candidate_evidence
write_secret_material_file

bash operations/harness-openclaw-live-retention/bin/run_secret_retention_surface.sh \
  --source-declaration-file "${DECLARATION_FILE}" \
  --candidate-evidence-dir "${CANDIDATE_DIR}" \
  --run-id "${BASE_RETENTION_RUN_ID}"

bash operations/harness-openclaw-live-execution-prep/bin/run_live_execution_prep.sh \
  --selector-file "${VALID_SELECTOR}" \
  --approval-file "${VALID_APPROVAL}" \
  --rollback-file "${VALID_ROLLBACK}" \
  --run-id "${BASE_PREP_RUN_ID}"

bash operations/harness-openclaw-live-wrapper-intake/bin/run_live_wrapper_intake.sh \
  --execution-prep-run-dir "operations/harness-openclaw-live-execution-prep/runs/${BASE_PREP_RUN_ID}" \
  --retention-run-dir "operations/harness-openclaw-live-retention/runs/${BASE_RETENTION_RUN_ID}" \
  --run-id "${BASE_INTAKE_RUN_ID}"

bash operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_preflight.sh \
  --wrapper-intake-run-dir "operations/harness-openclaw-live-wrapper-intake/runs/${BASE_INTAKE_RUN_ID}" \
  --run-id "${BASE_WRAPPER_PREFLIGHT_RUN_ID}"

bash operations/harness-openclaw-live-material-resolution/bin/run_live_material_resolution.sh \
  --wrapper-preflight-run-dir "operations/harness-openclaw-live-wrapper/runs/${BASE_WRAPPER_PREFLIGHT_RUN_ID}" \
  --source-declaration-file "${DECLARATION_FILE}" \
  --run-id "${BASE_MATERIAL_RUN_ID}"

bash operations/harness-openclaw-live-secret-session/bin/run_live_secret_session.sh \
  --material-resolution-run-dir "operations/harness-openclaw-live-material-resolution/runs/${BASE_MATERIAL_RUN_ID}" \
  --run-id "${VALID_SESSION_RUN_ID}"

bash operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_execution_owner.sh \
  --secret-session-run-dir "operations/harness-openclaw-live-secret-session/runs/${VALID_SESSION_RUN_ID}" \
  --run-id "${VALID_RUN_ID}"

assert_file "${VALID_RUN_DIR}/wrapper_execution_meta.json"
assert_file "${VALID_RUN_DIR}/wrapper_execution_report.json"
assert_file "${VALID_RUN_DIR}/wrapper_session_refs.json"
assert_file "${VALID_RUN_DIR}/execution_owner_manifest.json"
assert_file "${VALID_RUN_DIR}/apply_request_stub.json"
assert_file "${VALID_RUN_DIR}/checks/secret_session_validation.json"
assert_file "${VALID_RUN_DIR}/checks/execution_owner_boundary_validation.json"
assert_file "${VALID_RUN_DIR}/checks/redacted_observation_validation.json"
assert_file "${VALID_RUN_DIR}/checks/non_secret_bundle_validation.json"
assert_file "${VALID_RUN_DIR}/exit_code"
assert_file_text_equals "${VALID_RUN_DIR}/exit_code" "0"

"${PYTHON_BIN}" - "${VALID_RUN_DIR}" "${VALID_SESSION_RUN_DIR}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
session_dir = Path(sys.argv[2])

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

meta = load(run_dir / "wrapper_execution_meta.json")
report = load(run_dir / "wrapper_execution_report.json")
refs = load(run_dir / "wrapper_session_refs.json")
manifest = load(run_dir / "execution_owner_manifest.json")
stub = load(run_dir / "apply_request_stub.json")
secret_check = load(run_dir / "checks" / "secret_session_validation.json")
boundary_check = load(run_dir / "checks" / "execution_owner_boundary_validation.json")
observation_check = load(run_dir / "checks" / "redacted_observation_validation.json")
non_secret_check = load(run_dir / "checks" / "non_secret_bundle_validation.json")
observations = load(session_dir / "redacted_material_observations.json")

assert meta["surface_kind"] == "live-wrapper-execution-owner", meta
assert meta["execution_owner"] is True, meta
assert meta["live_wrapper"] is True, meta
assert meta["live_runtime_apply"] is False, meta
assert meta["crab_approved"] is False, meta
assert meta["approval_granting"] is False, meta
assert meta["rollback_execution"] is False, meta
assert meta["real_secret_loading"] is True, meta

assert report["overall_status"] == "pass", report
assert report["secret_session_validation"] == "pass", report
assert report["execution_owner_boundary_validation"] == "pass", report
assert report["redacted_observation_validation"] == "pass", report
assert report["non_secret_bundle_validation"] == "pass", report
assert report["execution_owner"] is True, report
assert report["live_wrapper"] is True, report
assert report["live_runtime_apply"] is False, report
assert report["crab_approved"] is False, report
assert report["real_secret_loading"] is True, report

assert secret_check["status"] == "pass", secret_check
assert boundary_check["status"] == "pass", boundary_check
assert boundary_check["flags"]["execution_owner"] is True, boundary_check
assert boundary_check["flags"]["live_wrapper"] is True, boundary_check
assert boundary_check["flags"]["live_runtime_apply"] is False, boundary_check
assert boundary_check["flags"]["target_mutation"] is False, boundary_check
assert boundary_check["flags"]["approval_granting"] is False, boundary_check
assert boundary_check["flags"]["rollback_execution"] is False, boundary_check
assert boundary_check["flags"]["crab_approved"] is False, boundary_check
assert boundary_check["flags"]["no_new_raw_secret_loading"] is True, boundary_check
assert boundary_check["flags"]["no_raw_secret_persistence"] is True, boundary_check
assert observation_check["status"] == "pass", observation_check
assert observation_check["observation_count"] >= 1, observation_check
assert non_secret_check["status"] == "pass", non_secret_check
assert non_secret_check["violations"] == [], non_secret_check

assert refs["secret_session_run_dir"].endswith("/live-wrapper-execution-owner-valid-session"), refs
assert refs["loaded_material_manifest"].endswith("/loaded_material_manifest.json"), refs
assert refs["redacted_material_observations"].endswith("/redacted_material_observations.json"), refs
assert refs["wrapper_secret_session_bundle"].endswith("/wrapper_secret_session_bundle.json"), refs
assert refs["target_instance_label"] == "reviewed-live-instance-a", refs
assert refs["execution_label"] == "execution-attempt-a", refs
assert refs["contains_raw_contents"] is False, refs
assert refs["contains_observation_body"] is False, refs

assert manifest["manifest_kind"] == "live-wrapper-execution-owner", manifest
assert manifest["execution_owner"] is True, manifest
assert manifest["live_wrapper"] is True, manifest
assert manifest["live_runtime_apply"] is False, manifest
assert manifest["crab_approved"] is False, manifest
assert manifest["approval_granting"] is False, manifest
assert manifest["rollback_execution"] is False, manifest
assert manifest["real_secret_loading"] is True, manifest
assert manifest["target_identity"]["target_instance_label"] == "reviewed-live-instance-a", manifest
assert manifest["target_identity"]["execution_label"] == "execution-attempt-a", manifest
assert manifest["wrapper_policy_flags"]["target_mutation"] is False, manifest
assert manifest["wrapper_policy_flags"]["apply_authorized"] is False, manifest
assert manifest["contains_redacted_observation_body"] is False, manifest

assert stub["request_kind"] == "live-runtime-apply-request-stub", stub
assert stub["execution_owner"] is True, stub
assert stub["live_wrapper"] is True, stub
assert stub["live_runtime_apply"] is False, stub
assert stub["apply_authorized"] is False, stub
assert stub["crab_approved"] is False, stub
assert stub["target_identity"]["target_instance_label"] == "reviewed-live-instance-a", stub
assert stub["target_identity"]["execution_label"] == "execution-attempt-a", stub
assert stub["refs"]["execution_owner_manifest"].endswith("/execution_owner_manifest.json"), stub
assert stub["refs"]["wrapper_session_refs"].endswith("/wrapper_session_refs.json"), stub
assert stub["future_requirements"] == [
    "bounded live runtime apply implementation",
    "operator approval binding at apply time",
    "first real rollout",
], stub
assert stub["contains_retained_content"] is False, stub
assert stub["contains_observation_body"] is False, stub
assert stub["contains_mutation_commands"] is False, stub

combined = "\n".join(
    json.dumps(payload, sort_keys=True)
    for payload in [refs, manifest, stub]
)
for raw in [
    "material-token-value",
    "material-pass-value",
    "material-bearer-value",
    "material-api-key-value",
    "material-credential-value",
]:
    assert raw not in combined, raw
for observation_text in json.dumps(observations, sort_keys=True).splitlines():
    if "[REDACTED]" in observation_text:
        assert observation_text not in combined, observation_text
PY

mkdir -p "${BAD_ROOT_DIR}"
run_execution_owner_expect_fail \
  "invalid secret-session run dir root" \
  "${BAD_SESSION_ROOT_RUN_ID}" \
  "${BAD_SESSION_ROOT_RUN_DIR}" \
  "secret_session_validation" \
  --secret-session-run-dir "operations/harness-openclaw-live-wrapper/tests/repo-local-invalid-root.tmp"

set +e
bash operations/harness-openclaw-live-secret-session/bin/run_live_secret_session.sh \
  --material-resolution-run-dir "operations/harness-openclaw-live-wrapper/tests/repo-local-invalid-root.tmp" \
  --run-id "${FAILED_SESSION_RUN_ID}" >/dev/null 2>&1
failed_session_status=$?
set -e
[[ "${failed_session_status}" -ne 0 ]] || fail "expected failed secret-session input to fail"
run_execution_owner_expect_fail \
  "failed secret-session input" \
  "${FAILED_SESSION_INPUT_RUN_ID}" \
  "${FAILED_SESSION_INPUT_RUN_DIR}" \
  "secret_session_validation" \
  --secret-session-run-dir "operations/harness-openclaw-live-secret-session/runs/${FAILED_SESSION_RUN_ID}"

cp -R "${VALID_SESSION_RUN_DIR}" "${BROKEN_SESSION_RUN_DIR}"
"${PYTHON_BIN}" - "${BROKEN_SESSION_RUN_DIR}" <<'PY'
import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
path = run_dir / "redacted_material_observations.json"
payload = json.loads(path.read_text(encoding="utf-8-sig"))
payload.setdefault("observations", []).append(
    {
        "source_label": "broken-observation",
        "preview_redacted": "token=unredacted-observation-value",
        "redaction_applied": False,
        "redaction_count": 0,
    }
)
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
run_execution_owner_expect_fail \
  "broken redacted observation input" \
  "${BROKEN_OBSERVATION_RUN_ID}" \
  "${BROKEN_OBSERVATION_RUN_DIR}" \
  "redacted_observation_validation" \
  --secret-session-run-dir "operations/harness-openclaw-live-secret-session/runs/${BROKEN_SESSION_RUN_ID}"

before_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
set +e
bash operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_execution_owner.sh \
  --secret-session-run-dir "operations/harness-openclaw-live-secret-session/runs/${VALID_SESSION_RUN_ID}" \
  --run-id "${INVALID_RUN_ID}" >/dev/null 2>&1
invalid_status=$?
set -e
[[ "${invalid_status}" -ne 0 ]] || fail "invalid run id unexpectedly passed"
after_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
[[ "${before_runs}" == "${after_runs}" ]] || fail "invalid run id created a live wrapper execution-owner run dir"

echo "PASS live wrapper execution-owner valid run"
echo "PASS live wrapper execution-owner rejects invalid inputs"
