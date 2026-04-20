#!/usr/bin/env python3
"""Post-render conformance validation and handoff verdict for Phase 2."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any


REQUIRED_JSON_ARTIFACTS = {
    "run_meta": "run_meta.json",
    "contracts_validation": "checks/contracts_validation.json",
    "policy_validation": "checks/policy_validation.json",
    "smoke_validation": "checks/smoke_validation.json",
    "validation_report": "validation_report.json",
    "admission_decision": "admission_decision.json",
    "placement_decision": "placement_decision.json",
    "apply_plan": "apply_plan.json",
}
REQUIRED_TEXT_ARTIFACTS = {
    "wrong_root_preflight": "checks/wrong_root_preflight.txt",
}
REQUIRED_RUNTIME_READY_FILES = [
    "openclaw.template.json",
    "tool-policy.template.yaml",
    "agent-routing.template.yaml",
    "placement-policy.yaml",
    "admission-policy.yaml",
    "APPLY_MODEL.md",
]
CONFORMANCE_BLOCKER_MAP = {
    "artifacts.run_meta.parse": "invalid_artifact:run_meta",
    "artifacts.wrong_root_preflight.parse": "invalid_artifact:wrong_root_preflight",
    "artifacts.contracts_validation.parse": "invalid_artifact:contracts_validation",
    "artifacts.policy_validation.parse": "invalid_artifact:policy_validation",
    "artifacts.smoke_validation.parse": "invalid_artifact:smoke_validation",
    "artifacts.validation_report.parse": "invalid_artifact:validation_report",
    "artifacts.admission_decision.parse": "invalid_artifact:admission_decision",
    "artifacts.placement_decision.parse": "invalid_artifact:placement_decision",
    "artifacts.apply_plan.parse": "invalid_artifact:apply_plan",
    "upstream.wrong_root_preflight.state": "wrong_root_preflight_failed",
    "upstream.contracts_validation.state": "contracts_validation_failed",
    "upstream.policy_validation.state": "policy_validation_failed",
    "upstream.smoke_validation.state": "smoke_validation_failed",
    "decisions.validation_report.state": "validation_report_failed",
    "decisions.admission_decision.state": "admission_decision_not_approved",
    "decisions.placement_decision.state": "placement_decision_not_approved",
    "decisions.apply_plan.state": "apply_plan_not_ready",
    "apply_plan.steps.non_empty": "apply_plan_steps_invalid",
    "apply_plan.source_refs.repo_relative": "apply_plan_source_refs_invalid",
    "apply_plan.runtime_ready_targets.exist": "runtime_ready_targets_missing",
    "runtime_ready.required_files_present": "runtime_ready_package_incomplete",
    "placement.runtime_ready_not_artifact": "runtime_ready_misclassified_as_placement_artifact",
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


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def repo_rel(repo_root: Path, path: Path) -> str:
    return path.relative_to(repo_root).as_posix()


def read_text(path: Path) -> str:
    with path.open("r", encoding="utf-8") as handle:
        return handle.read()


def read_json_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level JSON value must be an object")
    return payload


def is_non_empty_repo_relative_path(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    posix_path = PurePosixPath(value)
    windows_path = PureWindowsPath(value)
    if posix_path.is_absolute() or windows_path.is_absolute():
        return False
    return ".." not in posix_path.parts and ".." not in windows_path.parts


def is_under(path: Path, root: Path) -> bool:
    try:
        path.resolve(strict=False).relative_to(root.resolve(strict=False))
        return True
    except ValueError:
        return False


def parse_preflight(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {
            "artifact_ok": False,
            "value": "fail",
            "detail": f"missing required artifact: {path.name}",
            "blockers": ["missing_artifact:wrong_root_preflight"],
        }

    try:
        contents = read_text(path)
    except OSError as exc:
        return {
            "artifact_ok": False,
            "value": "fail",
            "detail": f"unreadable artifact: {exc}",
            "blockers": ["invalid_artifact:wrong_root_preflight"],
        }

    status_value: str | None = None
    inline_detail = ""
    bullet_details: list[str] = []
    collecting_bullets = False

    for raw_line in contents.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("status="):
            status_value = line.split("=", 1)[1].strip()
            collecting_bullets = False
        elif line.startswith("details="):
            inline_detail = line.split("=", 1)[1].strip()
            collecting_bullets = False
        elif line == "details:":
            collecting_bullets = True
        elif collecting_bullets and line.startswith("- "):
            bullet_details.append(line[2:].strip())

    if status_value not in {"PASS", "FAIL"}:
        return {
            "artifact_ok": False,
            "value": "fail",
            "detail": "malformed artifact: expected status=PASS or status=FAIL",
            "blockers": ["invalid_artifact:wrong_root_preflight"],
        }

    if status_value == "PASS":
        return {
            "artifact_ok": True,
            "value": "pass",
            "detail": inline_detail or "wrong-root preflight passed",
            "blockers": [],
        }

    failure_detail = inline_detail or "; ".join(bullet_details) or "wrong-root preflight reported blocking issues"
    return {
        "artifact_ok": True,
        "value": "fail",
        "detail": failure_detail,
        "blockers": ["wrong_root_preflight_failed"],
    }


def parse_status_artifact(path: Path, artifact_id: str) -> dict[str, Any]:
    if not path.is_file():
        return {
            "artifact_ok": False,
            "value": "fail",
            "detail": f"missing required artifact: {path.name}",
            "payload": None,
            "blockers": [f"missing_artifact:{artifact_id}"],
        }

    try:
        payload = read_json_object(path)
    except OSError as exc:
        return {
            "artifact_ok": False,
            "value": "fail",
            "detail": f"unreadable artifact: {exc}",
            "payload": None,
            "blockers": [f"invalid_artifact:{artifact_id}"],
        }
    except (ValueError, json.JSONDecodeError) as exc:
        return {
            "artifact_ok": False,
            "value": "fail",
            "detail": f"malformed artifact: {exc}",
            "payload": None,
            "blockers": [f"invalid_artifact:{artifact_id}"],
        }

    status_value = payload.get("status")
    checks = payload.get("checks")
    if status_value not in {"pass", "fail"}:
        return {
            "artifact_ok": False,
            "value": "fail",
            "detail": "malformed artifact: expected top-level status=pass|fail",
            "payload": None,
            "blockers": [f"invalid_artifact:{artifact_id}"],
        }
    if not isinstance(checks, list) or not checks:
        return {
            "artifact_ok": False,
            "value": "fail",
            "detail": "malformed artifact: expected a non-empty checks array",
            "payload": None,
            "blockers": [f"invalid_artifact:{artifact_id}"],
        }

    return {
        "artifact_ok": True,
        "value": status_value,
        "detail": f"status={status_value}",
        "payload": payload,
        "blockers": [f"{artifact_id}_failed"] if status_value == "fail" else [],
    }


def parse_field_artifact(path: Path, artifact_id: str, field_name: str, allowed_values: set[str]) -> dict[str, Any]:
    if not path.is_file():
        return {
            "artifact_ok": False,
            "value": "invalid",
            "detail": f"missing required artifact: {path.name}",
            "payload": None,
            "blockers": [f"missing_artifact:{artifact_id}"],
        }

    try:
        payload = read_json_object(path)
    except OSError as exc:
        return {
            "artifact_ok": False,
            "value": "invalid",
            "detail": f"unreadable artifact: {exc}",
            "payload": None,
            "blockers": [f"invalid_artifact:{artifact_id}"],
        }
    except (ValueError, json.JSONDecodeError) as exc:
        return {
            "artifact_ok": False,
            "value": "invalid",
            "detail": f"malformed artifact: {exc}",
            "payload": None,
            "blockers": [f"invalid_artifact:{artifact_id}"],
        }

    value = payload.get(field_name)
    if value not in allowed_values:
        return {
            "artifact_ok": False,
            "value": "invalid",
            "detail": f"malformed artifact: expected {field_name} in {sorted(allowed_values)}",
            "payload": None,
            "blockers": [f"invalid_artifact:{artifact_id}"],
        }

    blockers: list[str] = []
    if artifact_id == "validation_report" and value != "pass":
        blockers.append("validation_report_failed")
    elif artifact_id == "admission_decision" and value != "approved":
        blockers.append(f"admission_decision_{value}")
    elif artifact_id == "placement_decision" and value != "approved":
        blockers.append(f"placement_decision_{value}")
    elif artifact_id == "apply_plan" and value != "ready":
        blockers.append(f"apply_plan_{value}")

    return {
        "artifact_ok": True,
        "value": value,
        "detail": f"{field_name}={value}",
        "payload": payload,
        "blockers": blockers,
    }


def parse_run_meta(path: Path, fallback_run_id: str) -> dict[str, Any]:
    if not path.is_file():
        return {
            "artifact_ok": False,
            "run_id": fallback_run_id,
            "detail": f"missing required artifact: {path.name}",
            "payload": None,
            "blockers": ["missing_artifact:run_meta"],
        }

    try:
        payload = read_json_object(path)
    except OSError as exc:
        return {
            "artifact_ok": False,
            "run_id": fallback_run_id,
            "detail": f"unreadable artifact: {exc}",
            "payload": None,
            "blockers": ["invalid_artifact:run_meta"],
        }
    except (ValueError, json.JSONDecodeError) as exc:
        return {
            "artifact_ok": False,
            "run_id": fallback_run_id,
            "detail": f"malformed artifact: {exc}",
            "payload": None,
            "blockers": ["invalid_artifact:run_meta"],
        }

    run_id = payload.get("run_id")
    if not isinstance(run_id, str) or not run_id:
        return {
            "artifact_ok": False,
            "run_id": fallback_run_id,
            "detail": "malformed artifact: run_meta.json must contain a non-empty run_id",
            "payload": None,
            "blockers": ["invalid_artifact:run_meta"],
        }

    return {
        "artifact_ok": True,
        "run_id": run_id,
        "detail": "run_meta loaded",
        "payload": payload,
        "blockers": [],
    }


def summarize_handoff(
    preflight: dict[str, Any],
    contracts: dict[str, Any],
    policy: dict[str, Any],
    smoke: dict[str, Any],
    validation: dict[str, Any],
    admission: dict[str, Any],
    placement: dict[str, Any],
    apply_plan: dict[str, Any],
    conformance_status: str,
) -> dict[str, str]:
    return {
        "wrong_root_preflight": preflight["value"],
        "contracts_validation": contracts["value"],
        "policy_validation": policy["value"],
        "smoke_validation": smoke["value"],
        "conformance_validation": conformance_status,
        "validation_report": validation["value"],
        "admission_decision": admission["value"],
        "placement_decision": placement["value"],
        "apply_plan": apply_plan["value"],
    }


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: run_phase2_conformance.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve()
    run_dir = Path(sys.argv[2]).resolve()
    fallback_run_id = run_dir.name
    checks_dir = run_dir / "checks"
    runtime_ready_dir = run_dir / "output" / "runtime-ready"
    checks_dir.mkdir(parents=True, exist_ok=True)
    conformance_path = checks_dir / "conformance_validation.json"
    handoff_path = run_dir / "handoff_ready.json"

    recorder = CheckRecorder(fallback_run_id)
    handoff_payload: dict[str, Any] | None = None

    try:
        run_meta = parse_run_meta(run_dir / REQUIRED_JSON_ARTIFACTS["run_meta"], fallback_run_id)
        recorder.run_id = run_meta["run_id"]
        run_id = recorder.run_id

        preflight = parse_preflight(run_dir / REQUIRED_TEXT_ARTIFACTS["wrong_root_preflight"])
        contracts = parse_status_artifact(run_dir / REQUIRED_JSON_ARTIFACTS["contracts_validation"], "contracts_validation")
        policy = parse_status_artifact(run_dir / REQUIRED_JSON_ARTIFACTS["policy_validation"], "policy_validation")
        smoke = parse_status_artifact(run_dir / REQUIRED_JSON_ARTIFACTS["smoke_validation"], "smoke_validation")
        validation = parse_field_artifact(
            run_dir / REQUIRED_JSON_ARTIFACTS["validation_report"],
            "validation_report",
            "status",
            {"pass", "fail"},
        )
        admission = parse_field_artifact(
            run_dir / REQUIRED_JSON_ARTIFACTS["admission_decision"],
            "admission_decision",
            "decision",
            {"approved", "rejected", "needs_changes"},
        )
        placement = parse_field_artifact(
            run_dir / REQUIRED_JSON_ARTIFACTS["placement_decision"],
            "placement_decision",
            "decision",
            {"approved", "rejected", "needs_changes"},
        )
        apply_plan = parse_field_artifact(
            run_dir / REQUIRED_JSON_ARTIFACTS["apply_plan"],
            "apply_plan",
            "status",
            {"ready", "blocked", "draft"},
        )

        parse_checks = [
            ("artifacts.run_meta.parse", run_meta, repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["run_meta"])),
            (
                "artifacts.wrong_root_preflight.parse",
                preflight,
                repo_rel(repo_root, run_dir / REQUIRED_TEXT_ARTIFACTS["wrong_root_preflight"]),
            ),
            (
                "artifacts.contracts_validation.parse",
                contracts,
                repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["contracts_validation"]),
            ),
            (
                "artifacts.policy_validation.parse",
                policy,
                repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["policy_validation"]),
            ),
            (
                "artifacts.smoke_validation.parse",
                smoke,
                repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["smoke_validation"]),
            ),
            (
                "artifacts.validation_report.parse",
                validation,
                repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["validation_report"]),
            ),
            (
                "artifacts.admission_decision.parse",
                admission,
                repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["admission_decision"]),
            ),
            (
                "artifacts.placement_decision.parse",
                placement,
                repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["placement_decision"]),
            ),
            ("artifacts.apply_plan.parse", apply_plan, repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["apply_plan"])),
        ]

        for check_name, state, source_ref in parse_checks:
            if state["artifact_ok"]:
                recorder.pass_check(
                    check_name,
                    "Required artifact is present and parseable.",
                    source_refs=[source_ref],
                    actual="parseable",
                )
            else:
                recorder.fail_check(
                    check_name,
                    state["detail"],
                    source_refs=[source_ref],
                    expected="present and parseable artifact",
                    actual="missing or invalid",
                )

        state_checks = [
            ("upstream.wrong_root_preflight.state", preflight, "pass", repo_rel(repo_root, run_dir / REQUIRED_TEXT_ARTIFACTS["wrong_root_preflight"])),
            (
                "upstream.contracts_validation.state",
                contracts,
                "pass",
                repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["contracts_validation"]),
            ),
            (
                "upstream.policy_validation.state",
                policy,
                "pass",
                repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["policy_validation"]),
            ),
            (
                "upstream.smoke_validation.state",
                smoke,
                "pass",
                repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["smoke_validation"]),
            ),
            (
                "decisions.validation_report.state",
                validation,
                "pass",
                repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["validation_report"]),
            ),
            (
                "decisions.admission_decision.state",
                admission,
                "approved",
                repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["admission_decision"]),
            ),
            (
                "decisions.placement_decision.state",
                placement,
                "approved",
                repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["placement_decision"]),
            ),
            (
                "decisions.apply_plan.state",
                apply_plan,
                "ready",
                repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["apply_plan"]),
            ),
        ]

        for check_name, state, expected_value, source_ref in state_checks:
            if state["value"] == expected_value:
                recorder.pass_check(
                    check_name,
                    f"Artifact state matches expected {expected_value}.",
                    source_refs=[source_ref],
                    expected=expected_value,
                    actual=state["value"],
                )
            else:
                recorder.fail_check(
                    check_name,
                    f"Artifact state is not handoff-ready: {state['detail']}",
                    source_refs=[source_ref],
                    expected=expected_value,
                    actual=state["value"],
                )

        apply_plan_payload = apply_plan.get("payload")
        apply_plan_source_ref = repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["apply_plan"])
        if not isinstance(apply_plan_payload, dict):
            recorder.fail_check(
                "apply_plan.steps.non_empty",
                "Cannot verify apply_plan steps because apply_plan.json is unavailable or invalid.",
                source_refs=[apply_plan_source_ref],
                expected="non-empty steps array",
                actual="unavailable",
            )
            recorder.fail_check(
                "apply_plan.source_refs.repo_relative",
                "Cannot verify source_ref paths because apply_plan.json is unavailable or invalid.",
                source_refs=[apply_plan_source_ref],
                expected="non-empty repo-relative source_ref paths",
                actual="unavailable",
            )
            recorder.fail_check(
                "apply_plan.runtime_ready_targets.exist",
                "Cannot verify target_path presence because apply_plan.json is unavailable or invalid.",
                source_refs=[apply_plan_source_ref, repo_rel(repo_root, runtime_ready_dir)],
                expected="existing target_path files under runtime-ready/",
                actual="unavailable",
            )
        else:
            steps = apply_plan_payload.get("steps")
            if isinstance(steps, list) and steps:
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

            invalid_source_refs: list[str] = []
            present_targets: list[str] = []
            missing_targets: list[str] = []
            ignored_targets: list[str] = []
            runtime_ready_source_ref = repo_rel(repo_root, runtime_ready_dir)
            for index, step in enumerate(steps):
                if not isinstance(step, dict):
                    invalid_source_refs.append(f"<invalid-step:{index}>")
                    continue
                source_ref = step.get("source_ref")
                if not is_non_empty_repo_relative_path(source_ref):
                    invalid_source_refs.append(str(source_ref))

                kind = step.get("kind")
                if kind not in {"copy", "render"}:
                    continue
                target_path = step.get("target_path")
                if not is_non_empty_repo_relative_path(target_path):
                    missing_targets.append(f"<invalid-target:{index}>")
                    continue
                target_abs = repo_root / target_path
                if is_under(target_abs, runtime_ready_dir):
                    if target_abs.exists():
                        present_targets.append(target_path)
                    else:
                        missing_targets.append(target_path)
                else:
                    ignored_targets.append(target_path)

            if invalid_source_refs:
                recorder.fail_check(
                    "apply_plan.source_refs.repo_relative",
                    "One or more apply_plan source_ref values are missing, empty, absolute, or escape the repo root.",
                    source_refs=[apply_plan_source_ref],
                    expected="non-empty repo-relative source_ref paths",
                    actual=sorted(invalid_source_refs),
                )
            else:
                recorder.pass_check(
                    "apply_plan.source_refs.repo_relative",
                    "All apply_plan source_ref values are non-empty repo-relative paths.",
                    source_refs=[apply_plan_source_ref],
                    actual="all source_ref values are repo-relative",
                )

            if missing_targets:
                recorder.fail_check(
                    "apply_plan.runtime_ready_targets.exist",
                    "One or more copy/render target_path entries under runtime-ready/ are missing.",
                    source_refs=[apply_plan_source_ref, runtime_ready_source_ref],
                    expected="existing target_path files under runtime-ready/",
                    actual={
                        "present": sorted(present_targets),
                        "missing": sorted(missing_targets),
                        "ignored": sorted(ignored_targets),
                    },
                )
            else:
                recorder.pass_check(
                    "apply_plan.runtime_ready_targets.exist",
                    "All copy/render target_path entries under runtime-ready/ exist.",
                    source_refs=[apply_plan_source_ref, runtime_ready_source_ref],
                    actual={
                        "present": sorted(present_targets),
                        "ignored": sorted(ignored_targets),
                    },
                )

        package_paths = {name: runtime_ready_dir / name for name in REQUIRED_RUNTIME_READY_FILES}
        present_package_files = sorted(name for name, path in package_paths.items() if path.is_file())
        missing_package_files = sorted(name for name, path in package_paths.items() if not path.is_file())
        package_source_refs = [repo_rel(repo_root, path) for path in package_paths.values()]
        if missing_package_files:
            recorder.fail_check(
                "runtime_ready.required_files_present",
                "Rendered runtime-ready package is missing one or more required handoff files.",
                source_refs=package_source_refs,
                expected=sorted(REQUIRED_RUNTIME_READY_FILES),
                actual={"present": present_package_files, "missing": missing_package_files},
            )
        else:
            recorder.pass_check(
                "runtime_ready.required_files_present",
                "Rendered runtime-ready package contains the required handoff files.",
                source_refs=package_source_refs,
                expected=sorted(REQUIRED_RUNTIME_READY_FILES),
                actual=present_package_files,
            )

        placement_source_ref = repo_rel(repo_root, run_dir / REQUIRED_JSON_ARTIFACTS["placement_decision"])
        placement_payload = placement.get("payload")
        if not isinstance(placement_payload, dict):
            recorder.fail_check(
                "placement.runtime_ready_not_artifact",
                "Cannot verify placement semantics because placement_decision.json is unavailable or invalid.",
                source_refs=[placement_source_ref],
                expected="logical placement target outside operations/harness-phase2/runs/",
                actual="unavailable",
            )
        else:
            target_path = placement_payload.get("target_path")
            target_layer = placement_payload.get("target_layer")
            runtime_ready_is_artifact = False
            if isinstance(target_path, str):
                if target_path.startswith("operations/harness-phase2/runs/") or "runtime-ready/" in target_path:
                    runtime_ready_is_artifact = True
            if target_layer in {"runtime_ready", "phase2_run_output"}:
                runtime_ready_is_artifact = True

            if runtime_ready_is_artifact:
                recorder.fail_check(
                    "placement.runtime_ready_not_artifact",
                    "runtime-ready/ must remain a special Phase 2 render output, not a placement artifact target.",
                    source_refs=[placement_source_ref],
                    expected="logical future placement target outside runtime-ready/",
                    actual={"target_layer": target_layer, "target_path": target_path},
                )
            else:
                recorder.pass_check(
                    "placement.runtime_ready_not_artifact",
                    "Placement semantics keep runtime-ready/ outside placement artifact targeting.",
                    source_refs=[placement_source_ref],
                    actual={"target_layer": target_layer, "target_path": target_path},
                )

        if not recorder.checks:
            recorder.fail_check(
                "conformance.no_checks_recorded",
                "Conformance validator did not record any checks.",
                source_refs=[],
                expected="non-empty checks array",
                actual="empty",
            )

        conformance_report = recorder.build_report()
        conformance_status = conformance_report["status"]

        blocker_set: set[str] = set()
        for state in (run_meta, preflight, contracts, policy, smoke, validation, admission, placement, apply_plan):
            blocker_set.update(item for item in state["blockers"] if item)
        for check in recorder.checks:
            if check["status"] != "fail":
                continue
            blocker = CONFORMANCE_BLOCKER_MAP.get(check["name"])
            if blocker:
                blocker_set.add(blocker)
        if conformance_status == "fail":
            blocker_set.add("conformance_validation_failed")

        handoff_status = "ready"
        if conformance_status != "pass":
            handoff_status = "not_ready"

        handoff_payload = {
            "run_id": run_id,
            "generated_at": now_utc(),
            "engine_mode": "scaffold",
            "evaluation_mode": "static-v1",
            "status": handoff_status,
            "handoff_target": "phase3_execution_owner",
            "summary": summarize_handoff(
                preflight,
                contracts,
                policy,
                smoke,
                validation,
                admission,
                placement,
                apply_plan,
                conformance_status,
            ),
            "blockers": sorted(item for item in blocker_set if item),
        }

    except Exception as exc:  # noqa: BLE001
        recorder.fail_check(
            "conformance.unhandled_exception",
            f"Unhandled conformance exception: {exc}",
            source_refs=[],
            actual=type(exc).__name__,
        )
        conformance_report = recorder.build_report()
        handoff_payload = {
            "run_id": recorder.run_id,
            "generated_at": now_utc(),
            "engine_mode": "scaffold",
            "evaluation_mode": "static-v1",
            "status": "not_ready",
            "handoff_target": "phase3_execution_owner",
            "summary": {
                "wrong_root_preflight": "fail",
                "contracts_validation": "fail",
                "policy_validation": "fail",
                "smoke_validation": "fail",
                "conformance_validation": "fail",
                "validation_report": "fail",
                "admission_decision": "invalid",
                "placement_decision": "invalid",
                "apply_plan": "invalid",
            },
            "blockers": ["conformance_unhandled_exception", "conformance_validation_failed"],
        }
    else:
        conformance_report = recorder.build_report()

    write_json(conformance_path, conformance_report)
    if handoff_payload is None:
        handoff_payload = {
            "run_id": recorder.run_id,
            "generated_at": now_utc(),
            "engine_mode": "scaffold",
            "evaluation_mode": "static-v1",
            "status": "not_ready",
            "handoff_target": "phase3_execution_owner",
            "summary": {
                "wrong_root_preflight": "fail",
                "contracts_validation": "fail",
                "policy_validation": "fail",
                "smoke_validation": "fail",
                "conformance_validation": "fail",
                "validation_report": "fail",
                "admission_decision": "invalid",
                "placement_decision": "invalid",
                "apply_plan": "invalid",
            },
            "blockers": ["handoff_payload_missing", "conformance_validation_failed"],
        }
    write_json(handoff_path, handoff_payload)

    return 0 if conformance_report["status"] == "pass" and handoff_payload["status"] == "ready" else 1


if __name__ == "__main__":
    raise SystemExit(main())
