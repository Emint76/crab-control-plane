#!/usr/bin/env python3
"""Helpers for Phase 3 workspace KB admission target handling."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any

import yaml
from jsonschema import Draft202012Validator


class KBAdmissionError(Exception):
    pass


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise KBAdmissionError("top-level JSON value must be an object")
    return payload


def read_yaml_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        payload = yaml.safe_load(handle)
    if not isinstance(payload, dict):
        raise KBAdmissionError("top-level YAML value must be an object")
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


def redacted_path(path: Path) -> str:
    digest = hashlib.sha256(path.as_posix().encode("utf-8")).hexdigest()
    return f"redacted:sha256:{digest}"


def repo_ref(repo_root: Path, path: Path) -> str:
    resolved = path.resolve(strict=False)
    try:
        return resolved.relative_to(repo_root.resolve(strict=False)).as_posix()
    except ValueError:
        return resolved.as_posix()


def format_schema_error(error: Any) -> str:
    path = ".".join(str(item) for item in error.path)
    suffix = f".{path}" if path else ""
    if error.validator == "required":
        missing = error.message.split("'")
        if len(missing) >= 2:
            return f"schema.required.{missing[1]}"
        return "schema.required"
    return f"schema.{error.validator}{suffix}"


def validate_json_schema(instance: dict[str, Any], schema_path: Path) -> list[str]:
    schema = read_json_object(schema_path)
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(instance), key=lambda error: (list(error.path), error.validator, error.message))
    return [format_schema_error(error) for error in errors]


def is_windows_path(value: str) -> bool:
    return bool(re.match(r"^[A-Za-z]:[\\/]", value))


def normalize_kb_relative_path(value: Any, *, field_name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise KBAdmissionError(f"{field_name} must be a non-empty string")
    if "\\" in value:
        raise KBAdmissionError(f"{field_name} must use forward-slash paths")
    if value.startswith("/") or is_windows_path(value):
        raise KBAdmissionError(f"{field_name} must be relative to the configured KB root")
    path = PurePosixPath(value)
    if any(part in {"", ".", ".."} for part in path.parts):
        raise KBAdmissionError(f"{field_name} must not contain traversal or empty path segments")
    return path.as_posix()


def reject_existing_symlink_chain(root: Path, raw_path: Path, *, field_name: str, include_leaf: bool) -> None:
    root = root.resolve(strict=False)
    try:
        relative = raw_path.relative_to(root)
    except ValueError as exc:
        raise KBAdmissionError(f"{field_name} must resolve inside the configured KB root") from exc
    current = root
    parts = list(relative.parts)
    for part in (parts if include_leaf else parts[:-1]):
        current = current / part
        if current.exists() or current.is_symlink():
            if current.is_symlink():
                raise KBAdmissionError(f"{field_name} must not traverse symlinks")


def resolve_workspace_path(kb_root: Path, value: Any, *, field_name: str, must_exist_file: bool, include_leaf_symlink: bool) -> Path:
    normalized = normalize_kb_relative_path(value, field_name=field_name)
    raw_path = kb_root / normalized
    reject_existing_symlink_chain(kb_root, raw_path, field_name=field_name, include_leaf=include_leaf_symlink)
    resolved = raw_path.resolve(strict=False)
    try:
        resolved.relative_to(kb_root.resolve(strict=False))
    except ValueError as exc:
        raise KBAdmissionError(f"{field_name} must resolve inside the configured KB root") from exc
    if raw_path.is_symlink() or resolved.is_symlink():
        raise KBAdmissionError(f"{field_name} must not be a symlink")
    if must_exist_file and not resolved.is_file():
        raise KBAdmissionError(f"{field_name} must reference an existing file under the configured KB root")
    return resolved


def validate_kb_root(repo_root: Path, root_text: Any, *, field_name: str) -> Path:
    if not isinstance(root_text, str) or not root_text.strip():
        raise KBAdmissionError(f"{field_name} must be a non-empty environment value")
    if "\\" in root_text or is_windows_path(root_text):
        raise KBAdmissionError(f"{field_name} must be an absolute local POSIX path")
    raw_root = Path(root_text)
    if not raw_root.is_absolute():
        raise KBAdmissionError(f"{field_name} must be an absolute local path")
    if raw_root.is_symlink():
        raise KBAdmissionError(f"{field_name} must not be a symlink")
    resolved_root = raw_root.resolve(strict=True)
    if not resolved_root.is_dir():
        raise KBAdmissionError(f"{field_name} must exist before admission starts")
    repo_resolved = repo_root.resolve(strict=False)
    if resolved_root == repo_resolved:
        raise KBAdmissionError(f"{field_name} must not be the crab-control-plane repository")
    try:
        resolved_root.relative_to(repo_resolved)
    except ValueError:
        return resolved_root
    raise KBAdmissionError(f"{field_name} must not be inside the crab-control-plane repository")


def fallback_context(run_dir: Path) -> dict[str, Any]:
    context: dict[str, Any] = {}
    integration_path = run_dir / "input" / "kb_integration.yaml"
    manifest_path = run_dir / "input" / "admission_manifest.json"
    if integration_path.is_file():
        context["kb_integration_hash"] = sha256_file(integration_path)
        try:
            integration = read_yaml_object(integration_path)
            if isinstance(integration.get("root_path_env"), str):
                context["kb_root_env"] = integration["root_path_env"]
        except (OSError, yaml.YAMLError, KBAdmissionError):
            pass
    if manifest_path.is_file():
        context["manifest_hash"] = sha256_file(manifest_path)
    return context


def load_and_validate_integration(repo_root: Path, integration_path: Path) -> tuple[dict[str, Any], list[str]]:
    integration = read_yaml_object(integration_path)
    schema_path = repo_root / "control-plane" / "contracts" / "schemas" / "kb_runtime_integration.schema.json"
    return integration, validate_json_schema(integration, schema_path)


def load_and_validate_manifest(repo_root: Path, manifest_path: Path) -> tuple[dict[str, Any], list[str]]:
    manifest = read_json_object(manifest_path)
    schema_path = repo_root / "operations" / "harness-phase3" / "contracts" / "kb_admission_manifest.schema.json"
    return manifest, validate_json_schema(manifest, schema_path)


def resolve_runtime_context(repo_root: Path, run_dir: Path) -> dict[str, Any]:
    integration_path = run_dir / "input" / "kb_integration.yaml"
    manifest_path = run_dir / "input" / "admission_manifest.json"
    integration, integration_violations = load_and_validate_integration(repo_root, integration_path)
    context: dict[str, Any] = {
        "integration": integration,
        "kb_integration_hash": sha256_file(integration_path),
        "manifest_hash": sha256_file(manifest_path),
    }
    if integration_violations:
        raise KBAdmissionError("kb integration schema invalid: " + ",".join(integration_violations))
    root_path_env = integration.get("root_path_env")
    if not isinstance(root_path_env, str) or not root_path_env:
        raise KBAdmissionError("kb integration root_path_env must be a non-empty string")
    context["kb_root_env"] = root_path_env
    kb_root = validate_kb_root(repo_root, os.environ.get(root_path_env), field_name=root_path_env)
    context["kb_root"] = kb_root
    context["kb_root_resolved"] = redacted_path(kb_root)
    return context


def base_evidence(run_dir: Path, context: dict[str, Any] | None, *, status: str, failure_stage: str | None, evidence: list[dict[str, Any]]) -> dict[str, Any]:
    context = context or fallback_context(run_dir)
    return {
        "run_id": run_dir.name,
        "generated_at": now_utc(),
        "target_runtime": "workspace",
        "target_kind": "kb_admission",
        "status": status,
        "failure_stage": failure_stage,
        "kb_root_env": context.get("kb_root_env"),
        "kb_root_resolved": context.get("kb_root_resolved"),
        "kb_integration_hash": context.get("kb_integration_hash"),
        "manifest_hash": context.get("manifest_hash"),
        "layout_enforcement": "descriptive_metadata_only",
        "evidence": evidence,
    }


def write_failure_evidence(run_dir: Path, *, failure_stage: str, error: str, context: dict[str, Any] | None = None) -> None:
    context = context or fallback_context(run_dir)
    item = {
        "manifest_hash": context.get("manifest_hash"),
        "kb_integration_hash": context.get("kb_integration_hash"),
        "source_artifact_hash": None,
        "destination_kb_path": None,
        "final_destination_hash": None,
        "planned_action": "failed_closed",
        "action": "failed_closed",
        "execution_status": "not_executed",
        "overwrite_verdict": "not_attempted",
        "error": error,
    }
    write_json(
        run_dir / "checks" / "kb_admission_evidence.json",
        base_evidence(run_dir, context, status="fail", failure_stage=failure_stage, evidence=[item]),
    )


def public_plan_item(item: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in item.items() if key not in {"source_path", "destination_fs_path"}}


def base_plan_item(index: int, artifact: Any, context: dict[str, Any], admission_type: Any) -> dict[str, Any]:
    return {
        "artifact_index": index,
        "target_runtime": "workspace",
        "target_kind": "kb_admission",
        "kb_root_env": context.get("kb_root_env"),
        "kb_root_resolved": context.get("kb_root_resolved"),
        "kb_integration_hash": context.get("kb_integration_hash"),
        "manifest_hash": context.get("manifest_hash"),
        "admission_type": admission_type,
        "input_workspace_path": artifact.get("input_workspace_path") if isinstance(artifact, dict) else None,
        "destination_kb_path": artifact.get("destination_kb_path") if isinstance(artifact, dict) else None,
        "expected_hash": artifact.get("expected_sha256") if isinstance(artifact, dict) else None,
        "source_artifact_hash": None,
        "final_destination_hash": None,
        "planned_action": "failed_closed",
        "action": "failed_closed",
        "execution_status": "not_executed",
        "overwrite_verdict": "not_attempted",
    }


def build_copy_plan(kb_root: Path, manifest: dict[str, Any], context: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    plan: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []
    artifacts = manifest.get("artifacts")
    admission_type = manifest.get("admission_type")
    if not isinstance(artifacts, list):
        item = base_plan_item(0, None, context, admission_type)
        item["error"] = "manifest artifacts must be an array"
        return [item], [item]

    planned_destinations: set[str] = set()
    for index, artifact in enumerate(artifacts):
        item = base_plan_item(index, artifact, context, admission_type)
        try:
            if not isinstance(artifact, dict):
                raise KBAdmissionError("artifact entry must be an object")
            source_rel = normalize_kb_relative_path(artifact.get("input_workspace_path"), field_name="input_workspace_path")
            destination_rel = normalize_kb_relative_path(artifact.get("destination_kb_path"), field_name="destination_kb_path")
            source_path = resolve_workspace_path(kb_root, source_rel, field_name="input_workspace_path", must_exist_file=True, include_leaf_symlink=True)
            destination_path = resolve_workspace_path(kb_root, destination_rel, field_name="destination_kb_path", must_exist_file=False, include_leaf_symlink=False)
            if source_path == destination_path:
                item["overwrite_verdict"] = "same_source_and_destination"
                raise KBAdmissionError("source and destination must resolve to distinct files")
            if destination_rel in planned_destinations:
                item["overwrite_verdict"] = "duplicate_destination_in_manifest"
                raise KBAdmissionError("destination_kb_path appears more than once in the manifest")
            planned_destinations.add(destination_rel)
            source_hash = sha256_file(source_path)
            item.update({"input_workspace_path": source_rel, "destination_kb_path": destination_rel, "source_artifact_hash": source_hash, "source_path": str(source_path), "destination_fs_path": str(destination_path)})
            if source_hash != artifact.get("expected_sha256"):
                item["overwrite_verdict"] = "source_hash_mismatch"
                raise KBAdmissionError("source artifact hash does not match expected_sha256")
            if destination_path.exists():
                if destination_path.is_symlink():
                    item["overwrite_verdict"] = "destination_symlink"
                    raise KBAdmissionError("destination_kb_path must not be a symlink")
                if not destination_path.is_file():
                    item["overwrite_verdict"] = "destination_not_regular_file"
                    raise KBAdmissionError("destination exists but is not a regular file")
                destination_hash = sha256_file(destination_path)
                item["final_destination_hash"] = destination_hash
                if destination_hash == source_hash:
                    item["planned_action"] = "would_idempotent"
                    item["overwrite_verdict"] = "same_hash_existing"
                else:
                    item["overwrite_verdict"] = "different_hash_existing"
                    raise KBAdmissionError("destination exists with a different hash")
            else:
                item["planned_action"] = "would_copy"
                item["overwrite_verdict"] = "destination_missing"
        except KBAdmissionError as exc:
            if item.get("planned_action") not in {"would_copy", "would_idempotent"}:
                item["planned_action"] = "failed_closed"
            item["action"] = "failed_closed"
            item["execution_status"] = "not_executed"
            item["error"] = str(exc)
            failures.append(item)
        plan.append(item)
    return plan, failures


def preflight_failed_items(plan: list[dict[str, Any]]) -> list[dict[str, Any]]:
    evidence_items: list[dict[str, Any]] = []
    for item in plan:
        evidence = public_plan_item(item)
        evidence["action"] = "failed_closed"
        evidence["execution_status"] = "not_executed"
        evidence.setdefault("error", "manifest preflight failed; no artifact operations were executed")
        evidence_items.append(evidence)
    return evidence_items


def validate_pre_apply(repo_root: Path, run_dir: Path) -> tuple[dict[str, Any] | None, list[str], list[dict[str, Any]]]:
    context: dict[str, Any] | None = None
    manifest_path = run_dir / "input" / "admission_manifest.json"
    try:
        context = resolve_runtime_context(repo_root, run_dir)
    except (OSError, ValueError, yaml.YAMLError, json.JSONDecodeError, KBAdmissionError) as exc:
        write_failure_evidence(run_dir, failure_stage="kb_integration_or_root_validation", error=str(exc), context=context)
        return context, ["kb_integration_or_root_validation"], []

    try:
        manifest, schema_violations = load_and_validate_manifest(repo_root, manifest_path)
    except (OSError, ValueError, json.JSONDecodeError, KBAdmissionError) as exc:
        write_failure_evidence(run_dir, failure_stage="manifest_read", error=str(exc), context=context)
        return context, ["manifest_read"], []

    if schema_violations:
        write_failure_evidence(run_dir, failure_stage="manifest_schema", error=",".join(schema_violations), context=context)
        return context, schema_violations, []

    plan, failures = build_copy_plan(context["kb_root"], manifest, context)
    artifacts_report = [public_plan_item(item) for item in plan]
    if failures:
        write_json(run_dir / "checks" / "kb_admission_evidence.json", base_evidence(run_dir, context, status="fail", failure_stage="copy_plan_preflight", evidence=preflight_failed_items(plan)))
        return context, ["copy_plan_preflight"], artifacts_report
    return context, [], artifacts_report


def write_apply_log(apply_log_path: Path, log_lines: list[str], evidence_items: list[dict[str, Any]], status: str, context: dict[str, Any] | None) -> None:
    action_summary = ",".join(str(item.get("action")) for item in evidence_items) if evidence_items else "none"
    if context is not None:
        log_lines.extend([f"kb_root_env={context.get('kb_root_env')}", f"kb_integration_hash={context.get('kb_integration_hash')}", f"manifest_hash={context.get('manifest_hash')}"])
    log_lines.extend([f"actions={action_summary}", f"result={'success' if status == 'pass' else 'fail'}"])
    apply_log_path.write_text("\n".join(log_lines) + "\n", encoding="utf-8")


def execute_kb_admission(repo_root: Path, run_dir: Path) -> int:
    evidence_path = run_dir / "checks" / "kb_admission_evidence.json"
    apply_log_path = run_dir / "logs" / "apply.log"
    apply_log_path.parent.mkdir(parents=True, exist_ok=True)
    evidence_path.parent.mkdir(parents=True, exist_ok=True)
    log_lines = [f"timestamp={now_utc()}", f"run_id={run_dir.name}", "target_kind=kb_admission"]

    try:
        context = resolve_runtime_context(repo_root, run_dir)
        manifest, schema_violations = load_and_validate_manifest(repo_root, run_dir / "input" / "admission_manifest.json")
        if schema_violations:
            raise KBAdmissionError("kb admission manifest schema invalid: " + ",".join(schema_violations))
    except (OSError, ValueError, yaml.YAMLError, json.JSONDecodeError, KBAdmissionError) as exc:
        write_failure_evidence(run_dir, failure_stage="input_validation", error=str(exc), context=locals().get("context"))
        payload = read_json_object(evidence_path)
        write_apply_log(apply_log_path, log_lines, payload.get("evidence", []), "fail", locals().get("context"))
        return 1

    plan, failures = build_copy_plan(context["kb_root"], manifest, context)
    if failures:
        evidence_items = preflight_failed_items(plan)
        write_json(evidence_path, base_evidence(run_dir, context, status="fail", failure_stage="copy_plan_preflight", evidence=evidence_items))
        write_apply_log(apply_log_path, log_lines, evidence_items, "fail", context)
        return 1

    evidence_items: list[dict[str, Any]] = []
    overall_status = "pass"
    for plan_item in plan:
        item = public_plan_item(plan_item)
        try:
            source_path = Path(str(plan_item["source_path"]))
            destination_path = Path(str(plan_item["destination_fs_path"]))
            if plan_item["planned_action"] == "would_idempotent":
                item["action"] = "idempotent"
                item["execution_status"] = "executed"
            elif plan_item["planned_action"] == "would_copy":
                destination_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source_path, destination_path)
                final_hash = sha256_file(destination_path)
                item["final_destination_hash"] = final_hash
                if final_hash != plan_item["source_artifact_hash"]:
                    item["overwrite_verdict"] = "final_hash_mismatch"
                    raise KBAdmissionError("destination hash after copy does not match source hash")
                item["action"] = "copied"
                item["execution_status"] = "executed"
            else:
                raise KBAdmissionError("invalid planned action")
        except KBAdmissionError as exc:
            overall_status = "fail"
            item["action"] = "failed_closed"
            item["execution_status"] = "execution_failed"
            item["error"] = str(exc)
        evidence_items.append(item)

    write_json(evidence_path, base_evidence(run_dir, context, status=overall_status, failure_stage=None if overall_status == "pass" else "copy_execution", evidence=evidence_items))
    write_apply_log(apply_log_path, log_lines, evidence_items, overall_status, context)
    return 0 if overall_status == "pass" else 1
