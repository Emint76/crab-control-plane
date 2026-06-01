#!/usr/bin/env python3
"""Helpers for Phase 3 repo admission target handling."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any

from jsonschema import Draft202012Validator


ALLOWED_DESTINATION_PREFIXES = (
    "knowledge/kb/sources/",
    "knowledge/kb/knowledge/",
)
HEX_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class AdmissionError(ValueError):
    pass


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise AdmissionError("top-level JSON value must be an object")
    return payload


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def repo_ref(repo_root: Path, path: Path) -> str:
    resolved = path.resolve(strict=False)
    try:
        return resolved.relative_to(repo_root.resolve(strict=False)).as_posix()
    except ValueError:
        return resolved.as_posix()


def is_absolute_or_windows_path(ref: str) -> bool:
    return ref.startswith("/") or bool(re.match(r"^[A-Za-z]:[\\/]", ref))


def normalize_repo_ref(ref: str, *, field_name: str) -> str:
    if not isinstance(ref, str) or not ref.strip():
        raise AdmissionError(f"{field_name} must be a non-empty string")
    if "\\" in ref:
        raise AdmissionError(f"{field_name} must use forward-slash repo paths")
    if is_absolute_or_windows_path(ref):
        raise AdmissionError(f"{field_name} must be repository-relative")
    path = PurePosixPath(ref)
    if any(part in {"", ".", ".."} for part in path.parts):
        raise AdmissionError(f"{field_name} must not contain traversal or empty path segments")
    return path.as_posix()


def resolve_repo_path(repo_root: Path, ref: str, *, field_name: str) -> Path:
    normalized = normalize_repo_ref(ref, field_name=field_name)
    repo_root = repo_root.resolve(strict=False)
    resolved = (repo_root / normalized).resolve(strict=False)
    try:
        resolved.relative_to(repo_root)
    except ValueError as exc:
        raise AdmissionError(f"{field_name} must resolve inside the repository") from exc
    return resolved


def reject_symlink_chain(repo_root: Path, path: Path, *, field_name: str, include_leaf: bool) -> None:
    repo_root = repo_root.resolve(strict=False)
    target = path.resolve(strict=False)
    try:
        relative = target.relative_to(repo_root)
    except ValueError as exc:
        raise AdmissionError(f"{field_name} must resolve inside the repository") from exc

    current = repo_root
    parts = list(relative.parts)
    check_parts = parts if include_leaf else parts[:-1]
    for part in check_parts:
        current = current / part
        if current.is_symlink():
            raise AdmissionError(f"{field_name} must not traverse symlinks")


def resolve_existing_repo_file(repo_root: Path, ref: str, *, field_name: str) -> Path:
    path = resolve_repo_path(repo_root, ref, field_name=field_name)
    reject_symlink_chain(repo_root, path, field_name=field_name, include_leaf=True)
    if not path.is_file():
        raise AdmissionError(f"{field_name} must reference an existing repository file")
    return path


def resolve_destination_path(repo_root: Path, ref: str) -> Path:
    normalized = normalize_repo_ref(ref, field_name="destination_kb_path")
    if not any(normalized.startswith(prefix) and len(normalized) > len(prefix) for prefix in ALLOWED_DESTINATION_PREFIXES):
        raise AdmissionError("destination_kb_path must be under knowledge/kb/sources/ or knowledge/kb/knowledge/")
    path = resolve_repo_path(repo_root, normalized, field_name="destination_kb_path")
    reject_symlink_chain(repo_root, path, field_name="destination_kb_path", include_leaf=False)
    if path.is_symlink():
        raise AdmissionError("destination_kb_path must not be a symlink")
    return path


def validate_manifest_schema(repo_root: Path, manifest: dict[str, Any]) -> list[str]:
    schema_path = repo_root / "operations" / "harness-phase3" / "contracts" / "admission_manifest.schema.json"
    schema = read_json_object(schema_path)
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(manifest), key=lambda error: (list(error.path), error.validator, error.message))
    return [format_schema_error(error) for error in errors]


def format_schema_error(error: Any) -> str:
    path = ".".join(str(item) for item in error.path)
    suffix = f".{path}" if path else ""
    if error.validator == "required":
        missing = error.message.split("'")
        if len(missing) >= 2:
            return f"schema.required.{missing[1]}"
        return "schema.required"
    return f"schema.{error.validator}{suffix}"


def manifest_hash(run_dir: Path) -> str:
    return sha256_file(run_dir / "input" / "admission_manifest.json")


def validate_manifest_paths_and_hashes(repo_root: Path, manifest: dict[str, Any]) -> tuple[list[str], list[dict[str, Any]]]:
    violations: list[str] = []
    artifacts_report: list[dict[str, Any]] = []
    artifacts = manifest.get("artifacts") if isinstance(manifest, dict) else None
    if not isinstance(artifacts, list):
        return ["manifest.artifacts.invalid"], artifacts_report

    for index, artifact in enumerate(artifacts):
        item_report: dict[str, Any] = {"index": index}
        if not isinstance(artifact, dict):
            violations.append(f"artifact[{index}].invalid")
            artifacts_report.append(item_report)
            continue
        source_ref = artifact.get("input_artifact_ref")
        destination_ref = artifact.get("destination_kb_path")
        expected_hash = artifact.get("expected_sha256")
        item_report.update(
            {
                "input_artifact_ref": source_ref,
                "destination_kb_path": destination_ref,
                "expected_sha256": expected_hash,
            }
        )
        try:
            source_path = resolve_existing_repo_file(repo_root, source_ref, field_name="input_artifact_ref")
            source_hash = sha256_file(source_path)
            item_report["source_artifact_hash"] = source_hash
            if source_hash != expected_hash:
                violations.append(f"artifact[{index}].hash_mismatch")
        except AdmissionError as exc:
            violations.append(f"artifact[{index}].source_ref_unsafe")
            item_report["source_error"] = str(exc)
        try:
            destination_path = resolve_destination_path(repo_root, destination_ref)
            item_report["destination_path"] = repo_ref(repo_root, destination_path)
        except AdmissionError as exc:
            violations.append(f"artifact[{index}].destination_ref_unsafe")
            item_report["destination_error"] = str(exc)
        artifacts_report.append(item_report)
    return violations, artifacts_report


def execute_repo_admission(repo_root: Path, run_dir: Path) -> int:
    manifest_path = run_dir / "input" / "admission_manifest.json"
    evidence_path = run_dir / "checks" / "repo_admission_evidence.json"
    apply_log_path = run_dir / "logs" / "apply.log"
    apply_log_path.parent.mkdir(parents=True, exist_ok=True)
    evidence_path.parent.mkdir(parents=True, exist_ok=True)

    evidence_items: list[dict[str, Any]] = []
    log_lines = [f"timestamp={now_utc()}", f"run_id={run_dir.name}", "target_kind=repo_admission"]
    overall_status = "pass"

    try:
        manifest = read_json_object(manifest_path)
        current_manifest_hash = sha256_file(manifest_path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        payload = {
            "run_id": run_dir.name,
            "generated_at": now_utc(),
            "status": "fail",
            "manifest_hash": None,
            "evidence": [
                {
                    "action": "failed_closed",
                    "overwrite_verdict": "manifest_unreadable",
                    "error": str(exc),
                }
            ],
        }
        write_json(evidence_path, payload)
        apply_log_path.write_text("\n".join([*log_lines, "result=fail"]) + "\n", encoding="utf-8")
        return 1

    for index, artifact in enumerate(manifest.get("artifacts", [])):
        item = {
            "artifact_index": index,
            "manifest_hash": current_manifest_hash,
            "input_artifact_ref": artifact.get("input_artifact_ref") if isinstance(artifact, dict) else None,
            "destination_path": artifact.get("destination_kb_path") if isinstance(artifact, dict) else None,
            "expected_hash": artifact.get("expected_sha256") if isinstance(artifact, dict) else None,
            "source_artifact_hash": None,
            "final_destination_hash": None,
            "action": "failed_closed",
            "overwrite_verdict": "not_attempted",
        }
        try:
            if not isinstance(artifact, dict):
                raise AdmissionError("artifact entry must be an object")
            source_path = resolve_existing_repo_file(repo_root, artifact.get("input_artifact_ref"), field_name="input_artifact_ref")
            destination_path = resolve_destination_path(repo_root, artifact.get("destination_kb_path"))
            source_hash = sha256_file(source_path)
            item["source_artifact_hash"] = source_hash
            item["destination_path"] = repo_ref(repo_root, destination_path)
            if source_hash != artifact.get("expected_sha256"):
                item["overwrite_verdict"] = "source_hash_mismatch"
                raise AdmissionError("source artifact hash does not match expected_sha256")
            if destination_path.exists():
                if not destination_path.is_file():
                    item["overwrite_verdict"] = "destination_not_regular_file"
                    raise AdmissionError("destination exists but is not a regular file")
                destination_hash = sha256_file(destination_path)
                item["final_destination_hash"] = destination_hash
                if destination_hash == source_hash:
                    item["action"] = "idempotent"
                    item["overwrite_verdict"] = "same_hash_existing"
                else:
                    item["overwrite_verdict"] = "different_hash_existing"
                    raise AdmissionError("destination exists with a different hash")
            else:
                destination_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source_path, destination_path)
                final_hash = sha256_file(destination_path)
                item["final_destination_hash"] = final_hash
                if final_hash != source_hash:
                    item["overwrite_verdict"] = "final_hash_mismatch"
                    raise AdmissionError("destination hash after copy does not match source hash")
                item["action"] = "copied"
                item["overwrite_verdict"] = "destination_missing"
        except AdmissionError as exc:
            overall_status = "fail"
            item["error"] = str(exc)
        evidence_items.append(item)

    payload = {
        "run_id": run_dir.name,
        "generated_at": now_utc(),
        "status": overall_status,
        "manifest_hash": current_manifest_hash,
        "evidence": evidence_items,
    }
    write_json(evidence_path, payload)
    action_summary = ",".join(str(item.get("action")) for item in evidence_items) if evidence_items else "none"
    log_lines.extend([
        f"manifest_hash={current_manifest_hash}",
        f"actions={action_summary}",
        f"result={'success' if overall_status == 'pass' else 'fail'}",
    ])
    apply_log_path.write_text("\n".join(log_lines) + "\n", encoding="utf-8")
    return 0 if overall_status == "pass" else 1
