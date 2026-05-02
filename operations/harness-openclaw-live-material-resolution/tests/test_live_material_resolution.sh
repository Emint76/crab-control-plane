#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MATERIAL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${MATERIAL_ROOT}/../.." && pwd -P)"
RUNS_ROOT="${MATERIAL_ROOT}/runs"
PREP_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-execution-prep/runs"
PRECHECK_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-precheck/runs"
RETENTION_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-retention/runs"
INTAKE_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-wrapper-intake/runs"
WRAPPER_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-wrapper/runs"

PYTHON_BIN="${LIVE_MATERIAL_RESOLUTION_TEST_PYTHON_BIN:-${LIVE_MATERIAL_RESOLUTION_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set LIVE_MATERIAL_RESOLUTION_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi
export LIVE_MATERIAL_RESOLUTION_PYTHON_BIN="${LIVE_MATERIAL_RESOLUTION_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_WRAPPER_PREFLIGHT_PYTHON_BIN="${LIVE_WRAPPER_PREFLIGHT_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_WRAPPER_INTAKE_PYTHON_BIN="${LIVE_WRAPPER_INTAKE_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_EXECUTION_PREP_PYTHON_BIN="${LIVE_EXECUTION_PREP_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_PRECHECK_PYTHON_BIN="${LIVE_PRECHECK_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_RETENTION_PYTHON_BIN="${LIVE_RETENTION_PYTHON_BIN:-${PYTHON_BIN}}"

VALID_RUN_ID="live-material-resolution-valid"
BAD_WRAPPER_ROOT_RUN_ID="live-material-resolution-bad-wrapper-root"
REPO_LOCAL_DECL_RUN_ID="live-material-resolution-repo-local-declaration"
MISSING_SOURCE_RUN_ID="live-material-resolution-missing-source"
NON_SECRET_VIOLATION_RUN_ID="live-material-resolution-non-secret-violation"
INVALID_RUN_ID="../bad"

VALID_PREP_RUN_ID="live-material-resolution-valid-prep"
VALID_RETENTION_RUN_ID="live-material-resolution-valid-retention"
VALID_INTAKE_RUN_ID="live-material-resolution-valid-intake"
VALID_WRAPPER_RUN_ID="live-material-resolution-valid-wrapper"

VALID_RUN_DIR="${RUNS_ROOT}/${VALID_RUN_ID}"
BAD_WRAPPER_ROOT_RUN_DIR="${RUNS_ROOT}/${BAD_WRAPPER_ROOT_RUN_ID}"
REPO_LOCAL_DECL_RUN_DIR="${RUNS_ROOT}/${REPO_LOCAL_DECL_RUN_ID}"
MISSING_SOURCE_RUN_DIR="${RUNS_ROOT}/${MISSING_SOURCE_RUN_ID}"
NON_SECRET_VIOLATION_RUN_DIR="${RUNS_ROOT}/${NON_SECRET_VIOLATION_RUN_ID}"

VALID_PREP_RUN_DIR="${PREP_RUNS_ROOT}/${VALID_PREP_RUN_ID}"
VALID_RETENTION_RUN_DIR="${RETENTION_RUNS_ROOT}/${VALID_RETENTION_RUN_ID}"
VALID_INTAKE_RUN_DIR="${INTAKE_RUNS_ROOT}/${VALID_INTAKE_RUN_ID}"
VALID_WRAPPER_RUN_DIR="${WRAPPER_RUNS_ROOT}/${VALID_WRAPPER_RUN_ID}"

TMP_ROOT="$(mktemp -d)"
VALID_SELECTOR="${TMP_ROOT}/live-target-selector.json"
VALID_APPROVAL="${TMP_ROOT}/operator-approval.json"
VALID_ROLLBACK="${TMP_ROOT}/rollback-handoff.json"
DECLARATION_FILE="${TMP_ROOT}/source-declaration.json"
CANDIDATE_DIR="${TMP_ROOT}/candidate-evidence"
MATERIAL_FILE="${TMP_ROOT}/reviewed-material-root/material.txt"
MISSING_SOURCE_DECLARATION="${TMP_ROOT}/source-declaration-missing-source.json"
NON_SECRET_VIOLATION_DECLARATION="${TMP_ROOT}/source-declaration-non-secret-violation.json"
REPO_LOCAL_DECLARATION="${SCRIPT_DIR}/repo-local-source-declaration.tmp.json"
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
  rm -f -- "${REPO_LOCAL_DECLARATION}"
  rm -rf -- "${BAD_ROOT_DIR}"
  safe_rm_generated_dir "${VALID_RUN_DIR}" "${RUNS_ROOT}" "${VALID_RUN_ID}"
  safe_rm_generated_dir "${BAD_WRAPPER_ROOT_RUN_DIR}" "${RUNS_ROOT}" "${BAD_WRAPPER_ROOT_RUN_ID}"
  safe_rm_generated_dir "${REPO_LOCAL_DECL_RUN_DIR}" "${RUNS_ROOT}" "${REPO_LOCAL_DECL_RUN_ID}"
  safe_rm_generated_dir "${MISSING_SOURCE_RUN_DIR}" "${RUNS_ROOT}" "${MISSING_SOURCE_RUN_ID}"
  safe_rm_generated_dir "${NON_SECRET_VIOLATION_RUN_DIR}" "${RUNS_ROOT}" "${NON_SECRET_VIOLATION_RUN_ID}"
  cleanup_prep_pair "${VALID_PREP_RUN_ID}" "${VALID_PREP_RUN_DIR}"
  safe_rm_generated_dir "${VALID_RETENTION_RUN_DIR}" "${RETENTION_RUNS_ROOT}" "${VALID_RETENTION_RUN_ID}"
  safe_rm_generated_dir "${VALID_INTAKE_RUN_DIR}" "${INTAKE_RUNS_ROOT}" "${VALID_INTAKE_RUN_ID}"
  safe_rm_generated_dir "${VALID_WRAPPER_RUN_DIR}" "${WRAPPER_RUNS_ROOT}" "${VALID_WRAPPER_RUN_ID}"
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
    "execution_label": "material-resolution-execution-a",
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
            "event": "candidate-material-resolution-evidence",
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

run_material_expect_fail() {
  local label="$1"
  local run_id="$2"
  local run_dir="$3"
  local expected_field="$4"
  shift 4
  safe_rm_generated_dir "${run_dir}" "${RUNS_ROOT}" "${run_id}"

  set +e
  bash operations/harness-openclaw-live-material-resolution/bin/run_live_material_resolution.sh "$@" --run-id "${run_id}" >/dev/null 2>&1
  local status=$?
  set -e
  [[ "${status}" -ne 0 ]] || fail "negative live material resolution case unexpectedly passed: ${label}"
  assert_file "${run_dir}/material_resolution_report.json"
  assert_report_field "${run_dir}/material_resolution_report.json" "${expected_field}" "fail"
  echo "PASS live material resolution negative case rejected: ${label}"
}

cd "${REPO_ROOT}"
mkdir -p "${RUNS_ROOT}" "${PREP_RUNS_ROOT}" "${RETENTION_RUNS_ROOT}" "${INTAKE_RUNS_ROOT}" "${WRAPPER_RUNS_ROOT}" "${PRECHECK_RUNS_ROOT}"
cleanup
trap cleanup EXIT

mkdir -p "$(dirname "${MATERIAL_FILE}")"
printf 'outside-git reviewed material body that must never be inlined in generated repo-local bundles\n' > "${MATERIAL_FILE}"
write_records "${VALID_SELECTOR}" "${VALID_APPROVAL}" "${VALID_ROLLBACK}" "reviewed-live-instance-a" "reviewed-live-selector-a" "execution-attempt-a"
write_declaration "${DECLARATION_FILE}" "${MATERIAL_FILE}"
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

bash operations/harness-openclaw-live-material-resolution/bin/run_live_material_resolution.sh \
  --wrapper-preflight-run-dir "operations/harness-openclaw-live-wrapper/runs/${VALID_WRAPPER_RUN_ID}" \
  --source-declaration-file "${DECLARATION_FILE}" \
  --run-id "${VALID_RUN_ID}"

assert_file "${VALID_RUN_DIR}/material_resolution_meta.json"
assert_file "${VALID_RUN_DIR}/material_resolution_report.json"
assert_file "${VALID_RUN_DIR}/resolved_material_refs.json"
assert_file "${VALID_RUN_DIR}/wrapper_material_bundle.json"
assert_file "${VALID_RUN_DIR}/input_refs.json"
assert_file "${VALID_RUN_DIR}/checks/wrapper_preflight_validation.json"
assert_file "${VALID_RUN_DIR}/checks/source_declaration_validation.json"
assert_file "${VALID_RUN_DIR}/checks/material_path_validation.json"
assert_file "${VALID_RUN_DIR}/checks/non_secret_bundle_validation.json"
assert_file "${VALID_RUN_DIR}/exit_code"
assert_file_text_equals "${VALID_RUN_DIR}/exit_code" "0"

"${PYTHON_BIN}" - "${VALID_RUN_DIR}" "${MATERIAL_FILE}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
material_file = Path(sys.argv[2])

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

meta = load(run_dir / "material_resolution_meta.json")
report = load(run_dir / "material_resolution_report.json")
resolved = load(run_dir / "resolved_material_refs.json")
bundle = load(run_dir / "wrapper_material_bundle.json")
refs = load(run_dir / "input_refs.json")
wrapper_check = load(run_dir / "checks" / "wrapper_preflight_validation.json")
source_check = load(run_dir / "checks" / "source_declaration_validation.json")
path_check = load(run_dir / "checks" / "material_path_validation.json")
non_secret_check = load(run_dir / "checks" / "non_secret_bundle_validation.json")

assert meta["surface_kind"] == "live-material-resolution", meta
assert meta["material_resolution_only"] is True, meta
assert meta["live_runtime_apply"] is False, meta
assert meta["live_wrapper"] is False, meta
assert meta["crab_approved"] is False, meta
assert meta["approval_granting"] is False, meta
assert meta["rollback_execution"] is False, meta
assert meta["real_secret_loading"] is False, meta

assert report["overall_status"] == "pass", report
assert report["wrapper_preflight_validation"] == "pass", report
assert report["source_declaration_validation"] == "pass", report
assert report["material_path_validation"] == "pass", report
assert report["non_secret_bundle_validation"] == "pass", report
assert report["material_resolution_only"] is True, report
assert report["live_runtime_apply"] is False, report
assert report["live_wrapper"] is False, report
assert report["crab_approved"] is False, report

assert wrapper_check["status"] == "pass", wrapper_check
assert source_check["status"] == "pass", source_check
assert path_check["status"] == "pass", path_check
assert non_secret_check["status"] == "pass", non_secret_check
assert non_secret_check["violations"] == [], non_secret_check

assert resolved["bundle_kind"] == "live-material-refs", resolved
assert resolved["material_resolution_only"] is True, resolved
assert resolved["live_runtime_apply"] is False, resolved
assert resolved["live_wrapper"] is False, resolved
assert resolved["crab_approved"] is False, resolved
assert len(resolved["resolved_sources"]) >= 1, resolved
assert resolved["resolved_sources"][0]["source_label"] == "reviewed-provider-config", resolved
assert resolved["resolved_sources"][0]["resolved_path_kind"] == "file", resolved
assert resolved["resolved_sources"][0]["contains_raw_secrets"] is True, resolved

assert bundle["bundle_kind"] == "live-wrapper-material-bundle", bundle
assert bundle["material_resolution_only"] is True, bundle
assert bundle["live_runtime_apply"] is False, bundle
assert bundle["live_wrapper"] is False, bundle
assert bundle["crab_approved"] is False, bundle
assert bundle["approval_granting"] is False, bundle
assert bundle["rollback_execution"] is False, bundle
assert bundle["real_secret_loading"] is False, bundle
assert bundle["target_identity"]["target_instance_label"] == "reviewed-live-instance-a", bundle
assert bundle["target_identity"]["execution_label"] == "execution-attempt-a", bundle
assert bundle["wrapper_preflight"]["execution_plan_stub"].endswith("/execution_plan_stub.json"), bundle
assert bundle["material_refs"]["resolved_material_refs"].endswith("/resolved_material_refs.json"), bundle
assert bundle["material_refs"]["resolved_source_count"] >= 1, bundle

assert refs["wrapper_preflight_run_dir"].endswith("/live-material-resolution-valid-wrapper"), refs
assert refs["execution_plan_stub"].endswith("/execution_plan_stub.json"), refs
assert refs["wrapper_input_refs"].endswith("/wrapper_input_refs.json"), refs
assert refs["resolved_material_refs"].endswith("/resolved_material_refs.json"), refs
assert refs["contains_file_contents"] is False, refs
assert refs["contains_source_declaration_body"] is False, refs
assert refs["real_secret_loading"] is False, refs

raw_material = material_file.read_text(encoding="utf-8-sig").strip()
generated_text = "\n".join(
    path.read_text(encoding="utf-8-sig")
    for path in [
        run_dir / "resolved_material_refs.json",
        run_dir / "wrapper_material_bundle.json",
        run_dir / "input_refs.json",
    ]
)
assert raw_material not in generated_text, generated_text
assert "clear-token-value" not in generated_text, generated_text
assert "clear-bearer-value" not in generated_text, generated_text
assert "clear-credential-value" not in generated_text, generated_text
PY

mkdir -p "${BAD_ROOT_DIR}"
run_material_expect_fail \
  "invalid wrapper preflight run dir root" \
  "${BAD_WRAPPER_ROOT_RUN_ID}" \
  "${BAD_WRAPPER_ROOT_RUN_DIR}" \
  "wrapper_preflight_validation" \
  --wrapper-preflight-run-dir "operations/harness-openclaw-live-material-resolution/tests/repo-local-invalid-root.tmp" \
  --source-declaration-file "${DECLARATION_FILE}"

cp "${DECLARATION_FILE}" "${REPO_LOCAL_DECLARATION}"
run_material_expect_fail \
  "repo-local source declaration file" \
  "${REPO_LOCAL_DECL_RUN_ID}" \
  "${REPO_LOCAL_DECL_RUN_DIR}" \
  "source_declaration_validation" \
  --wrapper-preflight-run-dir "operations/harness-openclaw-live-wrapper/runs/${VALID_WRAPPER_RUN_ID}" \
  --source-declaration-file "${REPO_LOCAL_DECLARATION}"

write_declaration "${MISSING_SOURCE_DECLARATION}" "${TMP_ROOT}/missing-material-source.txt"
run_material_expect_fail \
  "missing declared material source" \
  "${MISSING_SOURCE_RUN_ID}" \
  "${MISSING_SOURCE_RUN_DIR}" \
  "material_path_validation" \
  --wrapper-preflight-run-dir "operations/harness-openclaw-live-wrapper/runs/${VALID_WRAPPER_RUN_ID}" \
  --source-declaration-file "${MISSING_SOURCE_DECLARATION}"

write_declaration "${NON_SECRET_VIOLATION_DECLARATION}" "${MATERIAL_FILE}" "token=unsafe-material-value"
run_material_expect_fail \
  "non-secret bundle violation" \
  "${NON_SECRET_VIOLATION_RUN_ID}" \
  "${NON_SECRET_VIOLATION_RUN_DIR}" \
  "non_secret_bundle_validation" \
  --wrapper-preflight-run-dir "operations/harness-openclaw-live-wrapper/runs/${VALID_WRAPPER_RUN_ID}" \
  --source-declaration-file "${NON_SECRET_VIOLATION_DECLARATION}"

before_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
set +e
bash operations/harness-openclaw-live-material-resolution/bin/run_live_material_resolution.sh \
  --wrapper-preflight-run-dir "operations/harness-openclaw-live-wrapper/runs/${VALID_WRAPPER_RUN_ID}" \
  --source-declaration-file "${DECLARATION_FILE}" \
  --run-id "${INVALID_RUN_ID}" >/dev/null 2>&1
invalid_status=$?
set -e
[[ "${invalid_status}" -ne 0 ]] || fail "invalid run id unexpectedly passed"
after_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
[[ "${before_runs}" == "${after_runs}" ]] || fail "invalid run id created a live material resolution run dir"

echo "PASS live material resolution valid run"
echo "PASS live material resolution rejects invalid inputs"
