#!/usr/bin/env python3
"""Validate the external execution target contract before Phase 3 materialization/apply."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def path_ref(repo_root: Path, path: Path) -> str:
    resolved = path.resolve(strict=False)
    try:
        return resolved.relative_to(repo_root.resolve(strict=False)).as_posix()
    except ValueError:
        return resolved.as_posix()


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


def is_non_empty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def looks_like_phase2_runtime_ready(target_ref: Any, phase2_runtime_ready_ref: Any) -> bool:
    if not isinstance(target_ref, str) or not target_ref:
        return False
    normalized = target_ref.replace("\\", "/")
    if isinstance(phase2_runtime_ready_ref, str):
        phase2_normalized = phase2_runtime_ready_ref.replace("\\", "/")
        if normalized == phase2_normalized or normalized.startswith(f"{phase2_normalized}/"):
            return True
    path = PurePosixPath(normalized)
    windows_path = PureWindowsPath(target_ref)
    return (
        "operations/harness-phase2/runs/" in normalized and "output/runtime-ready" in normalized
    ) or (
        any(part == "harness-phase2" for part in windows_path.parts)
        and any(part == "runtime-ready" for part in windows_path.parts)
    ) or ("runtime-ready" in path.parts and "harness-phase2" in path.parts)


class CheckRecorder:
    def __init__(self, run_id: str) -> None:
        self.run_id = run_id
        self.checks: list[dict[str, Any]] = []
        self.error_seen = False

    def add(
        self,
        name: str,
        status: str,
        detail: str,
        *,
        source_refs: list[str],
        expected: Any | None = None,
        actual: Any | None = None,
    ) -> None:
        item: dict[str, Any] = {
            "name": name,
            "status": status,
            "detail": detail,
            "source_refs": source_refs,
        }
        if expected is not None:
            item["expected"] = expected
        if actual is not None:
            item["actual"] = actual
        self.checks.append(item)
        if status == "fail":
            self.error_seen = True

    def pass_check(self, name: str, detail: str, *, source_refs: list[str], expected: Any | None = None, actual: Any | None = None) -> None:
        self.add(name, "pass", detail, source_refs=source_refs, expected=expected, actual=actual)

    def fail_check(self, name: str, detail: str, *, source_refs: list[str], expected: Any | None = None, actual: Any | None = None) -> None:
        self.add(name, "fail", detail, source_refs=source_refs, expected=expected, actual=actual)

    def build_report(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "generated_at": now_utc(),
            "engine_mode": "scaffold",
            "evaluation_mode": "phase3-static-v1",
            "status": "fail" if self.error_seen else "pass",
            "checks": self.checks,
        }


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: validate_pre_apply.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve(strict=False)
    run_dir = Path(sys.argv[2]).resolve(strict=False)
    run_id = run_dir.name
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)
    report_path = checks_dir / "pre_apply_validation.json"
    execution_target_path = run_dir / "input" / "execution_target.json"
    run_meta_path = run_dir / "run_meta.json"

    recorder = CheckRecorder(run_id)
    source_refs = [path_ref(repo_root, execution_target_path), path_ref(repo_root, run_meta_path)]

    execution_target_payload: dict[str, Any] | None = None
    phase2_runtime_ready_ref: Any = None
    try:
        execution_target_payload = read_json_object(execution_target_path)
        recorder.pass_check(
            "execution_target.parse",
            "External execution_target.json is parseable.",
            source_refs=[path_ref(repo_root, execution_target_path)],
            expected="parseable JSON object",
            actual="parseable JSON object",
        )
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        recorder.fail_check(
            "execution_target.parse",
            f"External execution_target.json must be a parseable JSON object: {exc}",
            source_refs=[path_ref(repo_root, execution_target_path)],
            expected="parseable JSON object",
            actual="invalid or unreadable",
        )

    try:
        run_meta = read_json_object(run_meta_path)
        phase2_runtime_ready_ref = run_meta.get("phase2_runtime_ready_ref")
    except (OSError, ValueError, json.JSONDecodeError):
        phase2_runtime_ready_ref = None

    canonical_target_ref = f"operations/harness-phase3/runs/{run_id}/staging/runtime-ready-applied"
    target_runtime = execution_target_payload.get("target_runtime") if execution_target_payload else None
    target_kind = execution_target_payload.get("target_kind") if execution_target_payload else None
    target_ref = execution_target_payload.get("target_ref") if execution_target_payload else None
    apply_mode = execution_target_payload.get("apply_mode") if execution_target_payload else None
    approval_ref = execution_target_payload.get("approval_ref") if execution_target_payload else None

    if target_runtime == "openclaw":
        recorder.pass_check(
            "target_runtime.allowed",
            "Only openclaw is allowed for the Phase 3 scaffold target runtime.",
            source_refs=source_refs,
            expected="openclaw",
            actual=target_runtime,
        )
    else:
        recorder.fail_check(
            "target_runtime.allowed",
            "Phase 3 scaffold only allows target_runtime=openclaw.",
            source_refs=source_refs,
            expected="openclaw",
            actual=target_runtime,
        )

    if target_kind == "phase3_staging":
        recorder.pass_check(
            "target_kind.allowed",
            "Only phase3_staging is allowed for the scaffold target kind.",
            source_refs=source_refs,
            expected="phase3_staging",
            actual=target_kind,
        )
    else:
        recorder.fail_check(
            "target_kind.allowed",
            "Phase 3 scaffold only allows target_kind=phase3_staging.",
            source_refs=source_refs,
            expected="phase3_staging",
            actual=target_kind,
        )

    if apply_mode in {"dry_run", "staged"}:
        recorder.pass_check(
            "apply_mode.allowed",
            "Phase 3 scaffold only allows dry_run or staged apply modes.",
            source_refs=source_refs,
            expected=["dry_run", "staged"],
            actual=apply_mode,
        )
    else:
        recorder.fail_check(
            "apply_mode.allowed",
            "Phase 3 scaffold only allows dry_run or staged apply modes.",
            source_refs=source_refs,
            expected=["dry_run", "staged"],
            actual=apply_mode,
        )

    approval_ok = False
    if apply_mode == "staged":
        approval_ok = is_non_empty_string(approval_ref)
    elif apply_mode == "dry_run":
        approval_ok = approval_ref is None or is_non_empty_string(approval_ref)
    if approval_ok:
        recorder.pass_check(
            "approval_ref.allowed_for_apply_mode",
            "approval_ref satisfies the narrow scaffold policy for the requested apply mode.",
            source_refs=source_refs,
            expected="staged requires a non-empty approval_ref; dry_run allows null or a non-empty string",
            actual=approval_ref,
        )
    else:
        recorder.fail_check(
            "approval_ref.allowed_for_apply_mode",
            "approval_ref does not satisfy the narrow scaffold policy for the requested apply mode.",
            source_refs=source_refs,
            expected="staged requires a non-empty approval_ref; dry_run allows null or a non-empty string",
            actual=approval_ref,
        )

    if target_ref == canonical_target_ref:
        recorder.pass_check(
            "target_ref.phase3_run_scoped",
            "Validated runs target the canonical Phase 3-owned staging path.",
            source_refs=source_refs,
            expected=canonical_target_ref,
            actual=target_ref,
        )
    else:
        recorder.fail_check(
            "target_ref.phase3_run_scoped",
            "Validated runs must target the canonical Phase 3-owned staging path.",
            source_refs=source_refs,
            expected=canonical_target_ref,
            actual=target_ref,
        )

    if not looks_like_phase2_runtime_ready(target_ref, phase2_runtime_ready_ref):
        recorder.pass_check(
            "target_ref.not_phase2_runtime_ready",
            "Execution target does not point at the upstream Phase 2 runtime-ready package.",
            source_refs=source_refs,
            expected="target outside Phase 2 runtime-ready/",
            actual=target_ref,
        )
    else:
        recorder.fail_check(
            "target_ref.not_phase2_runtime_ready",
            "Execution target must not point at the upstream Phase 2 runtime-ready package.",
            source_refs=source_refs,
            expected="target outside Phase 2 runtime-ready/",
            actual=target_ref,
        )

    report = recorder.build_report()
    write_json(report_path, report)
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
