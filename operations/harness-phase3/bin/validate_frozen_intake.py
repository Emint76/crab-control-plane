#!/usr/bin/env python3
"""Validate the frozen Phase 2 handoff intake for Phase 3."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
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


def parse_expected_field(path: Path, field_name: str) -> tuple[bool, Any]:
    try:
        payload = read_json_object(path)
    except (OSError, ValueError, json.JSONDecodeError):
        return False, "invalid"
    return True, payload.get(field_name)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: validate_frozen_intake.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve(strict=False)
    run_dir = Path(sys.argv[2]).resolve(strict=False)
    run_id = run_dir.name
    input_dir = run_dir / "input"
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)
    report_path = checks_dir / "freeze_intake_validation.json"

    recorder = CheckRecorder(run_id)

    handoff_path = input_dir / "handoff_ready.json"
    valid_handoff, handoff_status = parse_expected_field(handoff_path, "status")
    if valid_handoff and handoff_status == "ready":
        recorder.pass_check(
            "handoff_ready.status",
            "Frozen handoff_ready.json marks the upstream handoff as ready.",
            source_refs=[path_ref(repo_root, handoff_path)],
            expected="ready",
            actual=handoff_status,
        )
    else:
        recorder.fail_check(
            "handoff_ready.status",
            "Frozen handoff_ready.json must contain status=ready.",
            source_refs=[path_ref(repo_root, handoff_path)],
            expected="ready",
            actual=handoff_status,
        )

    valid_handoff_target, handoff_target = parse_expected_field(handoff_path, "handoff_target")
    if valid_handoff_target and handoff_target == "phase3_execution_owner":
        recorder.pass_check(
            "handoff_ready.handoff_target",
            "Frozen handoff target matches the Phase 3 execution owner.",
            source_refs=[path_ref(repo_root, handoff_path)],
            expected="phase3_execution_owner",
            actual=handoff_target,
        )
    else:
        recorder.fail_check(
            "handoff_ready.handoff_target",
            "Frozen handoff target must be phase3_execution_owner.",
            source_refs=[path_ref(repo_root, handoff_path)],
            expected="phase3_execution_owner",
            actual=handoff_target,
        )

    field_checks = [
        ("validation_report.status", input_dir / "validation_report.json", "status", "pass"),
        ("admission_decision.decision", input_dir / "admission_decision.json", "decision", "approved"),
        ("placement_decision.decision", input_dir / "placement_decision.json", "decision", "approved"),
        ("apply_plan.status", input_dir / "apply_plan.json", "status", "ready"),
        ("smoke_validation.status", input_dir / "smoke_validation.json", "status", "pass"),
        ("conformance_validation.status", input_dir / "conformance_validation.json", "status", "pass"),
    ]
    for check_name, artifact_path, field_name, expected_value in field_checks:
        valid_payload, actual_value = parse_expected_field(artifact_path, field_name)
        if valid_payload and actual_value == expected_value:
            recorder.pass_check(
                check_name,
                f"{artifact_path.name} matches the expected {field_name} value.",
                source_refs=[path_ref(repo_root, artifact_path)],
                expected=expected_value,
                actual=actual_value,
            )
        else:
            recorder.fail_check(
                check_name,
                f"{artifact_path.name} must contain {field_name}={expected_value}.",
                source_refs=[path_ref(repo_root, artifact_path)],
                expected=expected_value,
                actual=actual_value,
            )

    for check_name, artifact_path in [
        ("runtime_ready_manifest.present", input_dir / "runtime_ready_manifest.json"),
        ("runtime_ready.sha256.present", input_dir / "runtime_ready.sha256"),
        ("input.sha256.present", input_dir / "input.sha256"),
    ]:
        if artifact_path.is_file():
            recorder.pass_check(
                check_name,
                f"{artifact_path.name} is present in the frozen input surface.",
                source_refs=[path_ref(repo_root, artifact_path)],
                expected="present",
                actual="present",
            )
        else:
            recorder.fail_check(
                check_name,
                f"{artifact_path.name} must be present in the frozen input surface.",
                source_refs=[path_ref(repo_root, artifact_path)],
                expected="present",
                actual="missing",
            )

    if not recorder.checks:
        recorder.fail_check(
            "freeze_intake.no_checks_recorded",
            "Frozen intake validator did not record any checks.",
            source_refs=[],
            expected="non-empty checks array",
            actual="empty",
        )

    report = recorder.build_report()
    write_json(report_path, report)
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
