#!/usr/bin/env python3
"""Materialize the canonical Phase 3 staging target from the upstream runtime-ready package."""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path
from typing import Any


def read_json_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level JSON value must be an object")
    return payload


def resolve_from_run_meta(repo_root: Path, value: Any) -> Path:
    if not isinstance(value, str) or not value:
        raise ValueError("run_meta.json must contain a non-empty phase2_runtime_ready_ref")
    path = Path(value)
    if path.is_absolute():
        return path.resolve(strict=False)
    return (repo_root / path).resolve(strict=False)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: materialize_phase3_staging.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve(strict=False)
    run_dir = Path(sys.argv[2]).resolve(strict=False)
    run_meta = read_json_object(run_dir / "run_meta.json")

    source_dir = resolve_from_run_meta(repo_root, run_meta.get("phase2_runtime_ready_ref"))
    target_dir = (run_dir / "staging" / "runtime-ready-applied").resolve(strict=False)
    staging_root = (run_dir / "staging").resolve(strict=False)

    try:
        target_dir.relative_to(staging_root)
    except ValueError as exc:
        print(f"refusing to materialize outside canonical staging root: {exc}", file=sys.stderr)
        return 1

    if not source_dir.is_dir():
        print(f"missing upstream runtime-ready package: {source_dir}", file=sys.stderr)
        return 1
    if target_dir.exists():
        print(f"canonical staging target already exists: {target_dir}", file=sys.stderr)
        return 1

    source_files = sorted(path for path in source_dir.rglob("*") if path.is_file())
    if not source_files:
        print(f"upstream runtime-ready package is empty: {source_dir}", file=sys.stderr)
        return 1

    target_dir.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source_dir, target_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
