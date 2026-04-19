#!/usr/bin/env python3
"""Scaffold renderer for Phase 2 decision artifacts derived from check outputs."""

from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml


REQUIRED_CHECK_ARTIFACTS = {
    "wrong_root_preflight": "checks/wrong_root_preflight.txt",
    "contracts_validation": "checks/contracts_validation.json",
    "policy_validation": "checks/policy_validation.json",
}
RUNTIME_READY_SOURCES = [
    "control-plane/runtime/openclaw/openclaw.template.json",
    "control-plane/runtime/openclaw/tool-policy.template.yaml",
    "control-plane/runtime/openclaw/agent-routing.template.yaml",
    "operations/harness-phase2/policy/placement-policy.yaml",
    "operations/harness-phase2/policy/admission-policy.yaml",
    "docs/APPLY_MODEL.md",
]
PLACEMENT_POLICY_CHECK_PREFIXES = (
    "structure.placement_policy.",
    "placement_policy.",
    "tool_policy.gates.placement.",
    "consistency.gates.placement.",
    "consistency.placement.",
    "consistency.required_output.placement_decision.",
)
PLACEMENT_POLICY_CHECK_NAMES = {
    "consistency.kb.requires_placement_decision",
    "consistency.obsidian.requires_placement_decision",
}


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def make_report_check(name: str, status: str, detail: str) -> dict[str, str]:
    return {"name": name, "status": status, "detail": detail}


def normalize_detail(text: str) -> str:
    compact = " ".join(text.split())
    return compact if compact else "detail unavailable"


def read_text(path: Path) -> str:
    with path.open("r", encoding="utf-8") as handle:
        return handle.read()


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level JSON value must be an object")
    return payload


def read_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle)
    if not isinstance(payload, dict):
        raise ValueError("top-level YAML value must be a mapping")
    return payload


def parse_preflight_report(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {
            "status": "fail",
            "detail": f"missing required check artifact: {path.name}",
            "artifact_ok": False,
            "blockers": ["missing_check_artifact:wrong_root_preflight"],
        }

    try:
        contents = read_text(path)
    except OSError as exc:
        return {
            "status": "fail",
            "detail": normalize_detail(f"unreadable check artifact: {exc}"),
            "artifact_ok": False,
            "blockers": ["invalid_check_artifact:wrong_root_preflight"],
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
            "status": "fail",
            "detail": "malformed wrong_root_preflight.txt: expected status=PASS or status=FAIL",
            "artifact_ok": False,
            "blockers": ["invalid_check_artifact:wrong_root_preflight"],
        }

    if status_value == "PASS":
        detail = inline_detail or "wrong-root preflight passed"
        return {
            "status": "pass",
            "detail": normalize_detail(detail),
            "artifact_ok": True,
            "blockers": [],
        }

    failure_detail = inline_detail or "; ".join(bullet_details) or "wrong-root preflight reported blocking issues"
    return {
        "status": "fail",
        "detail": normalize_detail(f"status=FAIL; {failure_detail}"),
        "artifact_ok": True,
        "blockers": ["wrong_root_preflight_failed"],
    }


def parse_json_check_report(path: Path, artifact_id: str) -> dict[str, Any]:
    if not path.is_file():
        return {
            "status": "fail",
            "detail": f"missing required check artifact: {path.name}",
            "artifact_ok": False,
            "payload": None,
            "failing_check_names": [],
            "blockers": [f"missing_check_artifact:{artifact_id}"],
        }

    try:
        payload = read_json(path)
    except OSError as exc:
        return {
            "status": "fail",
            "detail": normalize_detail(f"unreadable check artifact: {exc}"),
            "artifact_ok": False,
            "payload": None,
            "failing_check_names": [],
            "blockers": [f"invalid_check_artifact:{artifact_id}"],
        }
    except (ValueError, json.JSONDecodeError) as exc:
        return {
            "status": "fail",
            "detail": normalize_detail(f"malformed check artifact: {exc}"),
            "artifact_ok": False,
            "payload": None,
            "failing_check_names": [],
            "blockers": [f"invalid_check_artifact:{artifact_id}"],
        }

    status_value = payload.get("status")
    checks = payload.get("checks")
    if status_value not in {"pass", "fail"}:
        return {
            "status": "fail",
            "detail": "malformed check artifact: expected top-level status to be pass or fail",
            "artifact_ok": False,
            "payload": None,
            "failing_check_names": [],
            "blockers": [f"invalid_check_artifact:{artifact_id}"],
        }
    if not isinstance(checks, list) or not checks:
        return {
            "status": "fail",
            "detail": "malformed check artifact: expected a non-empty checks array",
            "artifact_ok": False,
            "payload": None,
            "failing_check_names": [],
            "blockers": [f"invalid_check_artifact:{artifact_id}"],
        }

    failing_names: list[str] = []
    for check in checks:
        if not isinstance(check, dict):
            return {
                "status": "fail",
                "detail": "malformed check artifact: every checks entry must be an object",
                "artifact_ok": False,
                "payload": None,
                "failing_check_names": [],
                "blockers": [f"invalid_check_artifact:{artifact_id}"],
            }
        name = check.get("name")
        check_status = check.get("status")
        if not isinstance(name, str) or not name:
            return {
                "status": "fail",
                "detail": "malformed check artifact: every checks entry must include a non-empty name",
                "artifact_ok": False,
                "payload": None,
                "failing_check_names": [],
                "blockers": [f"invalid_check_artifact:{artifact_id}"],
            }
        if check_status not in {"pass", "fail"}:
            return {
                "status": "fail",
                "detail": "malformed check artifact: every checks entry must include status=pass|fail",
                "artifact_ok": False,
                "payload": None,
                "failing_check_names": [],
                "blockers": [f"invalid_check_artifact:{artifact_id}"],
            }
        if check_status == "fail":
            failing_names.append(name)

    failing_names = sorted(set(failing_names))
    detail = f"status={status_value}"
    if failing_names:
        detail = f"{detail}; failing_checks={','.join(failing_names)}"

    blockers = [f"{artifact_id}_failed"] if status_value == "fail" else []
    return {
        "status": status_value,
        "detail": normalize_detail(detail),
        "artifact_ok": True,
        "payload": payload,
        "failing_check_names": failing_names,
        "blockers": blockers,
    }


def is_placement_related_policy_check(check_name: str) -> bool:
    return check_name.startswith(PLACEMENT_POLICY_CHECK_PREFIXES) or check_name in PLACEMENT_POLICY_CHECK_NAMES


def derive_review_required(repo_root: Path) -> tuple[bool, list[str]]:
    tool_policy_path = repo_root / "control-plane" / "runtime" / "openclaw" / "tool-policy.template.yaml"
    fallback_blocker = ["tool_policy_review_gate_unavailable"]

    if not tool_policy_path.is_file():
        return True, fallback_blocker

    try:
        payload = read_yaml(tool_policy_path)
    except (OSError, ValueError, yaml.YAMLError):
        return True, fallback_blocker

    gates = payload.get("gates")
    if not isinstance(gates, dict):
        return True, fallback_blocker
    apply_gate = gates.get("apply")
    if not isinstance(apply_gate, dict):
        return True, fallback_blocker
    review_required = apply_gate.get("require_review_approval")
    if not isinstance(review_required, bool):
        return True, fallback_blocker
    return review_required, []


def build_runtime_ready_package(repo_root: Path, run_dir: Path) -> tuple[list[dict[str, str]], list[str]]:
    runtime_ready_dir = run_dir / "output" / "runtime-ready"
    runtime_ready_dir.mkdir(parents=True, exist_ok=True)

    steps: list[dict[str, str]] = []
    blockers: list[str] = []

    for rel_source in RUNTIME_READY_SOURCES:
        source = repo_root / rel_source
        target = runtime_ready_dir / Path(rel_source).name

        if source.is_file():
            try:
                shutil.copy2(source, target)
                kind = "copy"
                required_gate = "validated-scaffold"
            except OSError:
                kind = "skip"
                required_gate = "source-present"
                blockers.append(f"runtime_ready_copy_failed:{rel_source}")
        else:
            kind = "skip"
            required_gate = "source-present"
            blockers.append(f"runtime_ready_source_missing:{rel_source}")

        steps.append(
            {
                "id": f"{kind}-{source.stem}",
                "kind": kind,
                "source_ref": rel_source,
                "target_path": target.relative_to(repo_root).as_posix(),
                "required_gate": required_gate,
            }
        )

    return steps, sorted(set(blockers))


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: render_apply_plan.py <repo-root> <run-dir> <run-id>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve()
    run_dir = Path(sys.argv[2]).resolve()
    run_id = sys.argv[3]
    generated_at = now_utc()

    preflight = parse_preflight_report(run_dir / REQUIRED_CHECK_ARTIFACTS["wrong_root_preflight"])
    contracts = parse_json_check_report(run_dir / REQUIRED_CHECK_ARTIFACTS["contracts_validation"], "contracts_validation")
    policy = parse_json_check_report(run_dir / REQUIRED_CHECK_ARTIFACTS["policy_validation"], "policy_validation")

    required_check_artifacts_present = preflight["artifact_ok"] and contracts["artifact_ok"] and policy["artifact_ok"]
    required_check_detail = "all required check artifacts are present and structurally valid"
    if not required_check_artifacts_present:
        missing_or_invalid = sorted(
            name
            for name, state in (
                ("wrong_root_preflight", preflight),
                ("contracts_validation", contracts),
                ("policy_validation", policy),
            )
            if not state["artifact_ok"]
        )
        required_check_detail = f"missing or invalid check artifacts: {','.join(missing_or_invalid)}"

    validation_checks = [
        make_report_check("wrong_root_preflight", preflight["status"], preflight["detail"]),
        make_report_check("contracts_validation", contracts["status"], contracts["detail"]),
        make_report_check("policy_validation", policy["status"], policy["detail"]),
        make_report_check(
            "required_check_artifacts_present",
            "pass" if required_check_artifacts_present else "fail",
            required_check_detail,
        ),
    ]
    validation_status = "pass"
    if not required_check_artifacts_present:
        validation_status = "fail"
    if preflight["status"] != "pass" or contracts["status"] != "pass" or policy["status"] != "pass":
        validation_status = "fail"

    validation_blockers = set(preflight["blockers"] + contracts["blockers"] + policy["blockers"])
    if not required_check_artifacts_present:
        validation_blockers.add("required_check_artifacts_missing_or_invalid")
    validation_blockers_sorted = sorted(validation_blockers)

    validation_report = {
        "run_id": run_id,
        "generated_at": generated_at,
        "engine_mode": "scaffold",
        "evaluation_mode": "static-v1",
        "status": validation_status,
        "checks": validation_checks,
    }

    admission_decision_value = "approved" if validation_status == "pass" else "needs_changes"
    admission_decision = {
        "run_id": run_id,
        "generated_at": generated_at,
        "engine_mode": "scaffold",
        "evaluation_mode": "static-v1",
        "decision": admission_decision_value,
        "checklist": [
            f"required_check_artifacts_present={'pass' if required_check_artifacts_present else 'fail'}",
            f"wrong_root_preflight={preflight['status']}",
            f"contracts_validation={contracts['status']}",
            f"policy_validation={policy['status']}",
            f"validation_report={validation_status}",
        ],
        "blockers": [] if admission_decision_value == "approved" else validation_blockers_sorted,
    }

    placement_failures: list[str] = []
    if policy["payload"] is not None:
        placement_failures = sorted(
            check["name"]
            for check in policy["payload"]["checks"]
            if check["status"] == "fail" and is_placement_related_policy_check(check["name"])
        )
    elif not policy["artifact_ok"]:
        placement_failures = ["policy_validation_artifact_unavailable"]

    placement_decision_value = "approved"
    if validation_status != "pass" or placement_failures:
        placement_decision_value = "needs_changes"

    target_path = f"observability/phase2/{run_id}/"
    if placement_decision_value == "approved":
        placement_rationale = (
            f"Derived from validation_report=pass with no placement-related blocking failures; "
            f"scaffold future target remains {target_path}"
        )
    else:
        rationale_parts = [f"validation_report={validation_status}"]
        if placement_failures:
            rationale_parts.append(f"placement_failures={','.join(placement_failures)}")
        else:
            rationale_parts.append("placement_failures=none")
        rationale_parts.append(f"scaffold future target remains {target_path}")
        placement_rationale = "; ".join(rationale_parts)

    placement_decision = {
        "run_id": run_id,
        "generated_at": generated_at,
        "engine_mode": "scaffold",
        "evaluation_mode": "static-v1",
        "decision": placement_decision_value,
        "target_layer": "observability",
        "target_path": target_path,
        "rationale": placement_rationale,
    }

    review_required, review_blockers = derive_review_required(repo_root)
    steps, runtime_ready_blockers = build_runtime_ready_package(repo_root, run_dir)

    apply_blockers = set(validation_blockers_sorted)
    apply_blockers.update(review_blockers)
    apply_blockers.update(runtime_ready_blockers)
    if admission_decision_value != "approved":
        apply_blockers.add("admission_decision_needs_changes")
    if placement_decision_value != "approved":
        apply_blockers.add("placement_decision_needs_changes")

    apply_plan_status = "ready"
    if (
        validation_status != "pass"
        or admission_decision_value != "approved"
        or placement_decision_value != "approved"
        or review_blockers
        or runtime_ready_blockers
    ):
        apply_plan_status = "blocked"

    apply_plan = {
        "run_id": run_id,
        "plan_id": f"apply-plan-{run_id}",
        "generated_at": generated_at,
        "engine_mode": "scaffold",
        "evaluation_mode": "static-v1",
        "status": apply_plan_status,
        "review_required": review_required,
        "target_runtime": "openclaw",
        "steps": steps,
        "blockers": sorted(apply_blockers),
    }

    write_json(run_dir / "validation_report.json", validation_report)
    write_json(run_dir / "admission_decision.json", admission_decision)
    write_json(run_dir / "placement_decision.json", placement_decision)
    write_json(run_dir / "apply_plan.json", apply_plan)

    return 0 if apply_plan_status == "ready" else 1


if __name__ == "__main__":
    raise SystemExit(main())
