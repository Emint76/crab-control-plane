#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMISSION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ADMISSION_ROOT}/../.." && pwd)"
PYTHON_BIN="${ADMISSION_TEST_PYTHON_BIN:-${PYTHON:-python3}}"

cd "${REPO_ROOT}"

"${PYTHON_BIN}" - "${REPO_ROOT}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

repo = Path(sys.argv[1])
admission = repo / "operations" / "admission"


def load_structured(path: Path) -> object:
    if path.suffix in {".yaml", ".yml"}:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    return json.loads(path.read_text(encoding="utf-8"))


def load_schema(path: Path) -> dict[str, object]:
    schema = json.loads(path.read_text(encoding="utf-8"))
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema", path
    Draft202012Validator.check_schema(schema)
    return schema


schemas = {
    path.relative_to(repo).as_posix(): load_schema(path)
    for path in sorted((admission / "schemas").glob("*.schema.json"))
}
schemas["control-plane/contracts/schemas/review_decision.schema.json"] = load_schema(
    repo / "control-plane/contracts/schemas/review_decision.schema.json"
)
schemas["control-plane/contracts/schemas/kb_runtime_integration.schema.json"] = load_schema(
    repo / "control-plane/contracts/schemas/kb_runtime_integration.schema.json"
)
schemas["operations/harness-phase3/contracts/execution_target.schema.json"] = load_schema(
    repo / "operations/harness-phase3/contracts/execution_target.schema.json"
)
schemas["operations/harness-phase3/contracts/kb_admission_manifest.schema.json"] = load_schema(
    repo / "operations/harness-phase3/contracts/kb_admission_manifest.schema.json"
)


def validate(schema_key: str, instance: object, source: Path) -> None:
    errors = sorted(
        Draft202012Validator(schemas[schema_key]).iter_errors(instance),
        key=lambda error: list(error.path),
    )
    assert not errors, (source.as_posix(), [error.message for error in errors])


registry = json.loads((admission / "knowledge-profiles" / "registry.v1.json").read_text(encoding="utf-8"))
profiles = registry["profiles"]
assert {"product_type_extraction.v1", "recipe_formula_extraction.v1", "component_extraction.v1"} <= set(profiles)
for profile_id, entry in profiles.items():
    assert "enabled_for_admission" not in entry, profile_id
    assert set(entry).issubset({"payload_kind", "placement_policy_id", "status", "instruction_ref"}), profile_id
    if "instruction_ref" in entry:
        instruction_ref = entry["instruction_ref"]
        assert isinstance(instruction_ref, str) and instruction_ref, profile_id
        assert not instruction_ref.startswith("/"), profile_id
        assert ".." not in instruction_ref.split("/"), profile_id
        instruction_path = repo / instruction_ref
        assert instruction_path.is_file(), instruction_ref
        instruction_text = instruction_path.read_text(encoding="utf-8")
        assert profile_id in instruction_text, profile_id
    for forbidden in ["knowledge_type", "schema_ref", "semantic_validator", "structural_validator_ref", "parser_ref"]:
        assert forbidden not in entry, (profile_id, forbidden)
assert profiles["recipe_formula_extraction.v1"]["status"] == "registered"
assert profiles["recipe_formula_extraction.v1"]["instruction_ref"] == "knowledge/kb/extraction-profiles/cosmetics-household-chemistry/recipe-formula-extraction.v1.md"

for path in sorted((admission / "profiles").glob("*.json")):
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert "semantic_validator" not in json.dumps(payload), path

placement_registry = json.loads((admission / "placement-policies" / "registry.v1.json").read_text(encoding="utf-8"))
assert "kb_source_domain_first.v1" in placement_registry["placement_policies"]
assert "kb_knowledge_domain_first.v1" in placement_registry["placement_policies"]
for policy in placement_registry["placement_policies"].values():
    assert "<asset-slug>" in policy["path_template"], policy
    assert "<asset-id>" not in policy["path_template"], policy
assert "<knowledge-type>" in placement_registry["placement_policies"]["kb_knowledge_domain_first.v1"]["path_template"]
assert "<knowledge-type>" not in placement_registry["placement_policies"]["kb_source_domain_first.v1"]["path_template"]

examples = sorted((admission / "examples" / "stage2").glob("*/admission_handoff.json"))
assert examples, "Stage 2 examples are required"
seen_profiles: set[str] = set()
handoff_schema_text = (admission / "schemas" / "admission_handoff.v1.schema.json").read_text(encoding="utf-8")
handoff_schema = schemas["operations/admission/schemas/admission_handoff.v1.schema.json"]
assert "route" not in handoff_schema.get("required", []), "handoff schema must not require route"
assert "route" not in handoff_schema.get("properties", {}), "handoff schema must not define route"
assert "policy_readiness" not in handoff_schema_text, "handoff schema must not encode policy_readiness"
placement_schema = handoff_schema["properties"]["placement"]
assert "asset_slug" in placement_schema["required"], "handoff placement must require asset_slug"
assert placement_schema["properties"]["asset_slug"] == {"$ref": "#/$defs/path_segment"}
assert placement_schema["properties"]["knowledge_type"] == {"$ref": "#/$defs/path_segment"}
for handoff_path in examples:
    handoff_text = handoff_path.read_text(encoding="utf-8")
    assert "policy_readiness" not in handoff_text, handoff_path
    handoff = json.loads(handoff_path.read_text(encoding="utf-8"))
    assert "route" not in handoff, handoff_path
    validate("operations/admission/schemas/admission_handoff.v1.schema.json", handoff, handoff_path)
    placement = handoff["placement"]
    assert placement["destination_root"].endswith("/" + placement["asset_slug"]), handoff_path

    package_path = repo / handoff["admission_package_ref"]
    package = json.loads(package_path.read_text(encoding="utf-8"))
    validate("operations/admission/schemas/admission_package.schema.json", package, package_path)
    if package["admission_kind"] == "source_capture":
        validate("operations/admission/schemas/source_capture.v1.schema.json", package, package_path)
    else:
        validate("operations/admission/schemas/knowledge_asset.v1.schema.json", package, package_path)
        profile_id = package["knowledge_profile_id"]
        seen_profiles.add(profile_id)
        assert profile_id in profiles
    assert "knowledge_type" not in package, package_path

    review_path = repo / handoff["review_evidence"]["approval_ref"]
    review = json.loads(review_path.read_text(encoding="utf-8"))
    validate("control-plane/contracts/schemas/review_decision.schema.json", review, review_path)
    assert "knowledge_type" not in review, review_path

    target_path = repo / handoff["phase_inputs"]["phase3_execution_target_ref"]
    target = json.loads(target_path.read_text(encoding="utf-8"))
    validate("operations/harness-phase3/contracts/execution_target.schema.json", target, target_path)

    integration_path = repo / target["kb_integration_ref"]
    validate(
        "control-plane/contracts/schemas/kb_runtime_integration.schema.json",
        load_structured(integration_path),
        integration_path,
    )

    manifest_path = repo / handoff["phase_inputs"]["phase3_admission_manifest_ref"]
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    validate("operations/harness-phase3/contracts/kb_admission_manifest.schema.json", manifest, manifest_path)
    assert "knowledge_type" not in manifest["lineage"], manifest_path
    placement = handoff["placement"]
    if handoff["admission_kind"] == "knowledge_asset":
        assert "knowledge_type" in placement, handoff_path
        typed_prefix = f'{placement["domain_area"]}/{placement["source_family_id"]}/knowledge/{placement["knowledge_type"]}/{placement["asset_slug"]}/'
        for artifact in manifest["artifacts"]:
            assert artifact["destination_kb_path"].startswith(typed_prefix), artifact
    else:
        assert "knowledge_type" not in placement, handoff_path

assert seen_profiles == set(profiles), seen_profiles
taxonomy_fixture = json.loads((admission / "tests/fixtures/kb_taxonomy_config.noncanonical.json").read_text(encoding="utf-8"))
validate("operations/admission/schemas/kb_taxonomy_config.v1.schema.json", taxonomy_fixture, admission / "tests/fixtures/kb_taxonomy_config.noncanonical.json")
for example_type in taxonomy_fixture["allowed_knowledge_types"]:
    assert example_type.startswith("example-"), example_type
doc_paths = [
    repo / "docs/ADMISSION_STAGE2_CONTRACT.md",
    repo / "docs/ADMISSION_CHECK_OWNERSHIP.md",
    repo / "skills/source-admission/SKILL.md",
]
required_fragments = [
    "the current repository Git HEAD exactly equals that recorded HEAD",
    "the tracked repository working tree is clean",
    "Any new repository commit makes the previous Phase2 baseline stale",
    "phase2_run_id -> repo_head",
    "Accepted Phase2 baseline <RUN_ID> was created for and reused at repository HEAD <SHA>",
    "No operator override",
]
for doc_path in doc_paths:
    text = doc_path.read_text(encoding="utf-8")
    for fragment in required_fragments:
        assert fragment in text, (doc_path.as_posix(), fragment)
    forbidden_fragments = [
        "materially changed",
        "probably still current",
        "accepted after informal review",
        "relevant repo/control-plane baseline remains unchanged",
    ]
    for fragment in forbidden_fragments:
        assert fragment not in text, (doc_path.as_posix(), fragment)

normative_text = "\n".join(
    path.read_text(encoding="utf-8")
    for path in [
        repo / "docs/ADMISSION_CONTRACT.md",
        repo / "docs/ADMISSION_STAGE2_CONTRACT.md",
        repo / "docs/ADMISSION_CHECK_OWNERSHIP.md",
        repo / "knowledge/kb/KNOWLEDGE_CANDIDATE_ADMISSION_RUNBOOK.md",
        repo / "knowledge/kb/asset-templates/recipe-formula-extraction.md",
        repo / "control-plane/policy/KNOWLEDGE_EXTRACTION_PROFILE_POLICY.md",
    ]
)
for forbidden in [
    "semantic review has already happened",
    "producer-side semantic review",
    "reviewed knowledge package",
]:
    assert forbidden not in normative_text, forbidden

stage2_contract = (repo / "docs/ADMISSION_STAGE2_CONTRACT.md").read_text(encoding="utf-8")
assert "ADMISSION_KB_TAXONOMY_CONFIG" in stage2_contract
assert "absolute filesystem path to an outside-Git local config file" in stage2_contract
assert "resolved real path must be outside the repository root" in stage2_contract
assert "symlink outside the repository that resolves back into the repository is rejected" in stage2_contract
assert "positive validation tests copy them outside the repository" in stage2_contract
assert "Every mapped type must also appear in `allowed_knowledge_types`" in stage2_contract

skill_text = (repo / "skills/source-admission/SKILL.md").read_text(encoding="utf-8")
assert "admission_package.json" in skill_text
assert "admission_handoff.json" in skill_text
assert "check_admission_policy.py` validates the concrete universal `admission_handoff.json" in skill_text
assert "Legacy compatibility" in skill_text
assert "admission-fixture.json` is not a Stage 2 handoff" in skill_text
default_section = skill_text.split("## Legacy compatibility", 1)[0]
assert "admission-fixture.json" not in default_section
assert "Phase4 is the default operator-facing" in skill_text
assert "Phase3 performs admission and remains the only canonical execution owner" in skill_text
for fragment in [
    "asset_id` is the stable globally traceable source identity",
    "asset_slug` is a source-family-local directory segment used only for placement",
    "Do not automatically set `asset_slug = asset_id`",
    "cosmetics-household-chemistry/humblebee-and-me/sources/citrus-chamomile-liquid-shampoo-20260610",
    "cosmetics-household-chemistry/humblebee-and-me/sources/humblebee-citrus-chamomile-liquid-shampoo-20260610",
]:
    assert fragment in skill_text, fragment

runtime_files = [
    repo / "operations/harness-phase2/bin/run_phase2_bundle.sh",
    repo / "operations/harness-phase3/bin/run_phase3_bundle.sh",
    repo / "operations/harness-phase3/bin/freeze_phase2_input.py",
    repo / "operations/harness-phase4/bin/run_phase4_wrapper.sh",
]
for runtime_file in runtime_files:
    text = runtime_file.read_text(encoding="utf-8")
    for forbidden in [
        "--admission-handoff",
        "admission_handoff.json",
        "admission_package.json",
        "review-decision.json",
        "review_decision.json",
        "checks/admission_policy_validation.json",
    ]:
        assert forbidden not in text, (runtime_file.as_posix(), forbidden)

phase3_text = (repo / "operations/harness-phase3/bin/freeze_phase2_input.py").read_text(encoding="utf-8")
for forbidden in ["admission_handoff", "admission_package", "review_decision"]:
    assert forbidden not in phase3_text, forbidden

checker_text = (repo / "operations/harness-phase2/bin/check_admission_policy.py").read_text(encoding="utf-8")
assert "asset_slug" in checker_text
assert "humblebee" not in checker_text.lower()
assert "citrus-chamomile" not in checker_text
print("PASS admission contract validation")
PY
