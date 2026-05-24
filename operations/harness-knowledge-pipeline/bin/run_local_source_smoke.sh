#!/usr/bin/env bash
set -u

usage() {
  echo "usage: run_local_source_smoke.sh [--mode capture-only|semantic-required] <run-id> <repo-local-source>" >&2
}

MODE="capture-only"
if [[ $# -ge 2 && "${1:-}" == "--mode" ]]; then
  if [[ $# -lt 4 ]]; then
    usage
    exit 2
  fi
  MODE="$2"
  shift 2
fi

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

case "${MODE}" in
  capture-only|semantic-required)
    ;;
  *)
    echo "ERROR: invalid knowledge pipeline smoke mode: ${MODE}" >&2
    usage
    exit 2
    ;;
esac

RUN_ID="$1"
SOURCE_REF="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${HARNESS_ROOT}/../.." && pwd)"

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
"${PYTHON_BIN}" "${SCRIPT_DIR}/capture_local_source.py" \
  --repo-root "${REPO_ROOT}" \
  --run-id "${RUN_ID}" \
  --source "${SOURCE_REF}" || CAPTURE_EXIT=$?

VALIDATE_EXIT=${CAPTURE_EXIT}
if [[ "${CAPTURE_EXIT}" -eq 0 ]]; then
  "${PYTHON_BIN}" "${SCRIPT_DIR}/validate_knowledge_run.py" \
    --repo-root "${REPO_ROOT}" \
    --run-id "${RUN_ID}" \
    --mode "${MODE}" || VALIDATE_EXIT=$?
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

exit 0
