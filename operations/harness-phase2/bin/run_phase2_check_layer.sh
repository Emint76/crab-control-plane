#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE2_ROOT}/../.." && pwd)"

if [[ $# -gt 0 ]]; then
  RUN_ID="$1"
else
  RUN_ID="phase2-check-layer-$(date -u +%Y%m%dT%H%M%SZ)"
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

mkdir -p "${CHECKS_DIR}"

EXIT_STATUS="1"
cleanup() {
  printf '%s\n' "${EXIT_STATUS}" > "${RUN_DIR}/exit_code"
}
trap cleanup EXIT

verify_run_dir_invariants "true" || exit 1

cat > "${RUN_DIR}/run_meta.json" <<EOF
{
  "phase": "phase2",
  "run_id": "${RUN_ID}",
  "generated_at": "${GENERATED_AT}",
  "profile": "check-layer-strict",
  "canonical_run_dir": "operations/harness-phase2/runs/${RUN_ID}",
  "run_dir_identity_verified": true,
  "write_surface": "operations/harness-phase2/runs/${RUN_ID}/",
  "engine_mode": "external-check-layer",
  "evaluation_mode": "static-v1"
}
EOF

repo_rel() {
  local path="$1"
  case "${path}" in
    "${REPO_ROOT}"/*)
      printf '%s\n' "${path#${REPO_ROOT}/}"
      ;;
    *)
      printf '%s\n' "${path}"
      ;;
  esac
}

json_status() {
  "${PYTHON_BIN}" - "$1" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
status = payload.get("status")
if not isinstance(status, str) or not status:
    raise SystemExit(f"missing status in {sys.argv[1]}")
print(status)
PY
}

write_created_paths() {
  find "${RUN_DIR}" -type f -print | sort | while IFS= read -r created_path; do
    repo_rel "${created_path}"
  done > "${RUN_DIR}/CREATED_PATHS.txt"
}

write_evidence_pack() {
  local wrong_root_status
  local contracts_status
  local policy_status
  local fixture_smoke_status="pass"

  printf '0\n' > "${RUN_DIR}/exit_code"

  : > "${RUN_DIR}/PHASE2_TREE.txt"
  : > "${RUN_DIR}/PREFLIGHT_RESULT.txt"
  : > "${RUN_DIR}/SMOKE_OUTPUT.txt"
  : > "${RUN_DIR}/CREATED_PATHS.txt"
  : > "${RUN_DIR}/FINAL_REPORT.md"

  cp "${CHECKS_DIR}/wrong_root_preflight.txt" "${RUN_DIR}/PREFLIGHT_RESULT.txt"
  cp "${CHECKS_DIR}/fixture_smoke.txt" "${RUN_DIR}/SMOKE_OUTPUT.txt"

  wrong_root_status="$(sed -n 's/^status=//p' "${CHECKS_DIR}/wrong_root_preflight.txt" | head -n 1)"
  contracts_status="$(json_status "${CHECKS_DIR}/contracts_validation.json")"
  policy_status="$(json_status "${CHECKS_DIR}/policy_validation.json")"

  grep -Fq 'PASS valid task packet schema' "${CHECKS_DIR}/fixture_smoke.txt"
  write_created_paths

  {
    printf '# Phase 2 Strict Check-Layer Report\n\n'
    printf '## Baseline\n'
    printf -- '- repository: Emint76/crab-control-plane\n'
    printf -- '- profile: check-layer-strict\n'
    printf -- '- run_id: %s\n\n' "${RUN_ID}"
    printf '## Approved mutation root\n'
    printf -- '- operations/harness-phase2/runs/%s/\n\n' "${RUN_ID}"
    printf '## Files created\n'
    while IFS= read -r created_path; do
      printf -- '- %s\n' "${created_path}"
    done < "${RUN_DIR}/CREATED_PATHS.txt"
    printf '\n'
    printf '## Check results\n'
    printf -- '- wrong_root_preflight: %s\n' "${wrong_root_status}"
    printf -- '- contracts_validation: %s\n' "${contracts_status}"
    printf -- '- policy_validation: %s\n' "${policy_status}"
    printf -- '- fixture_smoke: %s\n\n' "${fixture_smoke_status}"
    printf '## Runtime statement\n'
    printf -- '- No OpenClaw runtime connection was implemented.\n'
    printf -- '- No automatic runtime enforcement was implemented.\n'
    printf -- '- No OpenClaw source, plugin, gateway, channel, model, auth, token, or config changes were made.\n\n'
    printf '## Write-surface statement\n'
    printf -- '- No writes occurred outside the strict Phase 2 run directory.\n'
  } > "${RUN_DIR}/FINAL_REPORT.md"

  find "${RUN_DIR}" -maxdepth 4 -print | sort > "${RUN_DIR}/PHASE2_TREE.txt"
}

bash "${PHASE2_ROOT}/bin/preflight_wrong_root_scan.sh" "${REPO_ROOT}" "${RUN_DIR}"
"${PYTHON_BIN}" "${PHASE2_ROOT}/bin/validate_contracts.py" "${REPO_ROOT}" "${RUN_DIR}"
"${PYTHON_BIN}" "${PHASE2_ROOT}/bin/validate_policy.py" "${REPO_ROOT}" "${RUN_DIR}"
PHASE2_PYTHON_BIN="${PYTHON_BIN}" bash "${PHASE2_ROOT}/tests/run_fixture_smoke.sh" > "${CHECKS_DIR}/fixture_smoke.txt" 2>&1

write_evidence_pack
EXIT_STATUS="0"
