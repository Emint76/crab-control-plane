#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE3_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE3_ROOT}/../.." && pwd)"

usage() {
  cat <<'EOF' >&2
usage: run_phase3_bundle.sh --phase2-run-dir <PATH> --execution-target-json <PATH> [--run-id <RUN_ID>]
EOF
}

RUN_ID="phase3-$(date -u +%Y%m%dT%H%M%SZ)"
PHASE2_RUN_DIR=""
EXECUTION_TARGET_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase2-run-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      PHASE2_RUN_DIR="$2"
      shift 2
      ;;
    --execution-target-json)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      EXECUTION_TARGET_JSON="$2"
      shift 2
      ;;
    --run-id)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      RUN_ID="$2"
      shift 2
      ;;
    *)
      echo "FAIL unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

[[ -n "${PHASE2_RUN_DIR}" ]] || { echo "FAIL missing --phase2-run-dir" >&2; usage; exit 2; }
[[ -n "${EXECUTION_TARGET_JSON}" ]] || { echo "FAIL missing --execution-target-json" >&2; usage; exit 2; }

PYTHON_BIN="${PHASE3_PYTHON_BIN:-python}"

validate_run_id() {
  local run_id="$1"
  if [[ -z "${run_id}" ]]; then
    echo "FAIL invalid --run-id: empty run id" >&2
    return 1
  fi
  if [[ "${run_id}" =~ ^[[:space:]] || "${run_id}" =~ [[:space:]]$ ]]; then
    echo "FAIL invalid --run-id: leading or trailing whitespace is not allowed" >&2
    return 1
  fi
  if [[ ! "${run_id}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "FAIL invalid --run-id: must match ^[A-Za-z0-9._-]+$" >&2
    return 1
  fi
  if [[ "${run_id}" == "." || "${run_id}" == ".." ]]; then
    echo "FAIL invalid --run-id: path traversal is not allowed" >&2
    return 1
  fi
}

RUNS_ROOT="${PHASE3_ROOT}/runs"
RUN_DIR="${RUNS_ROOT}/${RUN_ID}"
INPUT_DIR="${RUN_DIR}/input"
CHECKS_DIR="${RUN_DIR}/checks"
LOGS_DIR="${RUN_DIR}/logs"
STAGING_ROOT="${RUN_DIR}/staging"
STATE_FILE="${RUN_DIR}/.bundle_state.env"

validate_run_id "${RUN_ID}" || exit 2

if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "FAIL python runtime not found: ${PYTHON_BIN}" >&2
  exit 1
fi

verify_run_dir_invariants() {
  local write_report="${1:-false}"
  "${PYTHON_BIN}" - "${REPO_ROOT}" "${PHASE3_ROOT}" "${RUN_ID}" "${RUN_DIR}" "${write_report}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path


def repo_ref(repo_root: Path, path: Path) -> str:
    resolved = path.resolve(strict=False)
    try:
        return resolved.relative_to(repo_root.resolve(strict=False)).as_posix()
    except ValueError:
        return resolved.as_posix()


repo_root = Path(sys.argv[1]).resolve(strict=False)
phase3_root = Path(sys.argv[2]).resolve(strict=False)
run_id = sys.argv[3]
run_dir = Path(sys.argv[4])
write_report = sys.argv[5] == "true"

runs_root = (phase3_root / "runs").resolve(strict=False)
resolved_run_dir = run_dir.resolve(strict=False)
violations: list[str] = []

try:
    relative_run_dir = resolved_run_dir.relative_to(runs_root)
except ValueError:
    violations.append("run_dir_outside_phase3_runs_root")
    relative_run_dir = None

if resolved_run_dir.name != run_id:
    violations.append("run_dir_basename_mismatch")

if relative_run_dir is not None and len(relative_run_dir.parts) != 1:
    violations.append("run_dir_must_be_direct_child_of_phase3_runs_root")

expected_run_dir = (runs_root / run_id).resolve(strict=False)
if resolved_run_dir != expected_run_dir:
    violations.append("run_dir_identity_mismatch")

canonical_run_dir = repo_ref(repo_root, resolved_run_dir)
expected_canonical_run_dir = f"operations/harness-phase3/runs/{run_id}"
if canonical_run_dir != expected_canonical_run_dir:
    violations.append("canonical_run_dir_repo_ref_mismatch")

payload = {
    "status": "fail" if violations else "pass",
    "run_id": run_id,
    "canonical_run_dir": expected_canonical_run_dir,
    "run_dir_identity_verified": not violations,
    "write_surface_verified": not violations,
    "violations": violations,
}

if write_report:
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)
    with (checks_dir / "run_dir_invariants.json").open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")

if violations:
    print(f"FAIL Phase 3 run-dir invariant violation: {', '.join(violations)}", file=sys.stderr)
    raise SystemExit(1)
raise SystemExit(0)
PY
}

verify_run_dir_invariants "false" || exit 2

mkdir -p "${INPUT_DIR}" "${CHECKS_DIR}" "${LOGS_DIR}" "${STAGING_ROOT}"

FINAL_EXIT_STATUS="1"
cleanup() {
  printf '%s\n' "${FINAL_EXIT_STATUS}" > "${RUN_DIR}/exit_code"
}
trap cleanup EXIT

if ! verify_run_dir_invariants "true"; then
  FINAL_EXIT_STATUS="1"
  exit 1
fi

now_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

write_state() {
  local key="$1"
  local value="$2"
  local tmp_file="${STATE_FILE}.tmp"
  touch "${STATE_FILE}"
  grep -v "^${key}=" "${STATE_FILE}" > "${tmp_file}" || true
  printf '%s=%s\n' "${key}" "${value}" >> "${tmp_file}"
  mv "${tmp_file}" "${STATE_FILE}"
}

has_state_key() {
  local key="$1"
  [[ -f "${STATE_FILE}" ]] && grep -q "^${key}=" "${STATE_FILE}"
}

step_completed() {
  has_state_key "${1}_completed_at"
}

step_succeeded() {
  [[ -f "${STATE_FILE}" ]] && grep -q "^${1}_exit_status=0$" "${STATE_FILE}"
}

record_step() {
  local step_key="$1"
  local exit_status="$2"
  write_state "${step_key}_exit_status" "${exit_status}"
  write_state "${step_key}_completed_at" "$(now_utc)"
}

require_artifact_if_reached() {
  local step_key="$1"
  local artifact_path="$2"
  if step_completed "${step_key}" && [[ ! -e "${artifact_path}" ]]; then
    echo "FAIL missing artifact for reached step ${step_key}: ${artifact_path}" >&2
    FINAL_EXIT_STATUS="1"
  fi
}

require_artifact_if_success() {
  local step_key="$1"
  local artifact_path="$2"
  if step_succeeded "${step_key}" && [[ ! -e "${artifact_path}" ]]; then
    echo "FAIL missing artifact for successful step ${step_key}: ${artifact_path}" >&2
    FINAL_EXIT_STATUS="1"
  fi
}

STARTED_AT="$(now_utc)"
write_state "started_at" "${STARTED_AT}"

if ! "${PYTHON_BIN}" - "${REPO_ROOT}" "${RUN_ID}" "${PHASE2_RUN_DIR}" "${EXECUTION_TARGET_JSON}" "${STARTED_AT}" > "${RUN_DIR}/run_meta.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path


def as_repo_ref(repo_root: Path, path_text: str) -> str:
    path = Path(path_text).expanduser()
    if not path.is_absolute():
        path = (Path.cwd() / path).resolve(strict=False)
    else:
        path = path.resolve(strict=False)
    try:
        return path.relative_to(repo_root.resolve(strict=False)).as_posix()
    except ValueError:
        return path.as_posix()


repo_root = Path(sys.argv[1]).resolve(strict=False)
run_id = sys.argv[2]
phase2_run_dir_text = sys.argv[3]
execution_target_json = Path(sys.argv[4]).expanduser()
generated_at = sys.argv[5]

target_payload: dict[str, object] = {}
try:
    with execution_target_json.open("r", encoding="utf-8-sig") as handle:
        parsed = json.load(handle)
    if isinstance(parsed, dict):
        target_payload = parsed
except (OSError, ValueError, json.JSONDecodeError):
    target_payload = {}

phase2_run_ref = as_repo_ref(repo_root, phase2_run_dir_text)
phase2_runtime_ready_ref = as_repo_ref(repo_root, str(Path(phase2_run_dir_text) / "output" / "runtime-ready"))

payload = {
    "run_id": run_id,
    "generated_at": generated_at,
    "profile": "canonical-execution-owner",
    "phase": "phase3",
    "engine_mode": "scaffold",
    "execution_mode": "staged-only",
    "canonical_run_dir": f"operations/harness-phase3/runs/{run_id}",
    "run_dir_identity_verified": True,
    "write_surface": f"operations/harness-phase3/runs/{run_id}/",
    "phase2_run_ref": phase2_run_ref,
    "phase2_runtime_ready_ref": phase2_runtime_ready_ref,
    "target_runtime": target_payload.get("target_runtime"),
    "target_kind": target_payload.get("target_kind"),
    "target_ref": target_payload.get("target_ref"),
    "apply_mode": target_payload.get("apply_mode"),
    "approval_ref": target_payload.get("approval_ref"),
    "invoked_by": target_payload.get("invoked_by"),
}
json.dump(payload, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
then
  echo "FAIL unable to write initial run_meta.json" >&2
  exit 1
fi

run_python_step() {
  local step_key="$1"
  shift
  set +e
  "${PYTHON_BIN}" "$@"
  local exit_status=$?
  set -e
  record_step "${step_key}" "${exit_status}"
  return "${exit_status}"
}

BLOCKING_FAILURE=0
if ! run_python_step "freeze_input" "${PHASE3_ROOT}/bin/freeze_phase2_input.py" "${REPO_ROOT}" "${PHASE2_RUN_DIR}" "${RUN_DIR}" "${EXECUTION_TARGET_JSON}"; then
  BLOCKING_FAILURE=1
fi

if [[ "${BLOCKING_FAILURE}" -eq 0 ]]; then
  if ! run_python_step "freeze_input_hash" "${PHASE3_ROOT}/bin/hash_frozen_input.py" "${REPO_ROOT}" "${RUN_DIR}"; then
    BLOCKING_FAILURE=1
  fi
fi

if [[ "${BLOCKING_FAILURE}" -eq 0 ]]; then
  if ! run_python_step "freeze_intake_validation" "${PHASE3_ROOT}/bin/validate_frozen_intake.py" "${REPO_ROOT}" "${RUN_DIR}"; then
    BLOCKING_FAILURE=1
  fi
fi

if [[ "${BLOCKING_FAILURE}" -eq 0 ]]; then
  if ! run_python_step "pre_apply_validation" "${PHASE3_ROOT}/bin/validate_pre_apply.py" "${REPO_ROOT}" "${RUN_DIR}"; then
    BLOCKING_FAILURE=1
  fi
fi

if [[ "${BLOCKING_FAILURE}" -eq 0 ]]; then
  if ! run_python_step "runtime_ready_reverify" "${PHASE3_ROOT}/bin/reverify_runtime_ready.py" "${REPO_ROOT}" "${RUN_DIR}"; then
    BLOCKING_FAILURE=1
  fi
fi

if [[ "${BLOCKING_FAILURE}" -eq 0 ]]; then
  if ! run_python_step "materialize_staging" "${PHASE3_ROOT}/bin/materialize_phase3_staging.py" "${REPO_ROOT}" "${RUN_DIR}"; then
    BLOCKING_FAILURE=1
  fi
fi

EXECUTE_APPLY_EXIT_STATUS="1"
DECLARED_SCOPE_EXIT_STATUS="1"
POST_APPLY_EXIT_STATUS="1"
EXECUTION_RESULT_EXIT_STATUS="1"

if [[ "${BLOCKING_FAILURE}" -eq 0 ]]; then
  set +e
  "${PYTHON_BIN}" "${PHASE3_ROOT}/bin/execute_apply.py" "${REPO_ROOT}" "${RUN_DIR}"
  EXECUTE_APPLY_EXIT_STATUS=$?
  set -e
  record_step "execute_apply" "${EXECUTE_APPLY_EXIT_STATUS}"
  write_state "execute_apply_recorded_exit_status" "${EXECUTE_APPLY_EXIT_STATUS}"

  if [[ "${EXECUTE_APPLY_EXIT_STATUS}" -ne 0 ]]; then
    BLOCKING_FAILURE=1
  else
    set +e
    "${PYTHON_BIN}" "${PHASE3_ROOT}/bin/collect_declared_scope_evidence.py" "${REPO_ROOT}" "${RUN_DIR}"
    DECLARED_SCOPE_EXIT_STATUS=$?
    set -e
    record_step "declared_scope_evidence" "${DECLARED_SCOPE_EXIT_STATUS}"
    if [[ "${DECLARED_SCOPE_EXIT_STATUS}" -ne 0 ]]; then
      BLOCKING_FAILURE=1
    fi

    if [[ "${BLOCKING_FAILURE}" -eq 0 ]]; then
      set +e
      "${PYTHON_BIN}" "${PHASE3_ROOT}/bin/validate_post_apply.py" "${REPO_ROOT}" "${RUN_DIR}" --execute-apply-exit-status "${EXECUTE_APPLY_EXIT_STATUS}"
      POST_APPLY_EXIT_STATUS=$?
      set -e
      record_step "post_apply_validation" "${POST_APPLY_EXIT_STATUS}"
      if [[ "${POST_APPLY_EXIT_STATUS}" -ne 0 ]]; then
        BLOCKING_FAILURE=1
      fi
    fi

    if [[ "${BLOCKING_FAILURE}" -eq 0 ]]; then
      set +e
      "${PYTHON_BIN}" "${PHASE3_ROOT}/bin/emit_execution_result.py" "${REPO_ROOT}" "${RUN_DIR}" --execute-apply-exit-status "${EXECUTE_APPLY_EXIT_STATUS}"
      EXECUTION_RESULT_EXIT_STATUS=$?
      set -e
      record_step "execution_result" "${EXECUTION_RESULT_EXIT_STATUS}"
      if [[ -f "${RUN_DIR}/execution_result.json" ]]; then
        write_state "execution_result_emitted_at" "$(now_utc)"
      fi
      if [[ "${EXECUTION_RESULT_EXIT_STATUS}" -ne 0 ]]; then
        BLOCKING_FAILURE=1
      fi
    fi
  fi
fi

REPORT_EXIT_STATUS="1"
set +e
"${PYTHON_BIN}" "${PHASE3_ROOT}/bin/emit_phase3_report.py" "${REPO_ROOT}" "${RUN_DIR}"
REPORT_EXIT_STATUS=$?
set -e
record_step "report" "${REPORT_EXIT_STATUS}"

required_always=(
  "${RUN_DIR}/run_meta.json"
  "${CHECKS_DIR}/run_dir_invariants.json"
  "${RUN_DIR}/report.json"
  "${RUN_DIR}/report.md"
  "${RUN_DIR}/timestamps.json"
)

for artifact_path in "${required_always[@]}"; do
  if [[ ! -f "${artifact_path}" ]]; then
    echo "FAIL missing required output: ${artifact_path}" >&2
    FINAL_EXIT_STATUS="1"
  fi
done

require_artifact_if_success "freeze_input" "${INPUT_DIR}/execution_target.json"
require_artifact_if_success "freeze_input" "${INPUT_DIR}/runtime_ready_manifest.json"
require_artifact_if_success "freeze_input" "${INPUT_DIR}/runtime_ready.sha256"
require_artifact_if_success "freeze_input_hash" "${INPUT_DIR}/input.sha256"
require_artifact_if_reached "freeze_intake_validation" "${CHECKS_DIR}/freeze_intake_validation.json"
require_artifact_if_reached "pre_apply_validation" "${CHECKS_DIR}/pre_apply_validation.json"
require_artifact_if_reached "runtime_ready_reverify" "${CHECKS_DIR}/runtime_ready_reverify.json"
require_artifact_if_success "materialize_staging" "${RUN_DIR}/staging/runtime-ready-applied"
require_artifact_if_reached "execute_apply" "${LOGS_DIR}/apply.log"
require_artifact_if_reached "declared_scope_evidence" "${CHECKS_DIR}/declared_scope_evidence.json"
require_artifact_if_reached "post_apply_validation" "${CHECKS_DIR}/post_apply_validation.json"
require_artifact_if_reached "execution_result" "${RUN_DIR}/execution_result.json"

if [[ "${BLOCKING_FAILURE}" -eq 0 \
  && "${EXECUTE_APPLY_EXIT_STATUS}" -eq 0 \
  && "${DECLARED_SCOPE_EXIT_STATUS}" -eq 0 \
  && "${POST_APPLY_EXIT_STATUS}" -eq 0 \
  && "${EXECUTION_RESULT_EXIT_STATUS}" -eq 0 \
  && "${REPORT_EXIT_STATUS}" -eq 0 ]]; then
  FINAL_EXIT_STATUS="0"
fi

exit "${FINAL_EXIT_STATUS}"
