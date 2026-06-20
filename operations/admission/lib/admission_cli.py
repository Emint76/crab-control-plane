#!/usr/bin/env python3
"""Stage 1 universal admission dry-run CLI."""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from json import JSONDecodeError
from pathlib import Path
from typing import Any

try:
    from jsonschema import Draft202012Validator
except ModuleNotFoundError:
    print(
        "FAIL jsonschema is required; install operations/harness-phase2/requirements.txt",
        file=sys.stderr,
    )
    raise SystemExit(2)


ADMISSION_ROOT = Path(__file__).resolve().parents[1]
SCHEMAS_ROOT = ADMISSION_ROOT / "schemas"
PROFILES_ROOT = ADMISSION_ROOT / "profiles"
REGISTRY_PATH = ADMISSION_ROOT / "knowledge-profiles" / "registry.v1.json"

COMMON_SCHEMA = SCHEMAS_ROOT / "admission_package.schema.json"
RESULT_SCHEMA = SCHEMAS_ROOT / "admission_result.schema.json"

PROFILE_FILES = {
    "source_capture.v1": PROFILES_ROOT / "source_capture.v1.json",
    "knowledge_asset.v1": PROFILES_ROOT / "knowledge_asset.v1.json",
}

KIND_PROFILE = {
    "source_capture": "source_capture.v1",
    "knowledge_asset": "knowledge_asset.v1",
}


@dataclass(frozen=True)
class Blocker:
    code: str
    message: str

    def as_dict(self) -> dict[str, str]:
        return {"code": self.code, "message": self.message}


class AdmissionError(Exception):
    def __init__(self, blocker: Blocker) -> None:
        super().__init__(blocker.message)
        self.blocker = blocker


class InternalResultError(Exception):
    pass


def blocker(code: str, message: str) -> Blocker:
    return Blocker(code=code, message=message)


def load_json(path: Path, code: str) -> Any:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except JSONDecodeError as exc:
        raise AdmissionError(blocker(code, f"JSON is invalid: {exc.msg}")) from exc
    except OSError as exc:
        raise AdmissionError(blocker(code, f"JSON file cannot be read: {exc}")) from exc


def load_schema(path: Path) -> dict[str, Any]:
    schema = load_json(path, "profile_definition_invalid")
    if not isinstance(schema, dict):
        raise AdmissionError(blocker("profile_definition_invalid", f"Schema is not an object: {path.as_posix()}"))
    try:
        Draft202012Validator.check_schema(schema)
    except Exception as exc:  # noqa: BLE001
        raise AdmissionError(blocker("profile_definition_invalid", f"Schema is invalid: {path.as_posix()}: {exc}")) from exc
    return schema


def validate_instance(schema_path: Path, instance: Any, code: str, label: str) -> None:
    schema = load_schema(schema_path)
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(instance), key=lambda error: list(error.absolute_path))
    if errors:
        first = errors[0]
        path = ".".join(str(part) for part in first.absolute_path) or "<root>"
        raise AdmissionError(blocker(code, f"{label} failed schema validation at {path}: {first.message}"))


def load_profile(profile_id: str) -> dict[str, Any]:
    path = PROFILE_FILES.get(profile_id)
    if path is None:
        raise AdmissionError(blocker("unknown_profile_id", "Admission profile is not known"))
    profile = load_json(path, "profile_definition_invalid")
    if not isinstance(profile, dict):
        raise AdmissionError(blocker("profile_definition_invalid", "Admission profile definition is not an object"))

    required = {
        "admission_kind",
        "profile_id",
        "schema_ref",
        "required_review_status",
        "payload_kinds",
        "placement_policy_id",
    }
    missing = sorted(required - set(profile))
    if missing:
        raise AdmissionError(blocker("profile_definition_invalid", f"Admission profile is missing fields: {', '.join(missing)}"))
    if profile["profile_id"] != profile_id:
        raise AdmissionError(blocker("profile_definition_invalid", "Admission profile id does not match file name"))
    if profile["required_review_status"] != "approved":
        raise AdmissionError(blocker("profile_definition_invalid", "Admission profile must require approved review status"))
    if profile["placement_policy_id"] != "not_implemented":
        raise AdmissionError(blocker("profile_definition_invalid", "Stage 1 placement policy must be not_implemented"))
    if not isinstance(profile["payload_kinds"], list) or not profile["payload_kinds"]:
        raise AdmissionError(blocker("profile_definition_invalid", "Admission profile payload_kinds must be a non-empty array"))
    return profile


def load_registry() -> dict[str, Any]:
    registry = load_json(REGISTRY_PATH, "registry_definition_invalid")
    if not isinstance(registry, dict):
        raise AdmissionError(blocker("registry_definition_invalid", "Knowledge profile registry is not an object"))
    if registry.get("registry_id") != "knowledge_profiles.v1":
        raise AdmissionError(blocker("registry_definition_invalid", "Knowledge profile registry id is invalid"))
    entries = registry.get("profiles")
    if not isinstance(entries, dict):
        raise AdmissionError(blocker("registry_definition_invalid", "Knowledge profile registry profiles must be an object"))
    for profile_id, entry in entries.items():
        if not isinstance(entry, dict):
            raise AdmissionError(blocker("registry_definition_invalid", f"Registry entry is not an object: {profile_id}"))
        allowed = {"enabled_for_admission", "payload_kind", "placement_policy_id", "status"}
        extra = sorted(set(entry) - allowed)
        if extra:
            raise AdmissionError(blocker("registry_definition_invalid", f"Registry entry has forbidden fields: {profile_id}: {', '.join(extra)}"))
        for field in ("enabled_for_admission", "payload_kind", "placement_policy_id", "status"):
            if field not in entry:
                raise AdmissionError(blocker("registry_definition_invalid", f"Registry entry missing field: {profile_id}.{field}"))
        if entry["placement_policy_id"] != "not_implemented":
            raise AdmissionError(blocker("registry_definition_invalid", f"Registry placement policy must be not_implemented: {profile_id}"))
    return entries


def resolve_payload(package_dir: Path, payload_path_value: Any) -> Path:
    if not isinstance(payload_path_value, str) or not payload_path_value:
        raise AdmissionError(blocker("missing_payload", "Payload path is required"))
    payload_path = Path(payload_path_value)
    if payload_path.is_absolute():
        raise AdmissionError(blocker("absolute_payload_path", "Payload path must be relative to the package directory"))
    if ".." in payload_path.parts:
        raise AdmissionError(blocker("payload_path_escape", "Payload path must not contain traversal"))
    resolved_package = package_dir.resolve(strict=False)
    resolved_payload = (resolved_package / payload_path).resolve(strict=False)
    try:
        resolved_payload.relative_to(resolved_package)
    except ValueError as exc:
        raise AdmissionError(blocker("payload_path_escape", "Payload path escapes the package directory")) from exc
    if not resolved_payload.exists():
        raise AdmissionError(blocker("missing_payload", "Payload path does not exist"))
    return resolved_payload


def payload_kind(path: Path) -> str:
    if path.is_dir():
        return "directory"
    if path.is_file():
        return "file"
    return "other"


def ensure_payload_kind(actual: str, allowed: list[str]) -> None:
    if actual not in allowed:
        raise AdmissionError(blocker("payload_kind_mismatch", "Payload kind does not match admission policy"))


def build_result(
    *,
    package_dir: Path,
    package_data: dict[str, Any] | None,
    payload_path: Path | None,
    blockers: list[Blocker],
) -> dict[str, Any]:
    validation_status = "pass" if not blockers else "fail"
    package_data = package_data or {}
    result_admission_kind = package_data.get("admission_kind")
    result_knowledge_profile_id = package_data.get("knowledge_profile_id") if result_admission_kind == "knowledge_asset" else None
    if blockers and result_admission_kind == "knowledge_asset" and not result_knowledge_profile_id:
        result_admission_kind = None
    return {
        "validation_status": validation_status,
        "admission_status": "not_run",
        "mode": "dry_run",
        "admission_kind": result_admission_kind,
        "profile_id": package_data.get("profile_id"),
        "knowledge_profile_id": result_knowledge_profile_id,
        "asset_id": package_data.get("asset_id"),
        "package_path": package_dir.as_posix(),
        "payload_path": payload_path.as_posix() if payload_path is not None else None,
        "proposed_target_path": None,
        "blockers": [item.as_dict() for item in blockers],
        "evidence": {
            "phase_invoked": False,
            "canonical_write_performed": False,
        },
    }


def validate_result(result: dict[str, Any]) -> int:
    try:
        validate_instance(RESULT_SCHEMA, result, "result_schema_failed", "admission_result")
    except AdmissionError as exc:
        raise InternalResultError(exc.blocker.message) from exc
    return 0 if result["validation_status"] == "pass" else 1


def validate_package(package_dir: Path) -> tuple[dict[str, Any] | None, Path | None, list[Blocker]]:
    package_file = package_dir / "admission_package.json"
    if not package_file.is_file():
        return None, None, [blocker("missing_package_file", "Package directory must contain admission_package.json")]

    try:
        package_data = load_json(package_file, "package_json_invalid")
        if not isinstance(package_data, dict):
            raise AdmissionError(blocker("package_json_invalid", "Admission package JSON must be an object"))
        validate_instance(COMMON_SCHEMA, package_data, "common_schema_failed", "admission_package")

        admission_kind = package_data["admission_kind"]
        profile_id = package_data["profile_id"]
        if admission_kind not in KIND_PROFILE:
            raise AdmissionError(blocker("unknown_admission_kind", "Admission kind is not known"))
        if profile_id not in PROFILE_FILES:
            raise AdmissionError(blocker("unknown_profile_id", "Admission profile is not known"))
        if KIND_PROFILE[admission_kind] != profile_id:
            raise AdmissionError(blocker("kind_profile_mismatch", "Admission kind and profile_id are incompatible"))

        profile = load_profile(profile_id)
        if profile["admission_kind"] != admission_kind:
            raise AdmissionError(blocker("profile_definition_invalid", "Admission profile kind does not match package kind"))

        if admission_kind == "source_capture":
            if "knowledge_profile_id" in package_data:
                raise AdmissionError(blocker("forbidden_knowledge_profile_id", "Source capture packages must not include knowledge_profile_id"))
            if "profile_data" in package_data:
                raise AdmissionError(blocker("forbidden_profile_data", "Source capture packages must not include profile_data"))
        else:
            knowledge_profile_id = package_data.get("knowledge_profile_id")
            if not knowledge_profile_id:
                raise AdmissionError(blocker("missing_knowledge_profile_id", "Knowledge asset packages must include knowledge_profile_id"))
            if "profile_data" not in package_data:
                raise AdmissionError(blocker("missing_profile_data", "Knowledge asset packages must include profile_data"))
            profile_data = package_data.get("profile_data")
            if not isinstance(profile_data, dict) or not profile_data:
                raise AdmissionError(blocker("invalid_profile_data_container", "profile_data must be a non-empty object"))

        schema_ref = profile["schema_ref"]
        if not isinstance(schema_ref, str) or schema_ref.startswith("/") or ".." in Path(schema_ref).parts:
            raise AdmissionError(blocker("profile_definition_invalid", "Admission profile schema_ref must be repo-relative within admission"))
        kind_schema = ADMISSION_ROOT / schema_ref
        validate_instance(kind_schema, package_data, "common_schema_failed", profile_id)

        if package_data["review_status"] != profile["required_review_status"]:
            raise AdmissionError(blocker("review_not_approved", "Review status must be approved"))

        payload = resolve_payload(package_dir, package_data["payload_path"])
        actual_payload_kind = payload_kind(payload)
        ensure_payload_kind(actual_payload_kind, profile["payload_kinds"])

        if admission_kind == "source_capture":
            return package_data, payload, []

        knowledge_profile_id = package_data.get("knowledge_profile_id")
        registry = load_registry()
        entry = registry.get(knowledge_profile_id)
        if entry is None:
            raise AdmissionError(blocker("unknown_knowledge_profile_id", "Knowledge profile id is not registered"))
        if entry["enabled_for_admission"] is not True:
            raise AdmissionError(blocker("disabled_knowledge_profile_id", "Knowledge profile id is not enabled for admission"))
        registry_payload_kind = entry["payload_kind"]
        if registry_payload_kind is not None:
            ensure_payload_kind(actual_payload_kind, [registry_payload_kind])

        return package_data, payload, []
    except AdmissionError as exc:
        package_data_for_result = package_data if "package_data" in locals() and isinstance(package_data, dict) else None
        return package_data_for_result, None, [exc.blocker]


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Stage 1 admission dry-run validation")
    parser.add_argument("--package", required=True, dest="package_dir")
    parser.add_argument("--dry-run", action="store_true", required=True)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    package_dir = Path(args.package_dir).resolve(strict=False)

    package_data, payload, blockers = validate_package(package_dir)
    result = build_result(
        package_dir=package_dir,
        package_data=package_data,
        payload_path=payload,
        blockers=blockers,
    )
    try:
        exit_code = validate_result(result)
    except InternalResultError as exc:
        print(f"FAIL internal admission result schema validation failed: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return exit_code


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except BrokenPipeError:
        raise SystemExit(1)
