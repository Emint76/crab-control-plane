#!/usr/bin/env python3
"""Render report.json/report.md/exit_code for a knowledge-pipeline run."""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

RUNS_REF = Path("operations/harness-knowledge-pipeline/runs")
HARNESS_REF = Path("operations/harness-knowledge-pipeline")

DEFAULT_IMPROVEMENT_CANDIDATES = [
    "Promote normalized_note.candidate.schema.json into control-plane/contracts/schemas/ after one or more evidence-backed runs.",
    "Promote knowledge_result_packet.candidate.schema.json or extend result_packet.schema.json with claim-level fields.",
    "Add canonical knowledge candidate and wiki-derived draft contracts to repo canon if this run shape holds.",
    "Add knowledge-specific admission/placement policy vocabulary distinct from runtime/apply vocabulary.",
    "Add a Phase3-like knowledge evidence-owner contract and Phase4-like knowledge wrapper contract after this harness proves useful."
]


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def repo_ref(repo_root: Path, path: Path) -> str:
    return path.resolve(strict=False).relative_to(repo_root.resolve(strict=False)).as_posix()


def determine_status(checks: list[dict[str, Any]]) -> str:
    statuses = {str(check.get("status", "")) for check in checks}
    if "fail" in statuses:
        return "fail"
    if "awaiting_semantic_outputs" in statuses or "pending" in statuses:
        return "awaiting_semantic_outputs"
    return "pass"


def exit_code_for(status: str) -> int:
    if status == "pass":
        return 0
    if status == "awaiting_semantic_outputs":
        return 3
    return 1


def markdown_report(report: dict[str, Any]) -> str:
    lines = [
        "# Knowledge Pipeline Run Report",
        "",
        f"- run_id: `{report['run_id']}`",
        f"- status: `{report['status']}`",
        f"- generated_at: `{report['generated_at']}`",
        f"- canonical_admitted: `{report['canonical_admitted']}`",
        f"- auto_canonical_write_performed: `{report['auto_canonical_write_performed']}`",
        f"- openclaw_used: `{report['openclaw_used']}`",
        f"- docker_used: `{report['docker_used']}`",
        f"- network_used: `{report['network_used']}`",
        f"- outside_git_paths_used: `{report['outside_git_paths_used']}`",
        "",
        "## Artifacts",
    ]
    for artifact in report["artifacts"]:
        lines.append(f"- `{artifact}`")
    lines.extend(["", "## Checks"])
    for check in report["checks"]:
        lines.append(f"- `{check.get('path')}`: `{check.get('status')}` — {check.get('detail', '')}")
    lines.extend(["", "## Pipeline blockers"])
    if report["blockers"]:
        for blocker in report["blockers"]:
            lines.append(f"- {blocker}")
    else:
        lines.append("- none")
    admission = report.get("admission_candidate") or {}
    if admission:
        lines.extend(["", "## Admission candidate"])
        lines.append(f"- decision: `{admission.get('decision')}`")
        lines.append(f"- path: `{admission.get('path')}`")
        lines.append("- candidate blockers:")
        for blocker in admission.get("blockers", []) or ["none"]:
            lines.append(f"  - {blocker}")
    lines.extend(["", "## Improvement candidates"])
    for item in report["improvement_candidates"]:
        lines.append(f"- {item}")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--run-id", required=True)
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve(strict=True)
    run_id = args.run_id
    run_dir = repo_root / RUNS_REF / run_id
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)

    checks: list[dict[str, Any]] = []
    for path in sorted(checks_dir.glob("*.json")):
        try:
            payload = load_json(path)
            payload["path"] = repo_ref(repo_root, path)
            checks.append(payload)
        except Exception as exc:  # noqa: BLE001
            checks.append({"path": repo_ref(repo_root, path), "status": "fail", "detail": f"unreadable check: {exc}"})

    status = determine_status(checks)
    artifacts = [repo_ref(repo_root, path) for path in sorted(run_dir.rglob("*")) if path.is_file() and path.name not in {"report.json", "report.md", "exit_code"}]
    blockers = [str(check.get("detail", check.get("path"))) for check in checks if check.get("status") in {"fail", "awaiting_semantic_outputs", "pending"}]

    improvement_candidates = list(DEFAULT_IMPROVEMENT_CANDIDATES)
    result_packet_path = run_dir / "output/result_packet.json"
    if result_packet_path.is_file():
        try:
            for item in load_json(result_packet_path).get("improvement_candidates", []):
                if item not in improvement_candidates:
                    improvement_candidates.append(item)
        except Exception:  # noqa: BLE001
            pass

    admission_candidate = None
    admission_candidate_path = run_dir / "output/admission_decision.candidate.json"
    if admission_candidate_path.is_file():
        try:
            admission_payload = load_json(admission_candidate_path)
            admission_candidate = {
                "path": repo_ref(repo_root, admission_candidate_path),
                "decision": admission_payload.get("decision"),
                "blockers": admission_payload.get("blockers", []),
                "checklist": admission_payload.get("checklist", []),
            }
        except Exception as exc:  # noqa: BLE001
            admission_candidate = {
                "path": repo_ref(repo_root, admission_candidate_path),
                "decision": "unreadable",
                "blockers": [str(exc)],
                "checklist": [],
            }

    report = {
        "run_id": run_id,
        "generated_at": now_utc(),
        "status": status,
        "canonical_admitted": False,
        "auto_canonical_write_performed": False,
        "live_surface_used": False,
        "openclaw_used": False,
        "docker_used": False,
        "network_used": False,
        "outside_git_paths_used": False,
        "artifacts": artifacts,
        "checks": checks,
        "blockers": blockers,
        "admission_candidate": admission_candidate,
        "improvement_candidates": improvement_candidates,
        "reports": {
            "json": f"{RUNS_REF.as_posix()}/{run_id}/report.json",
            "markdown": f"{RUNS_REF.as_posix()}/{run_id}/report.md",
            "exit_code": f"{RUNS_REF.as_posix()}/{run_id}/exit_code"
        }
    }

    schema_path = repo_root / HARNESS_REF / "contracts/knowledge_run_report.schema.json"
    schema = load_json(schema_path)
    errors = sorted(Draft202012Validator(schema).iter_errors(report), key=lambda err: list(err.path))
    if errors:
        report["status"] = "fail"
        report["blockers"].extend([err.message for err in errors])
        status = "fail"

    write_json(run_dir / "report.json", report)
    (run_dir / "report.md").write_text(markdown_report(report), encoding="utf-8")
    code = exit_code_for(status)
    (run_dir / "exit_code").write_text(f"{code}\n", encoding="utf-8")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
