#!/usr/bin/env bash
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ORCH_ROOT}/../.." && pwd)"
RUNS_ROOT="${ORCH_ROOT}/runs"
APPROVED_ENTRYPOINT="operations/harness-orchestration/bin/run_repo_native_smoke.sh"
FALLBACK_SMOKE="operations/harness-e2e/tests/test_smoke_e2e.sh"
PHASE_PATH="Phase 2 repo-native-scaffold -> Phase 3 canonical execution owner -> Phase 4 thin wrapper"
PYTHON_BIN="${ORCH_PYTHON_BIN:-}"

usage() {
  cat <<'EOF' >&2
usage: run_repo_native_smoke.sh [--run-id <SAFE_RUN_ID>]
EOF
}

fail() {
  echo "FAIL $*" >&2
  exit 1
}

now_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

generated_run_id() {
  date -u +orchestration-%Y%m%dT%H%M%SZ
}

detect_python() {
  if [[ -n "${PYTHON_BIN}" ]]; then
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set ORCH_PYTHON_BIN or install python/python3" >&2
    return 1
  fi
}

validate_run_id() {
  local run_id="$1"
  if [[ -z "${run_id}" ]]; then
    echo "invalid run id: empty" >&2
    return 1
  fi
  if [[ "${run_id}" =~ ^[[:space:]] || "${run_id}" =~ [[:space:]]$ ]]; then
    echo "invalid run id: leading or trailing whitespace" >&2
    return 1
  fi
  if [[ "${run_id}" == "." || "${run_id}" == ".." ]]; then
    echo "invalid run id: . and .. are not allowed" >&2
    return 1
  fi
  if [[ "${run_id}" == /* || "${run_id}" =~ ^[A-Za-z]:[\\/] ]]; then
    echo "invalid run id: absolute paths are not allowed" >&2
    return 1
  fi
  if [[ "${run_id}" == *"/"* || "${run_id}" == *"\\"* ]]; then
    echo "invalid run id: traversal and path separators are not allowed" >&2
    return 1
  fi
  if [[ ! "${run_id}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "invalid run id: must match ^[A-Za-z0-9._-]+$" >&2
    return 1
  fi
}

RUN_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      RUN_ID="$2"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${RUN_ID}" ]]; then
  RUN_ID="$(generated_run_id)"
fi

validate_run_id "${RUN_ID}" || fail "invalid --run-id: ${RUN_ID}"
detect_python || exit 1

[[ -d "${REPO_ROOT}" ]] || fail "missing repo root"
[[ -d "${RUNS_ROOT}" ]] || mkdir -p "${RUNS_ROOT}"
[[ -f "${REPO_ROOT}/${FALLBACK_SMOKE}" ]] || fail "missing e2e smoke script: ${FALLBACK_SMOKE}"

RUN_DIR="${RUNS_ROOT}/${RUN_ID}"
[[ "${RUN_DIR}" == "${RUNS_ROOT}/${RUN_ID}" ]] || fail "refusing to write outside orchestration run surface"
CANONICAL_RUN_DIR="operations/harness-orchestration/runs/${RUN_ID}"

if ! INVARIANTS_JSON="$("${PYTHON_BIN}" - "${REPO_ROOT}" "${RUNS_ROOT}" "${RUN_ID}" "${RUN_DIR}" <<'PY'
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
runs_root = Path(sys.argv[2]).resolve(strict=False)
run_id = sys.argv[3]
run_dir = Path(sys.argv[4]).resolve(strict=False)
expected_runs_root = (repo_root / "operations" / "harness-orchestration" / "runs").resolve(strict=False)
expected_run_dir = (expected_runs_root / run_id).resolve(strict=False)
expected_canonical_run_dir = f"operations/harness-orchestration/runs/{run_id}"
violations: list[str] = []

if runs_root != expected_runs_root:
    violations.append("runs_root_repo_ref_mismatch")

if repo_ref(repo_root, runs_root) != "operations/harness-orchestration/runs":
    violations.append("canonical_runs_root_repo_ref_mismatch")

try:
    relative_run_dir = run_dir.relative_to(runs_root)
except ValueError:
    violations.append("run_dir_outside_orchestration_runs_root")
    relative_run_dir = None

if relative_run_dir is not None and len(relative_run_dir.parts) != 1:
    violations.append("run_dir_must_be_direct_child_of_orchestration_runs_root")

if run_dir.name != run_id:
    violations.append("run_dir_basename_mismatch")

if run_dir != expected_run_dir:
    violations.append("run_dir_identity_mismatch")

if repo_ref(repo_root, run_dir) != expected_canonical_run_dir:
    violations.append("canonical_run_dir_repo_ref_mismatch")

payload = {
    "status": "fail" if violations else "pass",
    "run_id": run_id,
    "canonical_run_dir": expected_canonical_run_dir,
    "run_dir_identity_verified": not violations,
    "write_surface_verified": not violations,
    "violations": sorted(set(violations)),
}

json.dump(payload, sys.stdout, indent=2)
sys.stdout.write("\n")

if violations:
    print(f"FAIL orchestration run-dir invariant violation: {', '.join(payload['violations'])}", file=sys.stderr)
    raise SystemExit(1)
PY
)"; then
  fail "orchestration run-dir containment verification failed"
fi

mkdir -p "${RUN_DIR}" || fail "unable to create orchestration run dir"
printf '%s\n' "${INVARIANTS_JSON}" > "${RUN_DIR}/run_dir_invariants.json"

UNDERLYING_COMMAND_TEXT=""
if command -v make >/dev/null 2>&1; then
  UNDERLYING_COMMAND_TEXT="make smoke-e2e"
else
  UNDERLYING_COMMAND_TEXT="bash ${FALLBACK_SMOKE}"
fi

printf '%s\n' "${UNDERLYING_COMMAND_TEXT}" > "${RUN_DIR}/underlying_command.txt"

cd "${REPO_ROOT}" || fail "missing repo root"

set +e
if [[ "${UNDERLYING_COMMAND_TEXT}" == "make smoke-e2e" ]]; then
  make smoke-e2e
else
  bash "${FALLBACK_SMOKE}"
fi
UNDERLYING_EXIT_CODE=$?
set -e

printf '%s\n' "${UNDERLYING_EXIT_CODE}" > "${RUN_DIR}/underlying_exit_code"

CREATED_AT="$(now_utc)"
cat > "${RUN_DIR}/orchestration_meta.json" <<EOF
{
  "profile": "crab-safe-repo-native-smoke",
  "run_id": "${RUN_ID}",
  "approved_entrypoint": "${APPROVED_ENTRYPOINT}",
  "underlying_path": "${UNDERLYING_COMMAND_TEXT}",
  "canonical_run_dir": "${CANONICAL_RUN_DIR}",
  "run_dir_identity_verified": true,
  "write_surface_verified": true,
  "phase_path": "${PHASE_PATH}",
  "live_openclaw_runtime_mutation": false,
  "deploy_or_migration": false,
  "runtime_adapter_behavior": false,
  "real_source_ingestion": false,
  "real_kb_write_back": false,
  "created_at": "${CREATED_AT}"
}
EOF

cat > "${RUN_DIR}/orchestration_summary.md" <<EOF
# Crab-safe repo-native smoke invocation

## Result

- run_id: \`${RUN_ID}\`
- underlying_exit_code: \`${UNDERLYING_EXIT_CODE}\`

## Underlying command

\`${UNDERLYING_COMMAND_TEXT}\`

## Run directory invariants

- canonical_run_dir: \`${CANONICAL_RUN_DIR}\`
- run_dir_identity_verified: \`true\`
- write_surface_verified: \`true\`

## Boundary statement

- This wrapper did not perform live OpenClaw runtime mutation.
- This wrapper did not perform deploy or migration.
- This wrapper did not perform runtime adapter behavior.
- This wrapper did not perform real source ingestion.
- This wrapper did not perform real KB write-back.
- This wrapper did not give Crab arbitrary shell access.
EOF

if [[ "${UNDERLYING_EXIT_CODE}" -eq 0 ]]; then
  echo "PASS Crab-safe repo-native smoke invocation: ${RUN_ID}"
else
  echo "FAIL Crab-safe repo-native smoke invocation: ${RUN_ID} underlying_exit_code=${UNDERLYING_EXIT_CODE}" >&2
fi

exit "${UNDERLYING_EXIT_CODE}"
