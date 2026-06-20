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

from repo_admission_lib import AdmissionError, resolve_existing_repo_file, sha256_file


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


def local_sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def reject_symlink_components(root: Path, path: Path, *, field_name: str) -> None:
    root = root.resolve(strict=False)
    try:
        relative = path.relative_to(root)
    except ValueError as exc:
        raise AdmissionError(f"{field_name} must resolve inside {path_ref(root, root)}") from exc
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise AdmissionError(f"{field_name} must not traverse or reference symlinks")


def resolve_phase4_invocation_claim(repo_root: Path, claim_path_text: str) -> Path:
    if not claim_path_text:
        raise AdmissionError("phase4 invocation claim path is empty")
    raw_path = Path(claim_path_text).expanduser()
    if any(part in {"..", ""} for part in raw_path.parts):
        raise AdmissionError("phase4 invocation claim path must not contain traversal or empty segments")
    if not raw_path.is_absolute():
        raw_path = repo_root / raw_path
    resolved = raw_path.resolve(strict=False)
    phase4_runs_root = (repo_root / "operations" / "harness-phase4" / "runs").resolve(strict=False)
    reject_symlink_components(repo_root.resolve(strict=False), raw_path, field_name="phase4_invocation_claim")
    try:
        relative = resolved.relative_to(phase4_runs_root)
    except ValueError as exc:
        raise AdmissionError("phase4 invocation claim must resolve under operations/harness-phase4/runs/") from exc
    if len(relative.parts) != 2 or relative.parts[1] != "phase4_invocation_claim.json":
        raise AdmissionError("phase4 invocation claim must be operations/harness-phase4/runs/<WRAPPER_RUN_ID>/phase4_invocation_claim.json")
    if not resolved.is_file():
        raise AdmissionError("phase4 invocation claim file is missing")
    if resolved.is_symlink():
        raise AdmissionError("phase4 invocation claim must not be a symlink")
    return resolved


def read_json_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level JSON value must be an object")
    return payload


def freeze_admission_manifest_if_needed(repo_root: Path, execution_target_json: Path, input_dir: Path) -> None:
    try:
        target_payload = read_json_object(execution_target_json)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        raise AdmissionError(f"external execution target JSON is invalid or unreadable: {exc}") from exc

    target_kind = target_payload.get("target_kind")
    if target_kind not in {"repo_admission", "kb_admission"}:
        return

    manifest_ref = target_payload.get("admission_manifest_ref")
    manifest_path = resolve_existing_repo_file(repo_root, manifest_ref, field_name="admission_manifest_ref")
    shutil.copyfile(manifest_path, input_dir / "admission_manifest.json")

    if target_kind == "repo_admission":
        write_json(
            input_dir / "admission_manifest_freeze.json",
            {
                "generated_at": now_utc(),
                "admission_manifest_ref": manifest_ref,
                "frozen_manifest_ref": "input/admission_manifest.json",
                "manifest_hash": sha256_file(manifest_path),
            },
        )
        return

    kb_integration_ref = target_payload.get("kb_integration_ref")
    kb_integration_path = resolve_existing_repo_file(repo_root, kb_integration_ref, field_name="kb_integration_ref")
    shutil.copyfile(kb_integration_path, input_dir / "kb_integration.yaml")
    write_json(
        input_dir / "kb_admission_freeze.json",
        {
            "generated_at": now_utc(),
            "admission_manifest_ref": manifest_ref,
            "frozen_manifest_ref": "input/admission_manifest.json",
            "manifest_hash": sha256_file(manifest_path),
            "kb_integration_ref": kb_integration_ref,
            "frozen_kb_integration_ref": "input/kb_integration.yaml",
            "kb_integration_hash": sha256_file(kb_integration_path),
        },
    )


def main() -> int:
    if len(sys.argv) not in {5, 6}:
        print(
            "usage: freeze_phase2_input.py <repo-root> <phase2-run-dir> <run-dir> <execution-target-json> [phase4-invocation-claim]",
            file=sys.stderr,
        )
        return 2

    repo_root = Path(sys.argv[1]).resolve(strict=False)
    phase2_run_dir = Path(sys.argv[2]).resolve(strict=False)
    run_dir = Path(sys.argv[3]).resolve(strict=False)
    execution_target_json = Path(sys.argv[4]).resolve(strict=False)
    phase4_invocation_claim_arg = sys.argv[5] if len(sys.argv) == 6 else ""

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

    try:
        freeze_admission_manifest_if_needed(repo_root, execution_target_json, input_dir)
    except AdmissionError as exc:
        print(f"invalid admission input ref: {exc}", file=sys.stderr)
        return 1

    for frozen_name, source_rel_path in REQUIRED_PHASE2_FILES.items():
        shutil.copyfile(phase2_run_dir / source_rel_path, input_dir / frozen_name)

    frozen_execution_target = input_dir / "execution_target.json"
    shutil.copyfile(execution_target_json, frozen_execution_target)
    write_json(
        input_dir / "execution_target_freeze.json",
        {
            "generated_at": now_utc(),
            "execution_target_ref": path_ref(repo_root, execution_target_json),
            "frozen_execution_target_ref": "input/execution_target.json",
            "execution_target_sha256": local_sha256_file(execution_target_json),
            "frozen_execution_target_sha256": local_sha256_file(frozen_execution_target),
        },
    )

    if phase4_invocation_claim_arg:
        try:
            claim_path = resolve_phase4_invocation_claim(repo_root, phase4_invocation_claim_arg)
        except AdmissionError as exc:
            print(f"invalid Phase 4 invocation claim path: {exc}", file=sys.stderr)
            return 1
        frozen_claim = input_dir / "phase4_invocation_claim.json"
        shutil.copyfile(claim_path, frozen_claim)
        source_hash = local_sha256_file(claim_path)
        frozen_hash = local_sha256_file(frozen_claim)
        write_json(
            input_dir / "phase4_invocation_claim_freeze.json",
            {
                "generated_at": now_utc(),
                "phase4_invocation_claim_ref": path_ref(repo_root, claim_path),
                "frozen_phase4_invocation_claim_ref": "input/phase4_invocation_claim.json",
                "phase4_invocation_claim_sha256": source_hash,
                "frozen_phase4_invocation_claim_sha256": frozen_hash,
                "byte_identical": source_hash == frozen_hash,
            },
        )

    manifest_entries: list[dict[str, Any]] = []
    hash_lines: list[str] = []
    for package_file in package_files:
        rel_path = package_file.relative_to(runtime_ready_dir).as_posix()
        digest = local_sha256_file(package_file)
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
