#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd -P)"
VALIDATOR="${REPO_ROOT}/operations/harness-openclaw-safety-validation/bin/validate_no_secret_leakage.sh"
DRYRUN_ROOT="${REPO_ROOT}/operations/harness-openclaw-dryrun"
PHASE3_ROOT="${REPO_ROOT}/operations/harness-phase3"

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
else
  echo "FAIL python runtime not found; install python or python3" >&2
  exit 1
fi

export OPENCLAW_DRYRUN_PYTHON_BIN="${OPENCLAW_DRYRUN_PYTHON_BIN:-${PYTHON_BIN}}"
export PHASE3_PYTHON_BIN="${PHASE3_PYTHON_BIN:-${PYTHON_BIN}}"

PHASE3_RUN_ID="no-secret-synthetic-phase3"
DRYRUN_ID="openclaw-dryrun-valid"
VALID_RUN_DIR="${DRYRUN_ROOT}/runs/${DRYRUN_ID}"
PHASE3_RUN_DIR="${PHASE3_ROOT}/runs/${PHASE3_RUN_ID}"
TMP_ROOT="$(mktemp -d)"

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

cleanup_generated() {
  safe_rm_generated_dir "${VALID_RUN_DIR}" "${DRYRUN_ROOT}/runs" "${DRYRUN_ID}"
  safe_rm_generated_dir "${PHASE3_RUN_DIR}" "${PHASE3_ROOT}/runs" "${PHASE3_RUN_ID}"
}

cleanup() {
  cleanup_generated
  if [[ -n "${TMP_ROOT:-}" && "${TMP_ROOT}" == /tmp/* && -d "${TMP_ROOT}" ]]; then
    rm -rf "${TMP_ROOT}"
  fi
}
trap cleanup EXIT

assert_pass_output() {
  local output_file="$1"
  "${PYTHON_BIN}" - "${output_file}" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload["status"] == "pass", payload
assert payload["files_scanned"] > 0, payload
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
assert payload["files_scanned"] >= 0, payload
assert isinstance(payload["violations"], list) and payload["violations"], payload
for violation in payload["violations"]:
    path = violation.get("path")
    if path is not None:
        assert not path.startswith("/"), payload
        assert "/mnt/" not in path, payload
        assert "/home/" not in path, payload
        assert "C:\\" not in path, payload
PY
}

run_expect_fail() {
  local label="$1"
  shift
  local output_file="${TMP_ROOT}/${label}.json"
  if bash "${VALIDATOR}" "$@" > "${output_file}"; then
    fail "expected no-secret validation failure for ${label}"
  fi
  assert_fail_output "${output_file}"
}

assert_file_unchanged_after_failure() {
  local label="$1"
  local path="$2"
  local expected="$3"
  run_expect_fail "${label}" --evidence-dir "operations/harness-openclaw-dryrun/runs/${DRYRUN_ID}"
  [[ -f "${path}" ]] || fail "validator deleted leaking file: ${path}"
  [[ "$(cat "${path}")" == "${expected}" ]] || fail "validator rewrote leaking file: ${path}"
  rm -f -- "${path}"
}

cd "${REPO_ROOT}"
mkdir -p "${DRYRUN_ROOT}/runs"
cleanup_generated

mkdir -p "${PHASE3_RUN_DIR}/staging/runtime-ready-applied"
cat > "${PHASE3_RUN_DIR}/report.json" <<'JSON'
{
  "overall_status": "pass"
}
JSON
cat > "${PHASE3_RUN_DIR}/staging/runtime-ready-applied/sample.json" <<'JSON'
{
  "fixture": "no-secret-leakage-validation"
}
JSON

bash operations/harness-openclaw-dryrun/bin/run_openclaw_dry_run.sh \
  --phase3-run-dir "operations/harness-phase3/runs/${PHASE3_RUN_ID}" \
  --run-id "${DRYRUN_ID}"

VALID_OUTPUT="${TMP_ROOT}/valid.json"
bash "${VALIDATOR}" --evidence-dir "operations/harness-openclaw-dryrun/runs/${DRYRUN_ID}" > "${VALID_OUTPUT}"
assert_pass_output "${VALID_OUTPUT}"

"${PYTHON_BIN}" - "${VALID_RUN_DIR}/checks/no_secret_leakage_validation.json" "${VALID_RUN_DIR}/dry_run_report.json" <<'PY'
import json
import sys
from pathlib import Path

no_secret = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
report = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8-sig"))
assert no_secret["status"] == "pass", no_secret
assert no_secret["files_scanned"] > 0, no_secret
assert no_secret["violations"] == [], no_secret
assert report["checks"]["no_secret_leakage_validation"] == "pass", report
PY

FORBIDDEN_FILE="${VALID_RUN_DIR}/.env"
FORBIDDEN_CONTENT="PLACEHOLDER_ONLY=true"
printf '%s' "${FORBIDDEN_CONTENT}" > "${FORBIDDEN_FILE}"
assert_file_unchanged_after_failure "forbidden-filename" "${FORBIDDEN_FILE}" "${FORBIDDEN_CONTENT}"

PRIVATE_KEY_FILE="${VALID_RUN_DIR}/leak_private_key.txt"
PRIVATE_KEY_CONTENT="-----BEGIN ""PRIVATE ""KEY-----"
printf '%s' "${PRIVATE_KEY_CONTENT}" > "${PRIVATE_KEY_FILE}"
assert_file_unchanged_after_failure "private-key-block" "${PRIVATE_KEY_FILE}" "${PRIVATE_KEY_CONTENT}"

KEY_ASSIGNMENT_FILE="${VALID_RUN_DIR}/leak_api_key.txt"
KEY_ASSIGNMENT_CONTENT="OPENAI_""API""_KEY=""sk-test-secret-value"
printf '%s' "${KEY_ASSIGNMENT_CONTENT}" > "${KEY_ASSIGNMENT_FILE}"
assert_file_unchanged_after_failure "api-key-assignment" "${KEY_ASSIGNMENT_FILE}" "${KEY_ASSIGNMENT_CONTENT}"

GITHUB_TOKEN_FILE="${VALID_RUN_DIR}/leak_github_token.txt"
GITHUB_TOKEN_CONTENT="token=ghp_1234567890ABCDEFGHIJabcd"
printf '%s' "${GITHUB_TOKEN_CONTENT}" > "${GITHUB_TOKEN_FILE}"
assert_file_unchanged_after_failure "github-token-like-string" "${GITHUB_TOKEN_FILE}" "${GITHUB_TOKEN_CONTENT}"

run_expect_fail "absolute-evidence-dir" --evidence-dir "${VALID_RUN_DIR}"
run_expect_fail "outside-approved-surface" --evidence-dir "operations/harness-phase3/runs/${PHASE3_RUN_ID}"
run_expect_fail "traversal-evidence-dir" --evidence-dir "operations/harness-openclaw-dryrun/runs/../runs/${DRYRUN_ID}"

echo "PASS no-secret-leakage validation: repo-local dry-run evidence only, no mutations, no secrets required"
