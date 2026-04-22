#!/usr/bin/env python3
"""Perform the minimal deterministic scaffold apply against the staged surface only."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REQUIRED_STAGED_FILES = [
    "openclaw.template.json",
    "tool-policy.template.yaml",
    "agent-routing.template.yaml",
    "placement-policy.yaml",
    "admission-policy.yaml",
    "APPLY_MODEL.md",
]


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level JSON value must be an object")
    return payload


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: execute_apply.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    run_dir = Path(sys.argv[2]).resolve(strict=False)
    run_meta = read_json_object(run_dir / "run_meta.json")
    staging_dir = run_dir / "staging" / "runtime-ready-applied"
    apply_log_path = run_dir / "logs" / "apply.log"
    apply_log_path.parent.mkdir(parents=True, exist_ok=True)

    status = 0
    missing_files: list[str] = []
    present_files: list[str] = []
    if not staging_dir.is_dir():
        status = 1
        missing_files = REQUIRED_STAGED_FILES[:]
    else:
        for filename in REQUIRED_STAGED_FILES:
            staged_file = staging_dir / filename
            if staged_file.is_file():
                present_files.append(filename)
            else:
                missing_files.append(filename)
        if missing_files:
            status = 1

    log_lines = [
        f"timestamp={now_utc()}",
        f"run_id={run_dir.name}",
        "engine_mode=scaffold",
        f"execution_mode={run_meta.get('execution_mode')}",
        f"apply_mode={run_meta.get('apply_mode')}",
        f"target_ref={run_meta.get('target_ref')}",
        f"staging_ref=operations/harness-phase3/runs/{run_dir.name}/staging/runtime-ready-applied",
        "action=deterministic-staging-surface-noop-apply",
        f"present_files={','.join(present_files) if present_files else 'none'}",
        f"missing_files={','.join(missing_files) if missing_files else 'none'}",
        f"result={'success' if status == 0 else 'fail'}",
    ]
    apply_log_path.write_text("\n".join(log_lines) + "\n", encoding="utf-8")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
