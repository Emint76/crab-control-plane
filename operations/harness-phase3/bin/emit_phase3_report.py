#!/usr/bin/env python3
"""Emit the canonical Phase 3 report surface with tolerant early-failure handling."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


CHECK_ARTIFACTS = {
    "freeze_intake_validation": "checks/freeze_intake_validation.json",
    "pre_apply_validation": "checks/pre_apply_validation.json",
    "runtime_ready_reverify": "checks/runtime_ready_reverify.json",
    "declared_scope_evidence": "checks/declared_scope_evidence.json",
    "post_apply_validation": "checks/post_apply_validation.json",
}

TIMESTAMP_FIELDS = [
    ("freeze_input_completed_at", "freeze_input_completed_at"),
    ("freeze_input_hash_completed_at", "freeze_input_hash_completed_at"),
    ("freeze_intake_validation_completed_at", "freeze_intake_validation_completed_at"),
    ("pre_apply_validation_completed_at", "pre_apply_validation_completed_at"),
    ("runtime_ready_reverify_completed_at", "runtime_ready_reverify_completed_at"),
    ("materialize_staging_completed_at", "materialize_staging_completed_at"),
    ("execute_apply_completed_at", "execute_apply_completed_at"),
    ("post_apply_validation_completed_at", "post_apply_validation_completed_at"),
]


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def normalize_text(value: str) -> str:
    return " ".join(value.split()) or "detail unavailable"


def read_json_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level JSON value must be an object")
    return payload


def read_state(path: Path) -> dict[str, str]:
    state: dict[str, str] = {}
    if not path.is_file():
        return state
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        state[key.strip()] = value.strip()
    return state


def parse_run_meta(path: Path, fallback_run_id: str) -> dict[str, Any]:
    try:
        payload = read_json_object(path)
    except (OSError, ValueError, json.JSONDecodeError):
        payload = {}
    run_id = payload.get("run_id") if isinstance(payload.get("run_id"), str) and payload.get("run_id") else fallback_run_id
    return {
        "run_id": run_id,
        "payload": payload,
        "artifact_ok": bool(payload),
    }


def parse_check_artifact(run_dir: Path, state: dict[str, str], step_key: str, artifact_id: str) -> dict[str, Any]:
    path = run_dir / CHECK_ARTIFACTS[artifact_id]
    if not path.is_file():
        if f"{step_key}_completed_at" not in state:
            return {"status": "not_reached", "detail": "step not reached", "blockers": []}
        return {"status": "unknown", "detail": "artifact missing after step execution", "blockers": [f"missing_artifact:{artifact_id}"]}
    try:
        payload = read_json_object(path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return {"status": "unknown", "detail": normalize_text(f"invalid artifact: {exc}"), "blockers": [f"invalid_artifact:{artifact_id}"]}
    status_value = payload.get("status")
    checks = payload.get("checks")
    if status_value not in {"pass", "fail"} or not isinstance(checks, list):
        return {"status": "unknown", "detail": "artifact missing valid status/checks fields", "blockers": [f"invalid_artifact:{artifact_id}"]}
    failing_checks = sorted(
        item.get("name")
        for item in checks
        if isinstance(item, dict) and item.get("status") == "fail" and isinstance(item.get("name"), str)
    )
    blockers = [f"{artifact_id}_failed"] if status_value == "fail" else []
    blockers.extend(failing_checks)
    return {"status": status_value, "detail": f"status={status_value}", "blockers": blockers}


def parse_run_dir_invariants(run_dir: Path) -> dict[str, Any]:
    artifact_id = "run_dir_invariants"
    path = run_dir / "checks" / "run_dir_invariants.json"
    if not path.is_file():
        return {"status": "unknown", "detail": "run-dir invariant check artifact missing", "blockers": [f"missing_artifact:{artifact_id}"]}
    try:
        payload = read_json_object(path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return {"status": "unknown", "detail": normalize_text(f"invalid artifact: {exc}"), "blockers": [f"invalid_artifact:{artifact_id}"]}
    status_value = payload.get("status")
    violations = payload.get("violations")
    if status_value not in {"pass", "fail"} or not isinstance(violations, list):
        return {"status": "unknown", "detail": "artifact missing valid status/violations fields", "blockers": [f"invalid_artifact:{artifact_id}"]}
    normalized_violations = sorted(item for item in violations if isinstance(item, str) and item)
    blockers = [f"run_dir_invariant:{item}" for item in normalized_violations]
    if status_value == "fail" and not blockers:
        blockers.append("run_dir_invariant_failed")
    detail = f"status={status_value}"
    if normalized_violations:
        detail = f"{detail}; violations={','.join(normalized_violations)}"
    return {"status": status_value, "detail": detail, "blockers": blockers}


def parse_non_artifact_step(state: dict[str, str], step_key: str, *, success_condition: bool, success_detail: str, fail_detail: str) -> dict[str, Any]:
    exit_key = f"{step_key}_exit_status"
    if exit_key not in state:
        return {"status": "not_reached", "detail": "step not reached", "blockers": []}
    if success_condition:
        return {"status": "pass", "detail": success_detail, "blockers": []}
    if state.get(exit_key) == "0":
        return {"status": "unknown", "detail": "step completed but required output is unavailable", "blockers": [f"missing_output:{step_key}"]}
    return {"status": "fail", "detail": fail_detail, "blockers": [f"{step_key}_failed"]}


def parse_execution_result(run_dir: Path, state: dict[str, str]) -> dict[str, Any]:
    path = run_dir / "execution_result.json"
    if not path.is_file():
        if "execution_result_completed_at" not in state:
            return {"status": "not_reached", "detail": "step not reached", "blockers": []}
        return {"status": "unknown", "detail": "execution_result.json missing after step execution", "blockers": ["missing_artifact:execution_result"]}
    try:
        payload = read_json_object(path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return {"status": "unknown", "detail": normalize_text(f"invalid artifact: {exc}"), "blockers": ["invalid_artifact:execution_result"]}
    status_value = payload.get("overall_status")
    blockers = payload.get("blockers")
    if status_value not in {"pass", "fail"} or not isinstance(blockers, list):
        return {"status": "unknown", "detail": "execution_result.json missing valid overall_status/blockers fields", "blockers": ["invalid_artifact:execution_result"]}
    derived_blockers = [item for item in blockers if isinstance(item, str) and item]
    if status_value == "fail":
        derived_blockers.append("execution_result_failed")
    return {"status": status_value, "detail": f"overall_status={status_value}", "blockers": sorted(set(derived_blockers))}


def clamp_monotonic(values: dict[str, str]) -> dict[str, str]:
    normalized: dict[str, str] = {}
    previous: str | None = None
    for key, value in values.items():
        if previous is not None and value < previous:
            value = previous
        normalized[key] = value
        previous = value
    return normalized


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: emit_phase3_report.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    run_dir = Path(sys.argv[2]).resolve(strict=False)
    fallback_run_id = run_dir.name
    report_json_path = run_dir / "report.json"
    report_md_path = run_dir / "report.md"
    timestamps_path = run_dir / "timestamps.json"
    state = read_state(run_dir / ".bundle_state.env")

    blockers: set[str] = set()
    report_run_id = fallback_run_id
    report_payload: dict[str, Any]
    report_md: str

    try:
        run_meta = parse_run_meta(run_dir / "run_meta.json", fallback_run_id)
        report_run_id = run_meta["run_id"]
        run_meta_payload = run_meta["payload"]

        run_dir_invariants = parse_run_dir_invariants(run_dir)
        freeze_input = parse_non_artifact_step(
            state,
            "freeze_input",
            success_condition=(run_dir / "input" / "runtime_ready_manifest.json").is_file()
            and (run_dir / "input" / "runtime_ready.sha256").is_file()
            and (run_dir / "input" / "execution_target.json").is_file(),
            success_detail="frozen Phase 2 intake artifacts are present",
            fail_detail="freeze input step failed",
        )
        freeze_input_hash = parse_non_artifact_step(
            state,
            "freeze_input_hash",
            success_condition=(run_dir / "input" / "input.sha256").is_file(),
            success_detail="input.sha256 is present",
            fail_detail="hash frozen input step failed",
        )
        freeze_intake_validation = parse_check_artifact(run_dir, state, "freeze_intake_validation", "freeze_intake_validation")
        pre_apply_validation = parse_check_artifact(run_dir, state, "pre_apply_validation", "pre_apply_validation")
        runtime_ready_reverify = parse_check_artifact(run_dir, state, "runtime_ready_reverify", "runtime_ready_reverify")
        materialize_staging = parse_non_artifact_step(
            state,
            "materialize_staging",
            success_condition=(run_dir / "staging" / "runtime-ready-applied").is_dir(),
            success_detail="canonical staging target is present",
            fail_detail="materialize staging step failed",
        )
        execute_apply = parse_non_artifact_step(
            state,
            "execute_apply",
            success_condition=state.get("execute_apply_exit_status") == "0" and (run_dir / "logs" / "apply.log").is_file(),
            success_detail="execute_apply completed and apply.log is present",
            fail_detail="execute_apply failed or apply.log is missing",
        )
        declared_scope_evidence = parse_check_artifact(run_dir, state, "declared_scope_evidence", "declared_scope_evidence")
        post_apply_validation = parse_check_artifact(run_dir, state, "post_apply_validation", "post_apply_validation")
        execution_result = parse_execution_result(run_dir, state)

        parsed_steps = {
            "run_dir_invariants": run_dir_invariants,
            "freeze_input": freeze_input,
            "freeze_input_hash": freeze_input_hash,
            "freeze_intake_validation": freeze_intake_validation,
            "pre_apply_validation": pre_apply_validation,
            "runtime_ready_reverify": runtime_ready_reverify,
            "materialize_staging": materialize_staging,
            "execute_apply": execute_apply,
            "declared_scope_evidence": declared_scope_evidence,
            "post_apply_validation": post_apply_validation,
            "execution_result": execution_result,
        }
        for parsed in parsed_steps.values():
            blockers.update(item for item in parsed["blockers"] if item)

        overall_status = "pass" if all(parsed["status"] == "pass" for parsed in parsed_steps.values()) else "fail"
        summary = {
            **{name: parsed["status"] for name, parsed in parsed_steps.items()},
            "phase2_run_ref": run_meta_payload.get("phase2_run_ref"),
            "phase2_runtime_ready_ref": run_meta_payload.get("phase2_runtime_ready_ref"),
            "target_runtime": run_meta_payload.get("target_runtime"),
            "target_kind": run_meta_payload.get("target_kind"),
            "target_ref": run_meta_payload.get("target_ref"),
            "apply_mode": run_meta_payload.get("apply_mode"),
            "approval_ref": run_meta_payload.get("approval_ref"),
        }
        details = {name: parsed["detail"] for name, parsed in parsed_steps.items()}

        report_payload = {
            "run_id": report_run_id,
            "generated_at": now_utc(),
            "engine_mode": "scaffold",
            "execution_mode": run_meta_payload.get("execution_mode", "staged-only"),
            "overall_status": overall_status,
            "summary": summary,
            "details": details,
            "blockers": sorted(blockers),
        }

        report_md = "\n".join(
            [
                "# Run",
                f"- run_id: `{report_run_id}`",
                f"- overall_status: `{overall_status}`",
                "",
                "## Target",
                f"- target_runtime: `{summary['target_runtime']}`",
                f"- target_kind: `{summary['target_kind']}`",
                f"- target_ref: `{summary['target_ref']}`",
                f"- apply_mode: `{summary['apply_mode']}`",
                f"- approval_ref: `{summary['approval_ref']}`",
                "",
                "## Step Summary",
                f"- run_dir_invariants: `{summary['run_dir_invariants']}`",
                f"- freeze_input: `{summary['freeze_input']}`",
                f"- freeze_input_hash: `{summary['freeze_input_hash']}`",
                f"- freeze_intake_validation: `{summary['freeze_intake_validation']}`",
                f"- pre_apply_validation: `{summary['pre_apply_validation']}`",
                f"- runtime_ready_reverify: `{summary['runtime_ready_reverify']}`",
                f"- materialize_staging: `{summary['materialize_staging']}`",
                f"- execute_apply: `{summary['execute_apply']}`",
                f"- declared_scope_evidence: `{summary['declared_scope_evidence']}`",
                f"- post_apply_validation: `{summary['post_apply_validation']}`",
                f"- execution_result: `{summary['execution_result']}`",
                "",
                "## Blockers",
                *([f"- {item}" for item in sorted(blockers)] if blockers else ["- none"]),
                "",
            ]
        )
    except Exception as exc:  # noqa: BLE001
        report_payload = {
            "run_id": report_run_id,
            "generated_at": now_utc(),
            "engine_mode": "scaffold",
            "execution_mode": "staged-only",
            "overall_status": "fail",
            "summary": {
                "run_dir_invariants": "unknown",
                "freeze_input": "unknown",
                "freeze_input_hash": "unknown",
                "freeze_intake_validation": "unknown",
                "pre_apply_validation": "unknown",
                "runtime_ready_reverify": "unknown",
                "materialize_staging": "unknown",
                "execute_apply": "unknown",
                "declared_scope_evidence": "unknown",
                "post_apply_validation": "unknown",
                "execution_result": "unknown",
                "phase2_run_ref": None,
                "phase2_runtime_ready_ref": None,
                "target_runtime": None,
                "target_kind": None,
                "target_ref": None,
                "apply_mode": None,
                "approval_ref": None,
            },
            "details": {"report": normalize_text(f"unhandled exception: {exc}")},
            "blockers": ["report_emitter_unhandled_exception"],
        }
        report_md = "\n".join(
            [
                "# Run",
                f"- run_id: `{report_run_id}`",
                "- overall_status: `fail`",
                "",
                "## Step Summary",
                "- report emitter hit an unhandled exception.",
                "",
                "## Blockers",
                "- report_emitter_unhandled_exception",
                "",
            ]
        )

    with report_json_path.open("w", encoding="utf-8") as handle:
        json.dump(report_payload, handle, indent=2)
        handle.write("\n")
    report_md_path.write_text(report_md, encoding="utf-8")

    started_at = state.get("started_at") or report_payload.get("generated_at") or now_utc()
    timestamp_values: dict[str, str] = {"started_at": started_at}
    for state_key, output_key in TIMESTAMP_FIELDS:
        value = state.get(state_key)
        if value:
            timestamp_values[output_key] = value
    if (run_dir / "execution_result.json").is_file():
        emitted_at = state.get("execution_result_emitted_at")
        if emitted_at:
            timestamp_values["execution_result_emitted_at"] = emitted_at
    finalized_at = now_utc()
    if finalized_at < started_at:
        finalized_at = started_at
    timestamp_values["finalized_at"] = finalized_at
    normalized_timestamps = clamp_monotonic(timestamp_values)

    timestamps_payload = {"run_id": report_run_id}
    timestamps_payload.update(normalized_timestamps)
    with timestamps_path.open("w", encoding="utf-8") as handle:
        json.dump(timestamps_payload, handle, indent=2)
        handle.write("\n")

    return 0 if report_payload["overall_status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
