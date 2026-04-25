#!/usr/bin/env python3
"""Fixture-driven Phase 2 smoke checks.

The admission fixture shape is local to this smoke suite because the current
contracts do not define a schema for placement.artifact_type.
"""

from __future__ import annotations

import json
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator


class SmokeFailure(Exception):
    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail)
        self.code = code
        self.detail = detail


class FixtureSmoke:
    def __init__(self, repo_root: Path, fixtures_dir: Path) -> None:
        self.repo_root = repo_root
        self.fixtures_dir = fixtures_dir
        self.schemas_dir = repo_root / "control-plane" / "contracts" / "schemas"
        self.policy_dir = repo_root / "operations" / "harness-phase2" / "policy"

    def fixture_path(self, fixture_name: str) -> Path:
        if "/" in fixture_name or "\\" in fixture_name:
            raise SmokeFailure("invalid_fixture_ref", f"fixture refs must be local filenames: {fixture_name}")
        return self.fixtures_dir / fixture_name

    def load_json_mapping(self, path: Path) -> dict[str, Any]:
        try:
            with path.open("r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except (OSError, json.JSONDecodeError) as exc:
            raise SmokeFailure("json_load_failed", f"{path}: {exc}") from exc
        if not isinstance(payload, dict):
            raise SmokeFailure("json_not_object", f"{path}: top-level JSON value must be an object")
        return payload

    def load_yaml_mapping(self, path: Path) -> dict[str, Any]:
        try:
            with path.open("r", encoding="utf-8") as handle:
                payload = yaml.safe_load(handle)
        except (OSError, yaml.YAMLError) as exc:
            raise SmokeFailure("yaml_load_failed", f"{path}: {exc}") from exc
        if not isinstance(payload, dict):
            raise SmokeFailure("yaml_not_mapping", f"{path}: top-level YAML value must be a mapping")
        return payload

    def load_schema(self, schema_name: str) -> dict[str, Any]:
        schema_path = self.schemas_dir / schema_name
        schema = self.load_json_mapping(schema_path)
        try:
            Draft202012Validator.check_schema(schema)
        except Exception as exc:  # noqa: BLE001
            raise SmokeFailure("schema_invalid", f"{schema_name}: {exc}") from exc
        return schema

    def validate_payload(self, schema_name: str, payload: dict[str, Any], source: str) -> dict[str, Any]:
        schema = self.load_schema(schema_name)
        validator = Draft202012Validator(schema)
        errors = sorted(validator.iter_errors(payload), key=lambda error: list(error.path))
        if errors:
            first = errors[0]
            path = ".".join(str(part) for part in first.path) or "<root>"
            raise SmokeFailure("schema_validation_failed", f"{source}: {path}: {first.message}")
        return payload

    def validate_fixture_schema(self, schema_name: str, fixture_name: str) -> dict[str, Any]:
        fixture_path = self.fixture_path(fixture_name)
        payload = self.load_json_mapping(fixture_path)
        return self.validate_payload(schema_name, payload, fixture_name)

    def validate_fixture_ref(self, schema_name: str, fixture: dict[str, Any], field_name: str) -> dict[str, Any]:
        ref = fixture.get(field_name)
        if not isinstance(ref, str) or not ref:
            raise SmokeFailure(f"missing_{field_name}", f"fixture is missing {field_name}")
        return self.validate_fixture_schema(schema_name, ref)

    def placement_policy_allows(self, fixture_name: str) -> None:
        placement = self.validate_fixture_schema("placement_decision.schema.json", fixture_name)
        policy = self.load_yaml_mapping(self.policy_dir / "placement-policy.yaml")
        rules = self.require_mapping(policy, "rules", "placement-policy.yaml")
        placement_rule = self.require_mapping(rules, "placement_decision", "placement-policy.yaml.rules")
        expected_layer = placement_rule.get("target_layer")
        actual_layer = placement.get("target_layer")
        if actual_layer != expected_layer:
            raise SmokeFailure(
                "placement_target_layer_policy_violation",
                f"placement_decision target_layer {actual_layer!r} does not match policy {expected_layer!r}",
            )

    def admission_allows(self, fixture_name: str) -> None:
        fixture = self.load_json_mapping(self.fixture_path(fixture_name))
        target_layer = self.require_string(fixture, "target_layer", fixture_name)
        policy = self.load_yaml_mapping(self.policy_dir / "admission-policy.yaml")
        rules = self.require_mapping(policy, "rules", "admission-policy.yaml")
        rule = self.require_mapping(rules, target_layer, f"admission-policy.yaml.rules.{target_layer}")
        requires = self.require_string_list(rule, "requires", f"admission-policy.yaml.rules.{target_layer}")

        result_packet: dict[str, Any] | None = None
        source_capture_package: dict[str, Any] | None = None

        if "result_packet" in requires:
            result_packet = self.validate_fixture_ref("result_packet.schema.json", fixture, "result_packet_ref")

        if "review_approval" in requires:
            review = self.validate_fixture_ref("review_decision.schema.json", fixture, "review_decision_ref")
            if review.get("decision") != "approve":
                raise SmokeFailure("review_not_approved", "review_decision.decision must be approve")

        if "admission_decision" in requires:
            admission = self.require_mapping(fixture, "admission_decision", fixture_name)
            self.validate_payload("admission_decision.schema.json", admission, f"{fixture_name}.admission_decision")
            if admission.get("decision") != "approved":
                raise SmokeFailure("admission_decision_not_approved", "admission_decision.decision must be approved")
            if admission.get("blockers"):
                raise SmokeFailure("admission_decision_has_blockers", "admission_decision.blockers must be empty")

        if "evidence" in requires:
            if result_packet is None:
                raise SmokeFailure("missing_result_packet", "evidence checks require result_packet")
            evidence = result_packet.get("evidence")
            if not isinstance(evidence, list) or not any(item.get("type") == "source-package" for item in evidence if isinstance(item, dict)):
                raise SmokeFailure("missing_source_package_evidence", "result_packet.evidence must include a source-package")
            source_capture_package = self.validate_fixture_ref(
                "source_capture_package.schema.json",
                fixture,
                "source_capture_package_ref",
            )

        placement = self.require_mapping(fixture, "placement", fixture_name)
        placement_layer = self.require_string(placement, "target_layer", f"{fixture_name}.placement")
        artifact_id = self.require_string(placement, "artifact_id", f"{fixture_name}.placement")
        artifact_type = self.require_string(placement, "artifact_type", f"{fixture_name}.placement")

        if placement_layer != target_layer:
            raise SmokeFailure("placement_target_layer_mismatch", "placement.target_layer must match admission target_layer")

        if target_layer == "kb":
            if source_capture_package is None:
                raise SmokeFailure("missing_source_capture_package", "kb admission requires a source capture package")
            if artifact_type != "source-capture-package":
                raise SmokeFailure(
                    "invalid_admission_artifact_type",
                    "placement.artifact_type must be source-capture-package for kb admission",
                )
            if source_capture_package.get("source_id") != artifact_id:
                raise SmokeFailure("source_capture_id_mismatch", "source_capture_package.source_id must match placement.artifact_id")

        if result_packet is not None:
            produced = result_packet.get("produced_artifacts")
            if isinstance(produced, list):
                source_artifacts = {
                    item.get("artifact_id")
                    for item in produced
                    if isinstance(item, dict) and item.get("artifact_type") == "source-capture-package"
                }
                if artifact_id not in source_artifacts:
                    raise SmokeFailure(
                        "result_packet_missing_source_capture_artifact",
                        "result_packet.produced_artifacts must include placement.artifact_id as a source-capture-package",
                    )

    def require_mapping(self, payload: dict[str, Any], field_name: str, source: str) -> dict[str, Any]:
        value = payload.get(field_name)
        if not isinstance(value, dict):
            raise SmokeFailure("missing_mapping", f"{source}.{field_name} must be a mapping")
        return value

    def require_string(self, payload: dict[str, Any], field_name: str, source: str) -> str:
        value = payload.get(field_name)
        if not isinstance(value, str) or not value:
            raise SmokeFailure("missing_string", f"{source}.{field_name} must be a non-empty string")
        return value

    def require_string_list(self, payload: dict[str, Any], field_name: str, source: str) -> list[str]:
        value = payload.get(field_name)
        if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
            raise SmokeFailure("missing_string_list", f"{source}.{field_name} must be a string list")
        return value


def pass_case(label: str, check: Callable[[], None]) -> bool:
    try:
        check()
    except SmokeFailure as exc:
        print(f"FAIL {label}: {exc.detail}", file=sys.stderr)
        return False
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL {label}: unexpected {type(exc).__name__}: {exc}", file=sys.stderr)
        return False
    print(f"PASS {label}")
    return True


def fail_case(label: str, expected_code: str, check: Callable[[], None]) -> bool:
    try:
        check()
    except SmokeFailure as exc:
        if exc.code != expected_code:
            print(
                f"FAIL {label}: expected {expected_code}, got {exc.code}: {exc.detail}",
                file=sys.stderr,
            )
            return False
        print(f"PASS {label}")
        return True
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL {label}: unexpected {type(exc).__name__}: {exc}", file=sys.stderr)
        return False

    print(f"FAIL {label}: expected failure but check passed", file=sys.stderr)
    return False


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: fixture_smoke.py <repo-root> <fixtures-dir>", file=sys.stderr)
        return 2

    suite = FixtureSmoke(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
    checks = [
        pass_case(
            "valid task packet schema",
            lambda: suite.validate_fixture_schema("task_packet.schema.json", "valid-task-packet.json"),
        ),
        fail_case(
            "invalid task packet rejected by schema",
            "schema_validation_failed",
            lambda: suite.validate_fixture_schema("task_packet.schema.json", "invalid-task-packet.json"),
        ),
        pass_case(
            "valid result packet schema",
            lambda: suite.validate_fixture_schema("result_packet.schema.json", "valid-result-packet.json"),
        ),
        pass_case(
            "valid placement decision schema",
            lambda: suite.validate_fixture_schema("placement_decision.schema.json", "valid-placement-decision.json"),
        ),
        fail_case(
            "policy-invalid KB placement rejected",
            "placement_target_layer_policy_violation",
            lambda: suite.placement_policy_allows("policy-invalid-kb-placement.json"),
        ),
        fail_case(
            "admission missing source capture package rejected",
            "missing_source_capture_package_ref",
            lambda: suite.admission_allows("admission-missing-source-capture-package.json"),
        ),
        fail_case(
            "admission invalid artifact_type rejected",
            "invalid_admission_artifact_type",
            lambda: suite.admission_allows("admission-invalid-artifact-type.json"),
        ),
    ]
    return 0 if all(checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
