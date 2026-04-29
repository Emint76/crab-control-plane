#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"
VALIDATOR="${REPO_ROOT}/operations/harness-openclaw-target-validation/bin/validate_disposable_target_path.sh"

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
else
  echo "FAIL python runtime not found; install python or python3" >&2
  exit 1
fi

TMP_ROOT="$(mktemp -d)"
REPO_TMP="${REPO_ROOT}/operations/harness-openclaw-target-validation/tests/tmp-repo-target-inside"

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && "${TMP_ROOT}" == /tmp/* && -d "${TMP_ROOT}" ]]; then
    rm -rf "${TMP_ROOT}"
  fi
  if [[ -n "${REPO_TMP:-}" && "${REPO_TMP}" == "${REPO_ROOT}/operations/harness-openclaw-target-validation/tests/tmp-"* && -d "${REPO_TMP}" ]]; then
    rm -rf "${REPO_TMP}"
  fi
}
trap cleanup EXIT

APPROVED_ROOT="${TMP_ROOT}/approved"
WORKSPACE_TARGET="${APPROVED_ROOT}/disposable-openclaw-workspace"
STATE_TARGET="${APPROVED_ROOT}/disposable-openclaw-state"
OUTSIDE_TARGET="${TMP_ROOT}/outside-target"
MISSING_MARKER_TARGET="${APPROVED_ROOT}/missing-marker-target"
WRONG_KIND_TARGET="${APPROVED_ROOT}/wrong-kind-target"
DISPOSABLE_FALSE_TARGET="${APPROVED_ROOT}/disposable-false-target"

mkdir -p "${WORKSPACE_TARGET}" "${STATE_TARGET}" "${OUTSIDE_TARGET}" "${MISSING_MARKER_TARGET}" "${WRONG_KIND_TARGET}" "${DISPOSABLE_FALSE_TARGET}"
mkdir -p "${REPO_TMP}"

cat > "${WORKSPACE_TARGET}/.crab-disposable-target.json" <<'JSON'
{
  "kind": "openclaw-workspace",
  "disposable": true
}
JSON

cat > "${STATE_TARGET}/.crab-disposable-target.json" <<'JSON'
{
  "kind": "openclaw-state",
  "disposable": true
}
JSON

cat > "${WRONG_KIND_TARGET}/.crab-disposable-target.json" <<'JSON'
{
  "kind": "openclaw-state",
  "disposable": true
}
JSON

cat > "${DISPOSABLE_FALSE_TARGET}/.crab-disposable-target.json" <<'JSON'
{
  "kind": "openclaw-workspace",
  "disposable": false
}
JSON

assert_pass_output() {
  local output_file="$1"
  "${PYTHON_BIN}" - "${output_file}" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["status"] == "pass", payload
assert payload["under_approved_root"] is True, payload
assert payload["outside_repo_root"] is True, payload
assert payload["marker_verified"] is True, payload
assert payload["violations"] == [], payload
PY
}

assert_fail_output() {
  local output_file="$1"
  "${PYTHON_BIN}" - "${output_file}" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["status"] == "fail", payload
assert isinstance(payload["violations"], list) and payload["violations"], payload
PY
}

run_pass() {
  local name="$1"
  shift
  local output_file="${TMP_ROOT}/${name}.json"
  bash "${VALIDATOR}" "$@" > "${output_file}"
  assert_pass_output "${output_file}"
}

run_fail() {
  local name="$1"
  shift
  local output_file="${TMP_ROOT}/${name}.json"
  if bash "${VALIDATOR}" "$@" > "${output_file}"; then
    echo "FAIL expected validator failure for ${name}" >&2
    exit 1
  fi
  assert_fail_output "${output_file}"
}

run_pass workspace-valid \
  --target-type workspace \
  --target-path "${WORKSPACE_TARGET}" \
  --approved-root "${APPROVED_ROOT}"

run_pass state-valid \
  --target-type state \
  --target-path "${STATE_TARGET}" \
  --approved-root "${APPROVED_ROOT}"

run_fail relative-target-path \
  --target-type workspace \
  --target-path relative/path \
  --approved-root "${APPROVED_ROOT}"

run_fail relative-approved-root \
  --target-type workspace \
  --target-path "${WORKSPACE_TARGET}" \
  --approved-root relative/root

run_fail outside-approved-root \
  --target-type workspace \
  --target-path "${OUTSIDE_TARGET}" \
  --approved-root "${APPROVED_ROOT}"

run_fail target-equal-approved-root \
  --target-type workspace \
  --target-path "${APPROVED_ROOT}" \
  --approved-root "${APPROVED_ROOT}"

run_fail target-inside-repo-root \
  --target-type workspace \
  --target-path "${REPO_TMP}" \
  --approved-root "${REPO_ROOT}"

run_fail missing-marker-file \
  --target-type workspace \
  --target-path "${MISSING_MARKER_TARGET}" \
  --approved-root "${APPROVED_ROOT}"

if [[ -e "${MISSING_MARKER_TARGET}/.crab-disposable-target.json" ]]; then
  echo "FAIL validator created missing marker file" >&2
  exit 1
fi

MISSING_DIR_TARGET="${APPROVED_ROOT}/validator-must-not-create-this"
run_fail missing-target-directory \
  --target-type workspace \
  --target-path "${MISSING_DIR_TARGET}" \
  --approved-root "${APPROVED_ROOT}"

if [[ -e "${MISSING_DIR_TARGET}" ]]; then
  echo "FAIL validator created missing target directory" >&2
  exit 1
fi

run_fail wrong-marker-kind \
  --target-type workspace \
  --target-path "${WRONG_KIND_TARGET}" \
  --approved-root "${APPROVED_ROOT}"

run_fail disposable-false \
  --target-type workspace \
  --target-path "${DISPOSABLE_FALSE_TARGET}" \
  --approved-root "${APPROVED_ROOT}"

run_fail invalid-target-type \
  --target-type live \
  --target-path "${WORKSPACE_TARGET}" \
  --approved-root "${APPROVED_ROOT}"

echo "PASS disposable target path validation: validation only, no OpenClaw writes, no secrets required"
