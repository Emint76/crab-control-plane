#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${E2E_ROOT}/../.." && pwd)"
PHASE2_ROOT="${REPO_ROOT}/operations/harness-phase2"
PHASE3_ROOT="${REPO_ROOT}/operations/harness-phase3"
PHASE4_ROOT="${REPO_ROOT}/operations/harness-phase4"

if [[ -n "${E2E_PYTHON_BIN:-}" ]]; then
  PYTHON_BIN="${E2E_PYTHON_BIN}"
elif [[ -n "${PHASE4_PYTHON_BIN:-}" ]]; then
  PYTHON_BIN="${PHASE4_PYTHON_BIN}"
elif [[ -n "${PHASE3_PYTHON_BIN:-}" ]]; then
  PYTHON_BIN="${PHASE3_PYTHON_BIN}"
elif [[ -n "${PHASE2_PYTHON_BIN:-}" ]]; then
  PYTHON_BIN="${PHASE2_PYTHON_BIN}"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
else
  echo "FAIL python runtime not found; set E2E_PYTHON_BIN or install python/python3" >&2
  exit 1
fi
export PHASE2_PYTHON_BIN="${PHASE2_PYTHON_BIN:-${PYTHON_BIN}}"
export PHASE3_PYTHON_BIN="${PHASE3_PYTHON_BIN:-${PYTHON_BIN}}"
export PHASE4_PYTHON_BIN="${PHASE4_PYTHON_BIN:-${PYTHON_BIN}}"

PHASE2_RUN_ID="smoke-e2e-phase2"
PHASE3_RUN_ID="smoke-e2e-phase3"
WRAPPER_RUN_ID="smoke-e2e-wrapper"
TARGET_RUN_ID="smoke-e2e-target"

PHASE2_RUN_DIR="${PHASE2_ROOT}/runs/${PHASE2_RUN_ID}"
PHASE3_RUN_DIR="${PHASE3_ROOT}/runs/${PHASE3_RUN_ID}"
WRAPPER_RUN_DIR="${PHASE4_ROOT}/runs/${WRAPPER_RUN_ID}"
TARGET_RUN_DIR="${PHASE4_ROOT}/runs/${TARGET_RUN_ID}"
EXECUTION_TARGET_JSON="${TARGET_RUN_DIR}/execution_target.json"

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

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
}

assert_dir() {
  local path="$1"
  [[ -d "${path}" ]] || fail "missing directory: ${path}"
}

assert_absent() {
  local path="$1"
  [[ ! -e "${path}" ]] || fail "unexpected path exists: ${path}"
}

assert_file_text_equals() {
  local path="$1"
  local expected="$2"
  assert_file "${path}"
  local actual
  actual="$(tr -d '\r\n' < "${path}")"
  [[ "${actual}" == "${expected}" ]] || fail "${path} expected ${expected}, got ${actual}"
}

cd "${REPO_ROOT}"

safe_rm_generated_dir "${PHASE2_RUN_DIR}" "${PHASE2_ROOT}/runs" "${PHASE2_RUN_ID}"
safe_rm_generated_dir "${PHASE3_RUN_DIR}" "${PHASE3_ROOT}/runs" "${PHASE3_RUN_ID}"
safe_rm_generated_dir "${WRAPPER_RUN_DIR}" "${PHASE4_ROOT}/runs" "${WRAPPER_RUN_ID}"
safe_rm_generated_dir "${TARGET_RUN_DIR}" "${PHASE4_ROOT}/runs" "${TARGET_RUN_ID}"

bash operations/harness-phase2/bin/run_phase2_bundle.sh "${PHASE2_RUN_ID}"

assert_file_text_equals "${PHASE2_RUN_DIR}/exit_code" "0"
assert_file "${PHASE2_RUN_DIR}/handoff_ready.json"
assert_dir "${PHASE2_RUN_DIR}/output/runtime-ready"
assert_file "${PHASE2_RUN_DIR}/checks/run_dir_invariants.json"

mkdir -p "${TARGET_RUN_DIR}"
cat > "${EXECUTION_TARGET_JSON}" <<EOF
{
  "target_runtime": "openclaw",
  "target_kind": "phase3_staging",
  "target_ref": "operations/harness-phase3/runs/${PHASE3_RUN_ID}/staging/runtime-ready-applied",
  "apply_mode": "staged",
  "approval_ref": "operations/harness-phase2/runs/${PHASE2_RUN_ID}/handoff_ready.json",
  "invoked_by": "smoke-e2e"
}
EOF

bash operations/harness-phase4/bin/run_phase4_wrapper.sh \
  --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
  --execution-target-json "operations/harness-phase4/runs/${TARGET_RUN_ID}/execution_target.json" \
  --phase3-run-id "${PHASE3_RUN_ID}" \
  --operator smoke-e2e \
  --wrapper-run-id "${WRAPPER_RUN_ID}"

assert_file_text_equals "${WRAPPER_RUN_DIR}/wrapper_exit_code" "0"
assert_file "${WRAPPER_RUN_DIR}/wrapper_meta.json"
assert_file "${WRAPPER_RUN_DIR}/preflight.json"
assert_file "${WRAPPER_RUN_DIR}/phase3_invocation.json"
assert_file "${WRAPPER_RUN_DIR}/wrapper_summary.md"

assert_file_text_equals "${PHASE3_RUN_DIR}/exit_code" "0"
assert_file "${PHASE3_RUN_DIR}/report.json"
assert_file "${PHASE3_RUN_DIR}/report.md"
assert_file "${PHASE3_RUN_DIR}/checks/execution_target_validation.json"
assert_dir "${PHASE3_RUN_DIR}/staging/runtime-ready-applied"

assert_absent "${WRAPPER_RUN_DIR}/report.json"
assert_absent "${WRAPPER_RUN_DIR}/report.md"
assert_absent "${WRAPPER_RUN_DIR}/exit_code"
assert_absent "${WRAPPER_RUN_DIR}/execution_result.json"

"${PYTHON_BIN}" - \
  "${PHASE2_RUN_DIR}/handoff_ready.json" \
  "${PHASE3_RUN_DIR}/report.json" \
  "${WRAPPER_RUN_DIR}/preflight.json" \
  "${WRAPPER_RUN_DIR}/phase3_invocation.json" \
  "${WRAPPER_RUN_DIR}/wrapper_meta.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path


def read_json(path_text: str) -> dict[str, object]:
    payload = json.loads(Path(path_text).read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise AssertionError(f"{path_text} must contain a JSON object")
    return payload


handoff = read_json(sys.argv[1])
phase3_report = read_json(sys.argv[2])
preflight = read_json(sys.argv[3])
invocation = read_json(sys.argv[4])
wrapper_meta = read_json(sys.argv[5])

handoff_status = handoff.get("status")
handoff_verdict = handoff.get("verdict")
assert handoff_status in {"ready", "pass"} or handoff_verdict in {"ready", "pass"}, handoff
assert phase3_report.get("overall_status") == "pass", phase3_report
assert preflight.get("status") == "pass", preflight
assert invocation.get("phase3_invoked") is True, invocation
assert invocation.get("phase3_exit_status") == 0, invocation
assert wrapper_meta.get("profile") == "thin-wrapper", wrapper_meta
PY

echo "PASS smoke-e2e repo-native only: no live OpenClaw runtime mutation"
