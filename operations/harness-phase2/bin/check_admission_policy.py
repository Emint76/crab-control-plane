#!/usr/bin/env python3
"""Standalone admission policy fixture/handoff preflight.

This repo-native utility is intentionally separate from the generic Phase2
bundle. It is not a production admission engine and does not emit canonical
Phase evidence.
"""

from __future__ import annotations

import json
import hashlib
import os
import sys
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator


class CheckFailure(Exception):
    pass


def load_json_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise CheckFailure(f"{path}: top-level JSON value must be an object")
    return payload


def load_yaml_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle)
    if not isinstance(payload, dict):
        raise CheckFailure(f"{path}: top-level YAML value must be a mapping")
    return payload


def resolve_ref(base_dir: Path, ref: str, field_name: str) -> Path:
    if not ref:
        raise CheckFailure(f"missing {field_name}")
    path = Path(ref)
    if path.is_absolute():
        return path
    return base_dir / path


def require_mapping(payload: dict[str, Any], field_name: str, source: str) -> dict[str, Any]:
    value = payload.get(field_name)
    if not isinstance(value, dict):
        raise CheckFailure(f"{source}.{field_name} must be a mapping")
    return value


def require_string(payload: dict[str, Any], field_name: str, source: str) -> str:
    value = payload.get(field_name)
    if not isinstance(value, str) or not value:
        raise CheckFailure(f"{source}.{field_name} must be a non-empty string")
    return value


def require_string_list(payload: dict[str, Any], field_name: str, source: str) -> list[str]:
    value = payload.get(field_name)
    if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
        raise CheckFailure(f"{source}.{field_name} must be a string list")
    return value


def validate_schema(repo_root: Path, schema_name: str, payload: dict[str, Any], source: Path | str) -> None:
    schema_path = repo_root / "control-plane" / "contracts" / "schemas" / schema_name
    validate_schema_path(schema_path, payload, source)


def validate_schema_path(schema_path: Path, payload: dict[str, Any], source: Path | str) -> None:
    schema = load_json_object(schema_path)
    Draft202012Validator.check_schema(schema)
    errors = sorted(Draft202012Validator(schema).iter_errors(payload), key=lambda error: list(error.path))
    if errors:
        first = errors[0]
        path = ".".join(str(part) for part in first.path) or "<root>"
        raise CheckFailure(f"{source}: {path}: {first.message}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_repo_ref(repo_root: Path, ref: str, field_name: str) -> Path:
    if not ref:
        raise CheckFailure(f"missing {field_name}")
    path = Path(ref)
    if path.is_absolute():
        raise CheckFailure(f"{field_name} must be repo-contained and relative")
    if ".." in path.parts:
        raise CheckFailure(f"{field_name} must not contain traversal")
    resolved_repo = repo_root.resolve(strict=False)
    resolved_path = (resolved_repo / path).resolve(strict=False)
    try:
        resolved_path.relative_to(resolved_repo)
    except ValueError as exc:
        raise CheckFailure(f"{field_name} escapes repo root") from exc
    if not resolved_path.is_file():
        raise CheckFailure(f"{field_name} does not reference an existing repo file")
    return resolved_path


def repo_ref_for_path(repo_root: Path, path: Path) -> str:
    try:
        return path.resolve(strict=False).relative_to(repo_root.resolve(strict=False)).as_posix()
    except ValueError:
        return path.as_posix()


def load_admission_registry(repo_root: Path) -> dict[str, Any]:
    registry = load_json_object(repo_root / "operations" / "admission" / "knowledge-profiles" / "registry.v1.json")
    profiles = registry.get("profiles")
    if not isinstance(profiles, dict):
        raise CheckFailure("knowledge profile registry profiles must be a mapping")
    return profiles


def load_kb_taxonomy_config(repo_root: Path) -> dict[str, Any]:
    if os.environ.get("ADMISSION_KB_TAXONOMY_MODE") == "shape-only-diagnostic":
        raise CheckFailure("shape-only diagnostic taxonomy mode is not admission readiness")
    config_ref = os.environ.get("ADMISSION_KB_TAXONOMY_CONFIG")
    if not config_ref:
        raise CheckFailure("ADMISSION_KB_TAXONOMY_CONFIG is required for knowledge_asset admission")
    config_path = Path(config_ref)
    if not config_path.is_absolute():
        raise CheckFailure("ADMISSION_KB_TAXONOMY_CONFIG must be an absolute path outside Git")
    if not config_path.is_file():
        raise CheckFailure("ADMISSION_KB_TAXONOMY_CONFIG does not reference an existing file")
    config = load_json_object(config_path)
    validate_schema_path(repo_root / "operations" / "admission" / "schemas" / "kb_taxonomy_config.v1.schema.json", config, config_path)
    allowed_types = config.get("allowed_knowledge_types")
    profile_map = config.get("profile_knowledge_type_map")
    if not isinstance(allowed_types, list) or not isinstance(profile_map, dict):
        raise CheckFailure("KB taxonomy config must define allowed types and profile map")
    allowed_set = set(allowed_types)
    inconsistent: list[str] = []
    for profile_id, mapped_types in profile_map.items():
        if not isinstance(mapped_types, list):
            raise CheckFailure("KB taxonomy config profile map entries must be type lists")
        for mapped_type in mapped_types:
            if mapped_type not in allowed_set:
                inconsistent.append(f"{profile_id}:{mapped_type}")
    if inconsistent:
        raise CheckFailure(
            "KB taxonomy config maps knowledge types not present in allowed_knowledge_types: "
            + ", ".join(sorted(inconsistent))
        )
    return config


def validate_knowledge_type_allowed(
    repo_root: Path,
    knowledge_profile_id: str,
    knowledge_type: str,
) -> None:
    config = load_kb_taxonomy_config(repo_root)
    allowed_types = config.get("allowed_knowledge_types")
    profile_map = config.get("profile_knowledge_type_map")
    if not isinstance(allowed_types, list) or not isinstance(profile_map, dict):
        raise CheckFailure("KB taxonomy config must define allowed types and profile map")
    if knowledge_type not in allowed_types:
        raise CheckFailure("placement.knowledge_type is not allowed by local KB taxonomy config")
    mapped_types = profile_map.get(knowledge_profile_id)
    if not isinstance(mapped_types, list) or knowledge_type not in mapped_types:
        raise CheckFailure("knowledge_profile_id is not allowed for placement.knowledge_type")


def validate_stage1_package(repo_root: Path, package_path: Path) -> dict[str, Any]:
    package = load_json_object(package_path)
    admission_root = repo_root / "operations" / "admission"
    validate_schema_path(admission_root / "schemas" / "admission_package.schema.json", package, package_path)

    admission_kind = require_string(package, "admission_kind", "admission_package")
    profile_id = require_string(package, "profile_id", "admission_package")
    if admission_kind == "source_capture":
        if profile_id != "source_capture.v1":
            raise CheckFailure("Stage 1 source_capture package must use profile_id source_capture.v1")
        validate_schema_path(admission_root / "schemas" / "source_capture.v1.schema.json", package, package_path)
        if "knowledge_profile_id" in package:
            raise CheckFailure("Stage 1 source_capture package must not include knowledge_profile_id")
    elif admission_kind == "knowledge_asset":
        if profile_id != "knowledge_asset.v1":
            raise CheckFailure("Stage 1 knowledge_asset package must use profile_id knowledge_asset.v1")
        validate_schema_path(admission_root / "schemas" / "knowledge_asset.v1.schema.json", package, package_path)
        knowledge_profile_id = require_string(package, "knowledge_profile_id", "admission_package")
        if knowledge_profile_id not in load_admission_registry(repo_root):
            raise CheckFailure("knowledge_profile_id is not registered")
    else:
        raise CheckFailure("Stage 1 admission_kind is not supported")

    if package.get("review_status") != "approved":
        raise CheckFailure("Stage 1 review_status must be approved")
    return package


def expected_asset_layer(admission_kind: str) -> str:
    if admission_kind == "source_capture":
        return "sources"
    if admission_kind == "knowledge_asset":
        return "knowledge"
    raise CheckFailure("admission_kind is not supported")


def expected_placement_policy(admission_kind: str) -> str:
    if admission_kind == "source_capture":
        return "kb_source_domain_first.v1"
    if admission_kind == "knowledge_asset":
        return "kb_knowledge_domain_first.v1"
    raise CheckFailure("admission_kind is not supported")


def check_stage2_handoff(repo_root: Path, handoff_path: Path, handoff: dict[str, Any]) -> None:
    admission_root = repo_root / "operations" / "admission"
    validate_schema_path(admission_root / "schemas" / "admission_handoff.v1.schema.json", handoff, handoff_path)

    admission_kind = require_string(handoff, "admission_kind", "admission_handoff")
    asset_id = require_string(handoff, "asset_id", "admission_handoff")
    profile_id = require_string(handoff, "profile_id", "admission_handoff")
    if admission_kind == "source_capture" and profile_id != "source_capture.v1":
        raise CheckFailure("source_capture handoff must use profile_id source_capture.v1")
    if admission_kind == "knowledge_asset" and profile_id != "knowledge_asset.v1":
        raise CheckFailure("knowledge_asset handoff must use profile_id knowledge_asset.v1")

    package_ref = require_string(handoff, "admission_package_ref", "admission_handoff")
    package_path = require_repo_ref(repo_root, package_ref, "admission_package_ref")
    expected_package_sha = require_string(handoff, "admission_package_sha256", "admission_handoff")
    if sha256_file(package_path) != expected_package_sha:
        raise CheckFailure("admission_package_sha256 does not match referenced Stage 1 package")
    package = validate_stage1_package(repo_root, package_path)

    if package.get("admission_kind") != admission_kind:
        raise CheckFailure("admission_kind must match Stage 1 package")
    if package.get("profile_id") != profile_id:
        raise CheckFailure("profile_id must match Stage 1 package")
    if package.get("asset_id") != asset_id:
        raise CheckFailure("asset_id must be preserved from Stage 1 package")

    handoff_knowledge_profile_id = handoff.get("knowledge_profile_id")
    if admission_kind == "source_capture":
        if handoff_knowledge_profile_id is not None:
            raise CheckFailure("source_capture handoff must not set knowledge_profile_id")
    else:
        if handoff_knowledge_profile_id != package.get("knowledge_profile_id"):
            raise CheckFailure("knowledge_profile_id must match Stage 1 package")
        registry_entry = load_admission_registry(repo_root).get(handoff_knowledge_profile_id)
        if registry_entry is None:
            raise CheckFailure("knowledge_profile_id is not registered")

    review_evidence = require_mapping(handoff, "review_evidence", "admission_handoff")
    if review_evidence.get("review_status") != "approved":
        raise CheckFailure("review_evidence.review_status must be approved")
    approval_ref = require_string(review_evidence, "approval_ref", "admission_handoff.review_evidence")
    approval_path = require_repo_ref(repo_root, approval_ref, "review_evidence.approval_ref")
    review_decision = load_json_object(approval_path)
    validate_schema(repo_root, "review_decision.schema.json", review_decision, approval_path)
    if review_decision.get("decision") != "approve":
        raise CheckFailure("review_decision.decision must be approve")
    if review_decision.get("artifact_id") != asset_id:
        raise CheckFailure("review_decision.artifact_id must match handoff asset_id")
    if review_decision.get("approved_destination") != "kb":
        raise CheckFailure("review_decision.approved_destination must be kb")

    placement = require_mapping(handoff, "placement", "admission_handoff")
    domain_area = require_string(placement, "domain_area", "admission_handoff.placement")
    source_family_id = require_string(placement, "source_family_id", "admission_handoff.placement")
    asset_layer = require_string(placement, "asset_layer", "admission_handoff.placement")
    asset_slug = require_string(placement, "asset_slug", "admission_handoff.placement")
    destination_root = require_string(placement, "destination_root", "admission_handoff.placement")
    placement_policy_id = require_string(placement, "placement_policy_id", "admission_handoff.placement")

    expected_layer = expected_asset_layer(admission_kind)
    if asset_layer != expected_layer:
        raise CheckFailure("placement.asset_layer must match admission_kind")
    if placement_policy_id != expected_placement_policy(admission_kind):
        raise CheckFailure("placement.placement_policy_id must match admission_kind")
    if admission_kind == "knowledge_asset":
        knowledge_type = require_string(placement, "knowledge_type", "admission_handoff.placement")
        validate_knowledge_type_allowed(repo_root, handoff_knowledge_profile_id, knowledge_type)
        expected_destination_root = f"{domain_area}/{source_family_id}/{asset_layer}/{knowledge_type}/{asset_slug}"
    else:
        if "knowledge_type" in placement:
            raise CheckFailure("source_capture handoff must not set placement.knowledge_type")
        expected_destination_root = f"{domain_area}/{source_family_id}/{asset_layer}/{asset_slug}"
    if destination_root != expected_destination_root:
        raise CheckFailure("placement.destination_root must follow domain-first layout")

    phase_inputs = require_mapping(handoff, "phase_inputs", "admission_handoff")
    target_ref = require_string(phase_inputs, "phase3_execution_target_ref", "admission_handoff.phase_inputs")
    manifest_ref = require_string(phase_inputs, "phase3_admission_manifest_ref", "admission_handoff.phase_inputs")
    target_path = require_repo_ref(repo_root, target_ref, "phase_inputs.phase3_execution_target_ref")
    manifest_path = require_repo_ref(repo_root, manifest_ref, "phase_inputs.phase3_admission_manifest_ref")
    target = load_json_object(target_path)
    manifest = load_json_object(manifest_path)

    if target.get("target_kind") != "kb_admission":
        raise CheckFailure("Phase3 execution target kind must be kb_admission")
    if target.get("admission_manifest_ref") != repo_ref_for_path(repo_root, manifest_path):
        raise CheckFailure("Phase3 execution target admission_manifest_ref must match handoff manifest ref")
    if manifest.get("admission_type") != admission_kind:
        raise CheckFailure("Phase3 admission manifest admission_type must match Stage 1 admission_kind")

    lineage = manifest.get("lineage")
    if not isinstance(lineage, dict):
        raise CheckFailure("Phase3 admission manifest lineage must be a mapping")
    if lineage.get("asset_id") != asset_id:
        raise CheckFailure("Phase3 admission manifest lineage.asset_id must preserve asset_id")
    if admission_kind == "knowledge_asset" and lineage.get("knowledge_profile_id") != handoff_knowledge_profile_id:
        raise CheckFailure("Phase3 admission manifest lineage.knowledge_profile_id must match handoff")

    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise CheckFailure("Phase3 admission manifest must declare admitted artifacts")
    destination_prefix = f"{destination_root}/"
    for index, artifact in enumerate(artifacts):
        if not isinstance(artifact, dict):
            raise CheckFailure(f"Phase3 admission manifest artifact {index} must be a mapping")
        destination = artifact.get("destination_kb_path")
        if not isinstance(destination, str) or not destination.startswith(destination_prefix):
            raise CheckFailure("Phase3 artifact destination_kb_path must be under placement.destination_root")


def load_and_validate_ref(
    repo_root: Path,
    fixture_dir: Path,
    fixture: dict[str, Any],
    field_name: str,
    schema_name: str,
) -> dict[str, Any]:
    ref = require_string(fixture, field_name, "admission fixture")
    path = resolve_ref(fixture_dir, ref, field_name)
    payload = load_json_object(path)
    validate_schema(repo_root, schema_name, payload, path)
    return payload


def check_admission(repo_root: Path, fixture_path: Path) -> None:
    fixture = load_json_object(fixture_path)
    if fixture.get("handoff_version") == "admission_handoff.v1":
        check_stage2_handoff(repo_root, fixture_path, fixture)
        return

    fixture_dir = fixture_path.parent

    target_layer = require_string(fixture, "target_layer", "admission fixture")
    policy_path = repo_root / "operations" / "harness-phase2" / "policy" / "admission-policy.yaml"
    policy = load_yaml_object(policy_path)
    rules = require_mapping(policy, "rules", "admission-policy.yaml")
    rule = require_mapping(rules, target_layer, f"admission-policy.yaml.rules")
    requires = require_string_list(rule, "requires", f"admission-policy.yaml.rules.{target_layer}")

    result_packet: dict[str, Any] | None = None
    source_capture_package: dict[str, Any] | None = None

    if "result_packet" in requires:
        result_packet = load_and_validate_ref(
            repo_root,
            fixture_dir,
            fixture,
            "result_packet_ref",
            "result_packet.schema.json",
        )

    if "review_approval" in requires:
        review = load_and_validate_ref(
            repo_root,
            fixture_dir,
            fixture,
            "review_decision_ref",
            "review_decision.schema.json",
        )
        if review.get("decision") != "approve":
            raise CheckFailure("review_decision.decision must be approve")

    if "admission_decision" in requires:
        admission = require_mapping(fixture, "admission_decision", "admission fixture")
        validate_schema(repo_root, "admission_decision.schema.json", admission, f"{fixture_path}.admission_decision")
        if admission.get("decision") != "approved":
            raise CheckFailure("admission_decision.decision must be approved")
        if admission.get("blockers"):
            raise CheckFailure("admission_decision.blockers must be empty")

    if "evidence" in requires:
        if result_packet is None:
            raise CheckFailure("evidence checks require result_packet")
        evidence = result_packet.get("evidence")
        if not isinstance(evidence, list) or not any(
            isinstance(item, dict) and item.get("type") == "source-package" for item in evidence
        ):
            raise CheckFailure("result_packet.evidence must include a source-package")
        source_capture_package = load_and_validate_ref(
            repo_root,
            fixture_dir,
            fixture,
            "source_capture_package_ref",
            "source_capture_package.schema.json",
        )

    placement = require_mapping(fixture, "placement", "admission fixture")
    placement_layer = require_string(placement, "target_layer", "admission fixture.placement")
    artifact_id = require_string(placement, "artifact_id", "admission fixture.placement")
    artifact_type = require_string(placement, "artifact_type", "admission fixture.placement")

    if placement_layer != target_layer:
        raise CheckFailure("placement.target_layer must match admission target_layer")

    if target_layer == "kb":
        if source_capture_package is None:
            raise CheckFailure("kb admission requires a source capture package")
        if artifact_type != "source-capture-package":
            raise CheckFailure("placement.artifact_type must be source-capture-package for kb admission")
        if source_capture_package.get("source_id") != artifact_id:
            raise CheckFailure("placement.artifact_id must match source_capture_package.source_id")


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: check_admission_policy.py <repo-root> <admission-handoff-or-legacy-fixture-json>",
            file=sys.stderr,
        )
        return 2

    repo_root = Path(sys.argv[1]).resolve()
    fixture_path = Path(sys.argv[2])
    if not fixture_path.is_absolute():
        fixture_path = repo_root / fixture_path

    try:
        check_admission(repo_root, fixture_path)
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL admission policy: {fixture_path.as_posix()}: {exc}", file=sys.stderr)
        return 1

    print(f"PASS admission policy: {fixture_path.as_posix()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
