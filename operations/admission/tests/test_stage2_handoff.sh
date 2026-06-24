#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMISSION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ADMISSION_ROOT}/../.." && pwd)"
PYTHON_BIN="${ADMISSION_TEST_PYTHON_BIN:-${PYTHON:-python3}}"
TMP_PARENT="${SCRIPT_DIR}"
TMP_ROOT="$(mktemp -d "${TMP_PARENT%/}/.tmp-stage2.XXXXXX")"
CASE_INDEX=0

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && -d "${TMP_ROOT}" && "${TMP_ROOT}" == "${TMP_PARENT%/}"/.tmp-stage2.* ]]; then
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
  local expected="$2"
  local log_path
  shift 2
  CASE_INDEX=$((CASE_INDEX + 1))
  log_path="${TMP_ROOT}/case-${CASE_INDEX}.log"
  if "$@" >"${log_path}" 2>&1; then
    printf 'FAIL %s: expected failure but command passed\n' "${label}" >&2
    cat "${log_path}" >&2
    exit 1
  fi
  if ! grep -Fq "${expected}" "${log_path}"; then
    printf 'FAIL %s: expected diagnostic not found: %s\n' "${label}" "${expected}" >&2
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
TAXONOMY_CONFIG="$(realpath operations/admission/tests/fixtures/kb_taxonomy_config.noncanonical.json)"
RELATIVE_TAXONOMY_CONFIG="operations/admission/tests/fixtures/kb_taxonomy_config.noncanonical.json"
NONEXISTENT_TAXONOMY_CONFIG="${TMP_ROOT}/missing-taxonomy.json"
INVALID_TAXONOMY_CONFIG="${TMP_ROOT}/invalid-taxonomy.json"
INCONSISTENT_TAXONOMY_CONFIG="${TMP_ROOT}/inconsistent-taxonomy.json"
printf '{"config_kind":"kb_taxonomy_config"}\n' >"${INVALID_TAXONOMY_CONFIG}"
cat >"${INCONSISTENT_TAXONOMY_CONFIG}" <<'EOF'
{
  "config_kind": "kb_taxonomy_config",
  "config_version": 1,
  "local_only": true,
  "allowed_knowledge_types": [
    "example-product-type"
  ],
  "profile_knowledge_type_map": {
    "product_type_extraction.v1": [
      "missing-example-type"
    ]
  }
}
EOF

before_snapshot="$(snapshot_repo_surfaces)"

"${PYTHON_BIN}" - "${REPO_ROOT}" "${stage2_examples[@]}" <<'PY_STAGE2_SCHEMA'
from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

repo = Path(sys.argv[1])
handoff_schema_path = repo / "operations/admission/schemas/admission_handoff.v1.schema.json"
target_schema_path = repo / "operations/harness-phase3/contracts/execution_target.schema.json"
manifest_schema_path = repo / "operations/harness-phase3/contracts/kb_admission_manifest.schema.json"
review_schema_path = repo / "control-plane/contracts/schemas/review_decision.schema.json"
integration_schema_path = repo / "control-plane/contracts/schemas/kb_runtime_integration.schema.json"
schemas = {
    "handoff": json.loads(handoff_schema_path.read_text(encoding="utf-8")),
    "target": json.loads(target_schema_path.read_text(encoding="utf-8")),
    "manifest": json.loads(manifest_schema_path.read_text(encoding="utf-8")),
    "review": json.loads(review_schema_path.read_text(encoding="utf-8")),
    "integration": json.loads(integration_schema_path.read_text(encoding="utf-8")),
}
for schema in schemas.values():
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    Draft202012Validator.check_schema(schema)


def validate(schema_name: str, instance: object, source: Path | str) -> None:
    errors = sorted(Draft202012Validator(schemas[schema_name]).iter_errors(instance), key=lambda error: list(error.path))
    assert not errors, (str(source), [error.message for error in errors])


def load_structured(path: Path) -> object:
    if path.suffix in {".yaml", ".yml"}:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    return json.loads(path.read_text(encoding="utf-8"))


for handoff_arg in sys.argv[2:]:
    handoff_path = repo / handoff_arg
    handoff = json.loads(handoff_path.read_text(encoding="utf-8"))
    validate("handoff", handoff, handoff_arg)

    review_path = repo / handoff["review_evidence"]["approval_ref"]
    review = json.loads(review_path.read_text(encoding="utf-8"))
    validate("review", review, review_path)

    target_path = repo / handoff["phase_inputs"]["phase3_execution_target_ref"]
    target = json.loads(target_path.read_text(encoding="utf-8"))
    validate("target", target, target_path)

    integration_path = repo / target["kb_integration_ref"]
    integration = load_structured(integration_path)
    validate("integration", integration, integration_path)

    manifest_path = repo / handoff["phase_inputs"]["phase3_admission_manifest_ref"]
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    validate("manifest", manifest, manifest_path)

    for artifact in manifest["artifacts"]:
        input_path = artifact["input_workspace_path"]
        parts = input_path.split("/")
        assert not input_path.startswith("/"), input_path
        assert ".." not in parts, input_path
        assert len(parts) >= 4 and parts[2] == "workflow", input_path
        assert parts[0] not in {"operations", "docs", "control-plane"}, input_path
PY_STAGE2_SCHEMA
printf 'PASS Stage 2, Phase3, review, and KB integration example schemas
'

for example in "${stage2_examples[@]}"; do
  pass_case "Stage 2 handoff passes standalone policy preflight: ${example}" \
    env ADMISSION_KB_TAXONOMY_CONFIG="${TAXONOMY_CONFIG}" \
    "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${example}"
done

make_case() {
  local source_dir="$1"
  local case_name="$2"
  local case_dir="${TMP_ROOT}/${case_name}"
  mkdir -p "${case_dir}"
  cp -R "${source_dir}/." "${case_dir}/"
  realpath --relative-to="${REPO_ROOT}" "${case_dir}"
}

mutate_case() {
  local case_rel="$1"
  local mutation="$2"
  "${PYTHON_BIN}" - "${REPO_ROOT}" "${case_rel}" "${mutation}" <<'PY_STAGE2_MUTATE'
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

repo = Path(sys.argv[1])
case_rel = sys.argv[2]
case_dir = repo / case_rel
mutation = sys.argv[3]
handoff_path = case_dir / "admission_handoff.json"
handoff = json.loads(handoff_path.read_text(encoding="utf-8"))


def rewrite_refs(obj: object) -> object:
    if isinstance(obj, dict):
        return {key: rewrite_refs(value) for key, value in obj.items()}
    if isinstance(obj, list):
        return [rewrite_refs(item) for item in obj]
    if isinstance(obj, str) and obj.startswith("operations/admission/examples/stage2/"):
        parts = obj.split("/")
        return f"{case_rel}/" + "/".join(parts[5:])
    return obj


handoff = rewrite_refs(handoff)
target_path = case_dir / "phase3" / "execution_target.json"
target = rewrite_refs(json.loads(target_path.read_text(encoding="utf-8")))
manifest_path = case_dir / "phase3" / "admission_manifest.json"
manifest = rewrite_refs(json.loads(manifest_path.read_text(encoding="utf-8")))
package_path = case_dir / "stage1" / "admission_package.json"
package = json.loads(package_path.read_text(encoding="utf-8"))
review_path = case_dir / "review" / "approval.json"
review = json.loads(review_path.read_text(encoding="utf-8"))

handoff["admission_package_ref"] = f"{case_rel}/stage1/admission_package.json"
handoff["review_evidence"]["approval_ref"] = f"{case_rel}/review/approval.json"
handoff["phase_inputs"]["phase3_execution_target_ref"] = f"{case_rel}/phase3/execution_target.json"
handoff["phase_inputs"]["phase3_admission_manifest_ref"] = f"{case_rel}/phase3/admission_manifest.json"
target["admission_manifest_ref"] = f"{case_rel}/phase3/admission_manifest.json"
target["kb_integration_ref"] = "control-plane/runtime/integrations/kb.template.yaml"

if mutation == "none":
    pass
elif mutation == "humblebee-slug":
    asset_id = "humblebee-citrus-chamomile-liquid-shampoo-20260610"
    asset_slug = "citrus-chamomile-liquid-shampoo-20260610"
    package["asset_id"] = asset_id
    review["artifact_id"] = asset_id
    handoff["asset_id"] = asset_id
    handoff["placement"]["domain_area"] = "cosmetics-household-chemistry"
    handoff["placement"]["source_family_id"] = "humblebee-and-me"
    handoff["placement"]["asset_layer"] = "sources"
    handoff["placement"]["asset_slug"] = asset_slug
    handoff["placement"]["placement_policy_id"] = "kb_source_domain_first.v1"
    handoff["placement"]["destination_root"] = (
        f"cosmetics-household-chemistry/humblebee-and-me/sources/{asset_slug}"
    )
    manifest["admission_type"] = "source_capture"
    manifest["lineage"]["asset_id"] = asset_id
    manifest["lineage"].pop("knowledge_profile_id", None)
    for artifact in manifest["artifacts"]:
        filename = artifact["destination_kb_path"].rsplit("/", 1)[-1]
        artifact["destination_kb_path"] = (
            f"cosmetics-household-chemistry/humblebee-and-me/sources/{asset_slug}/{filename}"
        )
elif mutation == "unknown-kind":
    handoff["admission_kind"] = "future_kind"
elif mutation == "unknown-profile":
    package["knowledge_profile_id"] = "future_profile.v1"
    handoff["knowledge_profile_id"] = "future_profile.v1"
    manifest["lineage"]["knowledge_profile_id"] = "future_profile.v1"
elif mutation == "source-targets-knowledge":
    handoff["placement"]["destination_root"] = "cosmetics/example-source-family/knowledge/source-capture-example"
elif mutation == "knowledge-targets-sources":
    handoff["placement"]["destination_root"] = "cosmetics/example-source-family/sources/product-type-example"
elif mutation == "role-first":
    handoff["placement"]["destination_root"] = "knowledge/cosmetics/example-source-family/product-type-example"
elif mutation == "asset-id-mismatch":
    handoff["asset_id"] = "different-asset-id"
elif mutation == "missing-knowledge-type":
    handoff["placement"].pop("knowledge_type", None)
elif mutation == "unknown-knowledge-type":
    handoff["placement"]["knowledge_type"] = "unknown-example-type"
    handoff["placement"]["destination_root"] = "cosmetics/example-source-family/knowledge/unknown-example-type/product-type-example"
    for artifact in manifest["artifacts"]:
        filename = artifact["destination_kb_path"].rsplit("/", 1)[-1]
        artifact["destination_kb_path"] = f"cosmetics/example-source-family/knowledge/unknown-example-type/product-type-example/{filename}"
elif mutation == "profile-type-mismatch":
    handoff["placement"]["knowledge_type"] = "example-component"
    handoff["placement"]["destination_root"] = "cosmetics/example-source-family/knowledge/example-component/product-type-example"
    for artifact in manifest["artifacts"]:
        filename = artifact["destination_kb_path"].rsplit("/", 1)[-1]
        artifact["destination_kb_path"] = f"cosmetics/example-source-family/knowledge/example-component/product-type-example/{filename}"
elif mutation == "knowledge-type-slash":
    handoff["placement"]["knowledge_type"] = "bad/type"
elif mutation == "knowledge-type-traversal":
    handoff["placement"]["knowledge_type"] = ".."
elif mutation == "old-untyped-knowledge-path":
    handoff["placement"]["destination_root"] = "cosmetics/example-source-family/knowledge/product-type-example"
    for artifact in manifest["artifacts"]:
        filename = artifact["destination_kb_path"].rsplit("/", 1)[-1]
        artifact["destination_kb_path"] = f"cosmetics/example-source-family/knowledge/product-type-example/{filename}"
elif mutation == "source-has-knowledge-type":
    handoff["placement"]["knowledge_type"] = "example-product-type"
elif mutation == "missing-asset-slug":
    handoff["placement"].pop("asset_slug", None)
elif mutation == "asset-slug-slash":
    handoff["placement"]["asset_slug"] = "bad/slug"
elif mutation == "asset-slug-traversal":
    handoff["placement"]["asset_slug"] = ".."
elif mutation == "destination-uses-asset-id":
    handoff["placement"]["asset_slug"] = "product-type-local-slug"
    handoff["placement"]["destination_root"] = "cosmetics/example-source-family/knowledge/example-product-type/product-type-example"
    for artifact in manifest["artifacts"]:
        filename = artifact["destination_kb_path"].rsplit("/", 1)[-1]
        artifact["destination_kb_path"] = f"cosmetics/example-source-family/knowledge/example-product-type/product-type-example/{filename}"
elif mutation == "manifest-destination-outside-slug-root":
    handoff["placement"]["asset_slug"] = "product-type-local-slug"
    handoff["placement"]["destination_root"] = "cosmetics/example-source-family/knowledge/example-product-type/product-type-local-slug"
    for artifact in manifest["artifacts"]:
        filename = artifact["destination_kb_path"].rsplit("/", 1)[-1]
        artifact["destination_kb_path"] = f"cosmetics/example-source-family/knowledge/example-product-type/product-type-example/{filename}"
elif mutation == "absolute-ref":
    handoff["phase_inputs"]["phase3_execution_target_ref"] = "/tmp/execution_target.json"
elif mutation == "traversal-ref":
    handoff["phase_inputs"]["phase3_execution_target_ref"] = "../execution_target.json"
elif mutation == "manifest-type-mismatch":
    manifest["admission_type"] = "source_capture"
elif mutation == "review-malformed":
    review = {"decision": "approve"}
elif mutation == "review-existing-file":
    handoff["review_evidence"]["approval_ref"] = "operations/admission/schemas/admission_handoff.v1.schema.json"
elif mutation in {"review-reject", "review-hold", "review-return-for-revision"}:
    review["decision"] = mutation.removeprefix("review-").replace("-", "_")
elif mutation == "review-missing-destination":
    review.pop("approved_destination", None)
elif mutation == "review-wrong-destination":
    review["approved_destination"] = "obsidian"
elif mutation == "review-asset-mismatch":
    review["artifact_id"] = "different-asset-id"
else:
    raise SystemExit(f"unknown mutation: {mutation}")

package_path.write_text(json.dumps(package, indent=2, sort_keys=True) + "\n", encoding="utf-8")
review_path.write_text(json.dumps(review, indent=2, sort_keys=True) + "\n", encoding="utf-8")
target_path.write_text(json.dumps(target, indent=2, sort_keys=True) + "\n", encoding="utf-8")
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
handoff["admission_package_sha256"] = hashlib.sha256(package_path.read_bytes()).hexdigest()
handoff_path.write_text(json.dumps(handoff, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY_STAGE2_MUTATE
}

positive_case="$(make_case operations/admission/examples/stage2/knowledge_product_type.v1 generated-positive)"
mutate_case "${positive_case}" "none"
pass_case "Stage 2 generated repo-relative handoff passes standalone policy preflight" \
  env ADMISSION_KB_TAXONOMY_CONFIG="${TAXONOMY_CONFIG}" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${positive_case}/admission_handoff.json"

humblebee_case="$(make_case operations/admission/examples/stage2/source_capture.v1 humblebee-slug-positive)"
mutate_case "${humblebee_case}" "humblebee-slug"
pass_case "Stage 2 accepts Humblebee source with global asset_id and local asset_slug" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${humblebee_case}/admission_handoff.json"

missing_config_case="$(make_case operations/admission/examples/stage2/knowledge_product_type.v1 missing-taxonomy-config)"
mutate_case "${missing_config_case}" "none"
fail_case "Stage 2 knowledge_asset rejects missing taxonomy config" "ADMISSION_KB_TAXONOMY_CONFIG is required" \
  env -u ADMISSION_KB_TAXONOMY_CONFIG \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${missing_config_case}/admission_handoff.json"

invalid_config_case="$(make_case operations/admission/examples/stage2/knowledge_product_type.v1 invalid-taxonomy-config)"
mutate_case "${invalid_config_case}" "none"
fail_case "Stage 2 knowledge_asset rejects invalid taxonomy config" "'config_version' is a required property" \
  env ADMISSION_KB_TAXONOMY_CONFIG="${INVALID_TAXONOMY_CONFIG}" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${invalid_config_case}/admission_handoff.json"

relative_config_case="$(make_case operations/admission/examples/stage2/knowledge_product_type.v1 relative-taxonomy-config)"
mutate_case "${relative_config_case}" "none"
fail_case "Stage 2 knowledge_asset rejects relative taxonomy config path" "ADMISSION_KB_TAXONOMY_CONFIG must be an absolute path outside Git" \
  env ADMISSION_KB_TAXONOMY_CONFIG="${RELATIVE_TAXONOMY_CONFIG}" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${relative_config_case}/admission_handoff.json"

nonexistent_config_case="$(make_case operations/admission/examples/stage2/knowledge_product_type.v1 nonexistent-taxonomy-config)"
mutate_case "${nonexistent_config_case}" "none"
fail_case "Stage 2 knowledge_asset rejects nonexistent taxonomy config" "ADMISSION_KB_TAXONOMY_CONFIG does not reference an existing file" \
  env ADMISSION_KB_TAXONOMY_CONFIG="${NONEXISTENT_TAXONOMY_CONFIG}" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${nonexistent_config_case}/admission_handoff.json"

inconsistent_config_case="$(make_case operations/admission/examples/stage2/knowledge_product_type.v1 inconsistent-taxonomy-config)"
mutate_case "${inconsistent_config_case}" "none"
fail_case "Stage 2 knowledge_asset rejects internally inconsistent taxonomy config" "KB taxonomy config maps knowledge types not present in allowed_knowledge_types" \
  env ADMISSION_KB_TAXONOMY_CONFIG="${INCONSISTENT_TAXONOMY_CONFIG}" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${inconsistent_config_case}/admission_handoff.json"

diagnostic_mode_case="$(make_case operations/admission/examples/stage2/knowledge_product_type.v1 diagnostic-mode)"
mutate_case "${diagnostic_mode_case}" "none"
fail_case "Stage 2 shape-only diagnostic mode is not admission readiness" "shape-only diagnostic taxonomy mode is not admission readiness" \
  env ADMISSION_KB_TAXONOMY_MODE="shape-only-diagnostic" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${diagnostic_mode_case}/admission_handoff.json"

source_case="$(make_case operations/admission/examples/stage2/source_capture.v1 source-targets-knowledge)"
mutate_case "${source_case}" "source-targets-knowledge"
fail_case "Stage 2 rejects source_capture targeting knowledge layer" "placement.destination_root must follow domain-first layout"   "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${source_case}/admission_handoff.json"

source_type_case="$(make_case operations/admission/examples/stage2/source_capture.v1 source-has-knowledge-type)"
mutate_case "${source_type_case}" "source-has-knowledge-type"
fail_case "Stage 2 rejects knowledge_type on source_capture" "should not be valid under" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${source_type_case}/admission_handoff.json"

knowledge_case="$(make_case operations/admission/examples/stage2/knowledge_product_type.v1 knowledge-targets-sources)"
mutate_case "${knowledge_case}" "knowledge-targets-sources"
fail_case "Stage 2 rejects knowledge_asset targeting sources layer" "placement.destination_root must follow domain-first layout" \
  env ADMISSION_KB_TAXONOMY_CONFIG="${TAXONOMY_CONFIG}" \
  "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${knowledge_case}/admission_handoff.json"

negative_cases=(
  "unknown-kind|'future_kind' is not one of"
  "unknown-profile|knowledge_profile_id is not registered"
  "role-first|placement.destination_root must follow domain-first layout"
  "asset-id-mismatch|asset_id must be preserved from Stage 1 package"
  "missing-knowledge-type|'knowledge_type' is a required property"
  "unknown-knowledge-type|placement.knowledge_type is not allowed by local KB taxonomy config"
  "profile-type-mismatch|knowledge_profile_id is not allowed for placement.knowledge_type"
  "knowledge-type-slash|does not match"
  "knowledge-type-traversal|should not be valid under"
  "old-untyped-knowledge-path|placement.destination_root must follow domain-first layout"
  "missing-asset-slug|'asset_slug' is a required property"
  "asset-slug-slash|does not match"
  "asset-slug-traversal|should not be valid under"
  "destination-uses-asset-id|placement.destination_root must follow domain-first layout"
  "manifest-destination-outside-slug-root|Phase3 artifact destination_kb_path must be under placement.destination_root"
  "absolute-ref|does not match"
  "traversal-ref|does not match"
  "manifest-type-mismatch|Phase3 admission manifest admission_type must match Stage 1 admission_kind"
  "review-malformed|'artifact_id' is a required property"
  "review-existing-file|'artifact_id' is a required property"
  "review-reject|review_decision.decision must be approve"
  "review-hold|review_decision.decision must be approve"
  "review-return-for-revision|review_decision.decision must be approve"
  "review-missing-destination|review_decision.approved_destination must be kb"
  "review-wrong-destination|review_decision.approved_destination must be kb"
  "review-asset-mismatch|review_decision.artifact_id must match handoff asset_id"
)

for entry in "${negative_cases[@]}"; do
  mutation="${entry%%|*}"
  expected="${entry#*|}"
  case_dir="$(make_case operations/admission/examples/stage2/knowledge_product_type.v1 "${mutation}")"
  mutate_case "${case_dir}" "${mutation}"
  fail_case "Stage 2 rejects ${mutation}" "${expected}" \
    env ADMISSION_KB_TAXONOMY_CONFIG="${TAXONOMY_CONFIG}" \
    "${PYTHON_BIN}" operations/harness-phase2/bin/check_admission_policy.py . "${case_dir}/admission_handoff.json"
done

after_snapshot="$(snapshot_repo_surfaces)"
[[ "${before_snapshot}" == "${after_snapshot}" ]] || {
  printf 'FAIL Stage 2 tests changed KB or Phase run surfaces\n' >&2
  exit 1
}

printf 'PASS admission Stage 2 handoff validation\n'
