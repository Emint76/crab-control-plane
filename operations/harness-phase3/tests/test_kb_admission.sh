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
OUTSIDE_ROOT="${TMP_DIR}/outside"
RUN_IDS=()

cleanup() {
  rm -rf "${TMP_DIR}" "${PHASE2_RUN_DIR}" "${FIXTURE_DIR}"
  for run_id in "${RUN_IDS[@]}"; do
    rm -rf "${PHASE3_ROOT}/runs/${run_id}" "${PHASE3_ROOT}/runs/${run_id}-target" "${PHASE3_ROOT}/runs/${run_id}-inside-root"
  done
}
trap cleanup EXIT

fail() { echo "FAIL $*" >&2; exit 1; }
sha256_of() { sha256sum "$1" | awk '{print $1}'; }

repo_ref() {
  "${PYTHON_BIN}" - "${REPO_ROOT}" "$1" <<'PY'
from __future__ import annotations
import sys
from pathlib import Path
repo_root = Path(sys.argv[1]).absolute()
path = Path(sys.argv[2]).absolute()
print(path.relative_to(repo_root).as_posix())
PY
}

write_integration() {
  local path="$1"
  mkdir -p "$(dirname "${path}")"
  cat > "${path}" <<'EOF'
version: 1
integration: kb
enabled: true
target_runtime: workspace
root_path_env: OPENCLAW_WORKSPACE_KB_ROOT
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
  write_integration "${path}"
  "${PYTHON_BIN}" - "${path}" <<'PY'
from pathlib import Path
path = Path(__import__('sys').argv[1])
text = path.read_text(encoding='utf-8')
path.write_text(text.replace('target_runtime: workspace', 'target_runtime: repo'), encoding='utf-8')
PY
}

write_manifest() {
  local path="$1" admission_type="$2" source_ref="$3" expected_sha="$4" destination_ref="$5"
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
      "copy_metadata": {"label": "${admission_type} fixture"}
    }
  ]
}
EOF
}

write_two_artifact_manifest() {
  local path="$1" source_ref_1="$2" expected_sha_1="$3" destination_ref_1="$4" source_ref_2="$5" expected_sha_2="$6" destination_ref_2="$7"
  mkdir -p "$(dirname "${path}")"
  cat > "${path}" <<EOF
{
  "admission_type": "source_capture",
  "lineage": {"source_ref": "test://phase3-kb-admission/atomic"},
  "copy_operation": {
    "operation_type": "copy",
    "content_mode": "byte_for_byte",
    "overwrite_policy": "fail_closed_on_hash_mismatch"
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
      "copy_metadata": {"label": "blocked overwrite"}
    }
  ]
}
EOF
}

write_invalid_manifest() {
  local path="$1"
  mkdir -p "$(dirname "${path}")"
  printf '{"admission_type":"source_capture","lineage":{"source_ref":"test://invalid"}}\n' > "${path}"
}

write_target() {
  local run_id="$1" integration_ref="$2" manifest_ref="$3"
  RUN_IDS+=("${run_id}")
  mkdir -p "${PHASE3_ROOT}/runs/${run_id}-target"
  cat > "${PHASE3_ROOT}/runs/${run_id}-target/execution_target.json" <<EOF
{
  "target_runtime": "workspace",
  "target_kind": "kb_admission",
  "kb_integration_ref": "${integration_ref}",
  "admission_manifest_ref": "${manifest_ref}",
  "invoked_by": "test://phase3-kb-admission"
}
EOF
}

run_kb() {
  local run_id="$1"
  local env_value="${KB_ROOT}"
  if [[ $# -ge 2 ]]; then env_value="$2"; fi
  OPENCLAW_WORKSPACE_KB_ROOT="${env_value}" bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
    --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
    --execution-target-json "operations/harness-phase3/runs/${run_id}-target/execution_target.json" \
    --run-id "${run_id}"
}

run_kb_without_env() {
  local run_id="$1"
  env -u OPENCLAW_WORKSPACE_KB_ROOT bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
    --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
    --execution-target-json "operations/harness-phase3/runs/${run_id}-target/execution_target.json" \
    --run-id "${run_id}"
}

expect_failure() {
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
  local run_id="$1" expected="$2" path="${PHASE3_ROOT}/runs/${run_id}/exit_code"
  [[ -f "${path}" ]] || fail "missing exit_code for ${run_id}"
  [[ "$(tr -d '\r\n' < "${path}")" == "${expected}" ]] || fail "unexpected exit_code for ${run_id}"
}

assert_pre_apply_failed() {
  local run_id="$1"
  "${PYTHON_BIN}" - "${PHASE3_ROOT}/runs/${run_id}/checks/pre_apply_validation.json" <<'PY'
from __future__ import annotations
import json, sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
assert payload['status'] == 'fail', payload
assert payload['target_kind'] == 'kb_admission', payload
PY
}

assert_action() {
  local run_id="$1" expected_action="$2" expected_verdict="$3"
  "${PYTHON_BIN}" - "${PHASE3_ROOT}/runs/${run_id}/checks/kb_admission_evidence.json" "${expected_action}" "${expected_verdict}" <<'PY'
from __future__ import annotations
import json, sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
item = payload['evidence'][0]
assert payload['target_runtime'] == 'workspace', payload
assert payload['target_kind'] == 'kb_admission', payload
assert payload['kb_root_env'] == 'OPENCLAW_WORKSPACE_KB_ROOT', payload
assert str(payload['kb_root_resolved']).startswith('redacted:sha256:'), payload
for key in ('kb_integration_hash', 'manifest_hash'):
    assert payload[key], payload
for key in ('kb_integration_hash', 'manifest_hash', 'source_artifact_hash', 'destination_kb_path'):
    assert item[key], payload
assert item['action'] == sys.argv[2], payload
assert item['overwrite_verdict'] == sys.argv[3], payload
if sys.argv[2] != 'failed_closed':
    assert item['final_destination_hash'], payload
PY
}

assert_atomic_evidence() {
  local run_id="$1"
  "${PYTHON_BIN}" - "${PHASE3_ROOT}/runs/${run_id}/checks/kb_admission_evidence.json" <<'PY'
from __future__ import annotations
import json, sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
items = payload['evidence']
assert payload['status'] == 'fail', payload
assert payload['failure_stage'] == 'copy_plan_preflight', payload
assert len(items) == 2, payload
assert items[0]['planned_action'] == 'would_copy', payload
assert items[0]['action'] == 'failed_closed', payload
assert items[0]['execution_status'] == 'not_executed', payload
assert items[0]['overwrite_verdict'] == 'destination_missing', payload
assert items[1]['action'] == 'failed_closed', payload
assert items[1]['execution_status'] == 'not_executed', payload
assert items[1]['overwrite_verdict'] == 'different_hash_existing', payload
PY
}

make_manifest_and_target() {
  local run_id="$1" admission_type="$2" source_ref="$3" expected_sha="$4" destination_ref="$5"
  local manifest="${PHASE3_ROOT}/runs/${run_id}-target/admission_manifest.json"
  write_manifest "${manifest}" "${admission_type}" "${source_ref}" "${expected_sha}" "${destination_ref}"
  write_target "${run_id}" "${BASE_INTEGRATION_REF}" "$(repo_ref "${manifest}")"
}

rm -rf "${TMP_DIR}" "${PHASE2_RUN_DIR}" "${FIXTURE_DIR}"
mkdir -p "${TMP_DIR}" "${KB_ROOT}/prepared" "${KB_ROOT}/cosmetics-household-chemistry" "${OUTSIDE_ROOT}" "${FIXTURE_DIR}"
bash "${REPO_ROOT}/operations/harness-phase2/bin/run_phase2_bundle.sh" "${PHASE2_RUN_ID}"

BASE_INTEGRATION="${FIXTURE_DIR}/kb.template.yaml"
write_integration "${BASE_INTEGRATION}"
BASE_INTEGRATION_REF="$(repo_ref "${BASE_INTEGRATION}")"

printf 'source capture bytes\n' > "${KB_ROOT}/prepared/source-capture.txt"
SOURCE_HASH="$(sha256_of "${KB_ROOT}/prepared/source-capture.txt")"
printf '# Knowledge asset\n\nStable bytes.\n' > "${KB_ROOT}/prepared/knowledge.md"
KNOWLEDGE_HASH="$(sha256_of "${KB_ROOT}/prepared/knowledge.md")"

make_manifest_and_target "phase3-kb-admission-source-pass" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/source-capture.txt"
run_kb "phase3-kb-admission-source-pass"
assert_exit_code "phase3-kb-admission-source-pass" "0"
[[ "$(sha256_of "${KB_ROOT}/cosmetics-household-chemistry/source-capture.txt")" == "${SOURCE_HASH}" ]] || fail "source destination hash mismatch"
[[ -f "${PHASE3_ROOT}/runs/phase3-kb-admission-source-pass/input/admission_manifest.json" ]] || fail "missing frozen manifest"
[[ -f "${PHASE3_ROOT}/runs/phase3-kb-admission-source-pass/input/kb_integration.yaml" ]] || fail "missing frozen KB integration"
assert_action "phase3-kb-admission-source-pass" "copied" "destination_missing"

make_manifest_and_target "phase3-kb-admission-knowledge-pass" "knowledge_asset" "prepared/knowledge.md" "${KNOWLEDGE_HASH}" "cosmetics-household-chemistry/knowledge.md"
run_kb "phase3-kb-admission-knowledge-pass"
assert_exit_code "phase3-kb-admission-knowledge-pass" "0"
[[ "$(sha256_of "${KB_ROOT}/cosmetics-household-chemistry/knowledge.md")" == "${KNOWLEDGE_HASH}" ]] || fail "knowledge destination hash mismatch"
assert_action "phase3-kb-admission-knowledge-pass" "copied" "destination_missing"

make_manifest_and_target "phase3-kb-admission-idempotent" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/source-capture.txt"
run_kb "phase3-kb-admission-idempotent"
assert_exit_code "phase3-kb-admission-idempotent" "0"
assert_action "phase3-kb-admission-idempotent" "idempotent" "same_hash_existing"

printf 'different existing bytes\n' > "${KB_ROOT}/cosmetics-household-chemistry/unsafe-overwrite.txt"
make_manifest_and_target "phase3-kb-admission-unsafe-overwrite" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/unsafe-overwrite.txt"
expect_failure "phase3-kb-admission-unsafe-overwrite" run_kb "phase3-kb-admission-unsafe-overwrite"
assert_exit_code "phase3-kb-admission-unsafe-overwrite" "1"
assert_action "phase3-kb-admission-unsafe-overwrite" "failed_closed" "different_hash_existing"
[[ "$(cat "${KB_ROOT}/cosmetics-household-chemistry/unsafe-overwrite.txt")" == "different existing bytes" ]] || fail "unsafe overwrite mutated destination"

printf 'atomic new bytes\n' > "${KB_ROOT}/prepared/atomic-new.txt"
printf 'atomic second new bytes\n' > "${KB_ROOT}/prepared/atomic-second.txt"
printf 'atomic existing bytes\n' > "${KB_ROOT}/cosmetics-household-chemistry/atomic-blocked.txt"
ATOMIC_MANIFEST="${PHASE3_ROOT}/runs/phase3-kb-admission-atomic-preflight-target/admission_manifest.json"
write_two_artifact_manifest \
  "${ATOMIC_MANIFEST}" \
  "prepared/atomic-new.txt" "$(sha256_of "${KB_ROOT}/prepared/atomic-new.txt")" "cosmetics-household-chemistry/atomic-would-copy.txt" \
  "prepared/atomic-second.txt" "$(sha256_of "${KB_ROOT}/prepared/atomic-second.txt")" "cosmetics-household-chemistry/atomic-blocked.txt"
write_target "phase3-kb-admission-atomic-preflight" "${BASE_INTEGRATION_REF}" "$(repo_ref "${ATOMIC_MANIFEST}")"
expect_failure "phase3-kb-admission-atomic-preflight" run_kb "phase3-kb-admission-atomic-preflight"
assert_exit_code "phase3-kb-admission-atomic-preflight" "1"
[[ ! -e "${KB_ROOT}/cosmetics-household-chemistry/atomic-would-copy.txt" ]] || fail "atomic preflight created first destination"
[[ "$(cat "${KB_ROOT}/cosmetics-household-chemistry/atomic-blocked.txt")" == "atomic existing bytes" ]] || fail "atomic preflight mutated blocked destination"
assert_atomic_evidence "phase3-kb-admission-atomic-preflight"

make_manifest_and_target "phase3-kb-admission-missing-env" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/missing-env.txt"
expect_failure "phase3-kb-admission-missing-env" run_kb_without_env "phase3-kb-admission-missing-env"
assert_exit_code "phase3-kb-admission-missing-env" "1"
assert_pre_apply_failed "phase3-kb-admission-missing-env"
[[ ! -e "${KB_ROOT}/cosmetics-household-chemistry/missing-env.txt" ]] || fail "missing env wrote destination"

make_manifest_and_target "phase3-kb-admission-empty-env" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/empty-env.txt"
expect_failure "phase3-kb-admission-empty-env" run_kb "phase3-kb-admission-empty-env" ""
assert_exit_code "phase3-kb-admission-empty-env" "1"
assert_pre_apply_failed "phase3-kb-admission-empty-env"

make_manifest_and_target "phase3-kb-admission-nonexistent-root" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/nonexistent-root.txt"
expect_failure "phase3-kb-admission-nonexistent-root" run_kb "phase3-kb-admission-nonexistent-root" "${TMP_DIR}/does-not-exist"
assert_exit_code "phase3-kb-admission-nonexistent-root" "1"
assert_pre_apply_failed "phase3-kb-admission-nonexistent-root"

ROOT_INSIDE_RUN="phase3-kb-admission-root-inside-repo"
ROOT_INSIDE_DIR="${PHASE3_ROOT}/runs/${ROOT_INSIDE_RUN}-inside-root"
mkdir -p "${ROOT_INSIDE_DIR}/prepared"
printf 'inside repo root bytes\n' > "${ROOT_INSIDE_DIR}/prepared/source.txt"
make_manifest_and_target "${ROOT_INSIDE_RUN}" "source_capture" "prepared/source.txt" "$(sha256_of "${ROOT_INSIDE_DIR}/prepared/source.txt")" "dest.txt"
expect_failure "${ROOT_INSIDE_RUN}" run_kb "${ROOT_INSIDE_RUN}" "${ROOT_INSIDE_DIR}"
assert_exit_code "${ROOT_INSIDE_RUN}" "1"
assert_pre_apply_failed "${ROOT_INSIDE_RUN}"

ROOT_SYMLINK="${TMP_DIR}/workspace-kb-link"
ln -s "${KB_ROOT}" "${ROOT_SYMLINK}"
make_manifest_and_target "phase3-kb-admission-root-symlink" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/root-symlink.txt"
expect_failure "phase3-kb-admission-root-symlink" run_kb "phase3-kb-admission-root-symlink" "${ROOT_SYMLINK}"
assert_exit_code "phase3-kb-admission-root-symlink" "1"
assert_pre_apply_failed "phase3-kb-admission-root-symlink"

make_manifest_and_target "phase3-kb-admission-absolute-destination" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "${TMP_DIR}/absolute-bad.txt"
expect_failure "phase3-kb-admission-absolute-destination" run_kb "phase3-kb-admission-absolute-destination"
assert_exit_code "phase3-kb-admission-absolute-destination" "1"
assert_pre_apply_failed "phase3-kb-admission-absolute-destination"
[[ ! -e "${TMP_DIR}/absolute-bad.txt" ]] || fail "absolute destination was written"

make_manifest_and_target "phase3-kb-admission-traversal-destination" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "../outside.txt"
expect_failure "phase3-kb-admission-traversal-destination" run_kb "phase3-kb-admission-traversal-destination"
assert_exit_code "phase3-kb-admission-traversal-destination" "1"
assert_pre_apply_failed "phase3-kb-admission-traversal-destination"

ln -s "${OUTSIDE_ROOT}" "${KB_ROOT}/link-out"
make_manifest_and_target "phase3-kb-admission-symlink-traversal" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "link-out/bad.txt"
expect_failure "phase3-kb-admission-symlink-traversal" run_kb "phase3-kb-admission-symlink-traversal"
assert_exit_code "phase3-kb-admission-symlink-traversal" "1"
assert_pre_apply_failed "phase3-kb-admission-symlink-traversal"
[[ ! -e "${OUTSIDE_ROOT}/bad.txt" ]] || fail "symlink traversal destination was written"

mkdir -p "${KB_ROOT}/nested"
ln -s "${OUTSIDE_ROOT}" "${KB_ROOT}/nested/link-out"
make_manifest_and_target "phase3-kb-admission-nested-symlink" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "nested/link-out/bad.txt"
expect_failure "phase3-kb-admission-nested-symlink" run_kb "phase3-kb-admission-nested-symlink"
assert_exit_code "phase3-kb-admission-nested-symlink" "1"
assert_pre_apply_failed "phase3-kb-admission-nested-symlink"
[[ ! -e "${OUTSIDE_ROOT}/bad.txt" ]] || fail "nested symlink traversal destination was written"

make_manifest_and_target "phase3-kb-admission-same-source-destination" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "prepared/source-capture.txt"
expect_failure "phase3-kb-admission-same-source-destination" run_kb "phase3-kb-admission-same-source-destination"
assert_exit_code "phase3-kb-admission-same-source-destination" "1"
assert_pre_apply_failed "phase3-kb-admission-same-source-destination"

BAD_INTEGRATION_ABS_MANIFEST="${PHASE3_ROOT}/runs/phase3-kb-admission-bad-integration-absolute-target/admission_manifest.json"
write_manifest "${BAD_INTEGRATION_ABS_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/bad-integration-absolute.txt"
write_target "phase3-kb-admission-bad-integration-absolute" "/tmp/bad-kb-template.yaml" "$(repo_ref "${BAD_INTEGRATION_ABS_MANIFEST}")"
expect_failure "phase3-kb-admission-bad-integration-absolute" run_kb "phase3-kb-admission-bad-integration-absolute"
assert_exit_code "phase3-kb-admission-bad-integration-absolute" "1"

BAD_INTEGRATION_TRAVERSAL_MANIFEST="${PHASE3_ROOT}/runs/phase3-kb-admission-bad-integration-traversal-target/admission_manifest.json"
write_manifest "${BAD_INTEGRATION_TRAVERSAL_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/bad-integration-traversal.txt"
write_target "phase3-kb-admission-bad-integration-traversal" "../kb.template.yaml" "$(repo_ref "${BAD_INTEGRATION_TRAVERSAL_MANIFEST}")"
expect_failure "phase3-kb-admission-bad-integration-traversal" run_kb "phase3-kb-admission-bad-integration-traversal"
assert_exit_code "phase3-kb-admission-bad-integration-traversal" "1"

BAD_INTEGRATION_LINK="${FIXTURE_DIR}/outside-integration-link.yaml"
printf 'version: 1\n' > "${TMP_DIR}/outside-integration.yaml"
ln -s "${TMP_DIR}/outside-integration.yaml" "${BAD_INTEGRATION_LINK}"
BAD_INTEGRATION_LINK_MANIFEST="${PHASE3_ROOT}/runs/phase3-kb-admission-bad-integration-symlink-target/admission_manifest.json"
write_manifest "${BAD_INTEGRATION_LINK_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/bad-integration-symlink.txt"
write_target "phase3-kb-admission-bad-integration-symlink" "$(repo_ref "${BAD_INTEGRATION_LINK}")" "$(repo_ref "${BAD_INTEGRATION_LINK_MANIFEST}")"
expect_failure "phase3-kb-admission-bad-integration-symlink" run_kb "phase3-kb-admission-bad-integration-symlink"
assert_exit_code "phase3-kb-admission-bad-integration-symlink" "1"

write_target "phase3-kb-admission-bad-manifest-absolute" "${BASE_INTEGRATION_REF}" "/tmp/bad-manifest.json"
expect_failure "phase3-kb-admission-bad-manifest-absolute" run_kb "phase3-kb-admission-bad-manifest-absolute"
assert_exit_code "phase3-kb-admission-bad-manifest-absolute" "1"

write_target "phase3-kb-admission-bad-manifest-traversal" "${BASE_INTEGRATION_REF}" "../bad-manifest.json"
expect_failure "phase3-kb-admission-bad-manifest-traversal" run_kb "phase3-kb-admission-bad-manifest-traversal"
assert_exit_code "phase3-kb-admission-bad-manifest-traversal" "1"

BAD_MANIFEST_LINK="${FIXTURE_DIR}/outside-manifest-link.json"
write_manifest "${TMP_DIR}/outside-manifest.json" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/bad-manifest-symlink.txt"
ln -s "${TMP_DIR}/outside-manifest.json" "${BAD_MANIFEST_LINK}"
write_target "phase3-kb-admission-bad-manifest-symlink" "${BASE_INTEGRATION_REF}" "$(repo_ref "${BAD_MANIFEST_LINK}")"
expect_failure "phase3-kb-admission-bad-manifest-symlink" run_kb "phase3-kb-admission-bad-manifest-symlink"
assert_exit_code "phase3-kb-admission-bad-manifest-symlink" "1"

INVALID_INTEGRATION="${FIXTURE_DIR}/invalid-kb.template.yaml"
write_invalid_integration "${INVALID_INTEGRATION}"
INVALID_INTEGRATION_MANIFEST="${PHASE3_ROOT}/runs/phase3-kb-admission-invalid-integration-target/admission_manifest.json"
write_manifest "${INVALID_INTEGRATION_MANIFEST}" "source_capture" "prepared/source-capture.txt" "${SOURCE_HASH}" "cosmetics-household-chemistry/invalid-integration.txt"
write_target "phase3-kb-admission-invalid-integration" "$(repo_ref "${INVALID_INTEGRATION}")" "$(repo_ref "${INVALID_INTEGRATION_MANIFEST}")"
expect_failure "phase3-kb-admission-invalid-integration" run_kb "phase3-kb-admission-invalid-integration"
assert_exit_code "phase3-kb-admission-invalid-integration" "1"
assert_pre_apply_failed "phase3-kb-admission-invalid-integration"

INVALID_MANIFEST="${PHASE3_ROOT}/runs/phase3-kb-admission-invalid-manifest-target/admission_manifest.json"
write_invalid_manifest "${INVALID_MANIFEST}"
write_target "phase3-kb-admission-invalid-manifest" "${BASE_INTEGRATION_REF}" "$(repo_ref "${INVALID_MANIFEST}")"
expect_failure "phase3-kb-admission-invalid-manifest" run_kb "phase3-kb-admission-invalid-manifest"
assert_exit_code "phase3-kb-admission-invalid-manifest" "1"
assert_pre_apply_failed "phase3-kb-admission-invalid-manifest"

echo "PASS kb_admission source_capture pass into temp workspace KB root"
echo "PASS kb_admission knowledge_asset pass into temp workspace KB root"
echo "PASS kb_admission idempotent rerun with same hash"
echo "PASS kb_admission unsafe overwrite fails closed"
echo "PASS kb_admission atomic preflight prevents partial writes"
echo "PASS kb_admission missing/empty/nonexistent env root failures"
echo "PASS kb_admission rejects repo and symlink KB roots"
echo "PASS kb_admission rejects unsafe destination paths and symlink traversal"
echo "PASS kb_admission rejects same source/destination path"
echo "PASS kb_admission rejects bad refs before write"
echo "PASS kb_admission rejects invalid integration and manifest before write"
