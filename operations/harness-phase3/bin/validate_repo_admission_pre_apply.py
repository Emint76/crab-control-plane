#!/usr/bin/env python3
"""Validate a frozen repo admission manifest before byte-for-byte copy."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from repo_admission_lib import (
    AdmissionError,
    manifest_hash,
    now_utc,
    read_json_object,
    repo_ref,
    validate_manifest_paths_and_hashes,
    validate_manifest_schema,
    write_json,
)


def add_check(checks: list[dict[str, Any]], name: str, status: str, detail: str, **extra: Any) -> None:
    item: dict[str, Any] = {"name": name, "status": status, "detail": detail}
    item.update(extra)
    checks.append(item)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: validate_repo_admission_pre_apply.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve(strict=False)
    run_dir = Path(sys.argv[2]).resolve(strict=False)
    report_path = run_dir / "checks" / "pre_apply_validation.json"
    manifest_path = run_dir / "input" / "admission_manifest.json"
    checks: list[dict[str, Any]] = []
    violations: list[str] = []
    artifacts_report: list[dict[str, Any]] = []
    current_manifest_hash: str | None = None

    try:
        manifest = read_json_object(manifest_path)
        current_manifest_hash = manifest_hash(run_dir)
        add_check(
            checks,
            "admission_manifest.parse",
            "pass",
            "Frozen admission manifest is a parseable JSON object.",
            source_refs=[repo_ref(repo_root, manifest_path)],
        )
    except (OSError, ValueError, json.JSONDecodeError, AdmissionError) as exc:
        add_check(
            checks,
            "admission_manifest.parse",
            "fail",
            f"Frozen admission manifest must be readable JSON: {exc}",
            source_refs=[repo_ref(repo_root, manifest_path)],
        )
        manifest = {}
        violations.append("admission_manifest.parse")

    if manifest:
        schema_violations = validate_manifest_schema(repo_root, manifest)
        if schema_violations:
            violations.extend(schema_violations)
            add_check(
                checks,
                "admission_manifest.schema",
                "fail",
                "Frozen admission manifest does not conform to admission_manifest.schema.json.",
                source_refs=[repo_ref(repo_root, manifest_path)],
                actual=schema_violations,
            )
        else:
            add_check(
                checks,
                "admission_manifest.schema",
                "pass",
                "Frozen admission manifest conforms to admission_manifest.schema.json.",
                source_refs=[repo_ref(repo_root, manifest_path)],
            )

        path_hash_violations, artifacts_report = validate_manifest_paths_and_hashes(repo_root, manifest)
        if path_hash_violations:
            violations.extend(path_hash_violations)
            add_check(
                checks,
                "admission_manifest.artifacts.safe_and_hashed",
                "fail",
                "Admission artifact refs, destination paths, or expected hashes are invalid.",
                source_refs=[repo_ref(repo_root, manifest_path)],
                actual=path_hash_violations,
            )
        else:
            add_check(
                checks,
                "admission_manifest.artifacts.safe_and_hashed",
                "pass",
                "Admission artifact refs are repo-contained, hashes match, and destinations are allowlisted KB paths.",
                source_refs=[repo_ref(repo_root, manifest_path)],
            )

    payload = {
        "run_id": run_dir.name,
        "generated_at": now_utc(),
        "engine_mode": "repo_admission",
        "evaluation_mode": "phase3-static-v1",
        "status": "fail" if violations else "pass",
        "manifest_hash": current_manifest_hash,
        "checks": checks,
        "artifacts": artifacts_report,
        "violations": sorted(set(violations)),
    }
    write_json(report_path, payload)
    return 0 if payload["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
