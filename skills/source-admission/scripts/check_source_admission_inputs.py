#!/usr/bin/env python3
"""Check source-admission input readiness without performing admission.

This helper is local/manual proof only. It does not replace Phase2 or Phase3.
Canonical admission requires Phase3 workspace/kb_admission evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path, PurePosixPath
from typing import Any

import yaml
from jsonschema import Draft202012Validator

SOURCE_EVIDENCE_JSON = {
    "task-packet.json": "control-plane/contracts/schemas/task_packet.schema.json",
    "source-capture-package.json": "control-plane/contracts/schemas/source_capture_package.schema.json",
    "result-packet.json": "control-plane/contracts/schemas/result_packet.schema.json",
    "review-decision.json": "control-plane/contracts/schemas/review_decision.schema.json",
    "admission-decision.json": "control-plane/contracts/schemas/admission_decision.schema.json",
    "placement-decision.json": "control-plane/contracts/schemas/placement_decision.schema.json",
}


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"{path}: top-level JSON must be an object")
    return payload


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        payload = yaml.safe_load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"{path}: top-level YAML must be an object")
    return payload


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_existing(ref: str | Path, repo_root: Path, proof_dir: Path) -> Path | None:
    candidate = Path(ref)
    if candidate.is_absolute():
        return candidate if candidate.exists() else None
    workspace = Path("/home/node/.openclaw/workspace")
    for base in (repo_root, proof_dir, workspace):
        resolved = base / candidate
        if resolved.exists():
            return resolved
    return None


def require_existing(ref: str | Path, repo_root: Path, proof_dir: Path, label: str) -> Path:
    resolved = resolve_existing(ref, repo_root, proof_dir)
    if resolved is None:
        raise ValueError(f"{label} not found: {ref}")
    return resolved


def validate_instance(instance: Any, schema_path: Path, label: str) -> list[str]:
    schema = load_json(schema_path)
    Draft202012Validator.check_schema(schema)
    errors = sorted(Draft202012Validator(schema).iter_errors(instance), key=lambda error: list(error.path))
    if not errors:
        return []
    first = errors[0]
    path = ".".join(str(part) for part in first.path) or "<root>"
    return [f"{label} schema failed at {path}: {first.message}"]


def is_safe_relative_posix(value: str) -> bool:
    if not value or value.startswith("/") or "\\" in value or "//" in value:
        return False
    path = PurePosixPath(value)
    return all(part not in {"", ".", ".."} for part in path.parts)


def check_phase2_fixture(repo_root: Path, proof_dir: Path, fixture_name: str) -> list[str]:
    failures: list[str] = []
    fixture_path = require_existing(fixture_name, repo_root, proof_dir, "admission fixture")
    fixture = load_json(fixture_path)
    source_capture_package_ref = fixture.get("source_capture_package_ref")
    source_capture_package: dict[str, Any] | None = None
    if not isinstance(source_capture_package_ref, str) or not source_capture_package_ref.strip():
        failures.append("admission-fixture source_capture_package_ref must be a non-empty string")
    else:
        try:
            source_capture_package_path = require_existing(
                source_capture_package_ref,
                repo_root,
                fixture_path.parent,
                "source capture package referenced by admission fixture",
            )
            source_capture_package = load_json(source_capture_package_path)
        except Exception as exc:  # noqa: BLE001
            failures.append(f"admission-fixture source_capture_package_ref could not be loaded: {exc}")
    if fixture.get("target_layer") != "kb":
        failures.append("admission-fixture target_layer must be kb")
    placement = fixture.get("placement")
    if not isinstance(placement, dict):
        failures.append("admission-fixture placement must be an object")
    else:
        if placement.get("target_layer") != "kb":
            failures.append("admission-fixture placement.target_layer must be kb")
        if placement.get("artifact_type") != "source-capture-package":
            failures.append("admission-fixture placement.artifact_type must be source-capture-package")
        artifact_id = placement.get("artifact_id")
        if not isinstance(artifact_id, str) or not artifact_id.strip():
            failures.append("admission-fixture placement.artifact_id must be a non-empty string")
        elif source_capture_package is not None:
            source_id = source_capture_package.get("source_id")
            if not isinstance(source_id, str) or not source_id.strip():
                failures.append("source_capture_package.source_id must be a non-empty string")
            elif artifact_id != source_id:
                failures.append(
                    "admission-fixture placement.artifact_id must exactly match "
                    f"source_capture_package.source_id: {artifact_id} != {source_id}"
                )
    return failures


def check_source_evidence(repo_root: Path, proof_dir: Path) -> list[str]:
    failures: list[str] = []
    for filename, schema_ref in SOURCE_EVIDENCE_JSON.items():
        path = proof_dir / filename
        if not path.is_file():
            failures.append(f"missing {filename}")
            continue
        try:
            payload = load_json(path)
            failures.extend(validate_instance(payload, repo_root / schema_ref, filename))
        except Exception as exc:  # noqa: BLE001
            failures.append(f"{filename}: {exc}")

    if failures:
        return failures

    source = load_json(proof_dir / "source-capture-package.json")
    result = load_json(proof_dir / "result-packet.json")
    review = load_json(proof_dir / "review-decision.json")
    admission = load_json(proof_dir / "admission-decision.json")
    placement = load_json(proof_dir / "placement-decision.json")
    task = load_json(proof_dir / "task-packet.json")

    if task.get("task_type") != "source-capture":
        failures.append("task-packet task_type should be source-capture for source admission")
    stable = source.get("stable_representation")
    if isinstance(stable, str) and resolve_existing(stable, repo_root, proof_dir) is None:
        failures.append(f"source stable_representation not found: {stable}")
    if not any(isinstance(e, dict) and e.get("type") == "source-package" for e in result.get("evidence", [])):
        failures.append("result-packet evidence must include type=source-package")
    if review.get("decision") != "approve" or review.get("approved_destination") != "kb":
        failures.append("review-decision must approve kb")
    if admission.get("decision") != "approved" or admission.get("blockers"):
        failures.append("admission-decision must be approved with empty blockers")
    if placement.get("target_layer") != "kb":
        failures.append("placement-decision target_layer must be kb")
    return failures


def check_phase3_inputs(repo_root: Path, proof_dir: Path, execution_target_ref: str, manifest_ref: str, integration_ref: str, kb_root_ref: str | None) -> list[str]:
    failures: list[str] = []
    target_path = require_existing(execution_target_ref, repo_root, proof_dir, "execution target")
    manifest_path = require_existing(manifest_ref, repo_root, proof_dir, "admission manifest")
    integration_path = require_existing(integration_ref, repo_root, proof_dir, "kb integration")

    target_path_ref = repo_ref(repo_root, target_path)
    manifest_path_ref = repo_ref(repo_root, manifest_path)
    integration_path_ref = repo_ref(repo_root, integration_path)
    for label, ref in (("execution target", target_path_ref), ("admission manifest", manifest_path_ref), ("kb integration", integration_path_ref)):
        if ref.startswith("/"):
            failures.append(f"{label} must be repo-contained for Phase3: {ref}")

    target = load_json(target_path)
    manifest = load_json(manifest_path)
    integration = load_yaml(integration_path)

    failures.extend(validate_instance(target, repo_root / "operations/harness-phase3/contracts/execution_target.schema.json", "execution_target.json"))
    failures.extend(validate_instance(manifest, repo_root / "operations/harness-phase3/contracts/kb_admission_manifest.schema.json", "admission_manifest.json"))
    failures.extend(validate_instance(integration, repo_root / "control-plane/contracts/schemas/kb_runtime_integration.schema.json", "kb_integration.yaml"))

    if target.get("target_runtime") != "workspace" or target.get("target_kind") != "kb_admission":
        failures.append("execution_target must be target_runtime=workspace and target_kind=kb_admission")
    if target.get("kb_integration_ref") != integration_path_ref:
        failures.append("execution_target kb_integration_ref must match the checked integration path")
    if target.get("admission_manifest_ref") != manifest_path_ref:
        failures.append("execution_target admission_manifest_ref must match the checked manifest path")

    if manifest.get("admission_type") != "source_capture":
        failures.append("admission_manifest admission_type must be source_capture")
    copy_operation = manifest.get("copy_operation")
    if not isinstance(copy_operation, dict):
        failures.append("admission_manifest copy_operation must be object")
    else:
        expected = {
            "operation_type": "copy",
            "content_mode": "byte_for_byte",
            "overwrite_policy": "fail_closed_on_hash_mismatch",
        }
        for key, value in expected.items():
            if copy_operation.get(key) != value:
                failures.append(f"admission_manifest copy_operation.{key} must be {value}")

    root_env = integration.get("root_path_env")
    kb_root_text = kb_root_ref or (os.environ.get(root_env) if isinstance(root_env, str) else None) or "/home/node/.openclaw/workspace/kb"
    kb_root = Path(kb_root_text).resolve(strict=False)
    if not kb_root.is_dir():
        failures.append(f"workspace KB root does not exist: {kb_root}")
        return failures

    artifacts = manifest.get("artifacts")
    if isinstance(artifacts, list):
        for index, item in enumerate(artifacts):
            if not isinstance(item, dict):
                failures.append(f"manifest artifact {index} must be object")
                continue
            src = item.get("input_workspace_path")
            dst = item.get("destination_kb_path")
            expected_sha = item.get("expected_sha256")
            if not isinstance(src, str) or not is_safe_relative_posix(src):
                failures.append(f"manifest artifact {index} input_workspace_path must be safe KB-root-relative path")
                continue
            if not isinstance(dst, str) or not is_safe_relative_posix(dst):
                failures.append(f"manifest artifact {index} destination_kb_path must be safe KB-root-relative path")
            src_path = kb_root / src
            if not src_path.is_file():
                failures.append(f"manifest artifact {index} source file missing under KB root: {src}")
                continue
            actual_sha = sha256_file(src_path)
            if actual_sha != expected_sha:
                failures.append(f"manifest artifact {index} sha mismatch: expected {expected_sha}, actual {actual_sha}")
    return failures


def repo_ref(repo_root: Path, path: Path) -> str:
    resolved = path.resolve(strict=False)
    try:
        return resolved.relative_to(repo_root.resolve(strict=False)).as_posix()
    except ValueError:
        return resolved.as_posix()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--proof-dir", required=True, type=Path)
    parser.add_argument("--fixture", default="admission-fixture.json")
    parser.add_argument("--execution-target", required=True)
    parser.add_argument("--admission-manifest", required=True)
    parser.add_argument("--kb-integration", default="control-plane/runtime/integrations/kb.template.yaml")
    parser.add_argument("--kb-root", default=None)
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    proof_dir = args.proof_dir.resolve()
    if not (repo_root / "operations/harness-phase2/bin/check_admission_policy.py").is_file():
        print(f"FAIL repo root does not look like crab-control-plane: {repo_root}", file=sys.stderr)
        return 2
    if not proof_dir.is_dir():
        print(f"FAIL proof dir missing: {proof_dir}", file=sys.stderr)
        return 2

    failures: list[str] = []
    try:
        failures.extend(check_source_evidence(repo_root, proof_dir))
        failures.extend(check_phase2_fixture(repo_root, proof_dir, args.fixture))
        failures.extend(check_phase3_inputs(repo_root, proof_dir, args.execution_target, args.admission_manifest, args.kb_integration, args.kb_root))
    except Exception as exc:  # noqa: BLE001
        failures.append(str(exc))

    if failures:
        print("FAIL source admission input readiness")
        for failure in failures:
            print(f"- {failure}")
        print("NOTE: this helper does not perform admission; Phase3 workspace/kb_admission is still required.")
        return 1

    print("PASS source admission input readiness")
    print(f"proof_dir={proof_dir}")
    print(f"execution_target={args.execution_target}")
    print(f"admission_manifest={args.admission_manifest}")
    print("NOTE: this helper did not admit anything; canonical admission requires Phase3 workspace/kb_admission evidence.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
