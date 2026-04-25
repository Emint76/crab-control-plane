#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE2_ROOT}/../.." && pwd)"
PYTHON_BIN="${PHASE2_PYTHON_BIN:-python}"
TMP_PARENT="${TMPDIR:-/tmp}"
TMP_ROOT="$(mktemp -d "${TMP_PARENT%/}/phase2-standalone-checks.XXXXXX")"
CASE_INDEX=0

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && -d "${TMP_ROOT}" && "${TMP_ROOT}" == "${TMP_PARENT%/}"/phase2-standalone-checks.* ]]; then
    rm -rf "${TMP_ROOT}"
  fi
}
trap cleanup EXIT

if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  echo "FAIL python runtime not found: ${PYTHON_BIN}" >&2
  exit 1
fi

cd "${REPO_ROOT}"

pass_case() {
  local label="$1"
  shift
  if "$@"; then
    printf 'PASS %s\n' "${label}"
  else
    printf 'FAIL %s\n' "${label}" >&2
    exit 1
  fi
}

fail_case() {
  local label="$1"
  local log_path
  shift
  CASE_INDEX=$((CASE_INDEX + 1))
  log_path="${TMP_ROOT}/case-${CASE_INDEX}.log"

  if "$@" >"${log_path}" 2>&1; then
    printf 'FAIL %s: expected failure but command passed\n' "${label}" >&2
    cat "${log_path}" >&2
    exit 1
  fi
  printf 'PASS %s\n' "${label}"
}

pass_case \
  "standalone valid task packet schema" \
  bash operations/harness-phase2/bin/validate_json_against_schema.sh \
    task_packet.schema.json \
    operations/harness-phase2/tests/fixtures/valid-task-packet.json

fail_case \
  "standalone invalid task packet rejected by schema" \
  bash operations/harness-phase2/bin/validate_json_against_schema.sh \
    task_packet.schema.json \
    operations/harness-phase2/tests/fixtures/invalid-task-packet.json

pass_case \
  "standalone valid placement policy" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_placement_policy.py \
    . \
    operations/harness-phase2/tests/fixtures/valid-placement-decision.json

fail_case \
  "standalone policy-invalid KB placement rejected" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_placement_policy.py \
    . \
    operations/harness-phase2/tests/fixtures/policy-invalid-kb-placement.json

pass_case \
  "standalone valid admission policy" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py \
    . \
    operations/harness-phase2/tests/fixtures/admission-valid-source-capture-package.json

fail_case \
  "standalone admission missing source capture package rejected" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py \
    . \
    operations/harness-phase2/tests/fixtures/admission-missing-source-capture-package.json

fail_case \
  "standalone admission invalid artifact_type rejected" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py \
    . \
    operations/harness-phase2/tests/fixtures/admission-invalid-artifact-type.json
