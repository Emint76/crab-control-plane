#!/usr/bin/env python3
"""Validate frozen Phase 4 invocation proof for Phase 3 KB admission."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator
from jsonschema.exceptions import SchemaError


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def read_json_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level JSON value must be an object")
    return payload


def sha256_file(path: Path) -> str:
    import hashlib

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


def schema_violation_name(error: Any) -> str:
    path = ".".join(str(item) for item in error.path)
    suffix = f".{path}" if path else ""
    if error.validator == "required":
        missing = error.message.split("'")
        if len(missing) >= 2:
            return f"schema.required.{missing[1]}"
        return "schema.required"
    if error.validator == "additionalProperties":
        return "schema.additionalProperties"
    if error.validator == "const":
        return f"schema.const{suffix}"
    if error.validator == "type":
        return f"schema.type{suffix}"
    if error.validator == "pattern":
        return f"schema.pattern{suffix}"
    return f"schema.{error.validator}{suffix}"


class Recorder:
    def __init__(self, repo_root: Path, run_dir: Path) -> None:
        self.repo_root = repo_root
        self.run_dir = run_dir
        self.checks: list[dict[str, Any]] = []
        self.failure_reasons: list[str] = []
        self.hashes: dict[str, Any] = {}
        self.refs: dict[str, Any] = {}
        self.schema_name: Any = None
        self.schema_version: Any = None

    def add(self, name: str, status: str, detail: str, **extra: Any) -> None:
        item: dict[str, Any] = {"name": name, "status": status, "detail": detail}
        item.update(extra)
        self.checks.append(item)
        if status == "fail":
            self.failure_reasons.append(name)

    def require_equal(self, name: str, actual: Any, expected: Any, detail: str) -> None:
        if actual == expected:
            self.add(name, "pass", detail, expected=expected, actual=actual)
        else:
            self.add(name, "fail", detail, expected=expected, actual=actual)

    def report(self) -> dict[str, Any]:
        return {
            "run_id": self.run_dir.name,
            "generated_at": now_utc(),
            "status": "fail" if self.failure_reasons else "pass",
            "schema_name": self.schema_name,
            "schema_version": self.schema_version,
            "checked_invariants": [item["name"] for item in self.checks],
            "failure_reasons": sorted(set(self.failure_reasons)),
            "hashes": self.hashes,
            "refs": self.refs,
            "checks": self.checks,
        }


def validate_no_symlink_source(repo_root: Path, claim_ref: str, recorder: Recorder) -> Path | None:
    raw_path = repo_root / claim_ref
    phase4_runs_root = repo_root / "operations" / "harness-phase4" / "runs"
    try:
        relative = raw_path.relative_to(phase4_runs_root)
    except ValueError:
        recorder.add(
            "claim_path.phase4_surface",
            "fail",
            "Claim source ref must be under operations/harness-phase4/runs/.",
            actual=claim_ref,
        )
        return None
    if len(relative.parts) != 2 or relative.parts[1] != "phase4_invocation_claim.json":
        recorder.add(
            "claim_path.phase4_surface",
            "fail",
            "Claim source ref must be operations/harness-phase4/runs/<WRAPPER_RUN_ID>/phase4_invocation_claim.json.",
            actual=claim_ref,
        )
        return None

    current = repo_root
    for part in Path(claim_ref).parts:
        current = current / part
        if current.is_symlink():
            recorder.add(
                "claim_path.no_symlink_components",
                "fail",
                "Claim source path must not traverse or reference symlinks.",
                actual=claim_ref,
            )
            return raw_path
    recorder.add(
        "claim_path.no_symlink_components",
        "pass",
        "Claim source path contains no symlink components.",
        actual=claim_ref,
    )
    recorder.add(
        "claim_path.phase4_surface",
        "pass",
        "Claim source ref is in the allowed Phase 4 wrapper-run surface.",
        actual=claim_ref,
    )
    return raw_path


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: validate_phase4_invocation.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve(strict=False)
    run_dir = Path(sys.argv[2]).resolve(strict=False)
    input_dir = run_dir / "input"
    report_path = run_dir / "checks" / "phase4_invocation_validation.json"
    recorder = Recorder(repo_root, run_dir)

    try:
        execution_target = read_json_object(input_dir / "execution_target.json")
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        recorder.add("execution_target.parse", "fail", f"Frozen execution target is invalid: {exc}")
        write_json(report_path, recorder.report())
        return 1

    if execution_target.get("target_kind") != "kb_admission":
        recorder.add(
            "phase4_invocation.not_required",
            "pass",
            "Phase 4 invocation proof is required only for target_kind=kb_admission.",
            target_kind=execution_target.get("target_kind"),
        )
        write_json(report_path, recorder.report())
        return 0

    claim_path = input_dir / "phase4_invocation_claim.json"
    freeze_meta_path = input_dir / "phase4_invocation_claim_freeze.json"
    target_freeze_path = input_dir / "execution_target_freeze.json"
    run_meta_path = run_dir / "run_meta.json"
    schema_path = repo_root / "operations" / "harness-phase4" / "contracts" / "phase4_invocation_claim.schema.json"

    claim: dict[str, Any] = {}
    freeze_meta: dict[str, Any] = {}
    target_freeze: dict[str, Any] = {}
    run_meta: dict[str, Any] = {}

    try:
        claim = read_json_object(claim_path)
        recorder.add("claim.parse", "pass", "Frozen Phase 4 invocation claim is valid JSON.")
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        recorder.add("claim.parse", "fail", f"Frozen Phase 4 invocation claim is missing or invalid: {exc}")

    for name, path, target in [
        ("claim_freeze_meta.parse", freeze_meta_path, "freeze_meta"),
        ("execution_target_freeze.parse", target_freeze_path, "target_freeze"),
        ("run_meta.parse", run_meta_path, "run_meta"),
    ]:
        try:
            parsed = read_json_object(path)
            if target == "freeze_meta":
                freeze_meta = parsed
            elif target == "target_freeze":
                target_freeze = parsed
            else:
                run_meta = parsed
            recorder.add(name, "pass", f"{path.name} is valid JSON.")
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            recorder.add(name, "fail", f"{path.name} is missing or invalid: {exc}")

    if claim:
        recorder.schema_name = claim.get("schema_name")
        recorder.schema_version = claim.get("schema_version")

    try:
        schema = read_json_object(schema_path)
        Draft202012Validator.check_schema(schema)
        schema_errors = sorted(
            Draft202012Validator(schema).iter_errors(claim),
            key=lambda error: (list(error.path), error.validator, error.message),
        )
    except (OSError, ValueError, json.JSONDecodeError, SchemaError) as exc:
        recorder.add("claim.schema", "fail", f"Phase 4 invocation claim schema is invalid or unreadable: {exc}")
        schema_errors = []

    if claim and not schema_errors:
        recorder.add("claim.schema", "pass", "Claim conforms to the Phase 4 invocation-claim schema.")
    elif schema_errors:
        recorder.add(
            "claim.schema",
            "fail",
            "Claim does not conform to the Phase 4 invocation-claim schema.",
            violations=sorted(set(schema_violation_name(error) for error in schema_errors)),
        )

    frozen_claim_hash = sha256_file(claim_path) if claim_path.is_file() else None
    frozen_target_hash = sha256_file(input_dir / "execution_target.json") if (input_dir / "execution_target.json").is_file() else None
    recorder.hashes = {
        "frozen_phase4_invocation_claim_sha256": frozen_claim_hash,
        "freeze_recorded_claim_sha256": freeze_meta.get("frozen_phase4_invocation_claim_sha256"),
        "phase4_source_claim_sha256": freeze_meta.get("phase4_invocation_claim_sha256"),
        "frozen_execution_target_sha256": frozen_target_hash,
        "freeze_recorded_execution_target_sha256": target_freeze.get("frozen_execution_target_sha256"),
        "claim_execution_target_sha256": claim.get("execution_target_sha256") if claim else None,
    }
    recorder.refs = {
        "phase4_invocation_claim_ref": freeze_meta.get("phase4_invocation_claim_ref"),
        "frozen_phase4_invocation_claim_ref": "operations/harness-phase3/runs/" + run_dir.name + "/input/phase4_invocation_claim.json",
        "execution_target_ref": target_freeze.get("execution_target_ref"),
        "frozen_execution_target_ref": "operations/harness-phase3/runs/" + run_dir.name + "/input/execution_target.json",
        "phase2_run_ref": run_meta.get("phase2_run_ref"),
        "wrapper_run_ref": claim.get("wrapper_run_ref") if claim else None,
        "phase3_run_ref": claim.get("phase3_run_ref") if claim else None,
    }

    if freeze_meta:
        recorder.require_equal(
            "claim_freeze.byte_identical",
            freeze_meta.get("byte_identical"),
            True,
            "Frozen claim must be byte-identical to the consumed Phase 4 claim.",
        )
        recorder.require_equal(
            "claim_freeze.sha256",
            freeze_meta.get("frozen_phase4_invocation_claim_sha256"),
            freeze_meta.get("phase4_invocation_claim_sha256"),
            "Frozen claim SHA-256 must match the source claim SHA-256.",
        )
        recorder.require_equal(
            "claim_freeze.actual_sha256",
            frozen_claim_hash,
            freeze_meta.get("frozen_phase4_invocation_claim_sha256"),
            "Current frozen claim bytes must match the freeze metadata.",
        )

    claim_ref = freeze_meta.get("phase4_invocation_claim_ref")
    source_claim_path = validate_no_symlink_source(repo_root, claim_ref, recorder) if isinstance(claim_ref, str) else None
    if source_claim_path and source_claim_path.is_file():
        recorder.require_equal(
            "claim_source.current_sha256",
            sha256_file(source_claim_path),
            freeze_meta.get("phase4_invocation_claim_sha256"),
            "Current Phase 4 claim source bytes still match the frozen source hash.",
        )

    if claim:
        expected_wrapper_ref = f"operations/harness-phase4/runs/{claim.get('wrapper_run_id')}"
        expected_claim_ref = f"{expected_wrapper_ref}/phase4_invocation_claim.json"
        recorder.require_equal("wrapper_run_ref.matches_id", claim.get("wrapper_run_ref"), expected_wrapper_ref, "Wrapper run ref must match wrapper_run_id.")
        recorder.require_equal("claim_path.matches_wrapper", claim_ref, expected_claim_ref, "Claim path must belong to the declared wrapper run.")
        recorder.require_equal("invariant_claim_ref.matches_source", claim.get("invariants", {}).get("phase4_claim_ref"), expected_claim_ref, "Claim invariant ref must match the consumed claim path.")
        recorder.require_equal("phase3_run_id.matches_current", claim.get("phase3_run_id"), run_dir.name, "Claim must bind to the exact current Phase 3 run id.")
        recorder.require_equal("phase3_run_ref.matches_current", claim.get("phase3_run_ref"), f"operations/harness-phase3/runs/{run_dir.name}", "Claim must bind to the exact current Phase 3 run ref.")
        recorder.require_equal("target_kind.kb_admission", claim.get("target_kind"), "kb_admission", "Claim target kind must be kb_admission.")
        recorder.require_equal("execution_target_ref.matches_frozen_source", claim.get("execution_target_ref"), target_freeze.get("execution_target_ref"), "Claim execution target ref must match the source target frozen by Phase 3.")
        recorder.require_equal("execution_target_sha256.matches_frozen", claim.get("execution_target_sha256"), frozen_target_hash, "Claim execution target hash must match frozen execution target bytes.")
        recorder.require_equal("phase2_run_ref.matches_input", claim.get("phase2_run_ref"), run_meta.get("phase2_run_ref"), "Claim Phase 2 ref must match Phase 3 frozen input provenance.")
        recorder.require_equal("claim_id.matches_exact_binding", claim.get("claim_id"), f"phase4-invocation:{claim.get('wrapper_run_id')}:{run_dir.name}:{frozen_target_hash}", "Claim id must bind wrapper run, Phase 3 run, and execution-target hash.")

    report = recorder.report()
    write_json(report_path, report)
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
