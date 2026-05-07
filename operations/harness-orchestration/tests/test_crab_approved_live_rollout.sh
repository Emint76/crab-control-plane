#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ORCH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${ORCH_ROOT}/../.." && pwd -P)"
ORCH_RUNS_ROOT="${ORCH_ROOT}/runs"
WRAPPER_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-wrapper"
WRAPPER_RUNS_ROOT="${WRAPPER_ROOT}/runs"
PREP_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-execution-prep/runs"
PRECHECK_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-precheck/runs"
RETENTION_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-retention/runs"
INTAKE_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-wrapper-intake/runs"
MATERIAL_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-material-resolution/runs"
SESSION_RUNS_ROOT="${REPO_ROOT}/operations/harness-openclaw-live-secret-session/runs"

PYTHON_BIN="${CRAB_APPROVED_LIVE_ROLLOUT_TEST_PYTHON_BIN:-${CRAB_APPROVED_LIVE_ROLLOUT_PYTHON_BIN:-${FIRST_REAL_ROLLOUT_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set CRAB_APPROVED_LIVE_ROLLOUT_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi
export CRAB_APPROVED_LIVE_ROLLOUT_PYTHON_BIN="${CRAB_APPROVED_LIVE_ROLLOUT_PYTHON_BIN:-${PYTHON_BIN}}"
export FIRST_REAL_ROLLOUT_PYTHON_BIN="${FIRST_REAL_ROLLOUT_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_RUNTIME_APPLY_PYTHON_BIN="${LIVE_RUNTIME_APPLY_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_WRAPPER_EXECUTION_OWNER_PYTHON_BIN="${LIVE_WRAPPER_EXECUTION_OWNER_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_SECRET_SESSION_PYTHON_BIN="${LIVE_SECRET_SESSION_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_MATERIAL_RESOLUTION_PYTHON_BIN="${LIVE_MATERIAL_RESOLUTION_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_WRAPPER_PREFLIGHT_PYTHON_BIN="${LIVE_WRAPPER_PREFLIGHT_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_WRAPPER_INTAKE_PYTHON_BIN="${LIVE_WRAPPER_INTAKE_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_EXECUTION_PREP_PYTHON_BIN="${LIVE_EXECUTION_PREP_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_PRECHECK_PYTHON_BIN="${LIVE_PRECHECK_PYTHON_BIN:-${PYTHON_BIN}}"
export LIVE_RETENTION_PYTHON_BIN="${LIVE_RETENTION_PYTHON_BIN:-${PYTHON_BIN}}"

TMP_ROOT="$(mktemp -d)"
BAD_RUN_ID="../bad"

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

cleanup_prefix() {
  local prefix="$1"
  safe_rm_generated_dir "${PREP_RUNS_ROOT}/${prefix}-prep" "${PREP_RUNS_ROOT}" "${prefix}-prep"
  safe_rm_generated_dir "${PRECHECK_RUNS_ROOT}/${prefix}-prep-precheck" "${PRECHECK_RUNS_ROOT}" "${prefix}-prep-precheck"
  safe_rm_generated_dir "${RETENTION_RUNS_ROOT}/${prefix}-retention" "${RETENTION_RUNS_ROOT}" "${prefix}-retention"
  safe_rm_generated_dir "${INTAKE_RUNS_ROOT}/${prefix}-intake" "${INTAKE_RUNS_ROOT}" "${prefix}-intake"
  safe_rm_generated_dir "${WRAPPER_RUNS_ROOT}/${prefix}-preflight" "${WRAPPER_RUNS_ROOT}" "${prefix}-preflight"
  safe_rm_generated_dir "${MATERIAL_RUNS_ROOT}/${prefix}-material" "${MATERIAL_RUNS_ROOT}" "${prefix}-material"
  safe_rm_generated_dir "${SESSION_RUNS_ROOT}/${prefix}-session" "${SESSION_RUNS_ROOT}" "${prefix}-session"
  safe_rm_generated_dir "${WRAPPER_RUNS_ROOT}/${prefix}-owner" "${WRAPPER_RUNS_ROOT}" "${prefix}-owner"
  safe_rm_generated_dir "${WRAPPER_RUNS_ROOT}/${prefix}-apply" "${WRAPPER_RUNS_ROOT}" "${prefix}-apply"
}

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && "${TMP_ROOT}" == /tmp/* && -d "${TMP_ROOT}" ]]; then
    rm -rf -- "${TMP_ROOT}"
  fi
  cleanup_prefix "crab-rollout-valid"
  for run_id in \
    crab-rollout-valid \
    crab-rollout-bad-apply-root \
    crab-rollout-shell-wrapper \
    crab-rollout-failed-delegate \
    crab-rollout-extra-arg; do
    safe_rm_generated_dir "${ORCH_RUNS_ROOT}/${run_id}" "${ORCH_RUNS_ROOT}" "${run_id}"
  done
  for run_id in \
    crab-rollout-valid-delegate \
    crab-rollout-failed-delegate-delegate; do
    safe_rm_generated_dir "${WRAPPER_RUNS_ROOT}/${run_id}" "${WRAPPER_RUNS_ROOT}" "${run_id}"
  done
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
  local prefix="$1"
  local root_base="$2"
  "${PYTHON_BIN}" - "${TMP_ROOT}/${prefix}-selector.json" "${TMP_ROOT}/${prefix}-approval.json" "${TMP_ROOT}/${prefix}-rollback.json" "${root_base}" <<'PY'
import json
import sys
from pathlib import Path

selector_path = Path(sys.argv[1])
approval_path = Path(sys.argv[2])
rollback_path = Path(sys.argv[3])
root_base = Path(sys.argv[4])

selector = {
    "selector_kind": "live-target-selector",
    "selector_label": f"{selector_path.stem}-selector",
    "target_class": "live",
    "target_instance_label": f"{selector_path.stem}-instance",
    "workspace_root": str(root_base / "reviewed-live-workspace-root"),
    "state_root": str(root_base / "reviewed-live-state-root"),
    "runtime_root": str(root_base / "reviewed-live-runtime-root"),
    "is_disposable": False,
}
approval = {
    "approval_kind": "operator-approval",
    "approval_label": f"{selector_path.stem}-approval",
    "approved_operation_class": "live-runtime-apply",
    "target_instance_label": selector["target_instance_label"],
    "selector_label": selector["selector_label"],
    "execution_label": f"{selector_path.stem}-execution",
    "non_reusable": True,
    "approved_by": "reviewed-human-operator",
}
rollback = {
    "rollback_kind": "rollback-handoff",
    "rollback_label": f"{selector_path.stem}-rollback",
    "target_instance_label": selector["target_instance_label"],
    "execution_label": approval["execution_label"],
    "rollback_ready": True,
    "rollback_boundary": "reviewed rollback handoff metadata for this attempt",
    "decision_points": ["operator decides rollback after post-apply validation failure"],
}
for path, payload in ((selector_path, selector), (approval_path, approval), (rollback_path, rollback)):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

write_declaration() {
  local prefix="$1"
  "${PYTHON_BIN}" - "${TMP_ROOT}/${prefix}-source-declaration.json" "${TMP_ROOT}/${prefix}-sources" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
sources_root = Path(sys.argv[2])
sources_root.mkdir(parents=True, exist_ok=True)

workspace = sources_root / "workspace-material.txt"
state = sources_root / "state-material.json"
runtime = sources_root / "runtime-provider"
runtime.mkdir(parents=True, exist_ok=True)
(runtime / "provider.conf").write_text("runtime live material body\n", encoding="utf-8")
workspace.write_text("workspace live material body\n", encoding="utf-8")
state.write_text('{"state":"live material body"}\n', encoding="utf-8")

payload = {
    "declaration_kind": "secret-material-source-declaration",
    "declaration_label": f"{path.stem}-declaration",
    "execution_label": f"{path.stem}-execution",
    "local_only": True,
    "outside_git": True,
    "sources": [
        {
            "source_label": "bot.env",
            "source_class": "workspace",
            "source_path": str(workspace),
            "contains_raw_secrets": True,
        },
        {
            "source_label": "session.json",
            "source_class": "state",
            "source_path": str(state),
            "contains_raw_secrets": True,
        },
        {
            "source_label": "provider",
            "source_class": "runtime",
            "source_path": str(runtime),
            "contains_raw_secrets": True,
        },
    ],
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

write_candidate_evidence() {
  local prefix="$1"
  "${PYTHON_BIN}" - "${TMP_ROOT}/${prefix}-candidate-evidence" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.mkdir(parents=True, exist_ok=True)
(path / "event.json").write_text(
    json.dumps({"event": "candidate-crab-approved-rollout-evidence", "plain": "kept"}, indent=2) + "\n",
    encoding="utf-8",
)
PY
}

run_pipeline() {
  local prefix="$1"
  local root_base="${TMP_ROOT}/${prefix}-target"

  write_records "${prefix}" "${root_base}"
  write_declaration "${prefix}"
  write_candidate_evidence "${prefix}"

  bash operations/harness-openclaw-live-retention/bin/run_secret_retention_surface.sh \
    --source-declaration-file "${TMP_ROOT}/${prefix}-source-declaration.json" \
    --candidate-evidence-dir "${TMP_ROOT}/${prefix}-candidate-evidence" \
    --run-id "${prefix}-retention"

  bash operations/harness-openclaw-live-execution-prep/bin/run_live_execution_prep.sh \
    --selector-file "${TMP_ROOT}/${prefix}-selector.json" \
    --approval-file "${TMP_ROOT}/${prefix}-approval.json" \
    --rollback-file "${TMP_ROOT}/${prefix}-rollback.json" \
    --run-id "${prefix}-prep"

  bash operations/harness-openclaw-live-wrapper-intake/bin/run_live_wrapper_intake.sh \
    --execution-prep-run-dir "operations/harness-openclaw-live-execution-prep/runs/${prefix}-prep" \
    --retention-run-dir "operations/harness-openclaw-live-retention/runs/${prefix}-retention" \
    --run-id "${prefix}-intake"

  bash operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_preflight.sh \
    --wrapper-intake-run-dir "operations/harness-openclaw-live-wrapper-intake/runs/${prefix}-intake" \
    --run-id "${prefix}-preflight"

  bash operations/harness-openclaw-live-material-resolution/bin/run_live_material_resolution.sh \
    --wrapper-preflight-run-dir "operations/harness-openclaw-live-wrapper/runs/${prefix}-preflight" \
    --source-declaration-file "${TMP_ROOT}/${prefix}-source-declaration.json" \
    --run-id "${prefix}-material"

  bash operations/harness-openclaw-live-secret-session/bin/run_live_secret_session.sh \
    --material-resolution-run-dir "operations/harness-openclaw-live-material-resolution/runs/${prefix}-material" \
    --run-id "${prefix}-session"

  bash operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_execution_owner.sh \
    --secret-session-run-dir "operations/harness-openclaw-live-secret-session/runs/${prefix}-session" \
    --run-id "${prefix}-owner"

  bash operations/harness-openclaw-live-wrapper/bin/run_live_runtime_apply.sh \
    --execution-owner-run-dir "operations/harness-openclaw-live-wrapper/runs/${prefix}-owner" \
    --run-id "${prefix}-apply"
}

write_mock_runtime_files() {
  local workdir="$1"
  "${PYTHON_BIN}" - "${workdir}" <<'PY'
import sys
from pathlib import Path

workdir = Path(sys.argv[1])
workdir.mkdir(parents=True, exist_ok=True)
(workdir / "mock_runtime.py").write_text(
    "from pathlib import Path\nPath('runtime-ready.txt').write_text('ready\\n', encoding='utf-8')\n",
    encoding="utf-8",
)
(workdir / "mock_healthcheck.py").write_text(
    "from pathlib import Path\nraise SystemExit(0 if Path('runtime-ready.txt').is_file() else 1)\n",
    encoding="utf-8",
)
(workdir / "mock_healthcheck_fail.py").write_text("raise SystemExit(1)\n", encoding="utf-8")
PY
}

write_rollout_declaration() {
  local path="$1"
  local apply_dir="$2"
  local workdir="$3"
  local mode="$4"
  "${PYTHON_BIN}" - "${path}" "${apply_dir}" "${workdir}" "${PYTHON_BIN}" "${mode}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
apply_dir = Path(sys.argv[2])
workdir = Path(sys.argv[3])
python_bin = sys.argv[4]
mode = sys.argv[5]
handoff = json.loads((apply_dir / "rollback_handoff.json").read_text(encoding="utf-8-sig"))
launch = [python_bin, str(workdir / "mock_runtime.py")]
healthcheck = [python_bin, str(workdir / "mock_healthcheck.py")]
if mode == "shell-wrapper":
    launch = ["bash", "-c", "true"]
elif mode == "healthcheck-fails":
    healthcheck = [python_bin, str(workdir / "mock_healthcheck_fail.py")]

payload = {
    "declaration_kind": "first-real-rollout",
    "target_instance_label": handoff["target_instance_label"],
    "execution_label": handoff["execution_label"],
    "working_directory": str(workdir),
    "launch_argv": launch,
    "healthcheck_argv": healthcheck,
    "environment_mode": "inherit",
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

run_crab_rollout_expect_fail() {
  local label="$1"
  local run_id="$2"
  local apply_run_dir="$3"
  local declaration_file="$4"
  local expected_field="$5"
  set +e
  bash operations/harness-orchestration/bin/run_crab_approved_live_rollout.sh \
    --apply-run-dir "${apply_run_dir}" \
    --rollout-declaration-file "${declaration_file}" \
    --run-id "${run_id}" >/dev/null 2>&1
  local status=$?
  set -e
  [[ "${status}" -ne 0 ]] || fail "negative Crab-approved rollout case unexpectedly passed: ${label}"
  assert_file "${ORCH_RUNS_ROOT}/${run_id}/crab_live_rollout_report.json"
  assert_report_field "${ORCH_RUNS_ROOT}/${run_id}/crab_live_rollout_report.json" "${expected_field}" "fail"
  echo "PASS Crab-approved rollout negative case rejected: ${label}"
}

cd "${REPO_ROOT}"
mkdir -p \
  "${ORCH_RUNS_ROOT}" \
  "${WRAPPER_RUNS_ROOT}" \
  "${PREP_RUNS_ROOT}" \
  "${PRECHECK_RUNS_ROOT}" \
  "${RETENTION_RUNS_ROOT}" \
  "${INTAKE_RUNS_ROOT}" \
  "${MATERIAL_RUNS_ROOT}" \
  "${SESSION_RUNS_ROOT}"
cleanup
trap cleanup EXIT

run_pipeline "crab-rollout-valid"
VALID_APPLY_DIR="${WRAPPER_RUNS_ROOT}/crab-rollout-valid-apply"
ROLLOUT_WORKDIR="${TMP_ROOT}/reviewed-crab-rollout-workdir"
VALID_DECLARATION="${TMP_ROOT}/reviewed-crab-rollout-declaration.json"
write_mock_runtime_files "${ROLLOUT_WORKDIR}"
write_rollout_declaration "${VALID_DECLARATION}" "${VALID_APPLY_DIR}" "${ROLLOUT_WORKDIR}" "valid"

bash operations/harness-orchestration/bin/run_crab_approved_live_rollout.sh \
  --apply-run-dir "operations/harness-openclaw-live-wrapper/runs/crab-rollout-valid-apply" \
  --rollout-declaration-file "${VALID_DECLARATION}" \
  --run-id "crab-rollout-valid"

VALID_CRAB_DIR="${ORCH_RUNS_ROOT}/crab-rollout-valid"
VALID_DELEGATE_DIR="${WRAPPER_RUNS_ROOT}/crab-rollout-valid-delegate"
assert_file "${VALID_CRAB_DIR}/crab_live_rollout_meta.json"
assert_file "${VALID_CRAB_DIR}/crab_live_rollout_report.json"
assert_file "${VALID_CRAB_DIR}/invocation_record.json"
assert_file "${VALID_CRAB_DIR}/delegate_rollout_ref.json"
assert_file "${VALID_CRAB_DIR}/checks/input_validation.json"
assert_file "${VALID_CRAB_DIR}/checks/allowed_surface_validation.json"
assert_file "${VALID_CRAB_DIR}/checks/delegate_run_validation.json"
assert_file "${VALID_CRAB_DIR}/checks/non_secret_evidence_validation.json"
assert_file_text_equals "${VALID_CRAB_DIR}/exit_code" "0"
assert_file "${VALID_DELEGATE_DIR}/rollout_report.json"

"${PYTHON_BIN}" - "${VALID_CRAB_DIR}" "${VALID_DELEGATE_DIR}" "${VALID_APPLY_DIR}" "${VALID_DECLARATION}" "${ROLLOUT_WORKDIR}" <<'PY'
import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
delegate_dir = Path(sys.argv[2])
apply_dir = Path(sys.argv[3])
declaration = Path(sys.argv[4])
workdir = Path(sys.argv[5])

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

meta = load(run_dir / "crab_live_rollout_meta.json")
report = load(run_dir / "crab_live_rollout_report.json")
invocation = load(run_dir / "invocation_record.json")
delegate_ref = load(run_dir / "delegate_rollout_ref.json")
input_validation = load(run_dir / "checks" / "input_validation.json")
allowed_surface = load(run_dir / "checks" / "allowed_surface_validation.json")
delegate_validation = load(run_dir / "checks" / "delegate_run_validation.json")
non_secret = load(run_dir / "checks" / "non_secret_evidence_validation.json")
delegate_report = load(delegate_dir / "rollout_report.json")
handoff = load(apply_dir / "rollback_handoff.json")

assert meta["surface_kind"] == "crab-approved-live-rollout", meta
assert meta["crab_approved"] is True, meta
assert meta["approved_surface"] == "first-real-rollout", meta
assert meta["live_runtime_apply"] is False, meta
assert meta["rollout_orchestration"] is False, meta
assert meta["deploy_framework"] is False, meta

assert report["overall_status"] == "pass", report
assert report["input_validation"] == "pass", report
assert report["allowed_surface_validation"] == "pass", report
assert report["delegate_run_validation"] == "pass", report
assert report["non_secret_evidence_validation"] == "pass", report
assert report["crab_approved"] is True, report
assert report["approved_surface"] == "first-real-rollout", report
assert report["rollout_orchestration"] is False, report

assert invocation["record_kind"] == "crab-approved-live-rollout-invocation", invocation
assert invocation["crab_approved"] is True, invocation
assert invocation["approved_surface"] == "first-real-rollout", invocation
assert invocation["target_instance_label"] == handoff["target_instance_label"], invocation
assert invocation["execution_label"] == handoff["execution_label"], invocation
assert invocation["apply_run_dir"].endswith("/crab-rollout-valid-apply"), invocation
assert invocation["rollout_declaration_file"] == str(declaration), invocation
assert invocation["delegate_run_dir"].endswith("/crab-rollout-valid-delegate"), invocation

assert delegate_ref["delegate_kind"] == "first-real-rollout", delegate_ref
assert delegate_ref["delegate_run_id"] == "crab-rollout-valid-delegate", delegate_ref
assert delegate_ref["delegate_status"] == "pass", delegate_ref
assert delegate_report["overall_status"] == "pass", delegate_report
assert delegate_report["crab_approved"] is False, delegate_report

assert input_validation["status"] == "pass", input_validation
assert allowed_surface["crab_approved_surface"] == "first-real-rollout-only", allowed_surface
for key in [
    "bounded_live_runtime_apply_direct",
    "execution_owner_direct",
    "secret_session_direct",
    "material_resolution_direct",
    "orchestration_framework",
    "retries",
    "supervisors",
    "schedulers",
]:
    assert allowed_surface[key] is False, allowed_surface
assert delegate_validation["status"] == "pass", delegate_validation
assert non_secret["status"] == "pass", non_secret

combined = "\n".join(
    json.dumps(payload, sort_keys=True)
    for payload in [meta, report, invocation, delegate_ref, input_validation, allowed_surface, delegate_validation, non_secret]
)
for path in [
    workdir / "runtime-ready.txt",
    apply_dir / "wrapper_apply_report.json",
]:
    content = path.read_text(encoding="utf-8").strip()
    assert content not in combined, path
PY

run_crab_rollout_expect_fail \
  "invalid apply run dir root" \
  "crab-rollout-bad-apply-root" \
  "operations/harness-openclaw-live-secret-session/runs/crab-rollout-valid-session" \
  "${VALID_DECLARATION}" \
  "input_validation"

SHELL_DECLARATION="${TMP_ROOT}/reviewed-crab-rollout-shell-declaration.json"
write_rollout_declaration "${SHELL_DECLARATION}" "${VALID_APPLY_DIR}" "${ROLLOUT_WORKDIR}" "shell-wrapper"
run_crab_rollout_expect_fail \
  "forbidden shell-wrapper launch form" \
  "crab-rollout-shell-wrapper" \
  "operations/harness-openclaw-live-wrapper/runs/crab-rollout-valid-apply" \
  "${SHELL_DECLARATION}" \
  "input_validation"

FAIL_HEALTHCHECK_DECLARATION="${TMP_ROOT}/reviewed-crab-rollout-failing-healthcheck-declaration.json"
write_rollout_declaration "${FAIL_HEALTHCHECK_DECLARATION}" "${VALID_APPLY_DIR}" "${ROLLOUT_WORKDIR}" "healthcheck-fails"
run_crab_rollout_expect_fail \
  "delegate rollout fails" \
  "crab-rollout-failed-delegate" \
  "operations/harness-openclaw-live-wrapper/runs/crab-rollout-valid-apply" \
  "${FAIL_HEALTHCHECK_DECLARATION}" \
  "delegate_run_validation"

set +e
bash operations/harness-orchestration/bin/run_crab_approved_live_rollout.sh \
  --apply-run-dir "operations/harness-openclaw-live-wrapper/runs/crab-rollout-valid-apply" \
  --rollout-declaration-file "${VALID_DECLARATION}" \
  --run-id "${BAD_RUN_ID}" >/dev/null 2>&1
status=$?
set -e
[[ "${status}" -ne 0 ]] || fail "invalid run id unexpectedly passed"
[[ ! -e "${ORCH_ROOT}/bad" ]] || fail "invalid run id created parent output directory"
echo "PASS Crab-approved rollout negative case rejected: invalid run id"

set +e
bash operations/harness-orchestration/bin/run_crab_approved_live_rollout.sh \
  --apply-run-dir "operations/harness-openclaw-live-wrapper/runs/crab-rollout-valid-apply" \
  --rollout-declaration-file "${VALID_DECLARATION}" \
  --run-id "crab-rollout-extra-arg" \
  --unexpected-extra-flag >/dev/null 2>&1
status=$?
set -e
[[ "${status}" -ne 0 ]] || fail "unexpected extra arg was accepted"
echo "PASS Crab-approved rollout negative case rejected: unexpected extra arg"

echo "PASS Crab-approved live rollout wrapper tests"
