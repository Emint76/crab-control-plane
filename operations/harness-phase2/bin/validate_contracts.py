#!/usr/bin/env python3
"""v1 scaffold validator for Phase 2 contract schemas and examples."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from jsonschema import Draft202012Validator


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: validate_contracts.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve()
    run_dir = Path(sys.argv[2]).resolve()
    run_id = run_dir.name
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)
    report_path = checks_dir / "contracts_validation.json"

    schemas_dir = repo_root / "control-plane" / "contracts" / "schemas"
    examples_dir = repo_root / "control-plane" / "contracts" / "examples"

    schema_example_pairs = [
        ("apply_plan.schema.json", "apply_plan.example.json"),
        ("validation_report.schema.json", "validation_report.example.json"),
        ("admission_decision.schema.json", "admission_decision.example.json"),
        ("placement_decision.schema.json", "placement_decision.example.json"),
    ]
    legacy_schema_names = [
        "task_packet.schema.json",
        "result_packet.schema.json",
    ]

    checks: list[dict[str, str]] = []
    failed = False

    for schema_name, example_name in schema_example_pairs:
        schema_path = schemas_dir / schema_name
        example_path = examples_dir / example_name
        try:
            schema = load_json(schema_path)
            Draft202012Validator.check_schema(schema)
            example = load_json(example_path)
            Draft202012Validator(schema).validate(example)
            checks.append({"name": schema_name, "status": "pass", "detail": f"validated with {example_name}"})
        except Exception as exc:  # noqa: BLE001
            failed = True
            checks.append({"name": schema_name, "status": "fail", "detail": str(exc)})

    for schema_name in legacy_schema_names:
        schema_path = schemas_dir / schema_name
        try:
            schema = load_json(schema_path)
            Draft202012Validator.check_schema(schema)
            checks.append({"name": schema_name, "status": "pass", "detail": "schema readable and valid"})
        except Exception as exc:  # noqa: BLE001
            failed = True
            checks.append({"name": schema_name, "status": "fail", "detail": str(exc)})

    report = {
        "run_id": run_id,
        "generated_at": now_utc(),
        "engine_mode": "scaffold",
        "evaluation_mode": "static-v1",
        "status": "fail" if failed else "pass",
        "checks": checks,
    }
    with report_path.open("w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
