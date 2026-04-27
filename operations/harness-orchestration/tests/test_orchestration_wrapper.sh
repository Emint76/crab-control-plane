#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ORCH_ROOT}/../.." && pwd)"
RUNS_ROOT="${ORCH_ROOT}/runs"
RUN_ID="orchestration-wrapper-valid"
RUN_DIR="${RUNS_ROOT}/${RUN_ID}"

PYTHON_BIN="${ORCH_TEST_PYTHON_BIN:-${PHASE4_PYTHON_BIN:-${PHASE3_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set ORCH_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi
export PHASE2_PYTHON_BIN="${PHASE2_PYTHON_BIN:-${PYTHON_BIN}}"
export PHASE3_PYTHON_BIN="${PHASE3_PYTHON_BIN:-${PYTHON_BIN}}"
export PHASE4_PYTHON_BIN="${PHASE4_PYTHON_BIN:-${PYTHON_BIN}}"

fail() {
  echo "FAIL $*" >&2
  exit 1
}

safe_rm_generated_dir() {
  local target="$1"
  "${PYTHON_BIN}" - "${target}" "${RUNS_ROOT}" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

target = Path(sys.argv[1]).resolve(strict=False)
runs_root = Path(sys.argv[2]).resolve(strict=False)

try:
    relative = target.relative_to(runs_root)
except ValueError:
    print(f"refusing to remove outside orchestration runs: {target}", file=sys.stderr)
    raise SystemExit(1)

if len(relative.parts) != 1:
    print(f"refusing to remove non-direct orchestration run child: {target}", file=sys.stderr)
    raise SystemExit(1)
PY
  rm -rf -- "${target}"
}

snapshot_orchestration_files_outside_runs() {
  find "${ORCH_ROOT}" -path "${RUNS_ROOT}" -prune -o -type f -print | sort
}

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
}

assert_absent() {
  local path="$1"
  [[ ! -e "${path}" ]] || fail "unexpected path exists: ${path}"
}

cleanup() {
  safe_rm_generated_dir "${RUN_DIR}"
}

cd "${REPO_ROOT}"
mkdir -p "${RUNS_ROOT}"
cleanup
trap cleanup EXIT

bash operations/harness-orchestration/bin/run_repo_native_smoke.sh --run-id "${RUN_ID}"

assert_file "${RUN_DIR}/orchestration_meta.json"
assert_file "${RUN_DIR}/orchestration_summary.md"
assert_file "${RUN_DIR}/run_dir_invariants.json"
assert_file "${RUN_DIR}/underlying_command.txt"
assert_file "${RUN_DIR}/underlying_exit_code"
[[ "$(tr -d '\r\n' < "${RUN_DIR}/underlying_exit_code")" == "0" ]] || fail "underlying_exit_code must be 0"

assert_absent "${RUN_DIR}/report.json"
assert_absent "${RUN_DIR}/report.md"
assert_absent "${RUN_DIR}/exit_code"
assert_absent "${RUN_DIR}/execution_result.json"

assert_no_host_paths() {
  local path="$1"
  ! grep -Fq "/mnt/" "${path}" || fail "host-specific path leaked into ${path}: /mnt/"
  ! grep -Fq "/home/" "${path}" || fail "host-specific path leaked into ${path}: /home/"
  ! grep -Fq 'C:\' "${path}" || fail "host-specific path leaked into ${path}: C:\\"
}

assert_no_host_paths "${RUN_DIR}/orchestration_meta.json"
assert_no_host_paths "${RUN_DIR}/run_dir_invariants.json"
assert_no_host_paths "${RUN_DIR}/orchestration_summary.md"

"${PYTHON_BIN}" - \
  "${RUN_DIR}/orchestration_meta.json" \
  "${RUN_DIR}/run_dir_invariants.json" \
  "${RUN_DIR}/underlying_command.txt" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

meta = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
invariants = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8-sig"))
underlying_command = Path(sys.argv[3]).read_text(encoding="utf-8").strip()
canonical_run_dir = "operations/harness-orchestration/runs/orchestration-wrapper-valid"

assert meta["profile"] == "crab-safe-repo-native-smoke", meta
assert meta["canonical_run_dir"] == canonical_run_dir, meta
assert meta["run_dir_identity_verified"] is True, meta
assert meta["write_surface_verified"] is True, meta
assert meta["live_openclaw_runtime_mutation"] is False, meta
assert meta["deploy_or_migration"] is False, meta
assert meta["runtime_adapter_behavior"] is False, meta
assert meta["real_source_ingestion"] is False, meta
assert meta["real_kb_write_back"] is False, meta
assert underlying_command in {
    "make smoke-e2e",
    "bash operations/harness-e2e/tests/test_smoke_e2e.sh",
}, underlying_command
assert meta["underlying_path"] == underlying_command, meta

assert invariants["status"] == "pass", invariants
assert invariants["run_id"] == "orchestration-wrapper-valid", invariants
assert invariants["canonical_run_dir"] == canonical_run_dir, invariants
assert invariants["run_dir_identity_verified"] is True, invariants
assert invariants["write_surface_verified"] is True, invariants
assert invariants["violations"] == [], invariants
PY

invalid_run_ids=(
  "../bad"
  "bad/run"
  'bad\run'
  "/tmp/bad"
  " bad"
  "bad "
  "."
  ".."
)

before_outside_runs="$(snapshot_orchestration_files_outside_runs)"
before_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"

for invalid_run_id in "${invalid_run_ids[@]}"; do
  set +e
  bash operations/harness-orchestration/bin/run_repo_native_smoke.sh --run-id "${invalid_run_id}" >/dev/null 2>&1
  status=$?
  set -e

  [[ "${status}" -ne 0 ]] || fail "invalid run id unexpectedly passed: ${invalid_run_id}"

  after_outside_runs="$(snapshot_orchestration_files_outside_runs)"
  [[ "${before_outside_runs}" == "${after_outside_runs}" ]] || fail "invalid run id wrote outside orchestration runs: ${invalid_run_id}"

  after_runs="$(find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort)"
  [[ "${before_runs}" == "${after_runs}" ]] || fail "invalid run id created an orchestration run dir: ${invalid_run_id}"
done

echo "PASS orchestration wrapper valid run"
echo "PASS orchestration wrapper rejects invalid run ids"
