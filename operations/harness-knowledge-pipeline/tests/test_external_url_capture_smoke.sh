#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${HARNESS_ROOT}/../.." && pwd)"
RUNS_ROOT="${HARNESS_ROOT}/runs"
RUN_ID="knowledge-external-url-fixture-smoke-test"
FIXTURE_REF="operations/harness-knowledge-pipeline/tests/fixtures/external-url/example.html"
SOURCE_URL="https://example.com/source"

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
  safe_remove_run_dir "${RUN_ID}"
  safe_remove_run_dir "knowledge-external-url-fixture-invalid-test"
}

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
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

KNOWLEDGE_PIPELINE_PYTHON_BIN="${PYTHON_BIN}" \
  bash operations/harness-knowledge-pipeline/bin/run_external_url_capture_smoke.sh \
    "${RUN_ID}" \
    "${SOURCE_URL}" \
    "${FIXTURE_REF}"

RUN_DIR="${RUNS_ROOT}/${RUN_ID}"
assert_file "${RUN_DIR}/run_meta.json"
assert_file "${RUN_DIR}/input/raw_snapshot.html"
assert_file "${RUN_DIR}/input/raw_snapshot.sha256"
assert_file "${RUN_DIR}/input/source.md"
assert_file "${RUN_DIR}/input/source.sha256"
assert_file "${RUN_DIR}/input/retrieval_metadata.json"
assert_file "${RUN_DIR}/input/source_capture_package.json"
assert_file "${RUN_DIR}/input/task_packet.json"
assert_file "${RUN_DIR}/checks/external_url_boundary.json"
assert_file "${RUN_DIR}/checks/raw_snapshot_hash_validation.json"
assert_file "${RUN_DIR}/checks/extracted_text_hash_validation.json"
assert_file "${RUN_DIR}/checks/external_capture_metadata_validation.json"
assert_file "${RUN_DIR}/checks/source_capture_schema.json"
assert_file "${RUN_DIR}/checks/task_packet_schema.json"
assert_file "${RUN_DIR}/checks/no_live_surface_validation.json"
assert_file "${RUN_DIR}/report.json"
assert_file "${RUN_DIR}/report.md"
assert_file "${RUN_DIR}/exit_code"
assert_exit_code_file "${RUN_ID}" "0"

"${PYTHON_BIN}" - "${REPO_ROOT}" "${RUN_DIR}" "${SOURCE_URL}" <<'PY'
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

repo_root = Path(sys.argv[1])
run_dir = Path(sys.argv[2])
source_url = sys.argv[3]
source_capture = json.loads((run_dir / "input/source_capture_package.json").read_text(encoding="utf-8"))
metadata = json.loads((run_dir / "input/retrieval_metadata.json").read_text(encoding="utf-8"))
run_meta = json.loads((run_dir / "run_meta.json").read_text(encoding="utf-8"))
report = json.loads((run_dir / "report.json").read_text(encoding="utf-8"))
raw_bytes = (run_dir / "input/raw_snapshot.html").read_bytes()
source_bytes = (run_dir / "input/source.md").read_bytes()
raw_hash = hashlib.sha256(raw_bytes).hexdigest()
source_hash = hashlib.sha256(source_bytes).hexdigest()

schema = json.loads((repo_root / "control-plane/contracts/schemas/source_capture_package.schema.json").read_text(encoding="utf-8"))
errors = sorted(Draft202012Validator(schema).iter_errors(source_capture), key=lambda err: list(err.path))
assert not errors, [err.message for err in errors]

assert source_capture["canonical_pointer"] == source_url, source_capture
assert source_capture["stable_representation"].endswith("/input/raw_snapshot.html"), source_capture
assert not source_capture["stable_representation"].endswith("/input/source.md"), source_capture
assert source_capture["hash"] == f"sha256:{raw_hash}", source_capture
assert source_capture["capture_method"] == "manual-download", source_capture
assert metadata["network_performed"] is False, metadata
assert metadata["requested_url"] == source_url, metadata
assert metadata["normalized_url"] == source_url, metadata
assert metadata["raw_snapshot_sha256"] == f"sha256:{raw_hash}", metadata
assert metadata["extracted_text_sha256"] == f"sha256:{source_hash}", metadata
assert metadata["fixture_source_ref"].endswith("tests/fixtures/external-url/example.html"), metadata
for flag in ["openclaw_used", "docker_used", "network_used", "live_surface_used", "outside_git_paths_used", "auto_canonical_write_performed"]:
    assert run_meta[flag] is False, (flag, run_meta)
    assert report[flag] is False, (flag, report)
assert report["mode"] == "capture-only", report
assert report["status"] == "pass", report
assert report["exit_code"] == 0, report
PY

for unsafe_url in \
  "file:///etc/passwd" \
  "data:text/html,hello" \
  "javascript:alert(1)" \
  "ftp://example.com/source" \
  "http://localhost/" \
  "http://127.0.0.1/" \
  "http://10.0.0.1/" \
  "https://user:pass@example.com/private"; do
  set +e
  KNOWLEDGE_PIPELINE_PYTHON_BIN="${PYTHON_BIN}" \
    bash operations/harness-knowledge-pipeline/bin/run_external_url_capture_smoke.sh \
      "knowledge-external-url-fixture-invalid-test" \
      "${unsafe_url}" \
      "${FIXTURE_REF}" >/tmp/knowledge-external-url-invalid.out 2>/tmp/knowledge-external-url-invalid.err
  status=$?
  set -e
  [[ "${status}" -eq 2 ]] || fail "unsafe URL ${unsafe_url} expected exit 2, got ${status}"
  safe_remove_run_dir "knowledge-external-url-fixture-invalid-test"
done

printf 'PASS external URL fixture smoke\n'
