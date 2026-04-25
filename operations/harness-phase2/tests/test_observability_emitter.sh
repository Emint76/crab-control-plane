#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE2_ROOT}/../.." && pwd)"
PYTHON_BIN="${PHASE2_PYTHON_BIN:-python}"
RUN_ID="observability-emitter-test"
REPORT_PATH="${PHASE2_ROOT}/reports/observability-sample.jsonl"

if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "FAIL python runtime not found: ${PYTHON_BIN}" >&2
  exit 1
fi

had_report="false"
original_report=""
if [[ -f "${REPORT_PATH}" ]]; then
  had_report="true"
  original_report="$(cat "${REPORT_PATH}")"
fi

restore_report() {
  if [[ "${had_report}" == "true" ]]; then
    printf '%s' "${original_report}" > "${REPORT_PATH}"
    if [[ -n "${original_report}" ]]; then
      printf '\n' >> "${REPORT_PATH}"
    fi
  else
    rm -f "${REPORT_PATH}"
  fi
}
trap restore_report EXIT

before_observability_status="$(git -C "${REPO_ROOT}" status --short -- observability)"

cd "${REPO_ROOT}"
"${PYTHON_BIN}" operations/harness-phase2/bin/emit_observability_record.py . "${RUN_ID}"

[[ -f "${REPORT_PATH}" ]] || { echo "FAIL missing observability JSONL: ${REPORT_PATH}" >&2; exit 1; }

last_line="$(tail -n 1 "${REPORT_PATH}")"
[[ -n "${last_line}" ]] || { echo "FAIL observability JSONL last line is empty" >&2; exit 1; }

"${PYTHON_BIN}" - "${last_line}" <<'PY'
from __future__ import annotations

import json
import sys
from datetime import datetime

payload = json.loads(sys.argv[1])
required = [
    "run_id",
    "actor",
    "task_id",
    "action_type",
    "timestamp",
    "outcome",
    "artifact_refs",
    "warnings",
]
missing = [field for field in required if field not in payload]
if missing:
    raise SystemExit(f"missing required fields: {missing}")

assert payload["run_id"] == "observability-emitter-test"
assert payload["actor"] == "phase2-observability-emitter"
assert payload["task_id"] == "phase2-observability-sample"
assert payload["action_type"] == "phase2.check_layer.observability_sample"
assert payload["outcome"] == "sample_emitted"
assert isinstance(payload["artifact_refs"], list)
assert isinstance(payload["warnings"], list)

timestamp = payload["timestamp"]
if not isinstance(timestamp, str) or not timestamp.endswith("Z"):
    raise SystemExit("timestamp must be a UTC ISO8601 string ending in Z")
datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
PY

after_observability_status="$(git -C "${REPO_ROOT}" status --short -- observability)"
if [[ "${before_observability_status}" != "${after_observability_status}" ]]; then
  echo "FAIL root observability/ status changed" >&2
  exit 1
fi

printf 'PASS observability emitter JSONL\n'
