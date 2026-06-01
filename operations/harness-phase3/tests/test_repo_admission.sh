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

PHASE2_RUN_ID="phase3-repo-admission-phase2-input"
PHASE2_RUN_DIR="${REPO_ROOT}/operations/harness-phase2/runs/${PHASE2_RUN_ID}"
FIXTURE_DIR="${PHASE3_ROOT}/runs/phase3-repo-admission-fixtures"
KB_TEST_ROOT="${REPO_ROOT}/knowledge/kb/sources/phase3-repo-admission-test"
KB_KNOWLEDGE_TEST_ROOT="${REPO_ROOT}/knowledge/kb/knowledge/phase3-repo-admission-test"

RUN_IDS=(
  "phase3-repo-admission-source-pass"
  "phase3-repo-admission-knowledge-pass"
  "phase3-repo-admission-unsafe-destination"
  "phase3-repo-admission-unsafe-overwrite"
  "phase3-repo-admission-atomic-preflight"
  "phase3-repo-admission-hash-mismatch"
  "phase3-repo-admission-staging-still-passes"
)

cleanup() {
  rm -rf "${TMP_DIR}" "${PHASE2_RUN_DIR}" "${FIXTURE_DIR}" "${KB_TEST_ROOT}" "${KB_KNOWLEDGE_TEST_ROOT}"
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

write_repo_admission_target() {
  local run_id="$1"
  local manifest_ref="$2"
  local target_dir="${PHASE3_ROOT}/runs/${run_id}-target"
  mkdir -p "${target_dir}"
  cat > "${target_dir}/execution_target.json" <<EOF
{
  "target_runtime": "repo",
  "target_kind": "repo_admission",
  "admission_manifest_ref": "${manifest_ref}",
  "invoked_by": "test://phase3-repo-admission"
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
    "source_ref": "test://phase3-repo-admission/${admission_type}",
    "captured_from": "repo-test-fixture",
    "captured_at": "2026-06-01T00:00:00Z",
    "parent_refs": []
  },
  "copy_operation": {
    "operation_type": "copy",
    "content_mode": "byte_for_byte",
    "overwrite_policy": "fail_closed_on_hash_mismatch",
    "requested_by": "test://phase3-repo-admission"
  },
  "artifacts": [
    {
      "input_artifact_ref": "${source_ref}",
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
    "source_ref": "test://phase3-repo-admission/atomic-preflight",
    "captured_from": "repo-test-fixture",
    "captured_at": "2026-06-01T00:00:00Z",
    "parent_refs": []
  },
  "copy_operation": {
    "operation_type": "copy",
    "content_mode": "byte_for_byte",
    "overwrite_policy": "fail_closed_on_hash_mismatch",
    "requested_by": "test://phase3-repo-admission"
  },
  "artifacts": [
    {
      "input_artifact_ref": "${source_ref_1}",
      "expected_sha256": "${expected_sha_1}",
      "destination_kb_path": "${destination_ref_1}",
      "copy_metadata": {
        "label": "atomic preflight would copy"
      }
    },
    {
      "input_artifact_ref": "${source_ref_2}",
      "expected_sha256": "${expected_sha_2}",
      "destination_kb_path": "${destination_ref_2}",
      "copy_metadata": {
        "label": "atomic preflight blocks overwrite"
      }
    }
  ]
}
EOF
}

run_repo_admission() {
  local run_id="$1"
  bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
    --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
    --execution-target-json "operations/harness-phase3/runs/${run_id}-target/execution_target.json" \
    --run-id "${run_id}"
}

run_repo_admission_expect_failure() {
  local run_id="$1"
  local log_path="${TMP_DIR}/${run_id}.log"
  set +e
  run_repo_admission "${run_id}" >"${log_path}" 2>&1
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

assert_repo_evidence_action() {
  local run_id="$1"
  local expected_action="$2"
  local expected_verdict="$3"
  "${PYTHON_BIN}" - "${PHASE3_ROOT}/runs/${run_id}/checks/repo_admission_evidence.json" "${expected_action}" "${expected_verdict}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
item = payload["evidence"][0]
assert item["manifest_hash"], payload
assert item["source_artifact_hash"], payload
assert item["destination_path"], payload
assert item["action"] == sys.argv[2], payload
assert item["overwrite_verdict"] == sys.argv[3], payload
if sys.argv[2] != "failed_closed":
    assert item["final_destination_hash"], payload
PY
}

assert_atomic_preflight_evidence() {
  local run_id="$1"
  "${PYTHON_BIN}" - "${PHASE3_ROOT}/runs/${run_id}/checks/repo_admission_evidence.json" <<'PY'
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

rm -rf "${PHASE2_RUN_DIR}" "${FIXTURE_DIR}" "${KB_TEST_ROOT}" "${KB_KNOWLEDGE_TEST_ROOT}"
for run_id in "${RUN_IDS[@]}"; do
  rm -rf "${PHASE3_ROOT}/runs/${run_id}" "${PHASE3_ROOT}/runs/${run_id}-target"
done
trap cleanup EXIT

mkdir -p "${FIXTURE_DIR}"
bash "${REPO_ROOT}/operations/harness-phase2/bin/run_phase2_bundle.sh" "${PHASE2_RUN_ID}"

SOURCE_PASS_RUN="phase3-repo-admission-source-pass"
SOURCE_PASS_FILE="${FIXTURE_DIR}/source-pass.txt"
SOURCE_PASS_DEST="knowledge/kb/sources/phase3-repo-admission-test/source-pass.txt"
printf 'source admission bytes\n' > "${SOURCE_PASS_FILE}"
SOURCE_PASS_REF="$(repo_ref "${SOURCE_PASS_FILE}")"
SOURCE_PASS_HASH="$(sha256_of "${SOURCE_PASS_FILE}")"
SOURCE_PASS_MANIFEST="${PHASE3_ROOT}/runs/${SOURCE_PASS_RUN}-target/admission_manifest.json"
write_manifest "${SOURCE_PASS_MANIFEST}" "source_capture" "${SOURCE_PASS_REF}" "${SOURCE_PASS_HASH}" "${SOURCE_PASS_DEST}"
write_repo_admission_target "${SOURCE_PASS_RUN}" "$(repo_ref "${SOURCE_PASS_MANIFEST}")"
run_repo_admission "${SOURCE_PASS_RUN}"
assert_exit_code "${SOURCE_PASS_RUN}" "0"
[[ "$(sha256_of "${REPO_ROOT}/${SOURCE_PASS_DEST}")" == "${SOURCE_PASS_HASH}" ]] || fail "source admission destination hash mismatch"
[[ -f "${PHASE3_ROOT}/runs/${SOURCE_PASS_RUN}/input/admission_manifest.json" ]] || fail "missing frozen admission manifest"
assert_repo_evidence_action "${SOURCE_PASS_RUN}" "copied" "destination_missing"

KNOWLEDGE_PASS_RUN="phase3-repo-admission-knowledge-pass"
KNOWLEDGE_PASS_FILE="${FIXTURE_DIR}/knowledge-pass.md"
KNOWLEDGE_PASS_DEST="knowledge/kb/knowledge/phase3-repo-admission-test/knowledge-pass.md"
printf '# Knowledge admission\n\nStable bytes.\n' > "${KNOWLEDGE_PASS_FILE}"
KNOWLEDGE_PASS_REF="$(repo_ref "${KNOWLEDGE_PASS_FILE}")"
KNOWLEDGE_PASS_HASH="$(sha256_of "${KNOWLEDGE_PASS_FILE}")"
mkdir -p "$(dirname "${REPO_ROOT}/${KNOWLEDGE_PASS_DEST}")"
cp "${KNOWLEDGE_PASS_FILE}" "${REPO_ROOT}/${KNOWLEDGE_PASS_DEST}"
KNOWLEDGE_PASS_MANIFEST="${PHASE3_ROOT}/runs/${KNOWLEDGE_PASS_RUN}-target/admission_manifest.json"
write_manifest "${KNOWLEDGE_PASS_MANIFEST}" "knowledge_asset" "${KNOWLEDGE_PASS_REF}" "${KNOWLEDGE_PASS_HASH}" "${KNOWLEDGE_PASS_DEST}"
write_repo_admission_target "${KNOWLEDGE_PASS_RUN}" "$(repo_ref "${KNOWLEDGE_PASS_MANIFEST}")"
run_repo_admission "${KNOWLEDGE_PASS_RUN}"
assert_exit_code "${KNOWLEDGE_PASS_RUN}" "0"
assert_repo_evidence_action "${KNOWLEDGE_PASS_RUN}" "idempotent" "same_hash_existing"

UNSAFE_DEST_RUN="phase3-repo-admission-unsafe-destination"
UNSAFE_DEST_MANIFEST="${PHASE3_ROOT}/runs/${UNSAFE_DEST_RUN}-target/admission_manifest.json"
write_manifest "${UNSAFE_DEST_MANIFEST}" "source_capture" "${SOURCE_PASS_REF}" "${SOURCE_PASS_HASH}" "docs/phase3-repo-admission-bad.txt"
write_repo_admission_target "${UNSAFE_DEST_RUN}" "$(repo_ref "${UNSAFE_DEST_MANIFEST}")"
run_repo_admission_expect_failure "${UNSAFE_DEST_RUN}"
assert_exit_code "${UNSAFE_DEST_RUN}" "1"
[[ ! -e "${REPO_ROOT}/docs/phase3-repo-admission-bad.txt" ]] || fail "unsafe destination was written"

UNSAFE_OVERWRITE_RUN="phase3-repo-admission-unsafe-overwrite"
UNSAFE_OVERWRITE_FILE="${FIXTURE_DIR}/unsafe-overwrite.txt"
UNSAFE_OVERWRITE_DEST="knowledge/kb/sources/phase3-repo-admission-test/unsafe-overwrite.txt"
printf 'new bytes\n' > "${UNSAFE_OVERWRITE_FILE}"
UNSAFE_OVERWRITE_REF="$(repo_ref "${UNSAFE_OVERWRITE_FILE}")"
UNSAFE_OVERWRITE_HASH="$(sha256_of "${UNSAFE_OVERWRITE_FILE}")"
mkdir -p "$(dirname "${REPO_ROOT}/${UNSAFE_OVERWRITE_DEST}")"
printf 'existing different bytes\n' > "${REPO_ROOT}/${UNSAFE_OVERWRITE_DEST}"
UNSAFE_OVERWRITE_MANIFEST="${PHASE3_ROOT}/runs/${UNSAFE_OVERWRITE_RUN}-target/admission_manifest.json"
write_manifest "${UNSAFE_OVERWRITE_MANIFEST}" "source_capture" "${UNSAFE_OVERWRITE_REF}" "${UNSAFE_OVERWRITE_HASH}" "${UNSAFE_OVERWRITE_DEST}"
write_repo_admission_target "${UNSAFE_OVERWRITE_RUN}" "$(repo_ref "${UNSAFE_OVERWRITE_MANIFEST}")"
run_repo_admission_expect_failure "${UNSAFE_OVERWRITE_RUN}"
assert_exit_code "${UNSAFE_OVERWRITE_RUN}" "1"
assert_repo_evidence_action "${UNSAFE_OVERWRITE_RUN}" "failed_closed" "different_hash_existing"
[[ "$(cat "${REPO_ROOT}/${UNSAFE_OVERWRITE_DEST}")" == "existing different bytes" ]] || fail "unsafe overwrite mutated destination"

ATOMIC_RUN="phase3-repo-admission-atomic-preflight"
ATOMIC_FILE_1="${FIXTURE_DIR}/atomic-would-copy.txt"
ATOMIC_FILE_2="${FIXTURE_DIR}/atomic-blocked-overwrite.txt"
ATOMIC_DEST_1="knowledge/kb/sources/phase3-repo-admission-test/atomic-would-copy.txt"
ATOMIC_DEST_2="knowledge/kb/sources/phase3-repo-admission-test/atomic-blocked-overwrite.txt"
printf 'atomic would copy bytes\n' > "${ATOMIC_FILE_1}"
printf 'atomic new bytes\n' > "${ATOMIC_FILE_2}"
ATOMIC_REF_1="$(repo_ref "${ATOMIC_FILE_1}")"
ATOMIC_REF_2="$(repo_ref "${ATOMIC_FILE_2}")"
ATOMIC_HASH_1="$(sha256_of "${ATOMIC_FILE_1}")"
ATOMIC_HASH_2="$(sha256_of "${ATOMIC_FILE_2}")"
mkdir -p "$(dirname "${REPO_ROOT}/${ATOMIC_DEST_2}")"
printf 'existing atomic different bytes\n' > "${REPO_ROOT}/${ATOMIC_DEST_2}"
ATOMIC_MANIFEST="${PHASE3_ROOT}/runs/${ATOMIC_RUN}-target/admission_manifest.json"
write_two_artifact_manifest \
  "${ATOMIC_MANIFEST}" \
  "${ATOMIC_REF_1}" \
  "${ATOMIC_HASH_1}" \
  "${ATOMIC_DEST_1}" \
  "${ATOMIC_REF_2}" \
  "${ATOMIC_HASH_2}" \
  "${ATOMIC_DEST_2}"
write_repo_admission_target "${ATOMIC_RUN}" "$(repo_ref "${ATOMIC_MANIFEST}")"
run_repo_admission_expect_failure "${ATOMIC_RUN}"
assert_exit_code "${ATOMIC_RUN}" "1"
[[ ! -e "${REPO_ROOT}/${ATOMIC_DEST_1}" ]] || fail "atomic preflight created first destination before full plan passed"
[[ "$(cat "${REPO_ROOT}/${ATOMIC_DEST_2}")" == "existing atomic different bytes" ]] || fail "atomic preflight mutated blocked destination"
assert_atomic_preflight_evidence "${ATOMIC_RUN}"

HASH_MISMATCH_RUN="phase3-repo-admission-hash-mismatch"
HASH_MISMATCH_DEST="knowledge/kb/sources/phase3-repo-admission-test/hash-mismatch.txt"
HASH_MISMATCH_MANIFEST="${PHASE3_ROOT}/runs/${HASH_MISMATCH_RUN}-target/admission_manifest.json"
write_manifest "${HASH_MISMATCH_MANIFEST}" "source_capture" "${SOURCE_PASS_REF}" "0000000000000000000000000000000000000000000000000000000000000000" "${HASH_MISMATCH_DEST}"
write_repo_admission_target "${HASH_MISMATCH_RUN}" "$(repo_ref "${HASH_MISMATCH_MANIFEST}")"
run_repo_admission_expect_failure "${HASH_MISMATCH_RUN}"
assert_exit_code "${HASH_MISMATCH_RUN}" "1"
[[ ! -e "${REPO_ROOT}/${HASH_MISMATCH_DEST}" ]] || fail "hash mismatch destination was written"

STAGING_RUN="phase3-repo-admission-staging-still-passes"
STAGING_TARGET_DIR="${PHASE3_ROOT}/runs/${STAGING_RUN}-target"
mkdir -p "${STAGING_TARGET_DIR}"
cat > "${STAGING_TARGET_DIR}/execution_target.json" <<EOF
{
  "target_runtime": "openclaw",
  "target_kind": "phase3_staging",
  "target_ref": "operations/harness-phase3/runs/${STAGING_RUN}/staging/runtime-ready-applied",
  "apply_mode": "staged",
  "approval_ref": "manual://${STAGING_RUN}",
  "invoked_by": "test://phase3-repo-admission-staging"
}
EOF
bash "${PHASE3_ROOT}/bin/run_phase3_bundle.sh" \
  --phase2-run-dir "operations/harness-phase2/runs/${PHASE2_RUN_ID}" \
  --execution-target-json "operations/harness-phase3/runs/${STAGING_RUN}-target/execution_target.json" \
  --run-id "${STAGING_RUN}"
assert_exit_code "${STAGING_RUN}" "0"


echo "PASS repo admission source_capture copy"
echo "PASS repo admission knowledge_asset idempotent copy"
echo "PASS repo admission unsafe destination fails"
echo "PASS repo admission unsafe overwrite fails closed"
echo "PASS repo admission atomic preflight prevents partial writes"
echo "PASS repo admission hash mismatch fails"
echo "PASS existing phase3_staging behavior still passes"
