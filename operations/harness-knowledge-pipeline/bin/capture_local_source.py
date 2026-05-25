#!/usr/bin/env python3
"""Capture one repo-local markdown/text source into a knowledge-pipeline run dir."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

from jsonschema import Draft202012Validator

HARNESS_REF = Path("operations/harness-knowledge-pipeline")
RUNS_REF = HARNESS_REF / "runs"
RUN_ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")
ALLOWED_SUFFIXES = {".md", ".markdown", ".txt"}


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def repo_ref(repo_root: Path, path: Path) -> str:
    return path.resolve(strict=False).relative_to(repo_root.resolve(strict=False)).as_posix()


def is_relative_safe(ref: str) -> bool:
    p = Path(ref)
    return not p.is_absolute() and ".." not in p.parts and not ref.startswith("~")


def check_payload(run_id: str, status: str, detail: str, **extra: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "run_id": run_id,
        "generated_at": now_utc(),
        "status": status,
        "detail": detail,
    }
    payload.update(extra)
    return payload


def validate_schema(schema_path: Path, instance_path: Path) -> tuple[str, list[str]]:
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    instance = json.loads(instance_path.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    errors = sorted(Draft202012Validator(schema).iter_errors(instance), key=lambda err: list(err.path))
    return ("pass" if not errors else "fail", [err.message for err in errors])


def fail(run_id: str, run_dir: Path | None, check_name: str, detail: str, code: int = 1) -> int:
    if run_dir is not None:
        write_json(run_dir / "checks" / f"{check_name}.json", check_payload(run_id, "fail", detail))
    print(f"FAIL {detail}", file=sys.stderr)
    return code


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--source", required=True)
    args = parser.parse_args()

    run_id = args.run_id
    if not RUN_ID_RE.fullmatch(run_id) or run_id in {".", ".."}:
        return fail(run_id, None, "run_dir_invariants", "invalid run id", 2)

    repo_root = Path(args.repo_root).resolve(strict=True)
    runs_root = repo_root / RUNS_REF
    run_dir = runs_root / run_id
    input_dir = run_dir / "input"
    output_dir = run_dir / "output"
    checks_dir = run_dir / "checks"
    input_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    checks_dir.mkdir(parents=True, exist_ok=True)

    source_arg = Path(args.source)
    if source_arg.is_absolute() or ".." in source_arg.parts or str(args.source).startswith("~"):
        return fail(run_id, run_dir, "source_path_boundary", "source path must be repo-local relative path", 2)
    if source_arg.suffix.lower() not in ALLOWED_SUFFIXES:
        return fail(run_id, run_dir, "source_path_boundary", "source suffix must be .md, .markdown, or .txt", 2)

    source_path = (repo_root / source_arg).resolve(strict=True)
    try:
        source_path.relative_to(repo_root)
    except ValueError:
        return fail(run_id, run_dir, "source_path_boundary", "source resolves outside repo root", 2)

    canonical_run_dir = f"{RUNS_REF.as_posix()}/{run_id}"
    if repo_ref(repo_root, run_dir) != canonical_run_dir:
        return fail(run_id, run_dir, "run_dir_invariants", "run dir identity mismatch", 2)

    write_json(checks_dir / "run_dir_invariants.json", check_payload(
        run_id, "pass", "run dir is direct child of harness runs root",
        canonical_run_dir=canonical_run_dir,
        write_surface=canonical_run_dir + "/",
    ))
    write_json(checks_dir / "source_path_boundary.json", check_payload(
        run_id, "pass", "source path is repo-local markdown/text",
        source_ref=source_arg.as_posix(),
    ))

    captured_source = input_dir / "source.md"
    shutil.copyfile(source_path, captured_source)
    digest = hashlib.sha256(captured_source.read_bytes()).hexdigest()
    (input_dir / "source.sha256").write_text(f"sha256:{digest}  source.md\n", encoding="utf-8")
    recomputed = hashlib.sha256(captured_source.read_bytes()).hexdigest()
    write_json(checks_dir / "source_hash_validation.json", check_payload(
        run_id, "pass" if digest == recomputed else "fail", "copied source sha256 matches recomputation",
        sha256=digest,
        source_ref=repo_ref(repo_root, captured_source),
    ))

    generated_at = now_utc()
    run_meta = {
        "run_id": run_id,
        "generated_at": generated_at,
        "profile": "knowledge-pipeline-local-source",
        "engine_mode": "knowledge-pipeline-scaffold",
        "evaluation_mode": "repo-local-static-v1",
        "canonical_run_dir": canonical_run_dir,
        "source_ref": source_arg.as_posix(),
        "write_surface": canonical_run_dir + "/",
        "openclaw_used": False,
        "docker_used": False,
        "network_used": False,
        "live_surface_used": False,
        "outside_git_paths_used": False,
        "auto_canonical_write_performed": False,
    }
    write_json(run_dir / "run_meta.json", run_meta)

    source_capture = {
        "source_id": run_id.lower().replace("_", "-"),
        "canonical_pointer": source_arg.as_posix(),
        "retrieval_status": "success",
        "retrieval_timestamp": generated_at,
        "content_type": "text/markdown" if source_arg.suffix.lower() in {".md", ".markdown"} else "text/plain",
        "stable_representation": f"{canonical_run_dir}/input/source.md",
        "human_identifier": source_arg.as_posix(),
        "provenance_notes": "Repo-local source captured by operations/harness-knowledge-pipeline/bin/capture_local_source.py; no network or live surface used.",
        "linkage": [source_arg.as_posix()],
        "capture_method": "repository-export",
        "hash": f"sha256:{digest}",
    }
    write_json(input_dir / "source_capture_package.json", source_capture)

    task_packet = {
        "id": run_id.lower().replace("_", "-"),
        "task_type": "knowledge-extraction",
        "title": f"Extract knowledge pipeline candidate from {source_arg.as_posix()}",
        "objective": f"Create bounded source-backed knowledge-pipeline candidate artifacts from the repo-local knowledge source {source_arg.as_posix()}.",
        "scope": "Repo-local markdown source only; all outputs remain inside the knowledge-pipeline run directory.",
        "inputs": [
            {"type": "document", "ref": source_arg.as_posix(), "description": "Original repo-local knowledge source."},
            {"type": "source-package", "ref": "input/source_capture_package.json", "description": "Frozen source capture package for this run."}
        ],
        "constraints": [
            "No OpenClaw, Docker, network, secrets, live/apply/rollout, or Hermes config/skills/memory/SOUL changes.",
            "All writes must stay under the canonical run directory.",
            "LLM may transform meaning only into run-dir semantic outputs.",
            "Scripts own evidence, validation, placement boundaries, admission gates, and reports.",
            "No automatic canonical write or admission."
        ],
        "expected_outputs": [
            {"type": "semantic-note", "description": "Source-backed normalized note candidate.", "destination_hint": "observability"},
            {"type": "result-packet", "description": "Claims, gaps, produced artifacts, and improvement candidates.", "destination_hint": "observability"},
            {"type": "review-decision-draft", "description": "Admission candidate that does not auto-admit canonical knowledge.", "destination_hint": "observability"}
        ],
        "acceptance_criteria": [
            "Source capture is hash-bound and schema-valid.",
            "Semantic outputs cite the source capture.",
            "Admission candidate is not treated as canonical admission.",
            "Wiki-derived draft references only the canonical knowledge candidate.",
            "Report and exit_code are emitted."
        ],
        "destination_hint": "mixed",
        "priority": "medium",
        "policy_refs": [
            "control-plane/policy/ADMISSION_POLICY.md",
            "control-plane/policy/PLACEMENT_POLICY.md",
            "control-plane/policy/KB_ROLE_CONTRACT.md",
            "control-plane/policy/RETRIEVAL_POLICY.md",
            "docs/EVIDENCE_RETENTION_POLICY.md"
        ],
        "placement_request": {
            "target_layer": "mixed",
            "target_path": f"{canonical_run_dir}/output/",
            "review_required": True,
            "apply_mode": "manual"
        },
        "provenance_requirements": [
            "Every substantive claim must reference input/source_capture_package.json and/or input/source.md.",
            "Canonical candidate remains candidate-only until explicit review/admission."
        ],
        "notes": "Knowledge-pipeline capture run for a repo-local source.",
        "status_hint": "in_progress"
    }
    write_json(input_dir / "task_packet.json", task_packet)

    schema_pairs = [
        (repo_root / "control-plane/contracts/schemas/source_capture_package.schema.json", input_dir / "source_capture_package.json", checks_dir / "source_capture_schema.json"),
        (repo_root / "control-plane/contracts/schemas/task_packet.schema.json", input_dir / "task_packet.json", checks_dir / "task_packet_schema.json"),
    ]
    failed = False
    for schema_path, instance_path, check_path in schema_pairs:
        status, errors = validate_schema(schema_path, instance_path)
        failed = failed or status == "fail"
        write_json(check_path, check_payload(
            run_id, status, "schema validation complete",
            schema=repo_ref(repo_root, schema_path),
            instance=repo_ref(repo_root, instance_path),
            errors=errors,
        ))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
