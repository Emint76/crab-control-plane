#!/usr/bin/env python3
"""Validate the frozen Phase 3 execution target contract."""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator
from jsonschema.exceptions import SchemaError, ValidationError


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def read_json_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level JSON value must be an object")
    return payload


def schema_violation_name(error: ValidationError) -> str:
    path = ".".join(str(item) for item in error.path)
    suffix = f".{path}" if path else ""
    if error.validator == "required":
        missing = error.message.split("'")
        if len(missing) >= 2:
            return f"schema.required.{missing[1]}"
        return "schema.required"
    if error.validator == "additionalProperties":
        return "schema.additionalProperties"
    if error.validator == "const":
        return f"schema.const{suffix}"
    if error.validator == "type":
        return f"schema.type{suffix}"
    if error.validator == "minLength":
        return f"schema.minLength{suffix}"
    return f"schema.{error.validator}{suffix}"


def unsafe_path_value(value: str) -> bool:
    if value.startswith("/"):
        return True
    if re.match(r"^[A-Za-z]:[\\/]", value):
        return True
    if "\\" in value:
        return True
    if value.startswith("../") or "/../" in value or value.endswith("/.."):
        return True
    return any(token in value for token in ("/tmp/", "/home/", "/Users/", "/mnt/"))


class Recorder:
    def __init__(self, run_id: str) -> None:
        self.run_id = run_id
        self.checks: list[dict[str, str]] = []
        self.violations: list[str] = []

    def add(self, name: str, status: str, detail: str) -> None:
        self.checks.append({"name": name, "status": status, "detail": detail})
        if status == "fail":
            self.violations.append(name)

    def add_violations(self, violations: list[str]) -> None:
        self.violations.extend(violations)

    def require_equal(self, payload: dict[str, Any], field: str, expected: str) -> None:
        actual = payload.get(field)
        if actual == expected:
            self.add(field, "pass", f"{field} matches {expected}.")
        else:
            self.add(field, "fail", f"{field} must equal {expected}.")

    def require_non_empty_string(self, payload: dict[str, Any], field: str) -> None:
        actual = payload.get(field)
        if isinstance(actual, str) and bool(actual.strip()):
            self.add(field, "pass", f"{field} is a non-empty string.")
        else:
            self.add(field, "fail", f"{field} must be a non-empty string.")

    def require_optional_string(self, payload: dict[str, Any], field: str) -> None:
        actual = payload.get(field)
        if actual is None or isinstance(actual, str):
            self.add(field, "pass", f"{field} is absent or a string.")
        else:
            self.add(field, "fail", f"{field} must be a string when present.")

    def reject_unsafe_paths(self, payload: dict[str, Any], field_names: list[str]) -> None:
        unsafe_fields = [
            field_name
            for field_name in field_names
            if isinstance(payload.get(field_name), str) and unsafe_path_value(payload[field_name])
        ]
        if unsafe_fields:
            for field_name in unsafe_fields:
                self.add(f"{field_name}.safe_path_value", "fail", f"{field_name} contains an unsafe path value.")
        else:
            self.add("target_fields.safe_path_values", "pass", "Target fields do not contain unsafe path values.")

    def report(self) -> dict[str, Any]:
        return {
            "status": "fail" if self.violations else "pass",
            "run_id": self.run_id,
            "generated_at": now_utc(),
            "checks": self.checks,
            "violations": sorted(set(self.violations)),
        }


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: validate_execution_target.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve(strict=False)
    run_dir = Path(sys.argv[2]).resolve(strict=False)
    run_id = run_dir.name
    target_path = run_dir / "input" / "execution_target.json"
    report_path = run_dir / "checks" / "execution_target_validation.json"
    schema_path = repo_root / "operations" / "harness-phase3" / "contracts" / "execution_target.schema.json"
    recorder = Recorder(run_id)
    payload: dict[str, Any] = {}

    try:
        payload = read_json_object(target_path)
        recorder.add("execution_target.parse", "pass", "Frozen execution_target.json is a parseable JSON object.")
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        recorder.add("execution_target.parse", "fail", f"Frozen execution_target.json is invalid or unreadable: {exc}")
        report = recorder.report()
        write_json(report_path, report)
        return 1

    try:
        schema = read_json_object(schema_path)
        Draft202012Validator.check_schema(schema)
        validator = Draft202012Validator(schema)
        schema_errors = sorted(
            validator.iter_errors(payload),
            key=lambda error: (list(error.path), error.validator, error.message),
        )
    except (OSError, ValueError, json.JSONDecodeError, SchemaError) as exc:
        recorder.add("execution_target.schema", "fail", f"execution_target.schema.json is invalid or unreadable: {exc}")
        report = recorder.report()
        write_json(report_path, report)
        return 1

    if schema_errors:
        violation_details = sorted((schema_violation_name(error), error.message) for error in schema_errors)
        violations = sorted(set(violation for violation, _message in violation_details))
        detail = "; ".join(f"{violation}: {message}" for violation, message in violation_details)
        recorder.add("execution_target.schema", "fail", f"Frozen execution_target.json does not conform to execution_target.schema.json: {detail}")
        recorder.add_violations(violations)
        report = recorder.report()
        write_json(report_path, report)
        return 1

    recorder.add(
        "execution_target.schema",
        "pass",
        "Frozen execution_target.json conforms to execution_target.schema.json.",
    )

    canonical_target_ref = f"operations/harness-phase3/runs/{run_id}/staging/runtime-ready-applied"
    recorder.require_equal(payload, "target_runtime", "openclaw")
    recorder.require_equal(payload, "target_kind", "phase3_staging")
    recorder.require_equal(payload, "apply_mode", "staged")
    recorder.require_equal(payload, "target_ref", canonical_target_ref)
    recorder.require_non_empty_string(payload, "approval_ref")
    recorder.require_optional_string(payload, "invoked_by")
    recorder.reject_unsafe_paths(
        payload,
        ["target_runtime", "target_kind", "apply_mode", "target_ref", "approval_ref", "invoked_by"],
    )

    report = recorder.report()
    write_json(report_path, report)
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
