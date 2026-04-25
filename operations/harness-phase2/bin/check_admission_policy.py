#!/usr/bin/env python3
"""Standalone Phase 2 admission policy fixture check.

This is a Phase-2-local external check-layer utility, not a production
admission engine.
"""

from __future__ import annotations

import json
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
    schema = load_json_object(schema_path)
    Draft202012Validator.check_schema(schema)
    errors = sorted(Draft202012Validator(schema).iter_errors(payload), key=lambda error: list(error.path))
    if errors:
        first = errors[0]
        path = ".".join(str(part) for part in first.path) or "<root>"
        raise CheckFailure(f"{source}: {path}: {first.message}")


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
        print("usage: check_admission_policy.py <repo-root> <admission-fixture-json>", file=sys.stderr)
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
