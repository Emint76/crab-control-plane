#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROOF_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${PROOF_ROOT}/../.." && pwd -P)"
RUNS_ROOT="${PROOF_ROOT}/runs"
RUN_ID="full-local-disposable-cycle-proof-valid"
RUN_DIR="${RUNS_ROOT}/${RUN_ID}"

PYTHON_BIN="${OPENCLAW_LOCAL_PROOF_TEST_PYTHON_BIN:-${OPENCLAW_LOCAL_PROOF_PYTHON_BIN:-${PHASE4_PYTHON_BIN:-${PHASE3_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set OPENCLAW_LOCAL_PROOF_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi
export OPENCLAW_LOCAL_PROOF_PYTHON_BIN="${OPENCLAW_LOCAL_PROOF_PYTHON_BIN:-${PYTHON_BIN}}"
export PHASE2_PYTHON_BIN="${PHASE2_PYTHON_BIN:-${PYTHON_BIN}}"
export PHASE3_PYTHON_BIN="${PHASE3_PYTHON_BIN:-${PYTHON_BIN}}"
export PHASE4_PYTHON_BIN="${PHASE4_PYTHON_BIN:-${PYTHON_BIN}}"
export OPENCLAW_DRYRUN_PYTHON_BIN="${OPENCLAW_DRYRUN_PYTHON_BIN:-${PYTHON_BIN}}"

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
    print(f"refusing to delete outside proof runs: {target}", file=sys.stderr)
    raise SystemExit(1)

if len(relative.parts) != 1 or target.name != expected_name:
    print(f"refusing to delete non-direct proof run child: {target}", file=sys.stderr)
    raise SystemExit(1)
PY

  rm -rf -- "${target}"
}

cleanup() {
  safe_rm_generated_dir "${RUN_DIR}" "${RUNS_ROOT}" "${RUN_ID}"
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

snapshot_proof_runs() {
  find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort
}

cd "${REPO_ROOT}"
mkdir -p "${RUNS_ROOT}"
cleanup
trap cleanup EXIT

bash operations/harness-openclaw-local-proof/bin/run_full_local_disposable_cycle.sh --run-id "${RUN_ID}"

assert_file "${RUN_DIR}/proof_meta.json"
assert_file "${RUN_DIR}/proof_report.json"
assert_file "${RUN_DIR}/proof_report.md"
assert_file "${RUN_DIR}/checks/run_dir_invariants.json"
assert_file "${RUN_DIR}/checks/step_results.json"
assert_file "${RUN_DIR}/exit_code"
assert_file_text_equals "${RUN_DIR}/exit_code" "0"

"${PYTHON_BIN}" - "${RUN_DIR}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

run_dir = Path(sys.argv[1])
expected_steps = [
    "orchestration-ci",
    "openclaw-dryrun-ci",
    "disposable-target-validation-ci",
    "no-secret-leakage-ci",
    "controlled-disposable-apply-ci",
    "local-target-selector-ci",
]


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def iter_items(value: Any):
    if isinstance(value, dict):
        for key, item in value.items():
            yield key, item
            yield from iter_items(item)
    elif isinstance(value, list):
        for item in value:
            yield from iter_items(item)


meta = load(run_dir / "proof_meta.json")
report = load(run_dir / "proof_report.json")
invariants = load(run_dir / "checks" / "run_dir_invariants.json")
step_results = load(run_dir / "checks" / "step_results.json")

assert meta["proof_kind"] == "full-local-disposable-cycle", meta
assert meta["local_only"] is True, meta
assert meta["disposable_only"] is True, meta
assert meta["live_runtime_apply"] is False, meta
assert meta["crab_approved"] is False, meta
assert meta["creates_new_openclaw_integration_power"] is False, meta
assert meta["owns_inner_canonical_evidence"] is False, meta

assert report["overall_status"] == "pass", report
assert report["steps_total"] == 6, report
assert report["steps_passed"] == 6, report
assert report["steps_failed"] == 0, report
assert report["local_only"] is True, report
assert report["disposable_only"] is True, report
assert report["live_runtime_apply"] is False, report
assert report["crab_approved"] is False, report

assert invariants["status"] == "pass", invariants
assert invariants["canonical_run_dir"] == "operations/harness-openclaw-local-proof/runs/full-local-disposable-cycle-proof-valid", invariants
assert invariants["run_dir_identity_verified"] is True, invariants
assert invariants["write_surface_verified"] is True, invariants
assert invariants["violations"] == [], invariants

assert [step["name"] for step in step_results] == expected_steps, step_results
assert [step["command"] for step in step_results] == [f"make {name}" for name in expected_steps], step_results
assert all(step["exit_status"] == 0 for step in step_results), step_results
assert all(step["status"] == "pass" for step in step_results), step_results

for payload in (meta, report, invariants, step_results):
    for key, value in iter_items(payload):
        lowered_key = str(key).lower()
        if "crab" in lowered_key and ("approved" in lowered_key or "approval" in lowered_key):
            assert value is False, (key, value, payload)

proof_artifacts = [
    run_dir / "proof_meta.json",
    run_dir / "proof_report.json",
    run_dir / "proof_report.md",
    run_dir / "checks" / "run_dir_invariants.json",
    run_dir / "checks" / "step_results.json",
    run_dir / "exit_code",
]
for artifact in proof_artifacts:
    text = artifact.read_text(encoding="utf-8-sig")
    lowered = text.lower()
    assert '"crab_approved": true' not in lowered, artifact
    assert "crab approval granted" not in lowered, artifact
    assert "live runtime target" not in lowered, artifact
    assert "production target" not in lowered, artifact
    assert "/mnt/" not in text, artifact
    assert "/home/" not in text, artifact
    assert "C:\\" not in text, artifact
PY

before_runs="$(snapshot_proof_runs)"
invalid_run_ids=(
  ""
  "   "
  "../bad"
  "bad/run"
  'bad\run'
  "/tmp/bad"
  " bad"
  "bad "
  "."
  ".."
)

for invalid_run_id in "${invalid_run_ids[@]}"; do
  set +e
  bash operations/harness-openclaw-local-proof/bin/run_full_local_disposable_cycle.sh --run-id "${invalid_run_id}" >/dev/null 2>&1
  status=$?
  set -e

  [[ "${status}" -ne 0 ]] || fail "invalid run id unexpectedly passed: ${invalid_run_id}"

  after_runs="$(snapshot_proof_runs)"
  [[ "${before_runs}" == "${after_runs}" ]] || fail "invalid run id created a proof run dir: ${invalid_run_id}"
done

echo "PASS full local disposable cycle proof valid run"
echo "PASS full local disposable cycle proof rejects invalid run ids"
