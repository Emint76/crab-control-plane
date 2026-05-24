#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${HARNESS_ROOT}/../.." && pwd)"
RUNS_ROOT="${HARNESS_ROOT}/runs"
CAPTURE_RUN_ID="knowledge-smoke-capture-only-test"
SEMANTIC_RUN_ID="knowledge-smoke-semantic-required-test"
BAD_PYTHON_RUN_ID="knowledge-smoke-bad-python-test"
SOURCE_REF="control-plane/policy/ADMISSION_POLICY.md"

PYTHON_BIN="${KNOWLEDGE_PIPELINE_TEST_PYTHON_BIN:-${KNOWLEDGE_PIPELINE_PYTHON_BIN:-}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set KNOWLEDGE_PIPELINE_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi

fail() {
  echo "FAIL $*" >&2
  exit 1
}

safe_remove_run_dir() {
  local run_id="$1"
  "${PYTHON_BIN}" - "${RUNS_ROOT}" "${run_id}" <<'PY'
from __future__ import annotations

import shutil
import sys
from pathlib import Path

runs_root = Path(sys.argv[1]).resolve(strict=False)
run_id = sys.argv[2]
target = (runs_root / run_id).resolve(strict=False)
try:
    relative = target.relative_to(runs_root)
except ValueError:
    print(f"refusing to remove outside knowledge runs: {target}", file=sys.stderr)
    raise SystemExit(1)
if len(relative.parts) != 1 or relative.parts[0] != run_id:
    print(f"refusing to remove non-direct knowledge run child: {target}", file=sys.stderr)
    raise SystemExit(1)
shutil.rmtree(target, ignore_errors=True)
PY
}

cleanup() {
  safe_remove_run_dir "${CAPTURE_RUN_ID}"
  safe_remove_run_dir "${SEMANTIC_RUN_ID}"
  safe_remove_run_dir "${BAD_PYTHON_RUN_ID}"
}

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
}

assert_absent() {
  local path="$1"
  [[ ! -e "${path}" ]] || fail "unexpected path exists: ${path}"
}

assert_exit_code_file() {
  local run_id="$1"
  local expected="$2"
  local actual
  actual="$(tr -d '\r\n' < "${RUNS_ROOT}/${run_id}/exit_code")"
  [[ "${actual}" == "${expected}" ]] || fail "${run_id} exit_code expected ${expected}, got ${actual}"
}

cd "${REPO_ROOT}"
mkdir -p "${RUNS_ROOT}"
cleanup
trap cleanup EXIT

# Default mode is capture-only and must pass without semantic outputs.
KNOWLEDGE_PIPELINE_PYTHON_BIN="${PYTHON_BIN}" \
  bash operations/harness-knowledge-pipeline/bin/run_local_source_smoke.sh \
    "${CAPTURE_RUN_ID}" \
    "${SOURCE_REF}"

CAPTURE_RUN_DIR="${RUNS_ROOT}/${CAPTURE_RUN_ID}"
assert_file "${CAPTURE_RUN_DIR}/run_meta.json"
assert_file "${CAPTURE_RUN_DIR}/input/source.md"
assert_file "${CAPTURE_RUN_DIR}/input/source.sha256"
assert_file "${CAPTURE_RUN_DIR}/input/source_capture_package.json"
assert_file "${CAPTURE_RUN_DIR}/input/task_packet.json"
assert_file "${CAPTURE_RUN_DIR}/checks/expected_core_files.json"
assert_file "${CAPTURE_RUN_DIR}/checks/source_capture_schema.json"
assert_file "${CAPTURE_RUN_DIR}/checks/task_packet_schema.json"
assert_file "${CAPTURE_RUN_DIR}/checks/source_hash_validation.json"
assert_file "${CAPTURE_RUN_DIR}/checks/no_live_surface_validation.json"
assert_file "${CAPTURE_RUN_DIR}/report.json"
assert_file "${CAPTURE_RUN_DIR}/report.md"
assert_file "${CAPTURE_RUN_DIR}/exit_code"
assert_absent "${CAPTURE_RUN_DIR}/output/normalized_note.json"
assert_exit_code_file "${CAPTURE_RUN_ID}" "0"

"${PYTHON_BIN}" - "${CAPTURE_RUN_DIR}/report.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert report["mode"] == "capture-only", report
assert report["semantic_outputs_required"] is False, report
assert report["status"] == "pass", report
assert report["exit_code"] == 0, report
assert not any(check.get("status") == "awaiting_semantic_outputs" for check in report["checks"]), report
PY

# Explicit semantic-required mode preserves awaiting-semantic behavior.
set +e
KNOWLEDGE_PIPELINE_PYTHON_BIN="${PYTHON_BIN}" \
  bash operations/harness-knowledge-pipeline/bin/run_local_source_smoke.sh \
    --mode semantic-required \
    "${SEMANTIC_RUN_ID}" \
    "${SOURCE_REF}"
semantic_status=$?
set -e
[[ "${semantic_status}" -eq 3 ]] || fail "semantic-required expected exit 3, got ${semantic_status}"
assert_exit_code_file "${SEMANTIC_RUN_ID}" "3"

"${PYTHON_BIN}" - "${RUNS_ROOT}/${SEMANTIC_RUN_ID}/report.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert report["mode"] == "semantic-required", report
assert report["semantic_outputs_required"] is True, report
assert report["status"] == "awaiting_semantic_outputs", report
assert report["exit_code"] == 3, report
PY

# Explicit unavailable Python override must fail before capture with a clear diagnostic.
set +e
KNOWLEDGE_PIPELINE_PYTHON_BIN="/definitely/missing/python-for-knowledge-smoke" \
  bash operations/harness-knowledge-pipeline/bin/run_local_source_smoke.sh \
    --mode capture-only \
    "${BAD_PYTHON_RUN_ID}" \
    "${SOURCE_REF}" >"${RUNS_ROOT}/bad-python.stdout" 2>"${RUNS_ROOT}/bad-python.stderr"
bad_python_status=$?
set -e
[[ "${bad_python_status}" -ne 0 ]] || fail "missing python override unexpectedly succeeded"
grep -Fq "KNOWLEDGE_PIPELINE_PYTHON_BIN" "${RUNS_ROOT}/bad-python.stderr" || fail "missing diagnostic did not mention KNOWLEDGE_PIPELINE_PYTHON_BIN"
grep -Fq "python" "${RUNS_ROOT}/bad-python.stderr" || fail "missing diagnostic did not mention python"
assert_absent "${RUNS_ROOT}/${BAD_PYTHON_RUN_ID}"
rm -f -- "${RUNS_ROOT}/bad-python.stdout" "${RUNS_ROOT}/bad-python.stderr"

echo "PASS knowledge capture-only smoke exits 0 without semantic outputs"
echo "PASS knowledge semantic-required smoke exits 3 without semantic outputs"
echo "PASS knowledge runner reports unavailable Python override clearly"
