#!/usr/bin/env bash
set -u

usage() {
  echo "usage: run_external_url_capture_smoke.sh <run-id> <http-or-https-url> <repo-local-html-fixture>" >&2
}

if [[ $# -ne 3 ]]; then
  usage
  exit 2
fi

RUN_ID="$1"
SOURCE_URL="$2"
FIXTURE_REF="$3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${HARNESS_ROOT}/../.." && pwd)"
MODE="capture-only"

resolve_python_bin() {
  if [[ -n "${KNOWLEDGE_PIPELINE_PYTHON_BIN:-}" ]]; then
    if command -v "${KNOWLEDGE_PIPELINE_PYTHON_BIN}" >/dev/null 2>&1; then
      printf '%s\n' "${KNOWLEDGE_PIPELINE_PYTHON_BIN}"
      return 0
    fi
    echo "ERROR: KNOWLEDGE_PIPELINE_PYTHON_BIN is set but unavailable: ${KNOWLEDGE_PIPELINE_PYTHON_BIN}" >&2
    echo "Set KNOWLEDGE_PIPELINE_PYTHON_BIN to an executable Python interpreter, or unset it to allow python/python3 fallback." >&2
    return 1
  fi

  if command -v python >/dev/null 2>&1; then
    printf '%s\n' "python"
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "python3"
    return 0
  fi

  echo "ERROR: no Python interpreter found for knowledge pipeline smoke runner." >&2
  echo "Tried: KNOWLEDGE_PIPELINE_PYTHON_BIN if set, python, python3." >&2
  echo "Set KNOWLEDGE_PIPELINE_PYTHON_BIN=python3 or install python/python3." >&2
  return 1
}

PYTHON_BIN="$(resolve_python_bin)" || exit 2

CAPTURE_EXIT=0
"${PYTHON_BIN}" "${SCRIPT_DIR}/capture_external_url_fixture.py" \
  --repo-root "${REPO_ROOT}" \
  --run-id "${RUN_ID}" \
  --url "${SOURCE_URL}" \
  --fixture "${FIXTURE_REF}" || CAPTURE_EXIT=$?

if [[ "${CAPTURE_EXIT}" -ne 0 ]]; then
  exit "${CAPTURE_EXIT}"
fi

VALIDATE_EXIT=0
"${PYTHON_BIN}" "${SCRIPT_DIR}/validate_knowledge_run.py" \
  --repo-root "${REPO_ROOT}" \
  --run-id "${RUN_ID}" \
  --mode "${MODE}" || VALIDATE_EXIT=$?

EXTERNAL_VALIDATE_EXIT=0
if [[ "${VALIDATE_EXIT}" -eq 0 ]]; then
  "${PYTHON_BIN}" "${SCRIPT_DIR}/validate_external_capture.py" \
    --repo-root "${REPO_ROOT}" \
    --run-id "${RUN_ID}" || EXTERNAL_VALIDATE_EXIT=$?
fi

REPORT_EXIT=0
"${PYTHON_BIN}" "${SCRIPT_DIR}/render_knowledge_report.py" \
  --repo-root "${REPO_ROOT}" \
  --run-id "${RUN_ID}" \
  --mode "${MODE}" || REPORT_EXIT=$?

if [[ "${REPORT_EXIT}" -ne 0 && "${REPORT_EXIT}" -ne 3 ]]; then
  exit "${REPORT_EXIT}"
fi

if [[ "${VALIDATE_EXIT}" -ne 0 ]]; then
  exit "${VALIDATE_EXIT}"
fi

if [[ "${EXTERNAL_VALIDATE_EXIT}" -ne 0 ]]; then
  exit "${EXTERNAL_VALIDATE_EXIT}"
fi

exit 0
