#!/usr/bin/env python3
"""Emit machine-readable and human-readable Phase 2 operator reports."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


CHECK_ARTIFACTS = {
    "wrong_root_preflight": "checks/wrong_root_preflight.txt",
    "contracts_validation": "checks/contracts_validation.json",
    "policy_validation": "checks/policy_validation.json",
    "smoke_validation": "checks/smoke_validation.json",
}
DECISION_ARTIFACTS = {
    "validation_report": "validation_report.json",
    "admission_decision": "admission_decision.json",
    "placement_decision": "placement_decision.json",
    "apply_plan": "apply_plan.json",
    "run_meta": "run_meta.json",
}


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def normalize_text(text: str) -> str:
    return " ".join(text.split()) or "detail unavailable"


def read_text(path: Path) -> str:
    with path.open("r", encoding="utf-8") as handle:
        return handle.read()


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level JSON value must be an object")
    return payload


def parse_preflight(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {
            "artifact_ok": False,
            "status": "fail",
            "detail": f"missing required artifact: {path.name}",
            "blockers": ["missing_artifact:wrong_root_preflight"],
        }

    try:
        contents = read_text(path)
    except OSError as exc:
        return {
            "artifact_ok": False,
            "status": "fail",
            "detail": normalize_text(f"unreadable artifact: {exc}"),
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
            "status": "fail",
            "detail": "malformed wrong_root_preflight.txt: expected status=PASS or status=FAIL",
            "blockers": ["invalid_artifact:wrong_root_preflight"],
        }

    if status_value == "PASS":
        return {
            "artifact_ok": True,
            "status": "pass",
            "detail": normalize_text(inline_detail or "wrong-root preflight passed"),
            "blockers": [],
        }

    failure_detail = inline_detail or "; ".join(bullet_details) or "wrong-root preflight reported blocking issues"
    return {
        "artifact_ok": True,
        "status": "fail",
        "detail": normalize_text(failure_detail),
        "blockers": ["wrong_root_preflight_failed"],
    }


def parse_status_report(path: Path, artifact_id: str) -> dict[str, Any]:
    if not path.is_file():
        return {
            "artifact_ok": False,
            "status": "fail",
            "detail": f"missing required artifact: {path.name}",
            "payload": None,
            "blockers": [f"missing_artifact:{artifact_id}"],
        }

    try:
        payload = read_json(path)
    except OSError as exc:
        return {
            "artifact_ok": False,
            "status": "fail",
            "detail": normalize_text(f"unreadable artifact: {exc}"),
            "payload": None,
            "blockers": [f"invalid_artifact:{artifact_id}"],
        }
    except (ValueError, json.JSONDecodeError) as exc:
        return {
            "artifact_ok": False,
            "status": "fail",
            "detail": normalize_text(f"malformed artifact: {exc}"),
            "payload": None,
            "blockers": [f"invalid_artifact:{artifact_id}"],
        }

    status_value = payload.get("status")
    if status_value not in {"pass", "fail"}:
        return {
            "artifact_ok": False,
            "status": "fail",
            "detail": "malformed artifact: expected top-level status=pass|fail",
            "payload": None,
            "blockers": [f"invalid_artifact:{artifact_id}"],
        }

    detail = f"status={status_value}"
    failing_checks: list[str] = []
    checks = payload.get("checks")
    if isinstance(checks, list):
        failing_checks = sorted(
            check.get("name")
            for check in checks
            if isinstance(check, dict) and check.get("status") == "fail" and isinstance(check.get("name"), str)
        )
    if failing_checks:
        detail = f"{detail}; failing_checks={','.join(failing_checks)}"

    blockers = [f"{artifact_id}_failed"] if status_value == "fail" else []
    return {
        "artifact_ok": True,
        "status": status_value,
        "detail": normalize_text(detail),
        "payload": payload,
        "blockers": blockers,
    }


def parse_decision(path: Path, artifact_id: str, field_name: str, allowed_values: set[str]) -> dict[str, Any]:
    if not path.is_file():
        return {
            "artifact_ok": False,
            "value": "missing",
            "detail": f"missing required artifact: {path.name}",
            "payload": None,
            "blockers": [f"missing_artifact:{artifact_id}"],
        }

    try:
        payload = read_json(path)
    except OSError as exc:
        return {
            "artifact_ok": False,
            "value": "invalid",
            "detail": normalize_text(f"unreadable artifact: {exc}"),
            "payload": None,
            "blockers": [f"invalid_artifact:{artifact_id}"],
        }
    except (ValueError, json.JSONDecodeError) as exc:
        return {
            "artifact_ok": False,
            "value": "invalid",
            "detail": normalize_text(f"malformed artifact: {exc}"),
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
    if artifact_id == "admission_decision" and value != "approved":
        blockers.append(f"admission_decision_{value}")
    elif artifact_id == "placement_decision" and value != "approved":
        blockers.append(f"placement_decision_{value}")
    elif artifact_id == "apply_plan" and value != "ready":
        blockers.append(f"apply_plan_{value}")
    elif artifact_id == "validation_report" and value != "pass":
        blockers.append("validation_report_failed")

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
            "blockers": ["missing_artifact:run_meta"],
        }

    try:
        payload = read_json(path)
    except OSError as exc:
        return {
            "artifact_ok": False,
            "run_id": fallback_run_id,
            "detail": normalize_text(f"unreadable artifact: {exc}"),
            "blockers": ["invalid_artifact:run_meta"],
        }
    except (ValueError, json.JSONDecodeError) as exc:
        return {
            "artifact_ok": False,
            "run_id": fallback_run_id,
            "detail": normalize_text(f"malformed artifact: {exc}"),
            "blockers": ["invalid_artifact:run_meta"],
        }

    run_id = payload.get("run_id")
    if not isinstance(run_id, str) or not run_id:
        return {
            "artifact_ok": False,
            "run_id": fallback_run_id,
            "detail": "malformed artifact: run_meta.json must contain a non-empty run_id",
            "blockers": ["invalid_artifact:run_meta"],
        }
    return {
        "artifact_ok": True,
        "run_id": run_id,
        "detail": "run_meta loaded",
        "blockers": [],
    }


def extract_runtime_ready_summary(smoke_payload: dict[str, Any] | None) -> dict[str, Any]:
    summary = {
        "status": "unknown",
        "present_files": [],
        "missing_files": [],
    }
    if smoke_payload is None:
        return summary

    status_value = smoke_payload.get("status")
    if status_value in {"pass", "fail"}:
        summary["status"] = status_value

    checks = smoke_payload.get("checks")
    if not isinstance(checks, list):
        return summary

    for check in checks:
        if not isinstance(check, dict):
            continue
        if check.get("name") == "runtime_ready.required_files_present":
            actual = check.get("actual")
            if isinstance(actual, dict):
                present = actual.get("present")
                missing = actual.get("missing")
                if isinstance(present, list):
                    summary["present_files"] = sorted(item for item in present if isinstance(item, str))
                elif isinstance(actual, list):
                    summary["present_files"] = sorted(item for item in actual if isinstance(item, str))
                if isinstance(missing, list):
                    summary["missing_files"] = sorted(item for item in missing if isinstance(item, str))
            elif isinstance(actual, list):
                summary["present_files"] = sorted(item for item in actual if isinstance(item, str))
    return summary


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: emit_phase2_report.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve()
    run_dir = Path(sys.argv[2]).resolve()
    fallback_run_id = run_dir.name
    report_json_path = run_dir / "report.json"
    report_md_path = run_dir / "report.md"

    overall_status = "fail"
    blockers: set[str] = set()

    try:
        run_meta = parse_run_meta(run_dir / DECISION_ARTIFACTS["run_meta"], fallback_run_id)
        run_id = run_meta["run_id"]
        blockers.update(run_meta["blockers"])

        preflight = parse_preflight(run_dir / CHECK_ARTIFACTS["wrong_root_preflight"])
        contracts = parse_status_report(run_dir / CHECK_ARTIFACTS["contracts_validation"], "contracts_validation")
        policy = parse_status_report(run_dir / CHECK_ARTIFACTS["policy_validation"], "policy_validation")
        smoke = parse_status_report(run_dir / CHECK_ARTIFACTS["smoke_validation"], "smoke_validation")
        validation = parse_decision(
            run_dir / DECISION_ARTIFACTS["validation_report"],
            "validation_report",
            "status",
            {"pass", "fail"},
        )
        admission = parse_decision(
            run_dir / DECISION_ARTIFACTS["admission_decision"],
            "admission_decision",
            "decision",
            {"approved", "rejected", "needs_changes"},
        )
        placement = parse_decision(
            run_dir / DECISION_ARTIFACTS["placement_decision"],
            "placement_decision",
            "decision",
            {"approved", "rejected", "needs_changes"},
        )
        apply_plan = parse_decision(
            run_dir / DECISION_ARTIFACTS["apply_plan"],
            "apply_plan",
            "status",
            {"ready", "blocked", "draft"},
        )

        for state in (preflight, contracts, policy, smoke, validation, admission, placement, apply_plan):
            blockers.update(state["blockers"])

        if isinstance(admission.get("payload"), dict):
            blockers.update(
                item
                for item in admission["payload"].get("blockers", [])
                if isinstance(item, str) and item
            )
        if isinstance(apply_plan.get("payload"), dict):
            blockers.update(
                item
                for item in apply_plan["payload"].get("blockers", [])
                if isinstance(item, str) and item
            )

        runtime_ready_summary = extract_runtime_ready_summary(smoke.get("payload"))

        summary = {
            "wrong_root_preflight": preflight["status"],
            "contracts_validation": contracts["status"],
            "policy_validation": policy["status"],
            "smoke_validation": smoke["status"],
            "validation_report": validation["value"],
            "admission_decision": admission["value"],
            "placement_decision": placement["value"],
            "apply_plan": apply_plan["value"],
            "runtime_ready_package": runtime_ready_summary,
        }

        if (
            preflight["status"] == "pass"
            and contracts["status"] == "pass"
            and policy["status"] == "pass"
            and smoke["status"] == "pass"
            and validation["value"] == "pass"
            and admission["value"] == "approved"
            and placement["value"] == "approved"
            and apply_plan["value"] == "ready"
            and run_meta["artifact_ok"]
        ):
            overall_status = "pass"

        sorted_blockers = sorted(item for item in blockers if item)

        report_json = {
            "run_id": run_id,
            "generated_at": now_utc(),
            "engine_mode": "scaffold",
            "evaluation_mode": "static-v1",
            "overall_status": overall_status,
            "summary": summary,
            "blockers": sorted_blockers,
        }

        block_lines = sorted_blockers if sorted_blockers else ["none"]
        present_files = runtime_ready_summary["present_files"]
        missing_files = runtime_ready_summary["missing_files"]
        present_line = ", ".join(present_files) if present_files else "none recorded"
        missing_line = ", ".join(missing_files) if missing_files else "none"

        report_md = "\n".join(
            [
                "# Run",
                f"- run_id: `{run_id}`",
                f"- overall_status: `{overall_status}`",
                "",
                "## Check summary",
                f"- wrong_root_preflight: `{preflight['status']}`",
                f"- contracts_validation: `{contracts['status']}`",
                f"- policy_validation: `{policy['status']}`",
                "",
                "## Decision summary",
                f"- validation_report: `{validation['value']}`",
                f"- admission_decision: `{admission['value']}`",
                f"- placement_decision: `{placement['value']}`",
                f"- apply_plan: `{apply_plan['value']}`",
                "",
                "## Smoke summary",
                f"- smoke_validation: `{smoke['status']}`",
                f"- runtime_ready_package_status: `{runtime_ready_summary['status']}`",
                "",
                "## Blockers",
                *[f"- {item}" for item in block_lines],
                "",
                "## Runtime-ready package summary",
                f"- present_files: {present_line}",
                f"- missing_files: {missing_line}",
                "",
            ]
        )

    except Exception as exc:  # noqa: BLE001
        run_id = fallback_run_id
        overall_status = "fail"
        sorted_blockers = ["report_emitter_unhandled_exception"]
        report_json = {
            "run_id": run_id,
            "generated_at": now_utc(),
            "engine_mode": "scaffold",
            "evaluation_mode": "static-v1",
            "overall_status": "fail",
            "summary": {
                "wrong_root_preflight": "unknown",
                "contracts_validation": "unknown",
                "policy_validation": "unknown",
                "smoke_validation": "unknown",
                "validation_report": "unknown",
                "admission_decision": "unknown",
                "placement_decision": "unknown",
                "apply_plan": "unknown",
                "runtime_ready_package": {
                    "status": "unknown",
                    "present_files": [],
                    "missing_files": [],
                },
            },
            "blockers": sorted_blockers,
        }
        report_md = "\n".join(
            [
                "# Run",
                f"- run_id: `{run_id}`",
                "- overall_status: `fail`",
                "",
                "## Check summary",
                "- report emitter hit an unhandled exception.",
                "",
                "## Decision summary",
                "- validation_report: `unknown`",
                "- admission_decision: `unknown`",
                "- placement_decision: `unknown`",
                "- apply_plan: `unknown`",
                "",
                "## Smoke summary",
                "- smoke_validation: `unknown`",
                "- runtime_ready_package_status: `unknown`",
                "",
                "## Blockers",
                "- report_emitter_unhandled_exception",
                "",
                "## Runtime-ready package summary",
                "- present_files: none recorded",
                "- missing_files: unknown",
                "",
            ]
        )

    with report_json_path.open("w", encoding="utf-8") as handle:
        json.dump(report_json, handle, indent=2)
        handle.write("\n")
    report_md_path.write_text(report_md, encoding="utf-8")

    return 0 if overall_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
