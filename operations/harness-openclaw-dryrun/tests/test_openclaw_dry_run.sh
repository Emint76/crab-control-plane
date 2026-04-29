#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRYRUN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${DRYRUN_ROOT}/../.." && pwd)"
RUNS_ROOT="${DRYRUN_ROOT}/runs"
PHASE2_ROOT="${REPO_ROOT}/operations/harness-phase2"
PHASE3_ROOT="${REPO_ROOT}/operations/harness-phase3"
PHASE4_ROOT="${REPO_ROOT}/operations/harness-phase4"

PYTHON_BIN="${OPENCLAW_DRYRUN_TEST_PYTHON_BIN:-${OPENCLAW_DRYRUN_PYTHON_BIN:-${PHASE3_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set OPENCLAW_DRYRUN_TEST_PYTHON_BIN or install python/python3" >&2
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
VALID_RUN_ID="openclaw-dryrun-valid"
MISSING_REPORT_PHASE3_RUN_ID="openclaw-dryrun-missing-report"
REPORT_FAIL_PHASE3_RUN_ID="openclaw-dryrun-report-fail"

PHASE2_RUN_DIR="${PHASE2_ROOT}/runs/${PHASE2_RUN_ID}"
PHASE3_RUN_DIR="${PHASE3_ROOT}/runs/${PHASE3_RUN_ID}"
WRAPPER_RUN_DIR="${PHASE4_ROOT}/runs/${WRAPPER_RUN_ID}"
TARGET_RUN_DIR="${PHASE4_ROOT}/runs/${TARGET_RUN_ID}"
VALID_RUN_DIR="${RUNS_ROOT}/${VALID_RUN_ID}"
MISSING_REPORT_PHASE3_RUN_DIR="${PHASE3_ROOT}/runs/${MISSING_REPORT_PHASE3_RUN_ID}"
REPORT_FAIL_PHASE3_RUN_DIR="${PHASE3_ROOT}/runs/${REPORT_FAIL_PHASE3_RUN_ID}"
PLACEMENT_PLAN_SCHEMA="${DRYRUN_ROOT}/schemas/proposed_openclaw_placement_plan.schema.json"

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
  safe_rm_generated_dir "${VALID_RUN_DIR}" "${RUNS_ROOT}" "${VALID_RUN_ID}"
  safe_rm_generated_dir "${MISSING_REPORT_PHASE3_RUN_DIR}" "${PHASE3_ROOT}/runs" "${MISSING_REPORT_PHASE3_RUN_ID}"
  safe_rm_generated_dir "${REPORT_FAIL_PHASE3_RUN_DIR}" "${PHASE3_ROOT}/runs" "${REPORT_FAIL_PHASE3_RUN_ID}"
  safe_rm_generated_dir "${PHASE2_RUN_DIR}" "${PHASE2_ROOT}/runs" "${PHASE2_RUN_ID}"
  safe_rm_generated_dir "${PHASE3_RUN_DIR}" "${PHASE3_ROOT}/runs" "${PHASE3_RUN_ID}"
  safe_rm_generated_dir "${WRAPPER_RUN_DIR}" "${PHASE4_ROOT}/runs" "${WRAPPER_RUN_ID}"
  safe_rm_generated_dir "${TARGET_RUN_DIR}" "${PHASE4_ROOT}/runs" "${TARGET_RUN_ID}"
}

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
}

assert_absent() {
  local path="$1"
  [[ ! -e "${path}" ]] || fail "unexpected path exists: ${path}"
}

assert_file_text_equals() {
  local path="$1"
  local expected="$2"
  assert_file "${path}"
  local actual
  actual="$(tr -d '\r\n' < "${path}")"
  [[ "${actual}" == "${expected}" ]] || fail "${path} expected ${expected}, got ${actual}"
}

assert_no_host_paths() {
  local path="$1"
  ! grep -Fq "/mnt/" "${path}" || fail "host-specific path leaked into ${path}: /mnt/"
  ! grep -Fq "/home/" "${path}" || fail "host-specific path leaked into ${path}: /home/"
  ! grep -Fq 'C:\' "${path}" || fail "host-specific path leaked into ${path}: C:\\"
}

snapshot_dryrun_run_dirs() {
  find "${RUNS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | sort
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

run_expect_fail_no_dryrun_dir() {
  local label="$1"
  local run_id="$2"
  shift 2
  safe_rm_generated_dir "${RUNS_ROOT}/${run_id}" "${RUNS_ROOT}" "${run_id}"

  set +e
  bash operations/harness-openclaw-dryrun/bin/run_openclaw_dry_run.sh "$@" --run-id "${run_id}" >/dev/null 2>&1
  local status=$?
  set -e

  [[ "${status}" -ne 0 ]] || fail "negative case unexpectedly passed: ${label}"
  assert_absent "${RUNS_ROOT}/${run_id}"
  echo "PASS dry-run negative case rejected: ${label}"
}

cd "${REPO_ROOT}"
mkdir -p "${RUNS_ROOT}"
cleanup
trap cleanup EXIT

live_surface_before="$(snapshot_repo_local_live_surfaces)"

bash operations/harness-e2e/tests/test_smoke_e2e.sh

bash operations/harness-openclaw-dryrun/bin/run_openclaw_dry_run.sh \
  --phase3-run-dir "operations/harness-phase3/runs/${PHASE3_RUN_ID}" \
  --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
  --run-id "${VALID_RUN_ID}"

assert_file "${VALID_RUN_DIR}/adapter_meta.json"
assert_file "${VALID_RUN_DIR}/input_refs.json"
assert_file "${VALID_RUN_DIR}/proposed_openclaw_placement_plan.json"
assert_file "${VALID_RUN_DIR}/dry_run_report.md"
assert_file "${VALID_RUN_DIR}/dry_run_report.json"
assert_file "${VALID_RUN_DIR}/exit_code"
assert_file "${VALID_RUN_DIR}/checks/run_dir_invariants.json"
assert_file "${VALID_RUN_DIR}/checks/input_refs_validation.json"
assert_file "${VALID_RUN_DIR}/checks/no_live_write_validation.json"
assert_file "${VALID_RUN_DIR}/checks/proposed_plan_schema_validation.json"
assert_file "${VALID_RUN_DIR}/checks/no_secret_leakage_validation.json"
assert_file_text_equals "${VALID_RUN_DIR}/exit_code" "0"

for evidence_file in \
  "${VALID_RUN_DIR}/adapter_meta.json" \
  "${VALID_RUN_DIR}/input_refs.json" \
  "${VALID_RUN_DIR}/proposed_openclaw_placement_plan.json" \
  "${VALID_RUN_DIR}/dry_run_report.md" \
  "${VALID_RUN_DIR}/dry_run_report.json" \
  "${VALID_RUN_DIR}/checks/run_dir_invariants.json" \
  "${VALID_RUN_DIR}/checks/input_refs_validation.json" \
  "${VALID_RUN_DIR}/checks/no_live_write_validation.json" \
  "${VALID_RUN_DIR}/checks/proposed_plan_schema_validation.json" \
  "${VALID_RUN_DIR}/checks/no_secret_leakage_validation.json"; do
  assert_no_host_paths "${evidence_file}"
done

"${PYTHON_BIN}" - \
  "${VALID_RUN_DIR}/adapter_meta.json" \
  "${VALID_RUN_DIR}/proposed_openclaw_placement_plan.json" \
  "${VALID_RUN_DIR}/dry_run_report.json" \
  "${VALID_RUN_DIR}/checks/run_dir_invariants.json" \
  "${VALID_RUN_DIR}/checks/input_refs_validation.json" \
  "${VALID_RUN_DIR}/checks/no_live_write_validation.json" \
  "${VALID_RUN_DIR}/checks/proposed_plan_schema_validation.json" \
  "${VALID_RUN_DIR}/checks/no_secret_leakage_validation.json" \
  "${PLACEMENT_PLAN_SCHEMA}" \
  "${VALID_RUN_DIR}/invalid_plan_missing_write_mode.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

import jsonschema

adapter_meta = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
placement_plan = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8-sig"))
dry_run_report = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8-sig"))
run_dir_invariants = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8-sig"))
input_refs_validation = json.loads(Path(sys.argv[5]).read_text(encoding="utf-8-sig"))
no_live_write_validation = json.loads(Path(sys.argv[6]).read_text(encoding="utf-8-sig"))
proposed_plan_schema_validation = json.loads(Path(sys.argv[7]).read_text(encoding="utf-8-sig"))
no_secret_leakage_validation = json.loads(Path(sys.argv[8]).read_text(encoding="utf-8-sig"))
schema = json.loads(Path(sys.argv[9]).read_text(encoding="utf-8-sig"))
invalid_plan_path = Path(sys.argv[10])

assert adapter_meta["dry_run_only"] is True, adapter_meta
assert adapter_meta["live_writes_performed"] is False, adapter_meta
assert adapter_meta["openclaw_runtime_mutation"] is False, adapter_meta
assert adapter_meta["deploy_or_migration"] is False, adapter_meta
assert adapter_meta["real_kb_write_back"] is False, adapter_meta
assert adapter_meta["secrets_required"] is False, adapter_meta

assert placement_plan["status"] == "dry-run", placement_plan
assert placement_plan["live_writes_performed"] is False, placement_plan
for proposed_write in placement_plan["proposed_writes"]:
    assert proposed_write["write_mode"] == "proposed-only", proposed_write

assert dry_run_report["overall_status"] == "pass", dry_run_report
assert dry_run_report["live_writes_performed"] is False, dry_run_report

assert run_dir_invariants["status"] == "pass", run_dir_invariants
assert input_refs_validation["status"] == "pass", input_refs_validation
assert no_live_write_validation["status"] == "pass", no_live_write_validation
assert proposed_plan_schema_validation["status"] == "pass", proposed_plan_schema_validation
assert proposed_plan_schema_validation["violations"] == [], proposed_plan_schema_validation
assert no_secret_leakage_validation["status"] == "pass", no_secret_leakage_validation
assert no_secret_leakage_validation["violations"] == [], no_secret_leakage_validation
assert dry_run_report["checks"]["proposed_plan_schema_validation"] == "pass", dry_run_report
assert dry_run_report["checks"]["no_secret_leakage_validation"] == "pass", dry_run_report

jsonschema.Draft202012Validator.check_schema(schema)
jsonschema.validate(instance=placement_plan, schema=schema)

invalid_plan = dict(placement_plan)
invalid_plan["proposed_writes"] = [dict(item) for item in placement_plan["proposed_writes"]]
if invalid_plan["proposed_writes"]:
    invalid_plan["proposed_writes"][0].pop("write_mode", None)
else:
    invalid_plan["proposed_writes"] = [
        {
            "source": "operations/harness-phase3/runs/smoke-e2e-phase3/staging/runtime-ready-applied/synthetic.json",
            "target": "declared-openclaw-target:synthetic.json",
            "reason": "synthetic invalid placement plan for schema negative test",
        }
    ]
invalid_plan_path.write_text(json.dumps(invalid_plan, indent=2) + "\n", encoding="utf-8")

try:
    jsonschema.validate(instance=invalid_plan, schema=schema)
except jsonschema.ValidationError:
    pass
else:
    raise AssertionError("invalid placement plan unexpectedly passed schema validation")
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

before_invalid_run_ids="$(snapshot_dryrun_run_dirs)"
for invalid_run_id in "${invalid_run_ids[@]}"; do
  set +e
  bash operations/harness-openclaw-dryrun/bin/run_openclaw_dry_run.sh \
    --phase3-run-dir "operations/harness-phase3/runs/${PHASE3_RUN_ID}" \
    --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
    --run-id "${invalid_run_id}" >/dev/null 2>&1
  status=$?
  set -e
  [[ "${status}" -ne 0 ]] || fail "invalid run id unexpectedly passed: ${invalid_run_id}"
  after_invalid_run_ids="$(snapshot_dryrun_run_dirs)"
  [[ "${before_invalid_run_ids}" == "${after_invalid_run_ids}" ]] || fail "invalid run id created dry-run run dir: ${invalid_run_id}"
done

run_expect_fail_no_dryrun_dir \
  "invalid-absolute-phase3" \
  "openclaw-dryrun-invalid-absolute" \
  --phase3-run-dir "/tmp/bad"

run_expect_fail_no_dryrun_dir \
  "invalid-traversal-phase3" \
  "openclaw-dryrun-invalid-traversal" \
  --phase3-run-dir "operations/harness-phase3/runs/../runs/${PHASE3_RUN_ID}"

run_expect_fail_no_dryrun_dir \
  "invalid-outside-phase3" \
  "openclaw-dryrun-invalid-outside" \
  --phase3-run-dir "operations/harness-phase4/runs/${WRAPPER_RUN_ID}"

mkdir -p "${MISSING_REPORT_PHASE3_RUN_DIR}/staging/runtime-ready-applied"
run_expect_fail_no_dryrun_dir \
  "invalid-missing-phase3-report" \
  "openclaw-dryrun-invalid-missing-report" \
  --phase3-run-dir "operations/harness-phase3/runs/${MISSING_REPORT_PHASE3_RUN_ID}"

mkdir -p "${REPORT_FAIL_PHASE3_RUN_DIR}/staging/runtime-ready-applied"
cat > "${REPORT_FAIL_PHASE3_RUN_DIR}/report.json" <<'EOF'
{
  "overall_status": "fail"
}
EOF
run_expect_fail_no_dryrun_dir \
  "invalid-phase3-report-not-pass" \
  "openclaw-dryrun-invalid-report-not-pass" \
  --phase3-run-dir "operations/harness-phase3/runs/${REPORT_FAIL_PHASE3_RUN_ID}"

live_surface_after="$(snapshot_repo_local_live_surfaces)"
[[ "${live_surface_before}" == "${live_surface_after}" ]] || fail "repo-local live OpenClaw-like surfaces changed"

echo "PASS OpenClaw dry-run adapter valid run"
echo "PASS OpenClaw dry-run adapter rejects invalid inputs"
echo "PASS OpenClaw dry-run adapter performed no live OpenClaw writes"
