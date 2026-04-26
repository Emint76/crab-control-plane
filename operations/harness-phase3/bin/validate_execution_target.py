#!/usr/bin/env python3
"""Validate the frozen Phase 3 execution target contract."""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


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

    run_dir = Path(sys.argv[2]).resolve(strict=False)
    run_id = run_dir.name
    target_path = run_dir / "input" / "execution_target.json"
    report_path = run_dir / "checks" / "execution_target_validation.json"
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
