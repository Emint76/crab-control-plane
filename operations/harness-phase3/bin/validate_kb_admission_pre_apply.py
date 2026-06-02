#!/usr/bin/env python3
"""Validate a frozen workspace KB admission manifest before byte-for-byte copy."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from kb_admission_lib import (
    KBAdmissionError,
    now_utc,
    read_json_object,
    repo_ref,
    sha256_file,
    validate_pre_apply,
    write_json,
)


def add_check(checks: list[dict[str, Any]], name: str, status: str, detail: str, **extra: Any) -> None:
    item: dict[str, Any] = {"name": name, "status": status, "detail": detail}
    item.update(extra)
    checks.append(item)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: validate_kb_admission_pre_apply.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve(strict=False)
    run_dir = Path(sys.argv[2]).resolve(strict=False)
    report_path = run_dir / "checks" / "pre_apply_validation.json"
    manifest_path = run_dir / "input" / "admission_manifest.json"
    integration_path = run_dir / "input" / "kb_integration.yaml"
    checks: list[dict[str, Any]] = []

    context, violations, artifacts_report = validate_pre_apply(repo_root, run_dir)

    if integration_path.is_file():
        add_check(
            checks,
            "kb_integration.frozen",
            "pass",
            "Frozen KB integration template is present.",
            source_refs=[repo_ref(repo_root, integration_path)],
            kb_integration_hash=sha256_file(integration_path),
        )
    else:
        add_check(
            checks,
            "kb_integration.frozen",
            "fail",
            "Frozen KB integration template must be present.",
            source_refs=[repo_ref(repo_root, integration_path)],
        )

    if manifest_path.is_file():
        add_check(
            checks,
            "admission_manifest.frozen",
            "pass",
            "Frozen admission manifest is present.",
            source_refs=[repo_ref(repo_root, manifest_path)],
            manifest_hash=sha256_file(manifest_path),
        )
    else:
        add_check(
            checks,
            "admission_manifest.frozen",
            "fail",
            "Frozen admission manifest must be present.",
            source_refs=[repo_ref(repo_root, manifest_path)],
        )

    if context is not None:
        add_check(
            checks,
            "kb_root.runtime_resolved",
            "pass",
            "Configured KB root environment variable resolves to a safe existing workspace root outside the repository.",
            kb_root_env=context.get("kb_root_env"),
            kb_root_resolved=context.get("kb_root_resolved"),
        )
    else:
        add_check(
            checks,
            "kb_root.runtime_resolved",
            "fail",
            "Configured KB root could not be safely resolved before write.",
        )

    if violations:
        add_check(
            checks,
            "kb_admission.copy_plan_preflight",
            "fail",
            "Workspace KB admission failed schema, root, path, hash, or overwrite preflight before write.",
            actual=sorted(set(violations)),
        )
    else:
        add_check(
            checks,
            "kb_admission.copy_plan_preflight",
            "pass",
            "Workspace KB admission full-manifest copy plan passed before write.",
        )

    payload = {
        "run_id": run_dir.name,
        "generated_at": now_utc(),
        "engine_mode": "kb_admission",
        "evaluation_mode": "phase3-static-v1",
        "status": "fail" if violations else "pass",
        "target_runtime": "workspace",
        "target_kind": "kb_admission",
        "kb_root_env": context.get("kb_root_env") if context else None,
        "kb_root_resolved": context.get("kb_root_resolved") if context else None,
        "kb_integration_hash": context.get("kb_integration_hash") if context else None,
        "manifest_hash": context.get("manifest_hash") if context else None,
        "layout_enforcement": "descriptive_metadata_only",
        "checks": checks,
        "artifacts": artifacts_report,
        "violations": sorted(set(violations)),
    }
    write_json(report_path, payload)
    return 0 if payload["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
