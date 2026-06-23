#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMISSION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ADMISSION_ROOT}/../.." && pwd)"
PYTHON_BIN="${ADMISSION_TEST_PYTHON_BIN:-${PYTHON:-python3}}"
TMP_PARENT="${TMPDIR:-/tmp}"
TMP_ROOT="$(mktemp -d "${TMP_PARENT%/}/admission-stage2.XXXXXX")"
CASE_INDEX=0

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && -d "${TMP_ROOT}" && "${TMP_ROOT}" == "${TMP_PARENT%/}"/admission-stage2.* ]]; then
    rm -rf "${TMP_ROOT}"
  fi
}
trap cleanup EXIT

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

snapshot_repo_surfaces() {
  "${PYTHON_BIN}" - "${REPO_ROOT}" <<'PY'
from __future__ import annotations

import hashlib
import json
import os
import stat
import sys
from pathlib import Path

repo = Path(sys.argv[1])
paths = [
    "knowledge/kb",
    "operations/harness-phase2/runs",
    "operations/harness-phase3/runs",
    "operations/harness-phase4/runs",
]


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def record(path: Path, rel: str | None = None) -> dict[str, object]:
    st = os.lstat(path)
    mode = st.st_mode
    item: dict[str, object] = {}
    if rel is not None:
        item["path"] = rel
    if stat.S_ISDIR(mode):
        item["type"] = "directory"
    elif stat.S_ISREG(mode):
        item["type"] = "file"
        item["sha256"] = file_sha256(path)
    elif stat.S_ISLNK(mode):
        item["type"] = "symlink"
        item["target"] = os.readlink(path)
    else:
        item["type"] = "other"
    return item


def snapshot(root: Path) -> dict[str, object]:
    if not root.exists() and not root.is_symlink():
        return {"state": "missing", "entries": []}
    root_record = record(root)
    if root_record["type"] != "directory":
        return {"state": root_record["type"], "entries": []}
    entries: list[dict[str, object]] = []
    for child in sorted(root.rglob("*")):
        entries.append(record(child, child.relative_to(root).as_posix()))
    return {"state": "directory", "entries": entries}


print(json.dumps({rel: snapshot(repo / rel) for rel in paths}, sort_keys=True))
PY
}

stage2_examples=(
  "operations/admission/examples/stage2/source_capture.v1/admission_handoff.json"
  "operations/admission/examples/stage2/knowledge_product_type.v1/admission_handoff.json"
  "operations/admission/examples/stage2/knowledge_recipe_formula.v1/admission_handoff.json"
  "operations/admission/examples/stage2/knowledge_component.v1/admission_handoff.json"
)

before_snapshot="$(snapshot_repo_surfaces)"

"${PYTHON_BIN}" - "${REPO_ROOT}" "${stage2_examples[@]}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

repo = Path(sys.argv[1])
handoff_schema_path = repo / "operations/admission/schemas/admission_handoff.v1.schema.json"
target_schema_path = repo / "operations/harness-phase3/contracts/execution_target.schema.json"
manifest_schema_path = repo / "operations/harness-phase3/contracts/kb_admission_manifest.schema.json"
schemas = {
    "handoff": json.loads(handoff_schema_path.read_text(encoding="utf-8")),
    "target": json.loads(target_schema_path.read_text(encoding="utf-8")),
    "manifest": json.loads(manifest_schema_path.read_text(encoding="utf-8")),
}
for schema in schemas.values():
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    Draft202012Validator.check_schema(schema)

for handoff_arg in sys.argv[2:]:
    handoff_path = repo / handoff_arg
    handoff = json.loads(handoff_path.read_text(encoding="utf-8"))
    handoff_errors = sorted(Draft202012Validator(schemas["handoff"]).iter_errors(handoff), key=lambda error: list(error.path))
    assert not handoff_errors, (handoff_arg, [error.message for error in handoff_errors])

    target_path = repo / handoff["phase_inputs"]["phase3_execution_target_ref"]
    target = json.loads(target_path.read_text(encoding="utf-8"))
    target_errors = sorted(Draft202012Validator(schemas["target"]).iter_errors(target), key=lambda error: list(error.path))
    assert not target_errors, (target_path.as_posix(), [error.message for error in target_errors])

    manifest_path = repo / handoff["phase_inputs"]["phase3_admission_manifest_ref"]
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest_errors = sorted(Draft202012Validator(schemas["manifest"]).iter_errors(manifest), key=lambda error: list(error.path))
    assert not manifest_errors, (manifest_path.as_posix(), [error.message for error in manifest_errors])
PY
printf 'PASS Stage 2 and Phase3 example schemas\n'

for example in "${stage2_examples[@]}"; do
  pass_case "Stage 2 handoff passes Phase2 readiness: ${example}" \
    "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${example}"
done

make_case() {
  local source_dir="$1"
  local case_name="$2"
  local case_dir="${TMP_ROOT}/${case_name}"
  mkdir -p "${case_dir}"
  cp -R "${source_dir}/." "${case_dir}/"
  printf '%s\n' "${case_dir}"
}

mutate_case() {
  local case_dir="$1"
  local mutation="$2"
  "${PYTHON_BIN}" - "${case_dir}" "${mutation}" <<'PY'
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

case_dir = Path(sys.argv[1])
mutation = sys.argv[2]
handoff_path = case_dir / "admission_handoff.json"
handoff = json.loads(handoff_path.read_text(encoding="utf-8"))

def rewrite_refs(obj: object) -> object:
    if isinstance(obj, dict):
        return {key: rewrite_refs(value) for key, value in obj.items()}
    if isinstance(obj, list):
        return [rewrite_refs(item) for item in obj]
    if isinstance(obj, str) and obj.startswith("operations/admission/examples/stage2/"):
        parts = obj.split("/")
        return case_dir.as_posix() + "/" + "/".join(parts[5:])
    return obj


handoff = rewrite_refs(handoff)
target_path = case_dir / "phase3" / "execution_target.json"
target = rewrite_refs(json.loads(target_path.read_text(encoding="utf-8")))
manifest_path = case_dir / "phase3" / "admission_manifest.json"
manifest = rewrite_refs(json.loads(manifest_path.read_text(encoding="utf-8")))
package_path = case_dir / "stage1" / "admission_package.json"
package = json.loads(package_path.read_text(encoding="utf-8"))
review_path = case_dir / "review" / "approval.json"

handoff["admission_package_ref"] = package_path.as_posix()
handoff["review_evidence"]["approval_ref"] = review_path.as_posix()
handoff["phase_inputs"]["phase2_admission_ref"] = handoff_path.as_posix()
handoff["phase_inputs"]["phase3_execution_target_ref"] = target_path.as_posix()
handoff["phase_inputs"]["phase3_admission_manifest_ref"] = manifest_path.as_posix()
target["admission_manifest_ref"] = manifest_path.as_posix()

if mutation == "unknown-kind":
    handoff["admission_kind"] = "future_kind"
elif mutation == "unknown-profile":
    package["knowledge_profile_id"] = "future_profile.v1"
    handoff["knowledge_profile_id"] = "future_profile.v1"
    manifest["lineage"]["knowledge_profile_id"] = "future_profile.v1"
elif mutation == "source-targets-knowledge":
    handoff["placement"]["asset_layer"] = "knowledge"
    handoff["placement"]["placement_policy_id"] = "kb_knowledge_domain_first.v1"
    handoff["placement"]["destination_root"] = "cosmetics/example-source-family/knowledge/source-capture-example"
elif mutation == "knowledge-targets-sources":
    handoff["placement"]["asset_layer"] = "sources"
    handoff["placement"]["placement_policy_id"] = "kb_source_domain_first.v1"
    handoff["placement"]["destination_root"] = "cosmetics/example-source-family/sources/product-type-example"
elif mutation == "role-first":
    handoff["placement"]["destination_root"] = "knowledge/cosmetics/example-source-family/product-type-example"
elif mutation == "asset-id-mismatch":
    handoff["asset_id"] = "different-asset-id"
elif mutation == "absolute-ref":
    handoff["phase_inputs"]["phase3_execution_target_ref"] = "/tmp/execution_target.json"
elif mutation == "traversal-ref":
    handoff["phase_inputs"]["phase3_execution_target_ref"] = "../execution_target.json"
elif mutation == "manifest-type-mismatch":
    manifest["admission_type"] = "source_capture"
else:
    raise SystemExit(f"unknown mutation: {mutation}")

package_path.write_text(json.dumps(package, indent=2, sort_keys=True) + "\n", encoding="utf-8")
target_path.write_text(json.dumps(target, indent=2, sort_keys=True) + "\n", encoding="utf-8")
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
handoff["admission_package_sha256"] = hashlib.sha256(package_path.read_bytes()).hexdigest()
handoff_path.write_text(json.dumps(handoff, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

source_case="$(make_case operations/admission/examples/stage2/source_capture.v1 source-targets-knowledge)"
mutate_case "${source_case}" "source-targets-knowledge"
fail_case "Stage 2 rejects source_capture targeting knowledge layer" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${source_case}/admission_handoff.json"

knowledge_case="$(make_case operations/admission/examples/stage2/knowledge_product_type.v1 knowledge-targets-sources)"
mutate_case "${knowledge_case}" "knowledge-targets-sources"
fail_case "Stage 2 rejects knowledge_asset targeting sources layer" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${knowledge_case}/admission_handoff.json"

for mutation in unknown-kind unknown-profile role-first asset-id-mismatch absolute-ref traversal-ref manifest-type-mismatch; do
  case_dir="$(make_case operations/admission/examples/stage2/knowledge_product_type.v1 "${mutation}")"
  mutate_case "${case_dir}" "${mutation}"
  fail_case "Stage 2 rejects ${mutation}" \
    "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${case_dir}/admission_handoff.json"
done

after_snapshot="$(snapshot_repo_surfaces)"
[[ "${before_snapshot}" == "${after_snapshot}" ]] || {
  printf 'FAIL Stage 2 tests changed KB or Phase run surfaces\n' >&2
  exit 1
}

printf 'PASS admission Stage 2 handoff validation\n'
