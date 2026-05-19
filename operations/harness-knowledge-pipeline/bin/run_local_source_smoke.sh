#!/usr/bin/env bash
set -u

if [[ $# -ne 2 ]]; then
  echo "usage: run_local_source_smoke.sh <run-id> <repo-local-source>" >&2
  exit 2
fi

RUN_ID="$1"
SOURCE_REF="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${HARNESS_ROOT}/../.." && pwd)"
PYTHON_BIN="${KNOWLEDGE_PIPELINE_PYTHON_BIN:-python}"

CAPTURE_EXIT=0
"${PYTHON_BIN}" "${SCRIPT_DIR}/capture_local_source.py" \
  --repo-root "${REPO_ROOT}" \
  --run-id "${RUN_ID}" \
  --source "${SOURCE_REF}" || CAPTURE_EXIT=$?

VALIDATE_EXIT=${CAPTURE_EXIT}
if [[ "${CAPTURE_EXIT}" -eq 0 ]]; then
  "${PYTHON_BIN}" "${SCRIPT_DIR}/validate_knowledge_run.py" \
    --repo-root "${REPO_ROOT}" \
    --run-id "${RUN_ID}" || VALIDATE_EXIT=$?
fi

REPORT_EXIT=0
"${PYTHON_BIN}" "${SCRIPT_DIR}/render_knowledge_report.py" \
  --repo-root "${REPO_ROOT}" \
  --run-id "${RUN_ID}" || REPORT_EXIT=$?

if [[ "${REPORT_EXIT}" -ne 0 && "${REPORT_EXIT}" -ne 3 ]]; then
  exit "${REPORT_EXIT}"
fi

if [[ "${VALIDATE_EXIT}" -ne 0 ]]; then
  exit "${VALIDATE_EXIT}"
fi

exit 0
