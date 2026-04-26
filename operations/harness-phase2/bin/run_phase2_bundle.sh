#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE2_ROOT}/../.." && pwd)"

if [[ $# -gt 0 ]]; then
  RUN_ID="$1"
else
  RUN_ID="phase2-$(date -u +%Y%m%dT%H%M%SZ)"
fi

validate_run_id() {
  local run_id="$1"
  if [[ -z "${run_id}" ]]; then
    echo "FAIL invalid RUN_ID: empty run id" >&2
    return 1
  fi
  if [[ "${run_id}" =~ ^[[:space:]] || "${run_id}" =~ [[:space:]]$ ]]; then
    echo "FAIL invalid RUN_ID: leading or trailing whitespace is not allowed" >&2
    return 1
  fi
  if [[ ! "${run_id}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "FAIL invalid RUN_ID: must match ^[A-Za-z0-9._-]+$" >&2
    return 1
  fi
  if [[ "${run_id}" == "." || "${run_id}" == ".." ]]; then
    echo "FAIL invalid RUN_ID: . and .. are not allowed" >&2
    return 1
  fi
}

validate_run_id "${RUN_ID}" || exit 2

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

PYTHON_BIN="${PHASE2_PYTHON_BIN:-python}"
if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "FAIL python runtime not found: ${PYTHON_BIN}" >&2
  exit 1
fi

RUNS_ROOT="${PHASE2_ROOT}/runs"
RUN_DIR="${RUNS_ROOT}/${RUN_ID}"
CHECKS_DIR="${RUN_DIR}/checks"
OUTPUT_DIR="${RUN_DIR}/output/runtime-ready"

verify_run_dir_invariants() {
  local write_report="${1:-false}"
  "${PYTHON_BIN}" - "${REPO_ROOT}" "${PHASE2_ROOT}" "${RUN_ID}" "${RUN_DIR}" "${write_report}" <<'PY'
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
phase2_root = Path(sys.argv[2]).resolve(strict=False)
run_id = sys.argv[3]
run_dir = Path(sys.argv[4])
write_report = sys.argv[5] == "true"

runs_root = (phase2_root / "runs").resolve(strict=False)
resolved_run_dir = run_dir.resolve(strict=False)
violations: list[str] = []

try:
    relative_run_dir = resolved_run_dir.relative_to(runs_root)
except ValueError:
    violations.append("run_dir_outside_phase2_runs_root")
    relative_run_dir = None

if resolved_run_dir.name != run_id:
    violations.append("run_dir_basename_mismatch")

if relative_run_dir is not None and len(relative_run_dir.parts) != 1:
    violations.append("run_dir_must_be_direct_child_of_phase2_runs_root")

expected_run_dir = (runs_root / run_id).resolve(strict=False)
if resolved_run_dir != expected_run_dir:
    violations.append("run_dir_identity_mismatch")

canonical_run_dir = repo_ref(repo_root, resolved_run_dir)
expected_canonical_run_dir = f"operations/harness-phase2/runs/{run_id}"
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
    print(f"FAIL Phase 2 run-dir invariant violation: {', '.join(violations)}", file=sys.stderr)
    raise SystemExit(1)
PY
}

verify_run_dir_invariants "false" || exit 2

mkdir -p "${CHECKS_DIR}" "${OUTPUT_DIR}"

EXIT_STATUS="1"
cleanup() {
  printf '%s\n' "${EXIT_STATUS}" > "${RUN_DIR}/exit_code"
}
trap cleanup EXIT

verify_run_dir_invariants "true" || exit 1

cat > "${RUN_DIR}/run_meta.json" <<EOF
{
  "phase": "phase2",
  "profile": "repo-native-scaffold",
  "run_id": "${RUN_ID}",
  "generated_at": "${GENERATED_AT}",
  "canonical_run_dir": "operations/harness-phase2/runs/${RUN_ID}",
  "run_dir_identity_verified": true,
  "write_surface": "operations/harness-phase2/runs/${RUN_ID}/",
  "engine_mode": "scaffold",
  "evaluation_mode": "static-v1"
}
EOF

PREFLIGHT_EXIT=0
CONTRACTS_EXIT=0
POLICY_EXIT=0
RENDER_EXIT=0
SMOKE_EXIT=0
CONFORMANCE_EXIT=0
REPORT_EXIT=0

if bash "${PHASE2_ROOT}/bin/preflight_wrong_root_scan.sh" "${REPO_ROOT}" "${RUN_DIR}"; then
  PREFLIGHT_EXIT=0
else
  PREFLIGHT_EXIT=$?
fi

if "${PYTHON_BIN}" "${PHASE2_ROOT}/bin/validate_contracts.py" "${REPO_ROOT}" "${RUN_DIR}"; then
  CONTRACTS_EXIT=0
else
  CONTRACTS_EXIT=$?
fi

if "${PYTHON_BIN}" "${PHASE2_ROOT}/bin/validate_policy.py" "${REPO_ROOT}" "${RUN_DIR}"; then
  POLICY_EXIT=0
else
  POLICY_EXIT=$?
fi

if "${PYTHON_BIN}" "${PHASE2_ROOT}/bin/render_apply_plan.py" "${REPO_ROOT}" "${RUN_DIR}" "${RUN_ID}"; then
  RENDER_EXIT=0
else
  RENDER_EXIT=$?
fi

if "${PYTHON_BIN}" "${PHASE2_ROOT}/bin/run_phase2_smoke.py" "${REPO_ROOT}" "${RUN_DIR}"; then
  SMOKE_EXIT=0
else
  SMOKE_EXIT=$?
fi

if "${PYTHON_BIN}" "${PHASE2_ROOT}/bin/run_phase2_conformance.py" "${REPO_ROOT}" "${RUN_DIR}"; then
  CONFORMANCE_EXIT=0
else
  CONFORMANCE_EXIT=$?
fi

if "${PYTHON_BIN}" "${PHASE2_ROOT}/bin/emit_phase2_report.py" "${REPO_ROOT}" "${RUN_DIR}"; then
  REPORT_EXIT=0
else
  REPORT_EXIT=$?
fi

required_files=(
  "${RUN_DIR}/run_meta.json"
  "${CHECKS_DIR}/run_dir_invariants.json"
  "${RUN_DIR}/validation_report.json"
  "${RUN_DIR}/admission_decision.json"
  "${RUN_DIR}/placement_decision.json"
  "${RUN_DIR}/apply_plan.json"
  "${CHECKS_DIR}/wrong_root_preflight.txt"
  "${CHECKS_DIR}/contracts_validation.json"
  "${CHECKS_DIR}/policy_validation.json"
  "${CHECKS_DIR}/smoke_validation.json"
  "${CHECKS_DIR}/conformance_validation.json"
  "${RUN_DIR}/handoff_ready.json"
  "${RUN_DIR}/report.json"
  "${RUN_DIR}/report.md"
)

for f in "${required_files[@]}"; do
  [[ -f "${f}" ]] || { echo "FAIL missing required output: ${f}" >&2; exit 1; }
done

[[ -d "${OUTPUT_DIR}" ]] || { echo "FAIL missing runtime-ready output directory" >&2; exit 1; }

for status_code in "${PREFLIGHT_EXIT}" "${CONTRACTS_EXIT}" "${POLICY_EXIT}" "${RENDER_EXIT}" "${SMOKE_EXIT}" "${CONFORMANCE_EXIT}" "${REPORT_EXIT}"; do
  [[ "${status_code}" -eq 0 ]] || exit 1
done

EXIT_STATUS="0"
