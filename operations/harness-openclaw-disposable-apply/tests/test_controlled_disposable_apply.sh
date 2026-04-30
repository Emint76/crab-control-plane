#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${APPLY_ROOT}/../.." && pwd)"
RUNS_ROOT="${APPLY_ROOT}/runs"
DRYRUN_ROOT="${REPO_ROOT}/operations/harness-openclaw-dryrun"
PHASE2_ROOT="${REPO_ROOT}/operations/harness-phase2"
PHASE3_ROOT="${REPO_ROOT}/operations/harness-phase3"
PHASE4_ROOT="${REPO_ROOT}/operations/harness-phase4"

PYTHON_BIN="${CONTROLLED_APPLY_TEST_PYTHON_BIN:-${OPENCLAW_DRYRUN_PYTHON_BIN:-${PHASE3_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set CONTROLLED_APPLY_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi
export OPENCLAW_DRYRUN_PYTHON_BIN="${OPENCLAW_DRYRUN_PYTHON_BIN:-${PYTHON_BIN}}"
export PHASE2_PYTHON_BIN="${PHASE2_PYTHON_BIN:-${PYTHON_BIN}}"
export PHASE3_PYTHON_BIN="${PHASE3_PYTHON_BIN:-${PYTHON_BIN}}"
export PHASE4_PYTHON_BIN="${PHASE4_PYTHON_BIN:-${PYTHON_BIN}}"
export E2E_PYTHON_BIN="${E2E_PYTHON_BIN:-${PYTHON_BIN}}"

PHASE2_RUN_ID="smoke-e2e-phase2"
PHASE3_RUN_ID="smoke-e2e-phase3"
WRAPPER_RUN_ID="smoke-e2e-wrapper"
TARGET_RUN_ID="smoke-e2e-target"
DRYRUN_ID="openclaw-dryrun-valid"
VALID_RUN_ID="controlled-disposable-apply-valid"

PHASE2_RUN_DIR="${PHASE2_ROOT}/runs/${PHASE2_RUN_ID}"
PHASE3_RUN_DIR="${PHASE3_ROOT}/runs/${PHASE3_RUN_ID}"
WRAPPER_RUN_DIR="${PHASE4_ROOT}/runs/${WRAPPER_RUN_ID}"
TARGET_RUN_DIR="${PHASE4_ROOT}/runs/${TARGET_RUN_ID}"
DRYRUN_RUN_DIR="${DRYRUN_ROOT}/runs/${DRYRUN_ID}"
VALID_RUN_DIR="${RUNS_ROOT}/${VALID_RUN_ID}"
TMP_ROOT="$(mktemp -d)"

WORKSPACE_APPROVED_ROOT="${TMP_ROOT}/approved-workspace-root"
STATE_APPROVED_ROOT="${TMP_ROOT}/approved-state-root"
WORKSPACE_TARGET="${WORKSPACE_APPROVED_ROOT}/disposable-openclaw-workspace"
STATE_TARGET="${STATE_APPROVED_ROOT}/disposable-openclaw-state"

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
    print(f"refusing to delete outside approved generated surface: {target}", file=sys.stderr)
    raise SystemExit(1)

if len(relative.parts) != 1 or target.name != expected_name:
    print(f"refusing to delete non-direct generated child: {target}", file=sys.stderr)
    raise SystemExit(1)
PY

  rm -rf -- "${target}"
}

cleanup() {
  rm -rf -- "${TMP_ROOT}"
  safe_rm_generated_dir "${VALID_RUN_DIR}" "${RUNS_ROOT}" "${VALID_RUN_ID}"
  for name in \
    controlled-disposable-apply-invalid-run \
    controlled-disposable-apply-absolute-dryrun \
    controlled-disposable-apply-outside-dryrun \
    controlled-disposable-apply-missing-plan \
    controlled-disposable-apply-report-fail \
    controlled-disposable-apply-missing-no-secret \
    controlled-disposable-apply-workspace-not-disposable \
    controlled-disposable-apply-state-not-disposable \
    controlled-disposable-apply-target-outside-root \
    controlled-disposable-apply-target-equal-root \
    controlled-disposable-apply-empty-approval; do
    safe_rm_generated_dir "${RUNS_ROOT}/${name}" "${RUNS_ROOT}" "${name}"
  done
  for name in \
    "${DRYRUN_ID}" \
    openclaw-dryrun-missing-plan \
    openclaw-dryrun-report-fail \
    openclaw-dryrun-missing-no-secret; do
    safe_rm_generated_dir "${DRYRUN_ROOT}/runs/${name}" "${DRYRUN_ROOT}/runs" "${name}"
  done
  safe_rm_generated_dir "${PHASE2_RUN_DIR}" "${PHASE2_ROOT}/runs" "${PHASE2_RUN_ID}"
  safe_rm_generated_dir "${PHASE3_RUN_DIR}" "${PHASE3_ROOT}/runs" "${PHASE3_RUN_ID}"
  safe_rm_generated_dir "${WRAPPER_RUN_DIR}" "${PHASE4_ROOT}/runs" "${WRAPPER_RUN_ID}"
  safe_rm_generated_dir "${TARGET_RUN_DIR}" "${PHASE4_ROOT}/runs" "${TARGET_RUN_ID}"
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

snapshot_repo_local_live_surfaces() {
  find "${REPO_ROOT}" -maxdepth 1 \( \
    -name ".env" -o \
    -name "openclaw" -o \
    -name "OpenClaw" -o \
    -name "local-overlay" -o \
    -name "crab-local-overlay" -o \
    -name "crab-instance-data" \
  \) -print | sort
}

write_marker() {
  local target="$1"
  local kind="$2"
  local disposable="$3"
  mkdir -p "${target}"
  printf '{\n  "kind": "%s",\n  "disposable": %s\n}\n' "${kind}" "${disposable}" > "${target}/.crab-disposable-target.json"
}

clone_dryrun() {
  local name="$1"
  local target="${DRYRUN_ROOT}/runs/${name}"
  safe_rm_generated_dir "${target}" "${DRYRUN_ROOT}/runs" "${name}"
  cp -R "${DRYRUN_RUN_DIR}" "${target}"
}

run_apply_expect_fail() {
  local label="$1"
  shift
  set +e
  bash operations/harness-openclaw-disposable-apply/bin/run_controlled_disposable_apply.sh "$@" >/dev/null 2>&1
  local status=$?
  set -e
  [[ "${status}" -ne 0 ]] || fail "negative case unexpectedly passed: ${label}"
  echo "PASS controlled disposable apply negative case rejected: ${label}"
}

cd "${REPO_ROOT}"
mkdir -p "${RUNS_ROOT}" "${DRYRUN_ROOT}/runs"
cleanup
trap cleanup EXIT

live_surface_before="$(snapshot_repo_local_live_surfaces)"

bash operations/harness-openclaw-dryrun/tests/test_openclaw_dry_run.sh

bash operations/harness-e2e/tests/test_smoke_e2e.sh
bash operations/harness-openclaw-dryrun/bin/run_openclaw_dry_run.sh \
  --phase3-run-dir "operations/harness-phase3/runs/${PHASE3_RUN_ID}" \
  --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
  --run-id "${DRYRUN_ID}"

mkdir -p "${WORKSPACE_APPROVED_ROOT}" "${STATE_APPROVED_ROOT}"
write_marker "${WORKSPACE_TARGET}" "openclaw-workspace" "true"
write_marker "${STATE_TARGET}" "openclaw-state" "true"

bash operations/harness-openclaw-disposable-apply/bin/run_controlled_disposable_apply.sh \
  --dry-run-run-dir "operations/harness-openclaw-dryrun/runs/${DRYRUN_ID}" \
  --workspace-target "${WORKSPACE_TARGET}" \
  --workspace-approved-root "${WORKSPACE_APPROVED_ROOT}" \
  --state-target "${STATE_TARGET}" \
  --state-approved-root "${STATE_APPROVED_ROOT}" \
  --approval-label "test-approved" \
  --run-id "${VALID_RUN_ID}"

for evidence_file in \
  apply_meta.json \
  input_refs.json \
  target_refs.json \
  pre_apply_snapshot.json \
  post_apply_snapshot.json \
  apply_actions.json \
  apply_report.md \
  apply_report.json \
  cleanup_plan.json \
  rollback_plan.json \
  exit_code \
  checks/run_dir_invariants.json \
  checks/target_path_validation.json \
  checks/no_secret_leakage_validation.json \
  checks/no_live_runtime_validation.json; do
  assert_file "${VALID_RUN_DIR}/${evidence_file}"
done
assert_file_text_equals "${VALID_RUN_DIR}/exit_code" "0"

"${PYTHON_BIN}" - \
  "${VALID_RUN_DIR}" \
  "${DRYRUN_RUN_DIR}" \
  "${WORKSPACE_TARGET}" \
  "${STATE_TARGET}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
dryrun_dir = Path(sys.argv[2])
workspace_target = Path(sys.argv[3])
state_target = Path(sys.argv[4])

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

apply_meta = load(run_dir / "apply_meta.json")
run_dir_invariants = load(run_dir / "checks" / "run_dir_invariants.json")
target_path_validation = load(run_dir / "checks" / "target_path_validation.json")
no_secret_leakage_validation = load(run_dir / "checks" / "no_secret_leakage_validation.json")
no_live_runtime_validation = load(run_dir / "checks" / "no_live_runtime_validation.json")
apply_report = load(run_dir / "apply_report.json")
placement_plan = load(dryrun_dir / "proposed_openclaw_placement_plan.json")
apply_actions = load(run_dir / "apply_actions.json")
cleanup_plan = load(run_dir / "cleanup_plan.json")
rollback_plan = load(run_dir / "rollback_plan.json")
target_refs = load(run_dir / "target_refs.json")
input_refs = load(run_dir / "input_refs.json")

assert apply_meta["local_only"] is True, apply_meta
assert apply_meta["disposable_only"] is True, apply_meta
assert apply_meta["live_runtime_apply"] is False, apply_meta

assert run_dir_invariants["status"] == "pass", run_dir_invariants
assert target_path_validation["status"] == "pass", target_path_validation
assert no_secret_leakage_validation["status"] == "pass", no_secret_leakage_validation
assert no_live_runtime_validation["status"] == "pass", no_live_runtime_validation

assert apply_report["overall_status"] == "pass", apply_report
assert apply_report["local_only"] is True, apply_report
assert apply_report["disposable_only"] is True, apply_report
assert apply_report["live_runtime_apply"] is False, apply_report
assert apply_report["workspace_write_count"] >= 0, apply_report
assert apply_report["state_write_count"] == 0, apply_report

assert target_refs["workspace_target"] == str(workspace_target.resolve()), target_refs
assert target_refs["state_target"] == str(state_target.resolve()), target_refs
assert input_refs["dry_run_run_dir"] == "operations/harness-openclaw-dryrun/runs/openclaw-dryrun-valid", input_refs

proposed_writes = placement_plan["proposed_writes"]
assert proposed_writes, "expected fixture dry-run plan to contain proposed writes"
assert apply_report["workspace_write_count"] == len(proposed_writes), apply_report
assert apply_report["state_write_count"] == 0, apply_report
assert len(apply_actions) == len(proposed_writes), apply_actions

source_by_target = {
    item["target"].removeprefix("declared-openclaw-target:"): item["source"]
    for item in proposed_writes
}
for action in apply_actions:
    rel_target = action["workspace_target_path"]
    assert action["applied"] is True, action
    assert isinstance(action["source"], str) and action["source"].startswith("operations/"), action
    assert not Path(action["source"]).is_absolute(), action
    assert "\\" not in action["source"], action
    assert ".." not in Path(action["source"]).parts, action
    assert isinstance(rel_target, str) and rel_target, action
    assert not Path(rel_target).is_absolute(), action
    assert "\\" not in rel_target, action
    assert ".." not in Path(rel_target).parts, action
    assert rel_target in source_by_target, action
    copied = workspace_target / rel_target
    assert copied.resolve().is_relative_to(workspace_target.resolve()), copied
    source = Path(source_by_target[rel_target])
    assert copied.is_file(), copied
    assert copied.read_bytes() == source.read_bytes(), (copied, source)

state_files = sorted(path.relative_to(state_target).as_posix() for path in state_target.rglob("*") if path.is_file())
assert state_files == [".crab-disposable-target.json"], state_files

def iter_strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from iter_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from iter_strings(item)

applied_targets = sorted(action["workspace_target_path"] for action in apply_actions)
assert sorted(cleanup_plan["workspace_paths"]) == applied_targets, cleanup_plan
assert cleanup_plan["state_paths"] == [], cleanup_plan
assert cleanup_plan["local_only"] is True, cleanup_plan
assert cleanup_plan["disposable_only"] is True, cleanup_plan
assert cleanup_plan["must_not_clean_live_runtime"] is True, cleanup_plan
assert sorted(rollback_plan["workspace_paths"]) == applied_targets, rollback_plan
assert rollback_plan["state_paths"] == [], rollback_plan
assert rollback_plan["local_only"] is True, rollback_plan
assert rollback_plan["disposable_only"] is True, rollback_plan
assert rollback_plan["must_remain_inside_disposable_targets"] is True, rollback_plan

for plan in (cleanup_plan, rollback_plan):
    for text in iter_strings(plan):
        assert "live runtime target" not in text.lower(), plan
        assert "production" not in text.lower(), plan
        if text.startswith("operations/"):
            assert text.startswith("operations/harness-openclaw-disposable-apply/runs/"), text
        if text.startswith("/"):
            resolved = Path(text).resolve()
            assert (
                resolved == workspace_target.resolve()
                or resolved == state_target.resolve()
                or resolved.is_relative_to(workspace_target.resolve())
                or resolved.is_relative_to(state_target.resolve())
            ), text
PY

clone_dryrun "openclaw-dryrun-missing-plan"
rm -f "${DRYRUN_ROOT}/runs/openclaw-dryrun-missing-plan/proposed_openclaw_placement_plan.json"

clone_dryrun "openclaw-dryrun-report-fail"
"${PYTHON_BIN}" - "${DRYRUN_ROOT}/runs/openclaw-dryrun-report-fail/dry_run_report.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8-sig"))
payload["overall_status"] = "fail"
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

clone_dryrun "openclaw-dryrun-missing-no-secret"
rm -f "${DRYRUN_ROOT}/runs/openclaw-dryrun-missing-no-secret/checks/no_secret_leakage_validation.json"

BAD_WORKSPACE_TARGET="${WORKSPACE_APPROVED_ROOT}/workspace-not-disposable"
BAD_STATE_TARGET="${STATE_APPROVED_ROOT}/state-not-disposable"
OUTSIDE_WORKSPACE_ROOT="${TMP_ROOT}/outside-workspace-root"
OUTSIDE_WORKSPACE_TARGET="${OUTSIDE_WORKSPACE_ROOT}/outside-workspace"
mkdir -p "${OUTSIDE_WORKSPACE_ROOT}"
write_marker "${BAD_WORKSPACE_TARGET}" "openclaw-workspace" "false"
write_marker "${BAD_STATE_TARGET}" "openclaw-state" "false"
write_marker "${OUTSIDE_WORKSPACE_TARGET}" "openclaw-workspace" "true"

run_apply_expect_fail "invalid-run-id" \
  --dry-run-run-dir "operations/harness-openclaw-dryrun/runs/${DRYRUN_ID}" \
  --workspace-target "${WORKSPACE_TARGET}" \
  --workspace-approved-root "${WORKSPACE_APPROVED_ROOT}" \
  --state-target "${STATE_TARGET}" \
  --state-approved-root "${STATE_APPROVED_ROOT}" \
  --approval-label "test-approved" \
  --run-id "../bad"

run_apply_expect_fail "absolute-dry-run-run-dir" \
  --dry-run-run-dir "${DRYRUN_RUN_DIR}" \
  --workspace-target "${WORKSPACE_TARGET}" \
  --workspace-approved-root "${WORKSPACE_APPROVED_ROOT}" \
  --state-target "${STATE_TARGET}" \
  --state-approved-root "${STATE_APPROVED_ROOT}" \
  --approval-label "test-approved" \
  --run-id "controlled-disposable-apply-absolute-dryrun"

run_apply_expect_fail "dry-run-run-dir-outside-approved-surface" \
  --dry-run-run-dir "operations/harness-phase3/runs/${PHASE3_RUN_ID}" \
  --workspace-target "${WORKSPACE_TARGET}" \
  --workspace-approved-root "${WORKSPACE_APPROVED_ROOT}" \
  --state-target "${STATE_TARGET}" \
  --state-approved-root "${STATE_APPROVED_ROOT}" \
  --approval-label "test-approved" \
  --run-id "controlled-disposable-apply-outside-dryrun"

run_apply_expect_fail "missing-placement-plan" \
  --dry-run-run-dir "operations/harness-openclaw-dryrun/runs/openclaw-dryrun-missing-plan" \
  --workspace-target "${WORKSPACE_TARGET}" \
  --workspace-approved-root "${WORKSPACE_APPROVED_ROOT}" \
  --state-target "${STATE_TARGET}" \
  --state-approved-root "${STATE_APPROVED_ROOT}" \
  --approval-label "test-approved" \
  --run-id "controlled-disposable-apply-missing-plan"

run_apply_expect_fail "dry-run-report-not-pass" \
  --dry-run-run-dir "operations/harness-openclaw-dryrun/runs/openclaw-dryrun-report-fail" \
  --workspace-target "${WORKSPACE_TARGET}" \
  --workspace-approved-root "${WORKSPACE_APPROVED_ROOT}" \
  --state-target "${STATE_TARGET}" \
  --state-approved-root "${STATE_APPROVED_ROOT}" \
  --approval-label "test-approved" \
  --run-id "controlled-disposable-apply-report-fail"

run_apply_expect_fail "missing-no-secret-check" \
  --dry-run-run-dir "operations/harness-openclaw-dryrun/runs/openclaw-dryrun-missing-no-secret" \
  --workspace-target "${WORKSPACE_TARGET}" \
  --workspace-approved-root "${WORKSPACE_APPROVED_ROOT}" \
  --state-target "${STATE_TARGET}" \
  --state-approved-root "${STATE_APPROVED_ROOT}" \
  --approval-label "test-approved" \
  --run-id "controlled-disposable-apply-missing-no-secret"

run_apply_expect_fail "workspace-target-not-disposable" \
  --dry-run-run-dir "operations/harness-openclaw-dryrun/runs/${DRYRUN_ID}" \
  --workspace-target "${BAD_WORKSPACE_TARGET}" \
  --workspace-approved-root "${WORKSPACE_APPROVED_ROOT}" \
  --state-target "${STATE_TARGET}" \
  --state-approved-root "${STATE_APPROVED_ROOT}" \
  --approval-label "test-approved" \
  --run-id "controlled-disposable-apply-workspace-not-disposable"

run_apply_expect_fail "state-target-not-disposable" \
  --dry-run-run-dir "operations/harness-openclaw-dryrun/runs/${DRYRUN_ID}" \
  --workspace-target "${WORKSPACE_TARGET}" \
  --workspace-approved-root "${WORKSPACE_APPROVED_ROOT}" \
  --state-target "${BAD_STATE_TARGET}" \
  --state-approved-root "${STATE_APPROVED_ROOT}" \
  --approval-label "test-approved" \
  --run-id "controlled-disposable-apply-state-not-disposable"

run_apply_expect_fail "target-outside-approved-root" \
  --dry-run-run-dir "operations/harness-openclaw-dryrun/runs/${DRYRUN_ID}" \
  --workspace-target "${OUTSIDE_WORKSPACE_TARGET}" \
  --workspace-approved-root "${WORKSPACE_APPROVED_ROOT}" \
  --state-target "${STATE_TARGET}" \
  --state-approved-root "${STATE_APPROVED_ROOT}" \
  --approval-label "test-approved" \
  --run-id "controlled-disposable-apply-target-outside-root"

run_apply_expect_fail "target-equal-approved-root" \
  --dry-run-run-dir "operations/harness-openclaw-dryrun/runs/${DRYRUN_ID}" \
  --workspace-target "${WORKSPACE_APPROVED_ROOT}" \
  --workspace-approved-root "${WORKSPACE_APPROVED_ROOT}" \
  --state-target "${STATE_TARGET}" \
  --state-approved-root "${STATE_APPROVED_ROOT}" \
  --approval-label "test-approved" \
  --run-id "controlled-disposable-apply-target-equal-root"

run_apply_expect_fail "approval-label-empty" \
  --dry-run-run-dir "operations/harness-openclaw-dryrun/runs/${DRYRUN_ID}" \
  --workspace-target "${WORKSPACE_TARGET}" \
  --workspace-approved-root "${WORKSPACE_APPROVED_ROOT}" \
  --state-target "${STATE_TARGET}" \
  --state-approved-root "${STATE_APPROVED_ROOT}" \
  --approval-label "" \
  --run-id "controlled-disposable-apply-empty-approval"

live_surface_after="$(snapshot_repo_local_live_surfaces)"
[[ "${live_surface_before}" == "${live_surface_after}" ]] || fail "repo-local live OpenClaw-like surfaces changed"

echo "PASS controlled disposable apply valid run"
echo "PASS controlled disposable apply rejects invalid inputs"
echo "PASS controlled disposable apply remains local-only and disposable-only"
