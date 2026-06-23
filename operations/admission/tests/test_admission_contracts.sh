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
    assert set(entry) == {"payload_kind", "placement_policy_id", "status"}, profile_id

for path in sorted((admission / "profiles").glob("*.json")):
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert "semantic_validator" not in json.dumps(payload), path

placement_registry = json.loads((admission / "placement-policies" / "registry.v1.json").read_text(encoding="utf-8"))
assert "kb_source_domain_first.v1" in placement_registry["placement_policies"]
assert "kb_knowledge_domain_first.v1" in placement_registry["placement_policies"]

examples = sorted((admission / "examples" / "stage2").glob("*/admission_handoff.json"))
assert examples, "Stage 2 examples are required"
seen_profiles: set[str] = set()
for handoff_path in examples:
    handoff = json.loads(handoff_path.read_text(encoding="utf-8"))
    validate("operations/admission/schemas/admission_handoff.v1.schema.json", handoff, handoff_path)

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

    review_path = repo / handoff["review_evidence"]["approval_ref"]
    review = json.loads(review_path.read_text(encoding="utf-8"))
    validate("control-plane/contracts/schemas/review_decision.schema.json", review, review_path)

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

assert seen_profiles == set(profiles), seen_profiles
print("PASS admission contract validation")
PY
