#!/usr/bin/env python3
"""Smoke validation for the Phase 2 runtime-ready package."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml


REQUIRED_DECISION_ARTIFACTS = {
    "validation_report": "validation_report.json",
    "admission_decision": "admission_decision.json",
    "placement_decision": "placement_decision.json",
    "apply_plan": "apply_plan.json",
}
REQUIRED_RUNTIME_READY_FILES = {
    "openclaw.template.json": "json",
    "tool-policy.template.yaml": "yaml",
    "agent-routing.template.yaml": "yaml",
    "placement-policy.yaml": "yaml",
    "admission-policy.yaml": "yaml",
    "APPLY_MODEL.md": "text",
}


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


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
        severity: str | None = None,
    ) -> None:
        check: dict[str, Any] = {
            "name": name,
            "status": status,
            "detail": detail,
            "source_refs": source_refs,
        }
        if expected is not None:
            check["expected"] = expected
        if actual is not None:
            check["actual"] = actual
        if severity is not None:
            check["severity"] = severity
        self.checks.append(check)
        if status == "fail" or severity == "error":
            self.error_seen = True

    def pass_check(
        self,
        name: str,
        detail: str,
        *,
        source_refs: list[str],
        expected: Any | None = None,
        actual: Any | None = None,
    ) -> None:
        self.add(name, "pass", detail, source_refs=source_refs, expected=expected, actual=actual)

    def fail_check(
        self,
        name: str,
        detail: str,
        *,
        source_refs: list[str],
        expected: Any | None = None,
        actual: Any | None = None,
    ) -> None:
        self.add(
            name,
            "fail",
            detail,
            source_refs=source_refs,
            expected=expected,
            actual=actual,
            severity="error",
        )

    def build_report(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "generated_at": now_utc(),
            "engine_mode": "scaffold",
            "evaluation_mode": "static-v1",
            "status": "fail" if self.error_seen else "pass",
            "checks": self.checks,
        }


def repo_rel(repo_root: Path, path: Path) -> str:
    return path.relative_to(repo_root).as_posix()


def load_json_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level JSON value must be an object")
    return payload


def load_yaml_mapping(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level YAML value must be a mapping")
    return payload


def is_under(path: Path, root: Path) -> bool:
    try:
        path.resolve(strict=False).relative_to(root.resolve(strict=False))
        return True
    except ValueError:
        return False


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: run_phase2_smoke.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve()
    run_dir = Path(sys.argv[2]).resolve()
    run_id = run_dir.name
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)
    report_path = checks_dir / "smoke_validation.json"

    recorder = CheckRecorder(run_id)

    try:
        decision_paths = {name: run_dir / rel_path for name, rel_path in REQUIRED_DECISION_ARTIFACTS.items()}
        present_artifacts = sorted(name for name, path in decision_paths.items() if path.is_file())
        missing_artifacts = sorted(name for name, path in decision_paths.items() if not path.is_file())
        if missing_artifacts:
            recorder.fail_check(
                "decision_artifacts.required_present",
                "One or more required rendered decision artifacts are missing.",
                source_refs=[repo_rel(repo_root, path) for path in decision_paths.values()],
                expected=sorted(REQUIRED_DECISION_ARTIFACTS.keys()),
                actual={"present": present_artifacts, "missing": missing_artifacts},
            )
        else:
            recorder.pass_check(
                "decision_artifacts.required_present",
                "All required rendered decision artifacts are present.",
                source_refs=[repo_rel(repo_root, path) for path in decision_paths.values()],
                expected=sorted(REQUIRED_DECISION_ARTIFACTS.keys()),
                actual=present_artifacts,
            )

        parsed_decision_payloads: dict[str, dict[str, Any]] = {}
        for artifact_name, artifact_path in decision_paths.items():
            check_name = f"decision_artifacts.{artifact_name}.parse"
            if not artifact_path.is_file():
                recorder.fail_check(
                    check_name,
                    "Required decision artifact is missing.",
                    source_refs=[repo_rel(repo_root, artifact_path)],
                    expected="existing JSON artifact",
                    actual="missing",
                )
                continue
            try:
                payload = load_json_object(artifact_path)
            except (OSError, ValueError, json.JSONDecodeError) as exc:
                recorder.fail_check(
                    check_name,
                    f"Failed to parse decision artifact: {exc}",
                    source_refs=[repo_rel(repo_root, artifact_path)],
                    expected="parseable JSON object",
                    actual="unreadable or malformed",
                )
                continue
            parsed_decision_payloads[artifact_name] = payload
            recorder.pass_check(
                check_name,
                "Decision artifact is parseable.",
                source_refs=[repo_rel(repo_root, artifact_path)],
                actual="parseable JSON object",
            )

        runtime_ready_dir = run_dir / "output" / "runtime-ready"
        runtime_ready_source_ref = repo_rel(repo_root, runtime_ready_dir)
        if runtime_ready_dir.is_dir():
            recorder.pass_check(
                "runtime_ready.directory_present",
                "Rendered runtime-ready directory is present.",
                source_refs=[runtime_ready_source_ref],
                actual=runtime_ready_source_ref,
            )
        else:
            recorder.fail_check(
                "runtime_ready.directory_present",
                "Rendered runtime-ready directory is missing.",
                source_refs=[runtime_ready_source_ref],
                expected="existing directory",
                actual="missing",
            )

        package_present: list[str] = []
        package_missing: list[str] = []
        package_paths = {name: runtime_ready_dir / name for name in REQUIRED_RUNTIME_READY_FILES}
        for name, path in package_paths.items():
            if path.is_file():
                package_present.append(name)
            else:
                package_missing.append(name)
        if package_missing:
            recorder.fail_check(
                "runtime_ready.required_files_present",
                "One or more required runtime-ready package files are missing.",
                source_refs=[repo_rel(repo_root, path) for path in package_paths.values()],
                expected=sorted(REQUIRED_RUNTIME_READY_FILES.keys()),
                actual={"present": sorted(package_present), "missing": sorted(package_missing)},
            )
        else:
            recorder.pass_check(
                "runtime_ready.required_files_present",
                "All required runtime-ready package files are present.",
                source_refs=[repo_rel(repo_root, path) for path in package_paths.values()],
                expected=sorted(REQUIRED_RUNTIME_READY_FILES.keys()),
                actual=sorted(package_present),
            )

        parsed_package_payloads: dict[str, dict[str, Any]] = {}
        for filename, parse_mode in REQUIRED_RUNTIME_READY_FILES.items():
            path = package_paths[filename]
            source_ref = repo_rel(repo_root, path)
            if parse_mode == "text":
                continue
            check_name = f"runtime_ready.{filename}.parse"
            if not path.is_file():
                recorder.fail_check(
                    check_name,
                    "Required runtime-ready package file is missing.",
                    source_refs=[source_ref],
                    expected=f"parseable {parse_mode}",
                    actual="missing",
                )
                continue
            try:
                if parse_mode == "json":
                    payload = load_json_object(path)
                else:
                    payload = load_yaml_mapping(path)
            except (OSError, ValueError, json.JSONDecodeError, yaml.YAMLError) as exc:
                recorder.fail_check(
                    check_name,
                    f"Failed to parse rendered package file: {exc}",
                    source_refs=[source_ref],
                    expected=f"parseable {parse_mode}",
                    actual="unreadable or malformed",
                )
                continue
            parsed_package_payloads[filename] = payload
            recorder.pass_check(
                check_name,
                "Rendered package file is parseable.",
                source_refs=[source_ref],
                actual=f"parseable {parse_mode}",
            )

        required_shapes = {
            "openclaw.template.json": ["validation", "apply"],
            "tool-policy.template.yaml": ["tools", "gates"],
            "agent-routing.template.yaml": ["routing"],
            "placement-policy.yaml": ["roots", "rules"],
            "admission-policy.yaml": ["rules"],
        }
        for filename, required_keys in required_shapes.items():
            path = package_paths[filename]
            source_ref = repo_rel(repo_root, path)
            payload = parsed_package_payloads.get(filename)
            check_name = f"runtime_ready.{filename}.shape"
            if payload is None:
                recorder.fail_check(
                    check_name,
                    "Cannot verify top-level shape because the rendered package file is unavailable or unparseable.",
                    source_refs=[source_ref],
                    expected=required_keys,
                    actual="unavailable",
                )
                continue
            missing_keys = [key for key in required_keys if key not in payload]
            if missing_keys:
                recorder.fail_check(
                    check_name,
                    "Rendered package file is missing required top-level keys.",
                    source_refs=[source_ref],
                    expected=required_keys,
                    actual={"missing": missing_keys, "present": sorted(payload.keys())},
                )
            else:
                recorder.pass_check(
                    check_name,
                    "Rendered package file contains the required top-level keys.",
                    source_refs=[source_ref],
                    expected=required_keys,
                    actual=sorted(payload.keys()),
                )

        apply_plan_payload = parsed_decision_payloads.get("apply_plan")
        apply_plan_path = decision_paths["apply_plan"]
        apply_plan_source_ref = repo_rel(repo_root, apply_plan_path)
        if apply_plan_payload is None:
            recorder.fail_check(
                "apply_plan.steps.non_empty",
                "Cannot verify apply plan steps because apply_plan.json is unavailable or unparseable.",
                source_refs=[apply_plan_source_ref],
                expected="non-empty steps array",
                actual="unavailable",
            )
            recorder.fail_check(
                "apply_plan.copy_targets.exist",
                "Cannot verify copy targets because apply_plan.json is unavailable or unparseable.",
                source_refs=[apply_plan_source_ref],
                expected="existing rendered copy targets",
                actual="unavailable",
            )
        else:
            steps = apply_plan_payload.get("steps")
            if isinstance(steps, list) and len(steps) > 0:
                recorder.pass_check(
                    "apply_plan.steps.non_empty",
                    "apply_plan.json contains a non-empty steps array.",
                    source_refs=[apply_plan_source_ref],
                    actual=len(steps),
                )
            else:
                recorder.fail_check(
                    "apply_plan.steps.non_empty",
                    "apply_plan.json must contain a non-empty steps array.",
                    source_refs=[apply_plan_source_ref],
                    expected="non-empty steps array",
                    actual=steps,
                )
                steps = []

            existing_copy_targets: list[str] = []
            missing_copy_targets: list[str] = []
            ignored_copy_targets: list[str] = []
            runtime_ready_root = runtime_ready_dir.resolve(strict=False)
            for step in steps:
                if not isinstance(step, dict):
                    continue
                if step.get("kind") != "copy":
                    continue
                target_path_value = step.get("target_path")
                if not isinstance(target_path_value, str) or not target_path_value:
                    missing_copy_targets.append("<missing-target-path>")
                    continue
                target_path = repo_root / target_path_value
                if is_under(target_path, runtime_ready_root):
                    if target_path.is_file():
                        existing_copy_targets.append(target_path_value)
                    else:
                        missing_copy_targets.append(target_path_value)
                else:
                    ignored_copy_targets.append(target_path_value)

            if missing_copy_targets:
                recorder.fail_check(
                    "apply_plan.copy_targets.exist",
                    "One or more copy targets under the runtime-ready package are missing.",
                    source_refs=[apply_plan_source_ref, runtime_ready_source_ref],
                    expected="existing files for copy targets under runtime-ready/",
                    actual={
                        "present": sorted(existing_copy_targets),
                        "missing": sorted(missing_copy_targets),
                        "ignored": sorted(ignored_copy_targets),
                    },
                )
            else:
                recorder.pass_check(
                    "apply_plan.copy_targets.exist",
                    "All copy targets under the runtime-ready package exist.",
                    source_refs=[apply_plan_source_ref, runtime_ready_source_ref],
                    actual={
                        "present": sorted(existing_copy_targets),
                        "ignored": sorted(ignored_copy_targets),
                    },
                )

    except Exception as exc:  # noqa: BLE001
        recorder.fail_check(
            "smoke.unhandled_exception",
            f"Unhandled smoke validation exception: {exc}",
            source_refs=[],
            actual=type(exc).__name__,
        )

    if not recorder.checks:
        recorder.fail_check(
            "smoke.no_checks_recorded",
            "Smoke validator did not record any checks.",
            source_refs=[],
            expected="non-empty checks array",
            actual="empty",
        )

    report = recorder.build_report()
    with report_path.open("w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")

    return 1 if recorder.error_seen else 0


if __name__ == "__main__":
    raise SystemExit(main())
