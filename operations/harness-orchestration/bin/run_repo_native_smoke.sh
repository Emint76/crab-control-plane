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

[[ -d "${REPO_ROOT}" ]] || fail "missing repo root"
[[ -d "${RUNS_ROOT}" ]] || mkdir -p "${RUNS_ROOT}"
[[ -f "${REPO_ROOT}/${FALLBACK_SMOKE}" ]] || fail "missing e2e smoke script: ${FALLBACK_SMOKE}"

RUN_DIR="${RUNS_ROOT}/${RUN_ID}"
[[ "${RUN_DIR}" == "${RUNS_ROOT}/${RUN_ID}" ]] || fail "refusing to write outside orchestration run surface"

mkdir -p "${RUN_DIR}" || fail "unable to create orchestration run dir"

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
