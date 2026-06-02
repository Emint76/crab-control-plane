#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE3_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PHASE3_ROOT}/../.." && pwd)"
TMP_DIR="$(mktemp -d)"

PHASE3_PYTHON_BIN="${PHASE3_PYTHON_BIN:-python}"
export PHASE3_PYTHON_BIN
PYTHON_BIN="${PHASE3_PYTHON_BIN}"
export PHASE2_PYTHON_BIN="${PHASE2_PYTHON_BIN:-${PYTHON_BIN}}"

PHASE2_RUN_ID="phase3-kb-admission-phase2-input"
PHASE2_RUN_DIR="${REPO_ROOT}/operations/harness-phase2/runs/${PHASE2_RUN_ID}"
FIXTURE_DIR="${PHASE3_ROOT}/runs/phase3-kb-admission-fixtures"
KB_ROOT="${TMP_DIR}/workspace-kb"
ALT_ROOT="${TMP_DIR}/workspace-kb-alt"
OUTSIDE_ROOT="${TMP_DIR}/outside"

RUN_IDS=(
  "phase3-kb-admission-source-pass"
  "phase3-kb-admission-knowledge-pass"
  "phase3-kb-admission-idempotent"
  "phase3-kb-admission-unsafe-overwrite"
  "phase3-kb-admission-atomic-preflight"
  "phase3-kb-admission-missing-env"
  "phase3-kb-admission-empty-env"
  "phase3-kb-admission-nonexistent-root"
  "phase3-kb-admission-root-inside-repo"
  "phase3-kb-admission-root-symlink"
  "phase3-kb-admission-absolute-destination"
  "phase3-kb-admission-traversal-destination"
  "phase3-kb-admission-symlink-traversal"
  "phase3-kb-admission-nested-symlink"
  "phase3-kb-admission-same-source-destination"
  "phase3-kb-admission-bad-integration-absolute"
  "phase3-kb-admission-bad-integration-traversal"
  "phase3-kb-admission-bad-integration-symlink"
  "phase3-kb-admission-bad-manifest-absolute"
  "phase3-kb-admission-bad-manifest-traversal"
  "phase3-kb-admission-bad-manifest-symlink"
  "phase3-kb-admission-invalid-integration"
  "phase3-kb-admission-invalid-manifest"
)

cleanup() {
  rm -rf "${TMP_DIR}" "${PHASE2_RUN_DIR}" "${FIXTURE_DIR}"
  for run_id in "${RUN_IDS[@]}"; do
    rm -rf "${PHASE3_ROOT}/runs/${run_id}" "${PHASE3_ROOT}/runs/${run_id}-target"
  done
}

fail() {
  echo "FAIL $*" >&2
  exit 1
}

sha256_of() {
  sha256sum "$1" | awk '{print $1}'
}

repo_ref() {
  local abs_path="$1"
  "${PYTHON_BIN}" - "${REPO_ROOT}" "${abs_path}" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

repo_root = Path(sys.argv[1]).resolve(strict=False)
path = Path(sys.argv[2]).resolve(strict=False)
print(path.relative_to(repo_root).as_posix())
PY
}

write_integration() {
  local path="$1"
  local env_name="${2:-OPENCLAW_WORKSPACE_KB_ROOT}"
  mkdir -p "$(dirname "${path}")"
  cat > "${path}" <<EOF
version: 1
integration: kb
enabled: true
target_runtime: workspace
root_path_env: ${env_name}
default_root_hint: /home/gennady/.openclaw/workspace/kb
root_path_policy:
  configured_at_runtime: true
  repo_payload: false
  default_root_hint_is_required: false
  repo_owns_root: false
  secrets_allowed: false
layout:
  sources:
    path: sources
    description: Test source layout metadata.
  knowledge:
    path: knowledge
    description: Test knowledge layout metadata.
  collections:
    path: collections
    description: Test collection layout metadata.
EOF
}

write_invalid_integration() {
  local path="$1"
  mkdir -p "$(dirname "${path}")"
  cat > "${path}" <<'EOF'
version: 1
integration: kb
enabled: true
target_runtime: repo
root_path_env: OPENCLAW_WORKSPACE_KB_ROOT
default_root_hint: example-only
root_path_policy:
  configured_at_runtime: true
  repo_payload: false
  default_root_hint_is_required: false
  repo_owns_root: false
  secrets_allowed: false
layout:
  sources:
    path: sources
    description: Test source layout metadata.
  knowledge:
    path: knowledge
    description: Test knowledge layout metadata.
  collections:
    path: collections
    description: Test collection layout metadata.
EOF
}

write_target() {
  local run_id="$1"
  local integration_ref="$2"
  local manifest_ref="$3"
  local target_dir="${PHASE3_ROOT}/runs/${run_id}-target"
  mkdir -p "${target_dir}"
  cat > "${target_dir}/execution_target.json" <<EOF
{
  "target_runtime": "workspace",
  "target_kind": "kb_admission",
  "kb_integration_ref": "${integration_ref}",
  "admission_manifest_ref": "${manifest_ref}",
  "invoked_by": "test://phase3-kb-admission"
}
EOF
}

write_manifest() {
  local path="$1"
  local admission_type="$2"
  local source_ref="$3"
  local expected_sha="$4"
  local destination_ref="$5"
  mkdir -p "$(dirname "${path}")"
  cat > "${path}" <<EOF
{
  "admission_type": "${admission_type}",
  "lineage": {
    "source_ref": "test://phase3-kb-admission/${admission_type}",
    "captured_from": "workspace-test-fixture",
    "captured_at": "2026-06-02T00:00:00Z"
  },
  "copy_operation": {
    "operation_type": "copy",
    "content_mode": "byte_for_byte",
    "overwrite_policy": "fail_closed_on_hash_mismatch",
    "requested_by": "test://phase3-kb-admission"
  },
  "artifacts": [
    {
      "input_workspace_path": "${source_ref}",
      "expected_sha256": "${expected_sha}",
      "destination_kb_path": "${destination_ref}",
      "copy_metadata": {
        "label": "${admission_type} fixture"
      }
    }
  ]
}
EOF
}

write_two_artifact_manifest() {
  local path="$1"
  local source_ref_1="$2"
  local expected_sha_1="$3"
  local destination_ref_1="$4"
  local source_ref_2="$5"
  local expected_sha_2="$6"
  local destination_ref_2="$7"
  mkdir -p "$(dirname "${path}")"
  cat > "${path}" <<EOF
{
  "admission_type": "source_capture",
  "lineage": {
    "source_ref": "test://phase3-kb-admission/atomic",
    "captured_from": "workspace-test-fixture",
    "captured_at": "2026-06-02T00:00:00Z"
  },
  "copy_operation": {
    "operation_type": "copy",
    "content_mode": "byte_for_byte",
    "overwrite_policy": "fail_closed_on_hash_mismatch",
    "requested_by": "test://phase3-kb-admission"
  },
  "artifacts": [
    {
      "input_workspace_path": "${source_ref_1}",
      "expected_sha256": "${expected_sha_1}",
      "destination_kb_path": "${destination_ref_1}",
      "copy_metadata": {"label": "would copy"}
    },
    {
      "input_workspace_path": "${source_ref_2}",
      "expected_sha256": "${expected_sha_2}",
      "destination_kb_path": "${destination_ref_2}",
      "copy_metadata": {"label": "blocks overwrite"}
    }
  ]
}
EOF
}

write_invalid_manifest() {
  local path="$1"
  mkdir -p "$(dirname "${path}")"
  cat > "${path}" <<'EOF'
{
  "admission_type": "source_capture",
  "lineage": {
    "source_ref": "test://invalid"
  },
  "copy_operation": {
    "operation_type": "copy",
    "content_mode": "byte_for_byte",
    "overwrite_policy": "fail_closed_on_hash_mismatch"
  }
}
EOF
}

run_kb_admission() {
  local run_id="$1"
  local env_value="${2:-${KB_ROOT}}"
  OPENCLAW_WORKSPACE_KB_ROOT="${env_value}" bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
    --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
    --execution-target-json "operations/harness-phase3/runs/${run_id}-target/execution_target.json" \
    --run-id "${run_id}"
}

run_kb_admission_without_env() {
  local run_id="$1"
  env -u OPENCLAW_WORKSPACE_KB_ROOT bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
    --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
    --execution-target-json "operations/harness-phase3/runs/${run_id}-target/execution_target.json" \
    --run-id "${run_id}"
}

run_expect_failure() {
  local run_id="$1"
  shift
  local log_path="${TMP_DIR}/${run_id}.log"
  set +e
  "$@" >"${log_path}" 2>&1
  local status=$?
  set -e
  [[ "${status}" -ne 0 ]] || fail "${run_id} unexpectedly passed"
}

assert_exit_code() {
  local run_id="$1"
  local expected="$2"
  local exit_code_path="${PHASE3_ROOT}/runs/${run_id}/exit_code"
  [[ -f "${exit_code_path}" ]] || fail "missing exit_code for ${run_id}"
  [[ "$(tr -d '\r\n' < "${exit_code_path}")" == "${expected}" ]] || fail "unexpected exit_code for ${run_id}"
}

assert_kb_evidence_action() {
  local run_id="$1"
  local expected_action="$2"
  local expected_verdict="$3"
  "${PYTHON_BIN}" - "${PHASE3_ROOT}/runs/${run_id}/checks/kb_admission_evidence.json" "${expected_action}" "${expected_verdict}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
item = payload["evidence"][0]
assert payload["target_runtime"] == "workspace", payload
assert payload["target_kind"] == "kb_admission", payload
assert payload["kb_root_env"] == "OPENCLAW_WORKSPACE_KB_ROOT", payload
assert str(payload["kb_root_resolved"]).startswith("redacted:sha256:"), payload
assert payload["kb_integration_hash"], payload
assert payload["manifest_hash"], payload
assert item["manifest_hash"], payload
assert item["kb_integration_hash"], payload
assert item["source_artifact_hash"], payload
assert item["destination_kb_path"], payload
assert item["action"] == sys.argv[2], payload
assert item["overwrite_verdict"] == sys.argv[3], payload
if sys.argv[2] != "failed_closed":
    assert item["final_destination_hash"], payload
PY
}

assert_pre_apply_failed() {
  local run_id="$1"
  "${PYTHON_BIN}" - "${PHASE3_ROOT}/runs/${run_id}/checks/pre_apply_validation.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
assert payload["status"] == "fail", payload
assert payload["target_kind"] == "kb_admission", payload
PY
}

assert_atomic_evidence() {
  local run_id="$1"
  "${PYTHON_BIN}" - "${PHASE3_ROOT}/runs/${run_id}/checks/kb_admission_evidence.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
assert payload["status"] == "fail", payload
assert payload["failure_stage"] == "copy_plan_preflight", payload
items = payload["evidence"]
assert len(items) == 2, payload
assert items[0]["planned_action"] == "would_copy", payload
assert items[0]["action"] == "failed_closed", payload
assert items[0]["execution_status"] == "not_executed", payload
assert items[0]["overwrite_verdict"] == "destination_missing", payload
assert items[1]["planned_action"] == "failed_closed", payload
assert items[1]["action"] == "failed_closed", payload
assert items[1]["execution_status"] == "not_executed", payload
assert items[1]["overwrite_verdict"] == "different_hash_existing", payload
PY
}

rm -rf "${TMP_DIR}" "${PHASE2_RUN_DIR}" "${FIXTURE_DIR}"
mkdir -p "${TMP_DIR}" "${KB_ROOT}/prepared" "${KB_ROOT}/cosmetics-household-chemistry" "${ALT_ROOT}" "${OUTSIDE_ROOT}" "${FIXTURE_DIR}"
for run_id in "${RUN_IDS[@]}"; do
  rm -rf "${PHASE3_ROOT}/runs/${run_id}" "${PHASE3_ROOT}/runs/${run_id}-target"
done
trap cleanup EXIT

bash "${REPO_ROOT}/operations/harness-phase2/bin/run_phase2_bundle.sh" "${PHASE2_RUN_ID}"

BASE_INTEGRATION="${FIXTURE_DIR}/kb.template.yaml"
write_integration "${BASE_INTEGRATION}"
BASE_INTEGRATION_REF="$(repo_ref "${BASE_INTEGRATION}")"

printf 'source capture bytes\n' > "${KB_ROOT}/prepared/source-capture.txt"
SOURCE_HASH="$(sha256_of "${KB_ROOT}/prepared/source-capture.txt")"
printf '# Knowledge asset\n\nStable bytes.\n' > "${KB_ROOT}/prepared/knowledge.md"
KNOWLEDGE_HASH="$(sha256_of "${KB_ROOT}/prepared/knowledge.md")"

SOURCE_PASS_RUN="phase3-kb-admission-source-pass"
SOURCE_PASS_MANIFEST="${PHASE3_ROOT}/runs/${SOURCE_PASS_RUN}-target/admission_manifest.json"
write_manifest "${SOURCE_PASS_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/source-capture.txt"
write_target "${SOURCE_PASS_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${SOURCE_PASS_MANIFEST}")"
run_kb_admission "${SOURCE_PASS_RUN}"
assert_exit_code "${SOURCE_PASS_RUN}" "0"
[[ "$(sha256_of "${KB_ROOT}/cosmetics-household-chemistry/source-capture.txt")" == "${SOURCE_HASH}" ]] || fail "source pass destination hash mismatch"
[[ -f "${PHASE3_ROOT}/runs/${SOURCE_PASS_RUN}/input/admission_manifest.json" ]] || fail "missing frozen KB admission manifest"
[[ -f "${PHASE3_ROOT}/runs/${SOURCE_PASS_RUN}/input/kb_integration.yaml" ]] || fail "missing frozen KB integration"
assert_kb_evidence_action "${SOURCE_PASS_RUN}" "copied" "destination_missing"

KNOWLEDGE_PASS_RUN="phase3-kb-admission-knowledge-pass"
KNOWLEDGE_PASS_MANIFEST="${PHASE3_ROOT}/runs/${KNOWLEDGE_PASS_RUN}-target/admission_manifest.json"
write_manifest "${KNOWLEDGE_PASS_MANIFEST}" "knowledge_asset" "prepared/knowledge.md" "${KNOWLEDGE_HASH}" "cosmetics-household-chemistry/knowledge.md"
write_target "${KNOWLEDGE_PASS_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${KNOWLEDGE_PASS_MANIFEST}")"
run_kb_admission "${KNOWLEDGE_PASS_RUN}"
assert_exit_code "${KNOWLEDGE_PASS_RUN}" "0"
[[ "$(sha256_of "${KB_ROOT}/cosmetics-household-chemistry/knowledge.md")" == "${KNOWLEDGE_HASH}" ]] || fail "knowledge pass destination hash mismatch"
assert_kb_evidence_action "${KNOWLEDGE_PASS_RUN}" "copied" "destination_missing"

IDEMPOTENT_RUN="phase3-kb-admission-idempotent"
IDEMPOTENT_MANIFEST="${PHASE3_ROOT}/runs/${IDEMPOTENT_RUN}-target/admission_manifest.json"
write_manifest "${IDEMPOTENT_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/source-capture.txt"
write_target "${IDEMPOTENT_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${IDEMPOTENT_MANIFEST}")"
run_kb_admission "${IDEMPOTENT_RUN}"
assert_exit_code "${IDEMPOTENT_RUN}" "0"
assert_kb_evidence_action "${IDEMPOTENT_RUN}" "idempotent" "same_hash_existing"

UNSAFE_OVERWRITE_RUN="phase3-kb-admission-unsafe-overwrite"
printf 'different existing bytes\n' > "${KB_ROOT}/cosmetics-household-chemistry/unsafe-overwrite.txt"
UNSAFE_OVERWRITE_MANIFEST="${PHASE3_ROOT}/runs/${UNSAFE_OVERWRITE_RUN}-target/admission_manifest.json"
write_manifest "${UNSAFE_OVERWRITE_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/unsafe-overwrite.txt"
write_target "${UNSAFE_OVERWRITE_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${UNSAFE_OVERWRITE_MANIFEST}")"
run_expect_failure "${UNSAFE_OVERWRITE_RUN}" run_kb_admission "${UNSAFE_OVERWRITE_RUN}"
assert_exit_code "${UNSAFE_OVERWRITE_RUN}" "1"
assert_kb_evidence_action "${UNSAFE_OVERWRITE_RUN}" "failed_closed" "different_hash_existing"
[[ "$(cat "${KB_ROOT}/cosmetics-household-chemistry/unsafe-overwrite.txt")" == "different existing bytes" ]] || fail "unsafe overwrite mutated destination"

ATOMIC_RUN="phase3-kb-admission-atomic-preflight"
printf 'atomic new bytes\n' > "${KB_ROOT}/prepared/atomic-new.txt"
printf 'atomic second new bytes\n' > "${KB_ROOT}/prepared/atomic-second.txt"
printf 'atomic existing bytes\n' > "${KB_ROOT}/cosmetics-household-chemistry/atomic-blocked.txt"
ATOMIC_HASH_1="$(sha256_of "${KB_ROOT}/prepared/atomic-new.txt")"
ATOMIC_HASH_2="$(sha256_of "${KB_ROOT}/prepared/atomic-second.txt")"
ATOMIC_MANIFEST="${PHASE3_ROOT}/runs/${ATOMIC_RUN}-target/admission_manifest.json"
write_two_artifact_manifest \
  "${ATOMIC_MANIFEST}" \
  "prepared/atomic-new.txt" \
  "${ATOMIC_HASH_1}" \
  "cosmetics-household-chemistry/atomic-would-copy.txt" \
  "prepared/atomic-second.txt" \
  "${ATOMIC_HASH_2}" \
  "cosmetics-household-chemistry/atomic-blocked.txt"
write_target "${ATOMIC_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${ATOMIC_MANIFEST}")"
run_expect_failure "${ATOMIC_RUN}" run_kb_admission "${ATOMIC_RUN}"
assert_exit_code "${ATOMIC_RUN}" "1"
[[ ! -e "${KB_ROOT}/cosmetics-household-chemistry/atomic-would-copy.txt" ]] || fail "atomic preflight created first destination"
[[ "$(cat "${KB_ROOT}/cosmetics-household-chemistry/atomic-blocked.txt")" == "atomic existing bytes" ]] || fail "atomic preflight mutated blocked destination"
assert_atomic_evidence "${ATOMIC_RUN}"

for case_name in missing-env empty-env nonexistent-root root-inside-repo root-symlink absolute-destination traversal-destination symlink-traversal nested-symlink same-source-destination invalid-integration invalid-manifest; do
  :
done

MISSING_ENV_RUN="phase3-kb-admission-missing-env"
MISSING_ENV_MANIFEST="${PHASE3_ROOT}/runs/${MISSING_ENV_RUN}-target/admission_manifest.json"
write_manifest "${MISSING_ENV_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/missing-env.txt"
write_target "${MISSING_ENV_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${MISSING_ENV_MANIFEST}")"
run_expect_failure "${MISSING_ENV_RUN}" run_kb_admission_without_env "${MISSING_ENV_RUN}"
assert_exit_code "${MISSING_ENV_RUN}" "1"
assert_pre_apply_failed "${MISSING_ENV_RUN}"
[[ ! -e "${KB_ROOT}/cosmetics-household-chemistry/missing-env.txt" ]] || fail "missing env wrote destination"

EMPTY_ENV_RUN="phase3-kb-admission-empty-env"
EMPTY_ENV_MANIFEST="${PHASE3_ROOT}/runs/${EMPTY_ENV_RUN}-target/admission_manifest.json"
write_manifest "${EMPTY_ENV_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/empty-env.txt"
write_target "${EMPTY_ENV_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${EMPTY_ENV_MANIFEST}")"
run_expect_failure "${EMPTY_ENV_RUN}" run_kb_admission "${EMPTY_ENV_RUN}" ""
assert_exit_code "${EMPTY_ENV_RUN}" "1"
assert_pre_apply_failed "${EMPTY_ENV_RUN}"
[[ ! -e "${KB_ROOT}/cosmetics-household-chemistry/empty-env.txt" ]] || fail "empty env wrote destination"

NONEXISTENT_ROOT_RUN="phase3-kb-admission-nonexistent-root"
NONEXISTENT_ROOT_MANIFEST="${PHASE3_ROOT}/runs/${NONEXISTENT_ROOT_RUN}-target/admission_manifest.json"
write_manifest "${NONEXISTENT_ROOT_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/nonexistent-root.txt"
write_target "${NONEXISTENT_ROOT_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${NONEXISTENT_ROOT_MANIFEST}")"
run_expect_failure "${NONEXISTENT_ROOT_RUN}" run_kb_admission "${NONEXISTENT_ROOT_RUN}" "${TMP_DIR}/does-not-exist"
assert_exit_code "${NONEXISTENT_ROOT_RUN}" "1"
assert_pre_apply_failed "${NONEXISTENT_ROOT_RUN}"

ROOT_INSIDE_RUN="phase3-kb-admission-root-inside-repo"
ROOT_INSIDE_DIR="${REPO_ROOT}/operations/harness-phase3/runs/${ROOT_INSIDE_RUN}-inside-root"
mkdir -p "${ROOT_INSIDE_DIR}/prepared"
printf 'inside repo root bytes\n' > "${ROOT_INSIDE_DIR}/prepared/source.txt"
ROOT_INSIDE_HASH="$(sha256_of "${ROOT_INSIDE_DIR}/prepared/source.txt")"
ROOT_INSIDE_MANIFEST="${PHASE3_ROOT}/runs/${ROOT_INSIDE_RUN}-target/admission_manifest.json"
write_manifest "${ROOT_INSIDE_MANIFEST}" "source_capture" "prepared/source.txt" "${ROOT_INSIDE_HASH}" "dest.txt"
write_target "${ROOT_INSIDE_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${ROOT_INSIDE_MANIFEST}")"
run_expect_failure "${ROOT_INSIDE_RUN}" run_kb_admission "${ROOT_INSIDE_RUN}" "${ROOT_INSIDE_DIR}"
assert_exit_code "${ROOT_INSIDE_RUN}" "1"
assert_pre_apply_failed "${ROOT_INSIDE_RUN}"
rm -rf "${ROOT_INSIDE_DIR}"

ROOT_SYMLINK_RUN="phase3-kb-admission-root-symlink"
ROOT_SYMLINK="${TMP_DIR}/workspace-kb-link"
ln -s "${KB_ROOT}" "${ROOT_SYMLINK}"
ROOT_SYMLINK_MANIFEST="${PHASE3_ROOT}/runs/${ROOT_SYMLINK_RUN}-target/admission_manifest.json"
write_manifest "${ROOT_SYMLINK_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/root-symlink.txt"
write_target "${ROOT_SYMLINK_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${ROOT_SYMLINK_MANIFEST}")"
run_expect_failure "${ROOT_SYMLINK_RUN}" run_kb_admission "${ROOT_SYMLINK_RUN}" "${ROOT_SYMLINK}"
assert_exit_code "${ROOT_SYMLINK_RUN}" "1"
assert_pre_apply_failed "${ROOT_SYMLINK_RUN}"

ABS_DEST_RUN="phase3-kb-admission-absolute-destination"
ABS_DEST_MANIFEST="${PHASE3_ROOT}/runs/${ABS_DEST_RUN}-target/admission_manifest.json"
write_manifest "${ABS_DEST_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "${TMP_DIR}/absolute-bad.txt"
write_target "${ABS_DEST_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${ABS_DEST_MANIFEST}")"
run_expect_failure "${ABS_DEST_RUN}" run_kb_admission "${ABS_DEST_RUN}"
assert_exit_code "${ABS_DEST_RUN}" "1"
assert_pre_apply_failed "${ABS_DEST_RUN}"
[[ ! -e "${TMP_DIR}/absolute-bad.txt" ]] || fail "absolute destination was written"

TRAVERSAL_DEST_RUN="phase3-kb-admission-traversal-destination"
TRAVERSAL_DEST_MANIFEST="${PHASE3_ROOT}/runs/${TRAVERSAL_DEST_RUN}-target/admission_manifest.json"
write_manifest "${TRAVERSAL_DEST_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "../outside.txt"
write_target "${TRAVERSAL_DEST_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${TRAVERSAL_DEST_MANIFEST}")"
run_expect_failure "${TRAVERSAL_DEST_RUN}" run_kb_admission "${TRAVERSAL_DEST_RUN}"
assert_exit_code "${TRAVERSAL_DEST_RUN}" "1"
assert_pre_apply_failed "${TRAVERSAL_DEST_RUN}"
[[ ! -e "${TMP_DIR}/outside.txt" ]] || fail "traversal destination was written"

SYMLINK_TRAVERSAL_RUN="phase3-kb-admission-symlink-traversal"
ln -s "${OUTSIDE_ROOT}" "${KB_ROOT}/link-out"
SYMLINK_TRAVERSAL_MANIFEST="${PHASE3_ROOT}/runs/${SYMLINK_TRAVERSAL_RUN}-target/admission_manifest.json"
write_manifest "${SYMLINK_TRAVERSAL_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "link-out/bad.txt"
write_target "${SYMLINK_TRAVERSAL_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${SYMLINK_TRAVERSAL_MANIFEST}")"
run_expect_failure "${SYMLINK_TRAVERSAL_RUN}" run_kb_admission "${SYMLINK_TRAVERSAL_RUN}"
assert_exit_code "${SYMLINK_TRAVERSAL_RUN}" "1"
assert_pre_apply_failed "${SYMLINK_TRAVERSAL_RUN}"
[[ ! -e "${OUTSIDE_ROOT}/bad.txt" ]] || fail "symlink traversal destination was written"

NESTED_SYMLINK_RUN="phase3-kb-admission-nested-symlink"
mkdir -p "${KB_ROOT}/nested"
ln -s "${OUTSIDE_ROOT}" "${KB_ROOT}/nested/link-out"
NESTED_SYMLINK_MANIFEST="${PHASE3_ROOT}/runs/${NESTED_SYMLINK_RUN}-target/admission_manifest.json"
write_manifest "${NESTED_SYMLINK_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "nested/link-out/bad.txt"
write_target "${NESTED_SYMLINK_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${NESTED_SYMLINK_MANIFEST}")"
run_expect_failure "${NESTED_SYMLINK_RUN}" run_kb_admission "${NESTED_SYMLINK_RUN}"
assert_exit_code "${NESTED_SYMLINK_RUN}" "1"
assert_pre_apply_failed "${NESTED_SYMLINK_RUN}"
[[ ! -e "${OUTSIDE_ROOT}/bad.txt" ]] || fail "nested symlink traversal destination was written"

SAME_PATH_RUN="phase3-kb-admission-same-source-destination"
SAME_PATH_MANIFEST="${PHASE3_ROOT}/runs/${SAME_PATH_RUN}-target/admission_manifest.json"
write_manifest "${SAME_PATH_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "prepared/source-capture.txt"
write_target "${SAME_PATH_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${SAME_PATH_MANIFEST}")"
run_expect_failure "${SAME_PATH_RUN}" run_kb_admission "${SAME_PATH_RUN}"
assert_exit_code "${SAME_PATH_RUN}" "1"
assert_pre_apply_failed "${SAME_PATH_RUN}"

BAD_INTEGRATION_ABS_RUN="phase3-kb-admission-bad-integration-absolute"
BAD_INTEGRATION_ABS_MANIFEST="${PHASE3_ROOT}/runs/${BAD_INTEGRATION_ABS_RUN}-target/admission_manifest.json"
write_manifest "${BAD_INTEGRATION_ABS_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/bad-integration-absolute.txt"
write_target "${BAD_INTEGRATION_ABS_RUN}" "/tmp/bad-kb-template.yaml" "$(repo_ref "${BAD_INTEGRATION_ABS_MANIFEST}")"
run_expect_failure "${BAD_INTEGRATION_ABS_RUN}" run_kb_admission "${BAD_INTEGRATION_ABS_RUN}"
assert_exit_code "${BAD_INTEGRATION_ABS_RUN}" "1"
[[ ! -e "${KB_ROOT}/cosmetics-household-chemistry/bad-integration-absolute.txt" ]] || fail "bad absolute integration ref wrote destination"

BAD_INTEGRATION_TRAVERSAL_RUN="phase3-kb-admission-bad-integration-traversal"
BAD_INTEGRATION_TRAVERSAL_MANIFEST="${PHASE3_ROOT}/runs/${BAD_INTEGRATION_TRAVERSAL_RUN}-target/admission_manifest.json"
write_manifest "${BAD_INTEGRATION_TRAVERSAL_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/bad-integration-traversal.txt"
write_target "${BAD_INTEGRATION_TRAVERSAL_RUN}" "../kb.template.yaml" "$(repo_ref "${BAD_INTEGRATION_TRAVERSAL_MANIFEST}")"
run_expect_failure "${BAD_INTEGRATION_TRAVERSAL_RUN}" run_kb_admission "${BAD_INTEGRATION_TRAVERSAL_RUN}"
assert_exit_code "${BAD_INTEGRATION_TRAVERSAL_RUN}" "1"
[[ ! -e "${KB_ROOT}/cosmetics-household-chemistry/bad-integration-traversal.txt" ]] || fail "bad traversal integration ref wrote destination"

BAD_INTEGRATION_SYMLINK_RUN="phase3-kb-admission-bad-integration-symlink"
BAD_INTEGRATION_LINK="${FIXTURE_DIR}/outside-integration-link.yaml"
ln -s "${TMP_DIR}/outside-integration.yaml" "${BAD_INTEGRATION_LINK}"
printf 'version: 1\n' > "${TMP_DIR}/outside-integration.yaml"
BAD_INTEGRATION_SYMLINK_MANIFEST="${PHASE3_ROOT}/runs/${BAD_INTEGRATION_SYMLINK_RUN}-target/admission_manifest.json"
write_manifest "${BAD_INTEGRATION_SYMLINK_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/bad-integration-symlink.txt"
write_target "${BAD_INTEGRATION_SYMLINK_RUN}" "$(repo_ref "${BAD_INTEGRATION_LINK}")" "$(repo_ref "${BAD_INTEGRATION_SYMLINK_MANIFEST}")"
run_expect_failure "${BAD_INTEGRATION_SYMLINK_RUN}" run_kb_admission "${BAD_INTEGRATION_SYMLINK_RUN}"
assert_exit_code "${BAD_INTEGRATION_SYMLINK_RUN}" "1"
[[ ! -e "${KB_ROOT}/cosmetics-household-chemistry/bad-integration-symlink.txt" ]] || fail "bad symlink integration ref wrote destination"

BAD_MANIFEST_ABS_RUN="phase3-kb-admission-bad-manifest-absolute"
write_target "${BAD_MANIFEST_ABS_RUN}" "${BASE_INTEGRATION_REF}" "/tmp/bad-manifest.json"
run_expect_failure "${BAD_MANIFEST_ABS_RUN}" run_kb_admission "${BAD_MANIFEST_ABS_RUN}"
assert_exit_code "${BAD_MANIFEST_ABS_RUN}" "1"

BAD_MANIFEST_TRAVERSAL_RUN="phase3-kb-admission-bad-manifest-traversal"
write_target "${BAD_MANIFEST_TRAVERSAL_RUN}" "${BASE_INTEGRATION_REF}" "../bad-manifest.json"
run_expect_failure "${BAD_MANIFEST_TRAVERSAL_RUN}" run_kb_admission "${BAD_MANIFEST_TRAVERSAL_RUN}"
assert_exit_code "${BAD_MANIFEST_TRAVERSAL_RUN}" "1"

BAD_MANIFEST_SYMLINK_RUN="phase3-kb-admission-bad-manifest-symlink"
BAD_MANIFEST_LINK="${FIXTURE_DIR}/outside-manifest-link.json"
ln -s "${TMP_DIR}/outside-manifest.json" "${BAD_MANIFEST_LINK}"
write_manifest "${TMP_DIR}/outside-manifest.json" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/bad-manifest-symlink.txt"
write_target "${BAD_MANIFEST_SYMLINK_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${BAD_MANIFEST_LINK}")"
run_expect_failure "${BAD_MANIFEST_SYMLINK_RUN}" run_kb_admission "${BAD_MANIFEST_SYMLINK_RUN}"
assert_exit_code "${BAD_MANIFEST_SYMLINK_RUN}" "1"
[[ ! -e "${KB_ROOT}/cosmetics-household-chemistry/bad-manifest-symlink.txt" ]] || fail "bad symlink manifest ref wrote destination"

INVALID_INTEGRATION_RUN="phase3-kb-admission-invalid-integration"
INVALID_INTEGRATION="${FIXTURE_DIR}/invalid-kb.template.yaml"
write_invalid_integration "${INVALID_INTEGRATION}"
INVALID_INTEGRATION_MANIFEST="${PHASE3_ROOT}/runs/${INVALID_INTEGRATION_RUN}-target/admission_manifest.json"
write_manifest "${INVALID_INTEGRATION_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/invalid-integration.txt"
write_target "${INVALID_INTEGRATION_RUN}" "$(repo_ref "${INVALID_INTEGRATION}")" "$(repo_ref "${INVALID_INTEGRATION_MANIFEST}")"
run_expect_failure "${INVALID_INTEGRATION_RUN}" run_kb_admission "${INVALID_INTEGRATION_RUN}"
assert_exit_code "${INVALID_INTEGRATION_RUN}" "1"
assert_pre_apply_failed "${INVALID_INTEGRATION_RUN}"
[[ ! -e "${KB_ROOT}/cosmetics-household-chemistry/invalid-integration.txt" ]] || fail "invalid integration wrote destination"

INVALID_MANIFEST_RUN="phase3-kb-admission-invalid-manifest"
INVALID_MANIFEST="${PHASE3_ROOT}/runs/${INVALID_MANIFEST_RUN}-target/admission_manifest.json"
write_invalid_manifest "${INVALID_MANIFEST}"
write_target "${INVALID_MANIFEST_RUN}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${INVALID_MANIFEST}")"
run_expect_failure "${INVALID_MANIFEST_RUN}" run_kb_admission "${INVALID_MANIFEST_RUN}"
assert_exit_code "${INVALID_MANIFEST_RUN}" "1"
assert_pre_apply_failed "${INVALID_MANIFEST_RUN}"

echo "PASS kb_admission source_capture pass into temp workspace KB root"
echo "PASS kb_admission knowledge_asset pass into temp workspace KB root"
echo "PASS kb_admission idempotent rerun with same hash"
echo "PASS kb_admission unsafe overwrite fails closed"
echo "PASS kb_admission atomic preflight prevents partial writes"
echo "PASS kb_admission missing env fails before write"
echo "PASS kb_admission empty env fails before write"
echo "PASS kb_admission nonexistent root fails before write"
echo "PASS kb_admission root inside repo is rejected"
echo "PASS kb_admission root symlink is rejected"
echo "PASS kb_admission absolute and traversal destinations are rejected"
echo "PASS kb_admission symlink traversal is rejected"
echo "PASS kb_admission same source/destination is rejected"
echo "PASS kb_admission bad refs are rejected before write"
echo "PASS kb_admission invalid integration and manifest fail before write"
