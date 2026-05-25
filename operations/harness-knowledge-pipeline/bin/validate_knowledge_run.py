#!/usr/bin/env python3
"""Validate a bounded knowledge-pipeline run directory."""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

RUNS_REF = Path("operations/harness-knowledge-pipeline/runs")
HARNESS_REF = Path("operations/harness-knowledge-pipeline")
SEMANTIC_FILES = [
    "output/normalized_note.md",
    "output/normalized_note.json",
    "output/result_packet.json",
    "output/placement_decision.candidate.json",
    "output/admission_decision.candidate.json",
    "output/canonical_knowledge_candidate.md",
    "output/wiki_derived_draft.md",
]
SEMANTIC_JSON_SCHEMA_MAP = [
    (
        "normalized_note_schema",
        "output/normalized_note.json",
        "operations/harness-knowledge-pipeline/contracts/normalized_note.schema.json",
    ),
    (
        "result_packet_schema",
        "output/result_packet.json",
        "operations/harness-knowledge-pipeline/contracts/result_packet.schema.json",
    ),
    (
        "placement_decision_candidate_schema",
        "output/placement_decision.candidate.json",
        "operations/harness-knowledge-pipeline/contracts/placement_decision_candidate.schema.json",
    ),
    (
        "admission_decision_candidate_schema",
        "output/admission_decision.candidate.json",
        "operations/harness-knowledge-pipeline/contracts/admission_decision_candidate.schema.json",
    ),
]
SEMANTIC_MARKDOWN_FILES = [
    "output/normalized_note.md",
    "output/canonical_knowledge_candidate.md",
    "output/wiki_derived_draft.md",
]


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def repo_ref(repo_root: Path, path: Path) -> str:
    return path.resolve(strict=False).relative_to(repo_root.resolve(strict=False)).as_posix()


def check_payload(run_id: str, status: str, detail: str, **extra: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "run_id": run_id,
        "generated_at": now_utc(),
        "status": status,
        "detail": detail,
    }
    payload.update(extra)
    return payload


def validate_schema(schema_path: Path, instance: Any) -> list[str]:
    try:
        schema = load_json(schema_path)
        Draft202012Validator.check_schema(schema)
        errors = sorted(Draft202012Validator(schema).iter_errors(instance), key=lambda err: list(err.path))
        return [err.message for err in errors]
    except Exception as exc:  # noqa: BLE001
        return [str(exc)]


def validate_schema_file(schema_path: Path, instance_path: Path) -> list[str]:
    try:
        instance = load_json(instance_path)
    except Exception as exc:  # noqa: BLE001
        return [f"could not load JSON instance: {exc}"]
    return validate_schema(schema_path, instance)


def looks_external_ref(ref: str) -> bool:
    return "://" in ref or ref.startswith(("http:", "https:", "file:", "mailto:"))


def safe_rel_ref(ref: str) -> bool:
    p = Path(ref)
    return bool(ref) and not looks_external_ref(ref) and not p.is_absolute() and ".." not in p.parts and not ref.startswith("~")


def collect_refs(obj: Any) -> list[str]:
    refs: list[str] = []
    if isinstance(obj, dict):
        for value in obj.values():
            refs.extend(collect_refs(value))
    elif isinstance(obj, list):
        for item in obj:
            refs.extend(collect_refs(item))
    elif isinstance(obj, str):
        if looks_external_ref(obj) or obj.endswith((".json", ".md", ".sha256")) or obj.startswith(("input/", "output/", "checks/", "operations/", "knowledge/")):
            refs.append(obj)
    return refs


def object_or_empty(payload: Any) -> dict[str, Any]:
    return payload if isinstance(payload, dict) else {}


def emit(checks_dir: Path, name: str, run_id: str, status: str, detail: str, **extra: object) -> None:
    write_json(checks_dir / f"{name}.json", check_payload(run_id, status, detail, **extra))


def semantic_artifact_set_instance() -> dict[str, object]:
    return {
        "artifact_type": "semantic-artifact-set",
        "required_artifacts": SEMANTIC_FILES,
        "json_artifacts": [
            {"path": instance_ref, "schema_ref": schema_ref}
            for _, instance_ref, schema_ref in SEMANTIC_JSON_SCHEMA_MAP
        ],
        "markdown_artifacts": [
            {
                "path": ref,
                "deep_schema_validated": False,
                "note": "Presence and non-empty validation only; markdown is not deeply schema-validated in this runner.",
            }
            for ref in SEMANTIC_MARKDOWN_FILES
        ],
    }


def output_path_boundary_errors(run_dir: Path) -> list[str]:
    output_dir = (run_dir / "output").resolve(strict=False)
    errors: list[str] = []
    for ref in SEMANTIC_FILES:
        path = (run_dir / ref).resolve(strict=False)
        if not ref.startswith("output/"):
            errors.append(f"semantic artifact ref is outside output/: {ref}")
            continue
        try:
            path.relative_to(output_dir)
        except ValueError:
            errors.append(f"semantic artifact resolves outside output/: {ref}")
    return errors


def load_optional_json(path: Path) -> Any:
    try:
        return load_json(path)
    except Exception:
        return {}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--mode", choices=["capture-only", "semantic-required"], default="semantic-required")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve(strict=True)
    run_id = args.run_id
    semantic_outputs_required = args.mode == "semantic-required"
    run_dir = repo_root / RUNS_REF / run_id
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)

    expected_run_ref = f"{RUNS_REF.as_posix()}/{run_id}"
    status = "pass"
    try:
        actual_run_ref = repo_ref(repo_root, run_dir)
        invariant_ok = actual_run_ref == expected_run_ref and run_dir.parent.resolve() == (repo_root / RUNS_REF).resolve()
    except Exception:  # noqa: BLE001
        invariant_ok = False
        actual_run_ref = str(run_dir)
    emit(checks_dir, "run_dir_invariants", run_id, "pass" if invariant_ok else "fail", "run dir identity checked", expected=expected_run_ref, actual=actual_run_ref)
    if not invariant_ok:
        status = "fail"

    core_files = [
        "run_meta.json",
        "input/source.md",
        "input/source.sha256",
        "input/source_capture_package.json",
        "input/task_packet.json",
    ]
    missing_core = [ref for ref in core_files if not (run_dir / ref).is_file()]
    if missing_core:
        emit(checks_dir, "expected_core_files", run_id, "fail", "missing core files", missing=missing_core)
        return 1
    emit(checks_dir, "expected_core_files", run_id, "pass", "core files exist", files=core_files)

    schema_checks = [
        ("source_capture_schema", repo_root / "control-plane/contracts/schemas/source_capture_package.schema.json", run_dir / "input/source_capture_package.json"),
        ("task_packet_schema", repo_root / "control-plane/contracts/schemas/task_packet.schema.json", run_dir / "input/task_packet.json"),
    ]
    for name, schema_path, instance_path in schema_checks:
        errors = validate_schema_file(schema_path, instance_path)
        emit(checks_dir, name, run_id, "fail" if errors else "pass", "schema validation complete", schema=repo_ref(repo_root, schema_path), instance=repo_ref(repo_root, instance_path), errors=errors)
        if errors:
            status = "fail"

    digest_line = (run_dir / "input/source.sha256").read_text(encoding="utf-8").strip()
    emit(checks_dir, "source_hash_validation", run_id, "pass" if digest_line.startswith("sha256:") else "fail", "source hash file has sha256 prefix", sha256=digest_line)
    if not digest_line.startswith("sha256:"):
        status = "fail"

    run_meta = load_json(run_dir / "run_meta.json")
    forbidden_flags_ok = all(run_meta.get(flag) is False for flag in ["openclaw_used", "docker_used", "network_used", "live_surface_used", "outside_git_paths_used", "auto_canonical_write_performed"])
    emit(checks_dir, "no_live_surface_validation", run_id, "pass" if forbidden_flags_ok else "fail", "run_meta forbidden-surface flags checked", flags={k: run_meta.get(k) for k in ["openclaw_used", "docker_used", "network_used", "live_surface_used", "outside_git_paths_used", "auto_canonical_write_performed"]})
    if not forbidden_flags_ok:
        status = "fail"

    missing_semantic = [ref for ref in SEMANTIC_FILES if not (run_dir / ref).is_file()]
    if missing_semantic:
        if not semantic_outputs_required:
            emit(checks_dir, "semantic_outputs_presence", run_id, "skipped", "semantic output files are not required in capture-only smoke mode", missing=missing_semantic)
            emit(checks_dir, "semantic_artifact_set_schema", run_id, "skipped", "semantic artifact set validation is not required in capture-only smoke mode")
            emit(checks_dir, "semantic_markdown_artifacts", run_id, "skipped", "semantic markdown artifacts are not required in capture-only smoke mode")
            emit(checks_dir, "layer_boundary_validation", run_id, "skipped", "semantic outputs are not required in capture-only smoke mode")
            emit(checks_dir, "ref_integrity", run_id, "skipped", "semantic outputs are not required in capture-only smoke mode")
            emit(checks_dir, "no_auto_canonical_write", run_id, "pass", "no semantic outputs available; no canonical write performed")
            write_json(checks_dir / "validation_summary.json", check_payload(run_id, status, "knowledge run validation complete"))
            return 0 if status == "pass" else 1
        emit(checks_dir, "semantic_outputs_presence", run_id, "awaiting_semantic_outputs", "semantic output files are not all present", missing=missing_semantic)
        emit(checks_dir, "semantic_artifact_set_schema", run_id, "pending", "semantic artifacts are required before artifact-set validation")
        emit(checks_dir, "semantic_markdown_artifacts", run_id, "pending", "semantic markdown artifacts are required before markdown presence validation")
        emit(checks_dir, "layer_boundary_validation", run_id, "pending", "semantic outputs are required before layer validation")
        emit(checks_dir, "ref_integrity", run_id, "pending", "semantic outputs are required before ref validation")
        emit(checks_dir, "no_auto_canonical_write", run_id, "pass", "no semantic outputs available; no canonical write performed")
        write_json(checks_dir / "validation_summary.json", check_payload(run_id, "awaiting_semantic_outputs" if status == "pass" else status, "knowledge run validation complete"))
        return 3 if status == "pass" else 1
    emit(checks_dir, "semantic_outputs_presence", run_id, "pass", "all semantic output files exist", files=SEMANTIC_FILES)

    boundary_errors = output_path_boundary_errors(run_dir)
    if boundary_errors:
        status = "fail"
    emit(checks_dir, "semantic_output_path_boundary", run_id, "fail" if boundary_errors else "pass", "semantic artifact paths are under output/", errors=boundary_errors)
    if boundary_errors:
        emit(checks_dir, "semantic_artifact_set_schema", run_id, "skipped", "semantic artifact set validation skipped because semantic artifact paths failed boundary checks")
        emit(checks_dir, "semantic_markdown_artifacts", run_id, "skipped", "semantic markdown validation skipped because semantic artifact paths failed boundary checks")
        emit(checks_dir, "ref_integrity", run_id, "fail", "semantic artifact refs were not read because artifact paths failed boundary checks", errors=boundary_errors)
        emit(checks_dir, "layer_boundary_validation", run_id, "fail", "semantic layer validation skipped because artifact paths failed boundary checks", errors=boundary_errors)
        emit(checks_dir, "no_auto_canonical_write", run_id, "fail", "semantic canonical-write validation skipped because artifact paths failed boundary checks", errors=boundary_errors)
        write_json(checks_dir / "validation_summary.json", check_payload(run_id, status, "knowledge run validation complete"))
        return 1

    harness_contracts = repo_root / HARNESS_REF / "contracts"
    artifact_set_errors = validate_schema(harness_contracts / "semantic_artifact_set.schema.json", semantic_artifact_set_instance())
    if artifact_set_errors:
        status = "fail"
    emit(checks_dir, "semantic_artifact_set_schema", run_id, "fail" if artifact_set_errors else "pass", "semantic artifact set path/schema mapping validation complete", schema=repo_ref(repo_root, harness_contracts / "semantic_artifact_set.schema.json"), errors=artifact_set_errors)

    for name, instance_ref, schema_ref in SEMANTIC_JSON_SCHEMA_MAP:
        schema_path = repo_root / schema_ref
        instance_path = run_dir / instance_ref
        errors = validate_schema_file(schema_path, instance_path)
        emit(checks_dir, name, run_id, "fail" if errors else "pass", "schema validation complete", schema=schema_ref, instance=instance_ref, errors=errors)
        if errors:
            status = "fail"

    markdown_errors = []
    for ref in SEMANTIC_MARKDOWN_FILES:
        text = (run_dir / ref).read_text(encoding="utf-8")
        if not text.strip():
            markdown_errors.append(f"markdown artifact is empty: {ref}")
    if markdown_errors:
        status = "fail"
    emit(checks_dir, "semantic_markdown_artifacts", run_id, "fail" if markdown_errors else "pass", "markdown semantic artifacts exist and are non-empty; deep markdown schema validation is not performed", files=SEMANTIC_MARKDOWN_FILES, errors=markdown_errors)

    normalized = object_or_empty(load_optional_json(run_dir / "output/normalized_note.json"))
    result_packet = object_or_empty(load_optional_json(run_dir / "output/result_packet.json"))
    placement = object_or_empty(load_optional_json(run_dir / "output/placement_decision.candidate.json"))
    admission = object_or_empty(load_optional_json(run_dir / "output/admission_decision.candidate.json"))

    ref_errors: list[str] = []
    provenance = normalized.get("provenance", {}) if isinstance(normalized, dict) else {}
    if provenance.get("source_capture_ref") != "input/source_capture_package.json":
        ref_errors.append("normalized_note.provenance.source_capture_ref must be input/source_capture_package.json")
    if provenance.get("task_packet_ref") != "input/task_packet.json":
        ref_errors.append("normalized_note.provenance.task_packet_ref must be input/task_packet.json")
    if provenance.get("captured_source_ref") != "input/source.md":
        ref_errors.append("normalized_note.provenance.captured_source_ref must be input/source.md")

    produced_artifacts = result_packet.get("produced_artifacts", [])
    produced_paths = sorted({str(item.get("path")) for item in produced_artifacts if isinstance(item, dict) and item.get("path")})
    if produced_paths != sorted(SEMANTIC_FILES):
        ref_errors.append("result_packet.produced_artifacts must list exactly the required semantic output artifacts")
    expected_schema_refs: dict[str, str | None] = {instance_ref: schema_ref for _, instance_ref, schema_ref in SEMANTIC_JSON_SCHEMA_MAP}
    expected_schema_refs.update({ref: None for ref in SEMANTIC_MARKDOWN_FILES})
    for item in produced_artifacts:
        if not isinstance(item, dict):
            continue
        path = item.get("path")
        if path in expected_schema_refs and item.get("schema_ref") != expected_schema_refs[path]:
            ref_errors.append(f"result_packet.produced_artifacts schema_ref mismatch for {path}")

    for name, payload in [("placement", placement), ("admission", admission)]:
        if isinstance(payload, dict):
            artifact_refs = sorted(payload.get("artifact_refs", []))
            if artifact_refs and artifact_refs != sorted(SEMANTIC_FILES):
                ref_errors.append(f"{name}.artifact_refs must list the required semantic output artifacts when present")

    all_refs = collect_refs(normalized) + collect_refs(result_packet) + collect_refs(placement) + collect_refs(admission)
    unsafe_refs = sorted({ref for ref in all_refs if not safe_rel_ref(ref)})
    if unsafe_refs:
        ref_errors.append(f"unsafe refs: {unsafe_refs}")
    emit(checks_dir, "ref_integrity", run_id, "fail" if ref_errors else "pass", "semantic artifact refs checked", errors=ref_errors, refs=sorted(set(all_refs)))
    if ref_errors:
        status = "fail"

    wiki_text = (run_dir / "output/wiki_derived_draft.md").read_text(encoding="utf-8")
    layer_errors: list[str] = []
    if "input/source.md" in wiki_text or "input/source_capture_package.json" in wiki_text:
        layer_errors.append("wiki draft must not reference raw source or source capture directly")
    if placement.get("canonical_write_allowed") is not False:
        layer_errors.append("placement candidate must set canonical_write_allowed: false")
    if admission.get("canonical_admitted") is not False:
        layer_errors.append("admission candidate must set canonical_admitted: false")
    emit(checks_dir, "layer_boundary_validation", run_id, "fail" if layer_errors else "pass", "semantic layer boundaries checked", errors=layer_errors)
    if layer_errors:
        status = "fail"

    outside_ref_errors = [ref for ref in all_refs if not safe_rel_ref(ref)]
    emit(checks_dir, "no_outside_git_paths", run_id, "fail" if outside_ref_errors else "pass", "all artifact refs are relative repo-local refs", errors=outside_ref_errors)
    if outside_ref_errors:
        status = "fail"

    auto_canonical_errors: list[str] = []
    if admission.get("canonical_admitted") is not False:
        auto_canonical_errors.append("admission candidate must keep canonical_admitted false")
    if placement.get("canonical_write_allowed") is not False:
        auto_canonical_errors.append("placement candidate must keep canonical_write_allowed false")
    produced = result_packet.get("produced_artifacts", []) if isinstance(result_packet, dict) else []
    for item in produced:
        path = item.get("path") if isinstance(item, dict) else item
        if str(path).startswith(("knowledge/kb/", "knowledge/canonical/")):
            auto_canonical_errors.append("produced artifacts must not be canonical KB writes")
    emit(checks_dir, "no_auto_canonical_write", run_id, "fail" if auto_canonical_errors else "pass", "no automatic canonical admission/write checked", errors=auto_canonical_errors)
    if auto_canonical_errors:
        status = "fail"

    write_json(checks_dir / "validation_summary.json", check_payload(run_id, status, "knowledge run validation complete"))
    return 0 if status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
