#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SESSION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${SESSION_ROOT}/../.." && pwd -P)"
RUNS_ROOT="${SESSION_ROOT}/runs"
PREP_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-execution-prep/runs"
PRECHECK_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-precheck/runs"
RETENTION_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-retention/runs"
INTAKE_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-wrapper-intake/runs"
WRAPPER_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-wrapper/runs"
MATERIAL_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-material-resolution/runs"

PYTHON_BIN="${LIVE_SECRET_SESSION_TEST_PYTHON_BIN:-${LIVE_SECRET_SESSION_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set LIVE_SECRET_SESSION_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi
export LIVE_SECRET_SESSION_PYTHON_BIN="${LIVE_SECRET_SESSION_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_MATERIAL_RESOLUTION_PYTHON_BIN="${LIVE_MATERIAL_RESOLUTION_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_WRAPPER_PREFLIGHT_PYTHON_BIN="${LIVE_WRAPPER_PREFLIGHT_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_WRAPPER_INTAKE_PYTHON_BIN="${LIVE_WRAPPER_INTAKE_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_EXECUTION_PREP_PYTHON_BIN="${LIVE_EXECUTION_PREP_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_PRECHECK_PYTHON_BIN="${LIVE_PRECHECK_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_RETENTION_PYTHON_BIN="${LIVE_RETENTION_PYTHON_BIN:-${PYTHON_BIN}}"

VALID_RUN_ID="live-secret-session-valid"
BAD_MATERIAL_ROOT_RUN_ID="live-secret-session-bad-material-root"
FAILED_MATERIAL_INPUT_RUN_ID="live-secret-session-failed-material-input"
MISSING_SOURCE_RUN_ID="live-secret-session-missing-source"
SYMLINK_SOURCE_RUN_ID="live-secret-session-symlink-source"
REDACTION_VIOLATION_RUN_ID="live-secret-session-redaction-violation"
INVALID_RUN_ID="../bad"

BASE_PREP_RUN_ID="live-secret-session-valid-prep"
BASE_RETENTION_RUN_ID="live-secret-session-valid-retention"
BASE_INTAKE_RUN_ID="live-secret-session-valid-intake"
BASE_WRAPPER_RUN_ID="live-secret-session-valid-wrapper"
VALID_MATERIAL_RUN_ID="live-secret-session-valid-material"
FAILED_MATERIAL_RUN_ID="live-secret-session-failed-material"
SYMLINK_MATERIAL_RUN_ID="live-secret-session-symlink-material"
REDACTION_MATERIAL_RUN_ID="live-secret-session-redaction-material"

VALID_RUN_DIR="${RUNS_ROOT}/${VALID_RUN_ID}"
BAD_MATERIAL_ROOT_RUN_DIR="${RUNS_ROOT}/${BAD_MATERIAL_ROOT_RUN_ID}"
FAILED_MATERIAL_INPUT_RUN_DIR="${RUNS_ROOT}/${FAILED_MATERIAL_INPUT_RUN_ID}"
MISSING_SOURCE_RUN_DIR="${RUNS_ROOT}/${MISSING_SOURCE_RUN_ID}"
SYMLINK_SOURCE_RUN_DIR="${RUNS_ROOT}/${SYMLINK_SOURCE_RUN_ID}"
REDACTION_VIOLATION_RUN_DIR="${RUNS_ROOT}/${REDACTION_VIOLATION_RUN_ID}"

BASE_PREP_RUN_DIR="${PREP_RUNS_ROOT}/${BASE_PREP_RUN_ID}"
BASE_RETENTION_RUN_DIR="${RETENTION_RUNS_ROOT}/${BASE_RETENTION_RUN_ID}"
BASE_INTAKE_RUN_DIR="${INTAKE_RUNS_ROOT}/${BASE_INTAKE_RUN_ID}"
BASE_WRAPPER_RUN_DIR="${WRAPPER_RUNS_ROOT}/${BASE_WRAPPER_RUN_ID}"
VALID_MATERIAL_RUN_DIR="${MATERIAL_RUNS_ROOT}/${VALID_MATERIAL_RUN_ID}"
FAILED_MATERIAL_RUN_DIR="${MATERIAL_RUNS_ROOT}/${FAILED_MATERIAL_RUN_ID}"
SYMLINK_MATERIAL_RUN_DIR="${MATERIAL_RUNS_ROOT}/${SYMLINK_MATERIAL_RUN_ID}"
REDACTION_MATERIAL_RUN_DIR="${MATERIAL_RUNS_ROOT}/${REDACTION_MATERIAL_RUN_ID}"

TMP_ROOT="$(mktemp -d)"
VALID_SELECTOR="${TMP_ROOT}/live-target-selector.json"
VALID_APPROVAL="${TMP_ROOT}/operator-approval.json"
VALID_ROLLBACK="${TMP_ROOT}/rollback-handoff.json"
DECLARATION_FILE="${TMP_ROOT}/source-declaration.json"
FAILED_DECLARATION_FILE="${TMP_ROOT}/source-declaration-failed.json"
SYMLINK_DECLARATION_FILE="${TMP_ROOT}/source-declaration-symlink.json"
REDACTION_DECLARATION_FILE="${TMP_ROOT}/source-declaration-redaction.json"
CANDIDATE_DIR="${TMP_ROOT}/candidate-evidence"
MATERIAL_FILE="${TMP_ROOT}/reviewed-material-root/material.txt"
FAILED_MISSING_MATERIAL_FILE="${TMP_ROOT}/missing-material-source.txt"
SYMLINK_TARGET_FILE="${TMP_ROOT}/symlink-target/material.txt"
SYMLINK_SOURCE_PATH="${TMP_ROOT}/symlink-material-source.txt"
REDACTION_MATERIAL_FILE="${TMP_ROOT}/redaction-material-root/material.txt"
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
  safe_rm_generated_dir "${BAD_MATERIAL_ROOT_RUN_DIR}" "${RUNS_ROOT}" "${BAD_MATERIAL_ROOT_RUN_ID}"
  safe_rm_generated_dir "${FAILED_MATERIAL_INPUT_RUN_DIR}" "${RUNS_ROOT}" "${FAILED_MATERIAL_INPUT_RUN_ID}"
  safe_rm_generated_dir "${MISSING_SOURCE_RUN_DIR}" "${RUNS_ROOT}" "${MISSING_SOURCE_RUN_ID}"
  safe_rm_generated_dir "${SYMLINK_SOURCE_RUN_DIR}" "${RUNS_ROOT}" "${SYMLINK_SOURCE_RUN_ID}"
  safe_rm_generated_dir "${REDACTION_VIOLATION_RUN_DIR}" "${RUNS_ROOT}" "${REDACTION_VIOLATION_RUN_ID}"
  cleanup_prep_pair "${BASE_PREP_RUN_ID}" "${BASE_PREP_RUN_DIR}"
  safe_rm_generated_dir "${BASE_RETENTION_RUN_DIR}" "${RETENTION_RUNS_ROOT}" "${BASE_RETENTION_RUN_ID}"
  safe_rm_generated_dir "${BASE_INTAKE_RUN_DIR}" "${INTAKE_RUNS_ROOT}" "${BASE_INTAKE_RUN_ID}"
  safe_rm_generated_dir "${BASE_WRAPPER_RUN_DIR}" "${WRAPPER_RUNS_ROOT}" "${BASE_WRAPPER_RUN_ID}"
  safe_rm_generated_dir "${VALID_MATERIAL_RUN_DIR}" "${MATERIAL_RUNS_ROOT}" "${VALID_MATERIAL_RUN_ID}"
  safe_rm_generated_dir "${FAILED_MATERIAL_RUN_DIR}" "${MATERIAL_RUNS_ROOT}" "${FAILED_MATERIAL_RUN_ID}"
  safe_rm_generated_dir "${SYMLINK_MATERIAL_RUN_DIR}" "${MATERIAL_RUNS_ROOT}" "${SYMLINK_MATERIAL_RUN_ID}"
  safe_rm_generated_dir "${REDACTION_MATERIAL_RUN_DIR}" "${MATERIAL_RUNS_ROOT}" "${REDACTION_MATERIAL_RUN_ID}"
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
  local source_path="$2"
  local source_label="${3:-reviewed-provider-config}"
  "${PYTHON_BIN}" - "${path}" "${source_path}" "${source_label}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
source_path = sys.argv[2]
source_label = sys.argv[3]
payload = {
    "declaration_kind": "secret-material-source-declaration",
    "declaration_label": "reviewed-live-material-source",
    "execution_label": "secret-session-execution-a",
    "local_only": True,
    "outside_git": True,
    "sources": [
        {
            "source_label": source_label,
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
            "event": "candidate-secret-session-evidence",
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
  local path="$1"
  "${PYTHON_BIN}" - "${path}" <<'PY'
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

write_redaction_violation_file() {
  local path="$1"
  "${PYTHON_BIN}" - "${path}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text("session_cookie=material-cookie-value\n", encoding="utf-8")
PY
}

run_material_resolution() {
  local run_id="$1"
  local declaration="$2"
  bash operations/harness-openclaw-live-material-resolution/bin/run_live_material_resolution.sh \
    --wrapper-preflight-run-dir "operations/harness-openclaw-live-wrapper/runs/${BASE_WRAPPER_RUN_ID}" \
    --source-declaration-file "${declaration}" \
    --run-id "${run_id}" >/dev/null
}

run_secret_session_expect_fail() {
  local label="$1"
  local run_id="$2"
  local run_dir="$3"
  local expected_field="$4"
  shift 4
  safe_rm_generated_dir "${run_dir}" "${RUNS_ROOT}" "${run_id}"

  set +e
  bash operations/harness-openclaw-live-secret-session/bin/run_live_secret_session.sh "$@" --run-id "${run_id}" >/dev/null 2>&1
  local status=$?
  set -e
  [[ "${status}" -ne 0 ]] || fail "negative live secret session case unexpectedly passed: ${label}"
  assert_file "${run_dir}/secret_session_report.json"
  assert_report_field "${run_dir}/secret_session_report.json" "${expected_field}" "fail"
  echo "PASS live secret session negative case rejected: ${label}"
}

cd "${REPO_ROOT}"
mkdir -p "${RUNS_ROOT}" "${PREP_RUNS_ROOT}" "${RETENTION_RUNS_ROOT}" "${INTAKE_RUNS_ROOT}" "${WRAPPER_RUNS_ROOT}" "${MATERIAL_RUNS_ROOT}" "${PRECHECK_RUNS_ROOT}"
cleanup
trap cleanup EXIT

write_secret_material_file "${MATERIAL_FILE}"
write_records "${VALID_SELECTOR}" "${VALID_APPROVAL}" "${VALID_ROLLBACK}" "reviewed-live-instance-a" "reviewed-live-selector-a" "execution-attempt-a"
write_declaration "${DECLARATION_FILE}" "${MATERIAL_FILE}"
write_candidate_evidence "${CANDIDATE_DIR}"

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
  --run-id "${BASE_WRAPPER_RUN_ID}"

run_material_resolution "${VALID_MATERIAL_RUN_ID}" "${DECLARATION_FILE}" || fail "valid material resolution did not pass"

bash operations/harness-openclaw-live-secret-session/bin/run_live_secret_session.sh \
  --material-resolution-run-dir "operations/harness-openclaw-live-material-resolution/runs/${VALID_MATERIAL_RUN_ID}" \
  --run-id "${VALID_RUN_ID}"

assert_file "${VALID_RUN_DIR}/secret_session_meta.json"
assert_file "${VALID_RUN_DIR}/secret_session_report.json"
assert_file "${VALID_RUN_DIR}/loaded_material_manifest.json"
assert_file "${VALID_RUN_DIR}/redacted_material_observations.json"
assert_file "${VALID_RUN_DIR}/wrapper_secret_session_bundle.json"
assert_file "${VALID_RUN_DIR}/input_refs.json"
assert_file "${VALID_RUN_DIR}/checks/material_resolution_validation.json"
assert_file "${VALID_RUN_DIR}/checks/material_load_validation.json"
assert_file "${VALID_RUN_DIR}/checks/redaction_validation.json"
assert_file "${VALID_RUN_DIR}/checks/non_secret_bundle_validation.json"
assert_file "${VALID_RUN_DIR}/exit_code"
assert_file_text_equals "${VALID_RUN_DIR}/exit_code" "0"

"${PYTHON_BIN}" - "${VALID_RUN_DIR}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

meta = load(run_dir / "secret_session_meta.json")
report = load(run_dir / "secret_session_report.json")
manifest = load(run_dir / "loaded_material_manifest.json")
observations = load(run_dir / "redacted_material_observations.json")
bundle = load(run_dir / "wrapper_secret_session_bundle.json")
refs = load(run_dir / "input_refs.json")
material_check = load(run_dir / "checks" / "material_resolution_validation.json")
load_check = load(run_dir / "checks" / "material_load_validation.json")
redaction_check = load(run_dir / "checks" / "redaction_validation.json")
non_secret_check = load(run_dir / "checks" / "non_secret_bundle_validation.json")

assert meta["surface_kind"] == "live-secret-session", meta
assert meta["secret_session_only"] is True, meta
assert meta["live_runtime_apply"] is False, meta
assert meta["live_wrapper"] is False, meta
assert meta["crab_approved"] is False, meta
assert meta["approval_granting"] is False, meta
assert meta["rollback_execution"] is False, meta
assert meta["real_secret_loading"] is True, meta

assert report["overall_status"] == "pass", report
assert report["material_resolution_validation"] == "pass", report
assert report["material_load_validation"] == "pass", report
assert report["redaction_validation"] == "pass", report
assert report["non_secret_bundle_validation"] == "pass", report
assert report["secret_session_only"] is True, report
assert report["live_runtime_apply"] is False, report
assert report["live_wrapper"] is False, report
assert report["crab_approved"] is False, report
assert report["real_secret_loading"] is True, report

assert material_check["status"] == "pass", material_check
assert load_check["status"] == "pass", load_check
assert redaction_check["status"] == "pass", redaction_check
assert non_secret_check["status"] == "pass", non_secret_check
assert non_secret_check["violations"] == [], non_secret_check

assert manifest["manifest_kind"] == "live-loaded-material-manifest", manifest
assert manifest["secret_session_only"] is True, manifest
assert manifest["live_runtime_apply"] is False, manifest
assert manifest["live_wrapper"] is False, manifest
assert manifest["crab_approved"] is False, manifest
assert manifest["real_secret_loading"] is True, manifest
assert len(manifest["loaded_sources"]) >= 1, manifest
first_source = manifest["loaded_sources"][0]
assert first_source["loaded"] is True, first_source
assert first_source["byte_count"] > 0, first_source
assert first_source["file_count"] == 1, first_source
assert first_source["text_file_count"] == 1, first_source
assert first_source["contains_raw_secrets"] is True, first_source

assert observations["observation_kind"] == "live-redacted-material-observations", observations
assert observations["redaction_applied"] is True, observations
assert len(observations["observations"]) >= 1, observations
preview = observations["observations"][0]["preview_redacted"]
assert "[REDACTED]" in preview, observations
assert observations["observations"][0]["redaction_count"] >= 3, observations

assert bundle["bundle_kind"] == "live-wrapper-secret-session-bundle", bundle
assert bundle["secret_session_only"] is True, bundle
assert bundle["live_runtime_apply"] is False, bundle
assert bundle["live_wrapper"] is False, bundle
assert bundle["crab_approved"] is False, bundle
assert bundle["approval_granting"] is False, bundle
assert bundle["rollback_execution"] is False, bundle
assert bundle["real_secret_loading"] is True, bundle
assert bundle["target_identity"]["target_instance_label"] == "reviewed-live-instance-a", bundle
assert bundle["target_identity"]["execution_label"] == "execution-attempt-a", bundle
assert bundle["loaded_materials"]["loaded_source_count"] >= 1, bundle

assert refs["material_resolution_run_dir"].endswith("/live-secret-session-valid-material"), refs
assert refs["resolved_material_refs"].endswith("/resolved_material_refs.json"), refs
assert refs["wrapper_material_bundle"].endswith("/wrapper_material_bundle.json"), refs
assert refs["loaded_material_manifest"].endswith("/loaded_material_manifest.json"), refs
assert refs["redacted_material_observations"].endswith("/redacted_material_observations.json"), refs
assert refs["contains_raw_contents"] is False, refs
assert refs["real_secret_loading"] is True, refs

all_outputs = "\n".join(
    path.read_text(encoding="utf-8-sig")
    for path in [
        run_dir / "loaded_material_manifest.json",
        run_dir / "redacted_material_observations.json",
        run_dir / "wrapper_secret_session_bundle.json",
        run_dir / "input_refs.json",
    ]
)
for raw in [
    "material-token-value",
    "material-pass-value",
    "material-bearer-value",
    "material-api-key-value",
    "material-credential-value",
]:
    assert raw not in all_outputs, raw
PY

mkdir -p "${BAD_ROOT_DIR}"
run_secret_session_expect_fail \
  "invalid material-resolution run dir root" \
  "${BAD_MATERIAL_ROOT_RUN_ID}" \
  "${BAD_MATERIAL_ROOT_RUN_DIR}" \
  "material_resolution_validation" \
  --material-resolution-run-dir "operations/harness-openclaw-live-secret-session/tests/repo-local-invalid-root.tmp"

write_declaration "${FAILED_DECLARATION_FILE}" "${FAILED_MISSING_MATERIAL_FILE}"
set +e
run_material_resolution "${FAILED_MATERIAL_RUN_ID}" "${FAILED_DECLARATION_FILE}" >/dev/null 2>&1
failed_material_status=$?
set -e
[[ "${failed_material_status}" -ne 0 ]] || fail "expected failed material-resolution input to fail"
run_secret_session_expect_fail \
  "failed material-resolution input" \
  "${FAILED_MATERIAL_INPUT_RUN_ID}" \
  "${FAILED_MATERIAL_INPUT_RUN_DIR}" \
  "material_resolution_validation" \
  --material-resolution-run-dir "operations/harness-openclaw-live-material-resolution/runs/${FAILED_MATERIAL_RUN_ID}"

rm -f -- "${MATERIAL_FILE}"
run_secret_session_expect_fail \
  "missing source after green resolution" \
  "${MISSING_SOURCE_RUN_ID}" \
  "${MISSING_SOURCE_RUN_DIR}" \
  "material_load_validation" \
  --material-resolution-run-dir "operations/harness-openclaw-live-material-resolution/runs/${VALID_MATERIAL_RUN_ID}"

write_secret_material_file "${SYMLINK_TARGET_FILE}"
ln -s "${SYMLINK_TARGET_FILE}" "${SYMLINK_SOURCE_PATH}"
cp -R "${VALID_MATERIAL_RUN_DIR}" "${SYMLINK_MATERIAL_RUN_DIR}"
"${PYTHON_BIN}" - "${SYMLINK_MATERIAL_RUN_DIR}" "${SYMLINK_SOURCE_PATH}" <<'PY'
import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
symlink_path = sys.argv[2]
refs_path = run_dir / "resolved_material_refs.json"
refs = json.loads(refs_path.read_text(encoding="utf-8-sig"))
refs["resolved_sources"][0]["source_path"] = symlink_path
refs_path.write_text(json.dumps(refs, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
run_secret_session_expect_fail \
  "symlink source" \
  "${SYMLINK_SOURCE_RUN_ID}" \
  "${SYMLINK_SOURCE_RUN_DIR}" \
  "material_load_validation" \
  --material-resolution-run-dir "operations/harness-openclaw-live-material-resolution/runs/${SYMLINK_MATERIAL_RUN_ID}"

write_redaction_violation_file "${REDACTION_MATERIAL_FILE}"
write_declaration "${REDACTION_DECLARATION_FILE}" "${REDACTION_MATERIAL_FILE}"
run_material_resolution "${REDACTION_MATERIAL_RUN_ID}" "${REDACTION_DECLARATION_FILE}" || fail "redaction material resolution did not pass"
run_secret_session_expect_fail \
  "redaction violation" \
  "${REDACTION_VIOLATION_RUN_ID}" \
  "${REDACTION_VIOLATION_RUN_DIR}" \
  "redaction_validation" \
  --material-resolution-run-dir "operations/harness-openclaw-live-material-resolution/runs/${REDACTION_MATERIAL_RUN_ID}"

before_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
set +e
bash operations/harness-openclaw-live-secret-session/bin/run_live_secret_session.sh \
  --material-resolution-run-dir "operations/harness-openclaw-live-material-resolution/runs/${VALID_MATERIAL_RUN_ID}" \
  --run-id "${INVALID_RUN_ID}" >/dev/null 2>&1
invalid_status=$?
set -e
[[ "${invalid_status}" -ne 0 ]] || fail "invalid run id unexpectedly passed"
after_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
[[ "${before_runs}" == "${after_runs}" ]] || fail "invalid run id created a live secret session run dir"

echo "PASS live secret session valid run"
echo "PASS live secret session rejects invalid inputs"
