#!/usr/bin/env python3
"""Standalone Phase 2 placement policy check."""

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


def validate_schema(repo_root: Path, schema_name: str, payload: dict[str, Any], source: Path) -> None:
    schema_path = repo_root / "control-plane" / "contracts" / "schemas" / schema_name
    schema = load_json_object(schema_path)
    Draft202012Validator.check_schema(schema)
    errors = sorted(Draft202012Validator(schema).iter_errors(payload), key=lambda error: list(error.path))
    if errors:
        first = errors[0]
        path = ".".join(str(part) for part in first.path) or "<root>"
        raise CheckFailure(f"{source}: {path}: {first.message}")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: check_placement_policy.py <repo-root> <placement-json>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve()
    placement_path = Path(sys.argv[2])
    if not placement_path.is_absolute():
        placement_path = repo_root / placement_path

    try:
        placement = load_json_object(placement_path)
        validate_schema(repo_root, "placement_decision.schema.json", placement, placement_path)

        policy_path = repo_root / "operations" / "harness-phase2" / "policy" / "placement-policy.yaml"
        policy = load_yaml_object(policy_path)
        rules = policy.get("rules")
        if not isinstance(rules, dict):
            raise CheckFailure("placement-policy.yaml rules must be a mapping")
        placement_rule = rules.get("placement_decision")
        if not isinstance(placement_rule, dict):
            raise CheckFailure("placement-policy.yaml must define rules.placement_decision")

        expected_layer = placement_rule.get("target_layer")
        actual_layer = placement.get("target_layer")
        if actual_layer != expected_layer:
            raise CheckFailure(
                f"placement_decision target_layer {actual_layer!r} does not match policy {expected_layer!r}"
            )
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL placement policy: {placement_path.as_posix()}: {exc}", file=sys.stderr)
        return 1

    print(f"PASS placement policy: {placement_path.as_posix()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
