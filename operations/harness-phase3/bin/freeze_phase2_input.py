#!/usr/bin/env python3
"""Freeze the Phase 2 handoff surface and external execution target into Phase 3 input/."""

from __future__ import annotations

import hashlib
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REQUIRED_PHASE2_FILES = {
    "run_meta.phase2.json": "run_meta.json",
    "validation_report.json": "validation_report.json",
    "admission_decision.json": "admission_decision.json",
    "placement_decision.json": "placement_decision.json",
    "apply_plan.json": "apply_plan.json",
    "handoff_ready.json": "handoff_ready.json",
    "smoke_validation.json": "checks/smoke_validation.json",
    "conformance_validation.json": "checks/conformance_validation.json",
}


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def path_ref(repo_root: Path, path: Path) -> str:
    resolved = path.resolve(strict=False)
    try:
        return resolved.relative_to(repo_root.resolve(strict=False)).as_posix()
    except ValueError:
        return resolved.as_posix()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    if len(sys.argv) != 5:
        print(
            "usage: freeze_phase2_input.py <repo-root> <phase2-run-dir> <run-dir> <execution-target-json>",
            file=sys.stderr,
        )
        return 2

    repo_root = Path(sys.argv[1]).resolve(strict=False)
    phase2_run_dir = Path(sys.argv[2]).resolve(strict=False)
    run_dir = Path(sys.argv[3]).resolve(strict=False)
    execution_target_json = Path(sys.argv[4]).resolve(strict=False)

    input_dir = run_dir / "input"
    input_dir.mkdir(parents=True, exist_ok=True)

    runtime_ready_dir = phase2_run_dir / "output" / "runtime-ready"
    missing_sources = [
        source_rel_path
        for source_rel_path in REQUIRED_PHASE2_FILES.values()
        if not (phase2_run_dir / source_rel_path).is_file()
    ]
    if missing_sources:
        print(f"missing required Phase 2 artifacts: {', '.join(sorted(missing_sources))}", file=sys.stderr)
        return 1
    if not execution_target_json.is_file():
        print(f"missing external execution target JSON: {execution_target_json}", file=sys.stderr)
        return 1
    if not runtime_ready_dir.is_dir():
        print(f"missing upstream runtime-ready package: {runtime_ready_dir}", file=sys.stderr)
        return 1

    package_files = sorted(path for path in runtime_ready_dir.rglob("*") if path.is_file())
    if not package_files:
        print(f"upstream runtime-ready package is empty: {runtime_ready_dir}", file=sys.stderr)
        return 1

    for frozen_name, source_rel_path in REQUIRED_PHASE2_FILES.items():
        shutil.copyfile(phase2_run_dir / source_rel_path, input_dir / frozen_name)

    shutil.copyfile(execution_target_json, input_dir / "execution_target.json")

    manifest_entries: list[dict[str, Any]] = []
    hash_lines: list[str] = []
    for package_file in package_files:
        rel_path = package_file.relative_to(runtime_ready_dir).as_posix()
        digest = sha256_file(package_file)
        manifest_entries.append(
            {
                "path": rel_path,
                "size_bytes": package_file.stat().st_size,
                "sha256": digest,
            }
        )
        hash_lines.append(f"{digest}  {rel_path}")

    runtime_ready_manifest = {
        "run_id": run_dir.name,
        "generated_at": now_utc(),
        "engine_mode": "scaffold",
        "evaluation_mode": "phase3-static-v1",
        "phase2_run_ref": path_ref(repo_root, phase2_run_dir),
        "phase2_runtime_ready_ref": path_ref(repo_root, runtime_ready_dir),
        "file_count": len(manifest_entries),
        "files": manifest_entries,
    }
    write_json(input_dir / "runtime_ready_manifest.json", runtime_ready_manifest)
    (input_dir / "runtime_ready.sha256").write_text("\n".join(hash_lines) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
