#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE2_ROOT}/../.." && pwd)"

RUN_ID="${1:-phase2-check-layer-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN_DIR="${PHASE2_ROOT}/runs/${RUN_ID}"
CHECKS_DIR="${RUN_DIR}/checks"

mkdir -p "${CHECKS_DIR}"

EXIT_STATUS="1"
cleanup() {
  printf '%s\n' "${EXIT_STATUS}" > "${RUN_DIR}/exit_code"
}
trap cleanup EXIT

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

PYTHON_BIN="${PHASE2_PYTHON_BIN:-python}"
if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "FAIL python runtime not found: ${PYTHON_BIN}" >&2
  exit 1
fi

cat > "${RUN_DIR}/run_meta.json" <<EOF
{
  "run_id": "${RUN_ID}",
  "generated_at": "${GENERATED_AT}",
  "profile": "check-layer-strict",
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
