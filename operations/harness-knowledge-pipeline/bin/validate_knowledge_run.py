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
    schema = load_json(schema_path)
    Draft202012Validator.check_schema(schema)
    errors = sorted(Draft202012Validator(schema).iter_errors(instance), key=lambda err: list(err.path))
    return [err.message for err in errors]


def validate_schema_file(schema_path: Path, instance_path: Path) -> list[str]:
    return validate_schema(schema_path, load_json(instance_path))


def parse_frontmatter(path: Path) -> dict[str, Any]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValueError("missing opening frontmatter delimiter")
    end = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end = idx
            break
    if end is None:
        raise ValueError("missing closing frontmatter delimiter")
    data: dict[str, Any] = {}
    for raw in lines[1:end]:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            raise ValueError(f"invalid frontmatter line: {raw}")
        key, value = line.split(":", 1)
        value = value.strip()
        if value == "false":
            parsed: Any = False
        elif value == "true":
            parsed = True
        else:
            parsed = value.strip('"\'')
        data[key.strip()] = parsed
    return data


def safe_rel_ref(ref: str) -> bool:
    p = Path(ref)
    return bool(ref) and not p.is_absolute() and ".." not in p.parts and not ref.startswith("~")


def collect_refs(obj: Any) -> list[str]:
    refs: list[str] = []
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key.endswith("ref") or key.endswith("refs") or key in {"evidence", "produced_artifacts", "derived_from", "source_canonical_candidate_ref"}:
                refs.extend(collect_refs(value))
            else:
                refs.extend(collect_refs(value))
    elif isinstance(obj, list):
        for item in obj:
            refs.extend(collect_refs(item))
    elif isinstance(obj, str):
        if obj.endswith(('.json', '.md', '.sha256')) or obj.startswith(("input/", "output/", "checks/", "operations/", "knowledge/")):
            refs.append(obj)
    return refs


def emit(checks_dir: Path, name: str, run_id: str, status: str, detail: str, **extra: object) -> None:
    write_json(checks_dir / f"{name}.json", check_payload(run_id, status, detail, **extra))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--run-id", required=True)
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve(strict=True)
    run_id = args.run_id
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

    # Re-validate upstream canon schemas for captured inputs.
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
        emit(checks_dir, "semantic_outputs_presence", run_id, "awaiting_semantic_outputs", "semantic output files are not all present", missing=missing_semantic)
        emit(checks_dir, "layer_boundary_validation", run_id, "pending", "semantic outputs are required before layer validation")
        emit(checks_dir, "ref_integrity", run_id, "pending", "semantic outputs are required before ref validation")
        emit(checks_dir, "no_auto_canonical_write", run_id, "pass", "no semantic outputs available; no canonical write performed")
        return 3 if status == "pass" else 1
    emit(checks_dir, "semantic_outputs_presence", run_id, "pass", "all semantic output files exist", files=SEMANTIC_FILES)

    harness_contracts = repo_root / HARNESS_REF / "contracts"
    semantic_schema_checks = [
        ("normalized_note_schema", harness_contracts / "normalized_note.candidate.schema.json", run_dir / "output/normalized_note.json"),
        ("result_packet_schema", harness_contracts / "knowledge_result_packet.candidate.schema.json", run_dir / "output/result_packet.json"),
        ("placement_decision_schema", repo_root / "control-plane/contracts/schemas/placement_decision.schema.json", run_dir / "output/placement_decision.candidate.json"),
        ("admission_decision_schema", repo_root / "control-plane/contracts/schemas/admission_decision.schema.json", run_dir / "output/admission_decision.candidate.json"),
    ]
    for name, schema_path, instance_path in semantic_schema_checks:
        errors = validate_schema_file(schema_path, instance_path)
        emit(checks_dir, name, run_id, "fail" if errors else "pass", "schema validation complete", schema=repo_ref(repo_root, schema_path), instance=repo_ref(repo_root, instance_path), errors=errors)
        if errors:
            status = "fail"

    try:
        canonical_fm = parse_frontmatter(run_dir / "output/canonical_knowledge_candidate.md")
        errors = validate_schema(harness_contracts / "canonical_knowledge_candidate.frontmatter.schema.json", canonical_fm)
    except Exception as exc:  # noqa: BLE001
        canonical_fm = {}
        errors = [str(exc)]
    emit(checks_dir, "canonical_candidate_frontmatter", run_id, "fail" if errors else "pass", "canonical candidate frontmatter validation complete", errors=errors, frontmatter=canonical_fm)
    if errors:
        status = "fail"

    try:
        wiki_fm = parse_frontmatter(run_dir / "output/wiki_derived_draft.md")
        errors = validate_schema(harness_contracts / "wiki_derived_draft.frontmatter.schema.json", wiki_fm)
    except Exception as exc:  # noqa: BLE001
        wiki_fm = {}
        errors = [str(exc)]
    emit(checks_dir, "wiki_draft_frontmatter", run_id, "fail" if errors else "pass", "wiki draft frontmatter validation complete", errors=errors, frontmatter=wiki_fm)
    if errors:
        status = "fail"

    normalized = load_json(run_dir / "output/normalized_note.json")
    result_packet = load_json(run_dir / "output/result_packet.json")
    placement = load_json(run_dir / "output/placement_decision.candidate.json")
    admission = load_json(run_dir / "output/admission_decision.candidate.json")
    ref_errors: list[str] = []
    if normalized.get("source_capture_ref") != "input/source_capture_package.json":
        ref_errors.append("normalized_note.source_capture_ref must be input/source_capture_package.json")
    if result_packet.get("source_capture_ref") != "input/source_capture_package.json":
        ref_errors.append("result_packet.source_capture_ref must be input/source_capture_package.json")
    if result_packet.get("normalized_note_ref") != "output/normalized_note.json":
        ref_errors.append("result_packet.normalized_note_ref must be output/normalized_note.json")
    if canonical_fm.get("source_capture_ref") != "input/source_capture_package.json":
        ref_errors.append("canonical candidate must reference source capture package")
    if canonical_fm.get("normalized_note_ref") != "output/normalized_note.json":
        ref_errors.append("canonical candidate must reference normalized note")
    if canonical_fm.get("result_packet_ref") != "output/result_packet.json":
        ref_errors.append("canonical candidate must reference result packet")
    if canonical_fm.get("admission_decision_ref") != "output/admission_decision.candidate.json":
        ref_errors.append("canonical candidate must reference admission candidate")
    if wiki_fm.get("derived_from") != "output/canonical_knowledge_candidate.md" or wiki_fm.get("source_canonical_candidate_ref") != "output/canonical_knowledge_candidate.md":
        ref_errors.append("wiki draft must derive from output/canonical_knowledge_candidate.md")
    all_refs = collect_refs(normalized) + collect_refs(result_packet) + collect_refs(placement) + collect_refs(admission) + collect_refs(canonical_fm) + collect_refs(wiki_fm)
    unsafe_refs = sorted({ref for ref in all_refs if not safe_rel_ref(ref)})
    if unsafe_refs:
        ref_errors.append(f"unsafe refs: {unsafe_refs}")
    emit(checks_dir, "ref_integrity", run_id, "fail" if ref_errors else "pass", "artifact refs checked", errors=ref_errors, refs=sorted(set(all_refs)))
    if ref_errors:
        status = "fail"

    wiki_text = (run_dir / "output/wiki_derived_draft.md").read_text(encoding="utf-8")
    layer_errors: list[str] = []
    if "input/source.md" in wiki_text or "input/source_capture_package.json" in wiki_text:
        layer_errors.append("wiki draft must not reference raw source or source capture directly")
    if wiki_fm.get("new_claims_allowed") is not False:
        layer_errors.append("wiki draft must set new_claims_allowed: false")
    if canonical_fm.get("canonical_admitted") is not False:
        layer_errors.append("canonical candidate must set canonical_admitted: false")
    emit(checks_dir, "layer_boundary_validation", run_id, "fail" if layer_errors else "pass", "layer boundaries checked", errors=layer_errors)
    if layer_errors:
        status = "fail"

    outside_ref_errors = [ref for ref in all_refs if not safe_rel_ref(ref)]
    emit(checks_dir, "no_outside_git_paths", run_id, "fail" if outside_ref_errors else "pass", "all artifact refs are relative repo-local refs", errors=outside_ref_errors)
    if outside_ref_errors:
        status = "fail"

    auto_canonical_errors: list[str] = []
    if admission.get("decision") == "approved":
        auto_canonical_errors.append("first run admission candidate must not be approved automatically")
    if canonical_fm.get("canonical_admitted") is not False:
        auto_canonical_errors.append("canonical candidate must remain unadmitted")
    if any(str(ref).startswith(("knowledge/kb/", "knowledge/canonical/")) for ref in result_packet.get("produced_artifacts", [])):
        auto_canonical_errors.append("produced artifacts must not be canonical KB writes")
    emit(checks_dir, "no_auto_canonical_write", run_id, "fail" if auto_canonical_errors else "pass", "no automatic canonical admission/write checked", errors=auto_canonical_errors)
    if auto_canonical_errors:
        status = "fail"

    write_json(checks_dir / "validation_summary.json", check_payload(run_id, status, "knowledge run validation complete"))
    return 0 if status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
