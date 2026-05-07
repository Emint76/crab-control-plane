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

PYTHON_BIN="${FIRST_REAL_ROLLOUT_TEST_PYTHON_BIN:-${FIRST_REAL_ROLLOUT_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set FIRST_REAL_ROLLOUT_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi
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
  safe_rm_generated_dir "${RUNS_ROOT}/${prefix}-preflight" "${RUNS_ROOT}" "${prefix}-preflight"
  safe_rm_generated_dir "${MATERIAL_RUNS_ROOT}/${prefix}-material" "${MATERIAL_RUNS_ROOT}" "${prefix}-material"
  safe_rm_generated_dir "${SESSION_RUNS_ROOT}/${prefix}-session" "${SESSION_RUNS_ROOT}" "${prefix}-session"
  safe_rm_generated_dir "${RUNS_ROOT}/${prefix}-owner" "${RUNS_ROOT}" "${prefix}-owner"
  safe_rm_generated_dir "${RUNS_ROOT}/${prefix}-apply" "${RUNS_ROOT}" "${prefix}-apply"
}

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && "${TMP_ROOT}" == /tmp/* && -d "${TMP_ROOT}" ]]; then
    rm -rf -- "${TMP_ROOT}"
  fi
  for prefix in rollout-valid; do
    cleanup_prefix "${prefix}"
  done
  for run_id in rollout-valid rollout-bad-apply-root rollout-target-mismatch rollout-shell-wrapper rollout-healthcheck-fails; do
    safe_rm_generated_dir "${RUNS_ROOT}/${run_id}" "${RUNS_ROOT}" "${run_id}"
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
    json.dumps({"event": "candidate-first-real-rollout-evidence", "plain": "kept"}, indent=2) + "\n",
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
(workdir / "mock_healthcheck_fail.py").write_text(
    "raise SystemExit(1)\n",
    encoding="utf-8",
)
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
target = handoff["target_instance_label"]
execution = handoff["execution_label"]
launch = [python_bin, str(workdir / "mock_runtime.py")]
healthcheck = [python_bin, str(workdir / "mock_healthcheck.py")]
if mode == "target-mismatch":
    target = "mismatched-reviewed-instance"
elif mode == "shell-wrapper":
    launch = ["bash", "-c", "true"]
elif mode == "healthcheck-fails":
    healthcheck = [python_bin, str(workdir / "mock_healthcheck_fail.py")]

payload = {
    "declaration_kind": "first-real-rollout",
    "target_instance_label": target,
    "execution_label": execution,
    "working_directory": str(workdir),
    "launch_argv": launch,
    "healthcheck_argv": healthcheck,
    "environment_mode": "inherit",
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

run_rollout_expect_fail() {
  local label="$1"
  local run_id="$2"
  local apply_run_dir="$3"
  local declaration_file="$4"
  local expected_field="$5"
  set +e
  bash operations/harness-openclaw-live-wrapper/bin/run_first_real_rollout.sh \
    --apply-run-dir "${apply_run_dir}" \
    --rollout-declaration-file "${declaration_file}" \
    --run-id "${run_id}" >/dev/null 2>&1
  local status=$?
  set -e
  [[ "${status}" -ne 0 ]] || fail "negative first real rollout case unexpectedly passed: ${label}"
  assert_file "${RUNS_ROOT}/${run_id}/rollout_report.json"
  assert_report_field "${RUNS_ROOT}/${run_id}/rollout_report.json" "${expected_field}" "fail"
  echo "PASS first real rollout negative case rejected: ${label}"
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

run_pipeline "rollout-valid"
VALID_APPLY_DIR="${RUNS_ROOT}/rollout-valid-apply"
ROLLOUT_WORKDIR="${TMP_ROOT}/reviewed-rollout-workdir"
VALID_DECLARATION="${TMP_ROOT}/reviewed-rollout-declaration.json"
write_mock_runtime_files "${ROLLOUT_WORKDIR}"
write_rollout_declaration "${VALID_DECLARATION}" "${VALID_APPLY_DIR}" "${ROLLOUT_WORKDIR}" "valid"

bash operations/harness-openclaw-live-wrapper/bin/run_first_real_rollout.sh \
  --apply-run-dir "operations/harness-openclaw-live-wrapper/runs/rollout-valid-apply" \
  --rollout-declaration-file "${VALID_DECLARATION}" \
  --run-id "rollout-valid"

VALID_ROLLOUT_DIR="${RUNS_ROOT}/rollout-valid"
assert_file "${VALID_ROLLOUT_DIR}/rollout_meta.json"
assert_file "${VALID_ROLLOUT_DIR}/rollout_report.json"
assert_file "${VALID_ROLLOUT_DIR}/rollout_declaration_snapshot.json"
assert_file "${VALID_ROLLOUT_DIR}/rollout_launch_record.json"
assert_file "${VALID_ROLLOUT_DIR}/rollout_healthcheck_record.json"
assert_file "${VALID_ROLLOUT_DIR}/rollout_input_refs.json"
assert_file "${VALID_ROLLOUT_DIR}/checks/apply_run_validation.json"
assert_file "${VALID_ROLLOUT_DIR}/checks/rollout_declaration_validation.json"
assert_file "${VALID_ROLLOUT_DIR}/checks/identity_binding_validation.json"
assert_file "${VALID_ROLLOUT_DIR}/checks/launch_validation.json"
assert_file "${VALID_ROLLOUT_DIR}/checks/healthcheck_validation.json"
assert_file "${VALID_ROLLOUT_DIR}/checks/non_secret_evidence_validation.json"
assert_file_text_equals "${VALID_ROLLOUT_DIR}/exit_code" "0"

"${PYTHON_BIN}" - "${VALID_ROLLOUT_DIR}" "${VALID_APPLY_DIR}" "${VALID_DECLARATION}" "${ROLLOUT_WORKDIR}" <<'PY'
import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
apply_dir = Path(sys.argv[2])
declaration = Path(sys.argv[3])
workdir = Path(sys.argv[4])

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

meta = load(run_dir / "rollout_meta.json")
report = load(run_dir / "rollout_report.json")
snapshot = load(run_dir / "rollout_declaration_snapshot.json")
launch = load(run_dir / "rollout_launch_record.json")
healthcheck = load(run_dir / "rollout_healthcheck_record.json")
input_refs = load(run_dir / "rollout_input_refs.json")
non_secret = load(run_dir / "checks" / "non_secret_evidence_validation.json")

assert meta["surface_kind"] == "first-real-rollout", meta
assert meta["execution_owner"] is True, meta
assert meta["live_wrapper"] is True, meta
assert meta["live_runtime_apply"] is True, meta
assert meta["first_real_rollout"] is True, meta
assert meta["crab_approved"] is False, meta
assert meta["rollout_orchestration"] is False, meta

assert report["overall_status"] == "pass", report
assert report["apply_run_validation"] == "pass", report
assert report["rollout_declaration_validation"] == "pass", report
assert report["identity_binding_validation"] == "pass", report
assert report["launch_validation"] == "pass", report
assert report["healthcheck_validation"] == "pass", report
assert report["non_secret_evidence_validation"] == "pass", report
assert report["first_real_rollout"] is True, report
assert report["crab_approved"] is False, report

assert snapshot == load(declaration), snapshot
assert launch["record_kind"] == "rollout-launch-record", launch
assert launch["launch_status"] in {"started", "exited"}, launch
assert isinstance(launch["pid"], int), launch
assert healthcheck["record_kind"] == "rollout-healthcheck-record", healthcheck
assert healthcheck["healthcheck_status"] == "pass", healthcheck
assert healthcheck["exit_code"] == 0, healthcheck
assert input_refs["apply_run_dir"].endswith("/rollout-valid-apply"), input_refs
assert input_refs["rollout_declaration_file"] == str(declaration), input_refs
assert input_refs["rollout_declaration_snapshot"].endswith("/rollout_declaration_snapshot.json"), input_refs
assert input_refs["rollout_launch_record"].endswith("/rollout_launch_record.json"), input_refs
assert input_refs["rollout_healthcheck_record"].endswith("/rollout_healthcheck_record.json"), input_refs
assert input_refs["contains_source_file_contents"] is False, input_refs
assert input_refs["contains_material_file_contents"] is False, input_refs
assert non_secret["status"] == "pass", non_secret

combined = "\n".join(
    json.dumps(payload, sort_keys=True)
    for payload in [meta, report, snapshot, launch, healthcheck, input_refs, non_secret]
)
for path in [
    workdir / "runtime-ready.txt",
    apply_dir / "wrapper_apply_report.json",
]:
    content = path.read_text(encoding="utf-8").strip()
    assert content not in combined, path
PY

run_rollout_expect_fail \
  "invalid apply run dir root" \
  "rollout-bad-apply-root" \
  "operations/harness-openclaw-live-secret-session/runs/rollout-valid-session" \
  "${VALID_DECLARATION}" \
  "apply_run_validation"

MISMATCH_DECLARATION="${TMP_ROOT}/reviewed-rollout-mismatch-declaration.json"
write_rollout_declaration "${MISMATCH_DECLARATION}" "${VALID_APPLY_DIR}" "${ROLLOUT_WORKDIR}" "target-mismatch"
run_rollout_expect_fail \
  "declaration target mismatch" \
  "rollout-target-mismatch" \
  "operations/harness-openclaw-live-wrapper/runs/rollout-valid-apply" \
  "${MISMATCH_DECLARATION}" \
  "identity_binding_validation"

SHELL_DECLARATION="${TMP_ROOT}/reviewed-rollout-shell-declaration.json"
write_rollout_declaration "${SHELL_DECLARATION}" "${VALID_APPLY_DIR}" "${ROLLOUT_WORKDIR}" "shell-wrapper"
run_rollout_expect_fail \
  "forbidden shell-wrapper launch form" \
  "rollout-shell-wrapper" \
  "operations/harness-openclaw-live-wrapper/runs/rollout-valid-apply" \
  "${SHELL_DECLARATION}" \
  "rollout_declaration_validation"

FAIL_HEALTHCHECK_DECLARATION="${TMP_ROOT}/reviewed-rollout-failing-healthcheck-declaration.json"
write_rollout_declaration "${FAIL_HEALTHCHECK_DECLARATION}" "${VALID_APPLY_DIR}" "${ROLLOUT_WORKDIR}" "healthcheck-fails"
run_rollout_expect_fail \
  "healthcheck fails" \
  "rollout-healthcheck-fails" \
  "operations/harness-openclaw-live-wrapper/runs/rollout-valid-apply" \
  "${FAIL_HEALTHCHECK_DECLARATION}" \
  "healthcheck_validation"

set +e
bash operations/harness-openclaw-live-wrapper/bin/run_first_real_rollout.sh \
  --apply-run-dir "operations/harness-openclaw-live-wrapper/runs/rollout-valid-apply" \
  --rollout-declaration-file "${VALID_DECLARATION}" \
  --run-id "${BAD_RUN_ID}" >/dev/null 2>&1
status=$?
set -e
[[ "${status}" -ne 0 ]] || fail "invalid run id unexpectedly passed"
[[ ! -e "${WRAPPER_ROOT}/bad" ]] || fail "invalid run id created parent output directory"
echo "PASS first real rollout negative case rejected: invalid run id"

echo "PASS first real rollout surface tests"
