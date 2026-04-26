#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE3_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE3_ROOT}/../.." && pwd)"
TMP_DIR="$(mktemp -d)"

PHASE3_PYTHON_BIN="${PHASE3_PYTHON_BIN:-python}"
export PHASE3_PYTHON_BIN
PYTHON_BIN="${PHASE3_PYTHON_BIN}"
export PHASE2_PYTHON_BIN="${PHASE2_PYTHON_BIN:-${PYTHON_BIN}}"

PHASE2_RUN_ID="phase3-report-shape-phase2-input"
PHASE2_RUN_DIR="${REPO_ROOT}/operations/harness-phase2/runs/${PHASE2_RUN_ID}"
RUN_ID="phase3-report-shape-test"
RUN_DIR="${PHASE3_ROOT}/runs/${RUN_ID}"
TARGET_DIR="${PHASE3_ROOT}/runs/${RUN_ID}-target"
TARGET_JSON="${TARGET_DIR}/execution_target.json"

cleanup() {
  rm -rf \
    "${TMP_DIR}" \
    "${PHASE2_RUN_DIR}" \
    "${RUN_DIR}" \
    "${TARGET_DIR}"
}

fail() {
  echo "FAIL $*" >&2
  exit 1
}

rm -rf "${PHASE2_RUN_DIR}" "${RUN_DIR}" "${TARGET_DIR}"
trap cleanup EXIT

bash "${REPO_ROOT}/operations/harness-phase2/bin/run_phase2_bundle.sh" "${PHASE2_RUN_ID}"

mkdir -p "${TARGET_DIR}"
cat > "${TARGET_JSON}" <<EOF
{
  "target_runtime": "openclaw",
  "target_kind": "phase3_staging",
  "target_ref": "operations/harness-phase3/runs/${RUN_ID}/staging/runtime-ready-applied",
  "apply_mode": "staged",
  "approval_ref": "manual://phase3-report-shape-test",
  "invoked_by": "test://phase3-report-shape"
}
EOF

bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
  --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
  --execution-target-json "operations/harness-phase3/runs/${RUN_ID}-target/execution_target.json" \
  --run-id "${RUN_ID}"

[[ -f "${RUN_DIR}/exit_code" ]] || fail "missing exit_code"
[[ "$(tr -d '\r\n' < "${RUN_DIR}/exit_code")" == "0" ]] || fail "exit_code must be 0"
[[ -f "${RUN_DIR}/report.json" ]] || fail "missing report.json"
[[ -f "${RUN_DIR}/report.md" ]] || fail "missing report.md"
[[ -f "${RUN_DIR}/timestamps.json" ]] || fail "missing timestamps.json"

"${PYTHON_BIN}" - "${RUN_DIR}/report.json" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


def iter_strings(value: Any, path: str = ""):
    if isinstance(value, str):
        yield path, value
    elif isinstance(value, dict):
        for key, item in value.items():
            child = str(key) if not path else f"{path}.{key}"
            yield from iter_strings(item, child)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from iter_strings(item, f"{path}[{index}]")


def is_unsafe_host_path(value: str) -> bool:
    if value.startswith("/"):
        return True
    if re.match(r"^[A-Za-z]:[\\/]", value):
        return True
    if "\\" in value:
        return True
    return any(token in value for token in ("/tmp/", "/home/", "/Users/", "/mnt/"))


report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
run_id = "phase3-report-shape-test"
canonical_run_dir = f"operations/harness-phase3/runs/{run_id}"

assert report["phase"] == "phase3", report
assert report["profile"] == "canonical-execution-owner", report
assert report["report_kind"] == "canonical-execution-report", report
assert report["canonical_run_dir"] == canonical_run_dir, report
assert report["write_surface"] == f"{canonical_run_dir}/", report
assert report["overall_status"] == "pass", report
assert report["input_refs"]["phase2_run_ref"], report
assert report["input_refs"]["phase2_runtime_ready_ref"], report
assert report["target"]["target_runtime"] == "openclaw", report
assert report["target"]["target_kind"] == "phase3_staging", report
assert report["step_summary"]["execution_target_validation"] == "pass", report
assert report["canonical_outputs"]["report_json"] == f"{canonical_run_dir}/report.json", report
assert report["runtime_statement"]["live_openclaw_runtime_mutation"] is False, report

assert report["summary"]["execution_target_validation"] == "pass", report

unsafe = [(path, value) for path, value in iter_strings(report) if is_unsafe_host_path(value)]
assert unsafe == [], unsafe
PY

grep -F "# Phase 3 canonical execution report" "${RUN_DIR}/report.md" >/dev/null || fail "missing canonical report title"
grep -F "profile: \`canonical-execution-owner\`" "${RUN_DIR}/report.md" >/dev/null || fail "missing profile in report.md"
grep -F "report_kind: \`canonical-execution-report\`" "${RUN_DIR}/report.md" >/dev/null || fail "missing report_kind in report.md"
grep -F "No live OpenClaw runtime mutation was performed." "${RUN_DIR}/report.md" >/dev/null || fail "missing runtime statement in report.md"
grep -F "Phase 4 wrapper execution was not performed." "${RUN_DIR}/report.md" >/dev/null || fail "missing Phase 4 runtime statement in report.md"

echo "PASS Phase 3 report shape"
