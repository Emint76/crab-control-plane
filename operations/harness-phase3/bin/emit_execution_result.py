#!/usr/bin/env python3
"""Emit the canonical Phase 3 execution_result.json surface."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


CHECK_ARTIFACTS = {
    "freeze_intake_validation": "checks/freeze_intake_validation.json",
    "pre_apply_validation": "checks/pre_apply_validation.json",
    "runtime_ready_reverify": "checks/runtime_ready_reverify.json",
    "post_apply_validation": "checks/post_apply_validation.json",
}


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json_object(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level JSON value must be an object")
    return payload


def parse_check_artifact(path: Path, artifact_id: str) -> dict[str, Any]:
    if not path.is_file():
        return {
            "status": "unknown",
            "detail": f"missing required artifact: {path.name}",
            "blockers": [f"missing_artifact:{artifact_id}"],
        }
    try:
        payload = read_json_object(path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return {
            "status": "unknown",
            "detail": f"invalid artifact: {exc}",
            "blockers": [f"invalid_artifact:{artifact_id}"],
        }

    status_value = payload.get("status")
    checks = payload.get("checks")
    if status_value not in {"pass", "fail"} or not isinstance(checks, list):
        return {
            "status": "unknown",
            "detail": "artifact missing valid status/checks fields",
            "blockers": [f"invalid_artifact:{artifact_id}"],
        }

    failing_checks = sorted(
        item.get("name")
        for item in checks
        if isinstance(item, dict) and item.get("status") == "fail" and isinstance(item.get("name"), str)
    )
    blockers = [f"{artifact_id}_failed"] if status_value == "fail" else []
    blockers.extend(failing_checks)
    return {
        "status": status_value,
        "detail": f"status={status_value}",
        "blockers": blockers,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repo_root")
    parser.add_argument("run_dir")
    parser.add_argument("--execute-apply-exit-status", required=True, type=int)
    args = parser.parse_args()

    run_dir = Path(args.run_dir).resolve(strict=False)
    run_id = run_dir.name
    output_path = run_dir / "execution_result.json"
    apply_log_path = run_dir / "logs" / "apply.log"

    parsed_checks = {
        artifact_id: parse_check_artifact(run_dir / rel_path, artifact_id)
        for artifact_id, rel_path in CHECK_ARTIFACTS.items()
    }

    execute_apply_status = "pass" if args.execute_apply_exit_status == 0 and apply_log_path.is_file() else "fail"
    execute_apply_detail = (
        "execute_apply returned 0 and apply.log is present."
        if execute_apply_status == "pass"
        else "execute_apply must return 0 and produce apply.log."
    )
    blockers: set[str] = set()
    for parsed in parsed_checks.values():
        blockers.update(item for item in parsed["blockers"] if item)
    if execute_apply_status != "pass":
        blockers.add("execute_apply_failed")

    summary = {
        "freeze_intake_validation": parsed_checks["freeze_intake_validation"]["status"],
        "pre_apply_validation": parsed_checks["pre_apply_validation"]["status"],
        "runtime_ready_reverify": parsed_checks["runtime_ready_reverify"]["status"],
        "execute_apply": execute_apply_status,
        "post_apply_validation": parsed_checks["post_apply_validation"]["status"],
    }
    details = {
        "freeze_intake_validation": parsed_checks["freeze_intake_validation"]["detail"],
        "pre_apply_validation": parsed_checks["pre_apply_validation"]["detail"],
        "runtime_ready_reverify": parsed_checks["runtime_ready_reverify"]["detail"],
        "execute_apply": execute_apply_detail,
        "post_apply_validation": parsed_checks["post_apply_validation"]["detail"],
    }

    overall_status = "pass"
    if any(value != "pass" for value in summary.values()):
        overall_status = "fail"

    payload = {
        "run_id": run_id,
        "generated_at": now_utc(),
        "engine_mode": "scaffold",
        "evaluation_mode": "phase3-static-v1",
        "overall_status": overall_status,
        "summary": summary,
        "details": details,
        "blockers": sorted(blockers),
    }
    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")

    return 0 if overall_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
