#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SELECTOR_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${SELECTOR_ROOT}/../.." && pwd -P)"
APPLY_ROOT="${REPO_ROOT}/operations/harness-openclaw-disposable-apply"
DRYRUN_ROOT="${REPO_ROOT}/operations/harness-openclaw-dryrun"
PHASE3_ROOT="${REPO_ROOT}/operations/harness-phase3"

PYTHON_BIN="${LOCAL_SELECTOR_TEST_PYTHON_BIN:-${OPENCLAW_DRYRUN_PYTHON_BIN:-${PHASE3_PYTHON_BIN:-${PHASE2_PYTHON_BIN:-}}}}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "FAIL python runtime not found; set LOCAL_SELECTOR_TEST_PYTHON_BIN or install python/python3" >&2
    exit 1
  fi
fi
export OPENCLAW_DRYRUN_PYTHON_BIN="${OPENCLAW_DRYRUN_PYTHON_BIN:-${PYTHON_BIN}}"
export PHASE3_PYTHON_BIN="${PHASE3_PYTHON_BIN:-${PYTHON_BIN}}"

PHASE3_RUN_ID="local-selector-synthetic-phase3"
DRYRUN_ID="openclaw-dryrun-valid"
APPLY_RUN_ID="controlled-disposable-apply-from-selector-valid"

PHASE3_RUN_DIR="${PHASE3_ROOT}/runs/${PHASE3_RUN_ID}"
DRYRUN_RUN_DIR="${DRYRUN_ROOT}/runs/${DRYRUN_ID}"
APPLY_RUN_DIR="${APPLY_ROOT}/runs/${APPLY_RUN_ID}"
TMP_ROOT="$(mktemp -d)"

WORKSPACE_APPROVED_ROOT="${TMP_ROOT}/approved-workspace-root"
STATE_APPROVED_ROOT="${TMP_ROOT}/approved-state-root"
WORKSPACE_TARGET="${WORKSPACE_APPROVED_ROOT}/disposable-openclaw-workspace"
STATE_TARGET="${STATE_APPROVED_ROOT}/disposable-openclaw-state"
VALID_SELECTOR="${TMP_ROOT}/disposable-target-selector.json"
INSIDE_REPO_SELECTOR="${SCRIPT_DIR}/selector-inside-repo.tmp.json"

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

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && "${TMP_ROOT}" == /tmp/* && -d "${TMP_ROOT}" ]]; then
    rm -rf -- "${TMP_ROOT}"
  fi
  rm -f -- "${INSIDE_REPO_SELECTOR}"
  safe_rm_generated_dir "${APPLY_RUN_DIR}" "${APPLY_ROOT}/runs" "${APPLY_RUN_ID}"
  for name in \
    controlled-disposable-apply-selector-relative \
    controlled-disposable-apply-selector-inside-repo \
    controlled-disposable-apply-selector-missing-field \
    controlled-disposable-apply-selector-extra-field \
    controlled-disposable-apply-selector-empty-approval; do
    safe_rm_generated_dir "${APPLY_ROOT}/runs/${name}" "${APPLY_ROOT}/runs" "${name}"
  done
  safe_rm_generated_dir "${DRYRUN_RUN_DIR}" "${DRYRUN_ROOT}/runs" "${DRYRUN_ID}"
  safe_rm_generated_dir "${PHASE3_RUN_DIR}" "${PHASE3_ROOT}/runs" "${PHASE3_RUN_ID}"
}

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
}

assert_absent() {
  local path="$1"
  [[ ! -e "${path}" ]] || fail "unexpected path exists: ${path}"
}

snapshot_repo_local_live_surfaces() {
  find "${REPO_ROOT}" -maxdepth 1 \( \
    -name ".env" -o \
    -name "openclaw" -o \
    -name "OpenClaw" -o \
    -name "local-overlay" -o \
    -name "crab-local-overlay" -o \
    -name "crab-instance-data" \
  \) -print | sort
}

write_marker() {
  local target="$1"
  local kind="$2"
  mkdir -p "${target}"
  printf '{\n  "kind": "%s",\n  "disposable": true\n}\n' "${kind}" > "${target}/.crab-disposable-target.json"
}

write_selector() {
  local path="$1"
  local approval_label="$2"
  "${PYTHON_BIN}" - \
    "${path}" \
    "${WORKSPACE_TARGET}" \
    "${WORKSPACE_APPROVED_ROOT}" \
    "${STATE_TARGET}" \
    "${STATE_APPROVED_ROOT}" \
    "${approval_label}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = {
    "kind": "openclaw-disposable-target-selector",
    "version": 1,
    "workspace_target": sys.argv[2],
    "workspace_approved_root": sys.argv[3],
    "state_target": sys.argv[4],
    "state_approved_root": sys.argv[5],
    "approval_label": sys.argv[6],
    "local_only": True,
    "disposable_only": True,
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

run_selector_expect_fail() {
  local label="$1"
  local run_id="$2"
  shift 2
  safe_rm_generated_dir "${APPLY_ROOT}/runs/${run_id}" "${APPLY_ROOT}/runs" "${run_id}"

  set +e
  bash operations/harness-openclaw-local-selector/bin/run_controlled_disposable_apply_from_selector.sh "$@" \
    --dry-run-run-dir "operations/harness-openclaw-dryrun/runs/${DRYRUN_ID}" \
    --run-id "${run_id}" >/dev/null 2>&1
  local status=$?
  set -e
  [[ "${status}" -ne 0 ]] || fail "negative selector case unexpectedly passed: ${label}"
  echo "PASS local selector negative case rejected: ${label}"
}

cd "${REPO_ROOT}"
mkdir -p "${APPLY_ROOT}/runs" "${DRYRUN_ROOT}/runs" "${PHASE3_ROOT}/runs"
cleanup
trap cleanup EXIT

live_surface_before="$(snapshot_repo_local_live_surfaces)"
assert_absent "${SELECTOR_ROOT}/runs"

mkdir -p \
  "${PHASE3_RUN_DIR}/staging/runtime-ready-applied/workspace/config" \
  "${PHASE3_RUN_DIR}/staging/runtime-ready-applied/state/memory"
cat > "${PHASE3_RUN_DIR}/report.json" <<'JSON'
{
  "overall_status": "pass"
}
JSON
cat > "${PHASE3_RUN_DIR}/staging/runtime-ready-applied/workspace/config/settings.json" <<'JSON'
{
  "fixture": "local-selector-workspace"
}
JSON
cat > "${PHASE3_RUN_DIR}/staging/runtime-ready-applied/state/memory/state.json" <<'JSON'
{
  "fixture": "local-selector-state"
}
JSON

bash operations/harness-openclaw-dryrun/bin/run_openclaw_dry_run.sh \
  --phase3-run-dir "operations/harness-phase3/runs/${PHASE3_RUN_ID}" \
  --run-id "${DRYRUN_ID}"

write_marker "${WORKSPACE_TARGET}" "openclaw-workspace"
write_marker "${STATE_TARGET}" "openclaw-state"
write_selector "${VALID_SELECTOR}" "selector-approved"

"${PYTHON_BIN}" - "${VALID_SELECTOR}" "${REPO_ROOT}" <<'PY'
import sys
from pathlib import Path

selector = Path(sys.argv[1]).resolve(strict=True)
repo = Path(sys.argv[2]).resolve(strict=True)
try:
    selector.relative_to(repo)
except ValueError:
    pass
else:
    raise AssertionError("positive selector file must stay outside Git")
PY

bash operations/harness-openclaw-local-selector/bin/run_controlled_disposable_apply_from_selector.sh \
  --selector-file "${VALID_SELECTOR}" \
  --dry-run-run-dir "operations/harness-openclaw-dryrun/runs/${DRYRUN_ID}" \
  --run-id "${APPLY_RUN_ID}"

assert_file "${APPLY_RUN_DIR}/apply_meta.json"
assert_file "${APPLY_RUN_DIR}/target_refs.json"
assert_file "${APPLY_RUN_DIR}/apply_report.json"
assert_file "${APPLY_RUN_DIR}/checks/evidence_schema_validation.json"
assert_file "${APPLY_RUN_DIR}/exit_code"

"${PYTHON_BIN}" - \
  "${VALID_SELECTOR}" \
  "${APPLY_RUN_DIR}/apply_meta.json" \
  "${APPLY_RUN_DIR}/target_refs.json" \
  "${APPLY_RUN_DIR}/apply_report.json" <<'PY'
import json
import sys
from pathlib import Path

selector = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
apply_meta = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8-sig"))
target_refs = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8-sig"))
apply_report = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8-sig"))

assert apply_meta["approval_label"] == selector["approval_label"], apply_meta
assert apply_meta["local_only"] is True, apply_meta
assert apply_meta["disposable_only"] is True, apply_meta
assert apply_meta["live_runtime_apply"] is False, apply_meta
assert target_refs["workspace_target"] == str(Path(selector["workspace_target"]).resolve()), target_refs
assert target_refs["workspace_approved_root"] == str(Path(selector["workspace_approved_root"]).resolve()), target_refs
assert target_refs["state_target"] == str(Path(selector["state_target"]).resolve()), target_refs
assert target_refs["state_approved_root"] == str(Path(selector["state_approved_root"]).resolve()), target_refs
assert apply_report["overall_status"] == "pass", apply_report
assert apply_report["local_only"] is True, apply_report
assert apply_report["disposable_only"] is True, apply_report
assert apply_report["live_runtime_apply"] is False, apply_report
PY

run_selector_expect_fail \
  "relative-selector-file" \
  "controlled-disposable-apply-selector-relative" \
  --selector-file "relative-selector.json"

write_selector "${INSIDE_REPO_SELECTOR}" "selector-inside-repo"
run_selector_expect_fail \
  "selector-file-inside-repo" \
  "controlled-disposable-apply-selector-inside-repo" \
  --selector-file "${INSIDE_REPO_SELECTOR}"

MISSING_FIELD_SELECTOR="${TMP_ROOT}/selector-missing-field.json"
write_selector "${MISSING_FIELD_SELECTOR}" "selector-missing-field"
"${PYTHON_BIN}" - "${MISSING_FIELD_SELECTOR}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8-sig"))
payload.pop("state_target")
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
run_selector_expect_fail \
  "selector-missing-required-field" \
  "controlled-disposable-apply-selector-missing-field" \
  --selector-file "${MISSING_FIELD_SELECTOR}"

EXTRA_FIELD_SELECTOR="${TMP_ROOT}/selector-extra-field.json"
write_selector "${EXTRA_FIELD_SELECTOR}" "selector-extra-field"
"${PYTHON_BIN}" - "${EXTRA_FIELD_SELECTOR}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8-sig"))
payload["openai_api_key"] = "should-not-be-allowed"
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
run_selector_expect_fail \
  "selector-extra-forbidden-property" \
  "controlled-disposable-apply-selector-extra-field" \
  --selector-file "${EXTRA_FIELD_SELECTOR}"

EMPTY_APPROVAL_SELECTOR="${TMP_ROOT}/selector-empty-approval.json"
write_selector "${EMPTY_APPROVAL_SELECTOR}" ""
run_selector_expect_fail \
  "selector-empty-approval-label" \
  "controlled-disposable-apply-selector-empty-approval" \
  --selector-file "${EMPTY_APPROVAL_SELECTOR}"

assert_absent "${SELECTOR_ROOT}/runs"
live_surface_after="$(snapshot_repo_local_live_surfaces)"
[[ "${live_surface_before}" == "${live_surface_after}" ]] || fail "repo-local live OpenClaw-like surfaces changed"

echo "PASS local disposable target selector wrapper"
