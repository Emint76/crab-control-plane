#!/usr/bin/env python3
"""Scaffold renderer for Phase 2 machine-readable outputs."""

from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: render_apply_plan.py <repo-root> <run-dir> <run-id>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve()
    run_dir = Path(sys.argv[2]).resolve()
    run_id = sys.argv[3]
    generated_at = now_utc()

    runtime_ready_dir = run_dir / "output" / "runtime-ready"
    runtime_ready_dir.mkdir(parents=True, exist_ok=True)

    copy_sources = [
        repo_root / "control-plane" / "runtime" / "openclaw" / "openclaw.template.json",
        repo_root / "control-plane" / "runtime" / "openclaw" / "tool-policy.template.yaml",
        repo_root / "control-plane" / "runtime" / "openclaw" / "agent-routing.template.yaml",
        repo_root / "operations" / "harness-phase2" / "policy" / "placement-policy.yaml",
        repo_root / "operations" / "harness-phase2" / "policy" / "admission-policy.yaml",
        repo_root / "docs" / "APPLY_MODEL.md",
    ]

    steps = []
    for source in copy_sources:
        target = runtime_ready_dir / source.name
        shutil.copy2(source, target)
        steps.append(
            {
                "id": f"copy-{source.stem}",
                "kind": "copy",
                "source_ref": source.relative_to(repo_root).as_posix(),
                "target_path": target.relative_to(repo_root).as_posix(),
                "required_gate": "validated-scaffold",
            }
        )

    write_json(
        run_dir / "validation_report.json",
        {
            "run_id": run_id,
            "generated_at": generated_at,
            "engine_mode": "scaffold",
            "evaluation_mode": "static-v1",
            "status": "pass",
            "checks": [
                {
                    "name": "phase2_scaffold_render",
                    "status": "pass",
                    "detail": "Scaffold decisions rendered after preflight and validators.",
                }
            ],
        },
    )
    write_json(
        run_dir / "admission_decision.json",
        {
            "run_id": run_id,
            "generated_at": generated_at,
            "engine_mode": "scaffold",
            "evaluation_mode": "static-v1",
            "decision": "approved",
            "checklist": [
                "validation_report present",
                "placement_decision present",
                "apply_plan present",
            ],
            "blockers": [],
        },
    )
    write_json(
        run_dir / "placement_decision.json",
        {
            "run_id": run_id,
            "generated_at": generated_at,
            "engine_mode": "scaffold",
            "evaluation_mode": "static-v1",
            "decision": "approved",
            "target_layer": "observability",
            "target_path": f"observability/phase2/{run_id}/",
            "rationale": "Scaffold Phase 2 machine artifacts are represented as future observability-facing outputs.",
        },
    )
    write_json(
        run_dir / "apply_plan.json",
        {
            "run_id": run_id,
            "plan_id": f"apply-plan-{run_id}",
            "generated_at": generated_at,
            "engine_mode": "scaffold",
            "evaluation_mode": "static-v1",
            "status": "ready",
            "review_required": True,
            "target_runtime": "openclaw",
            "steps": steps,
            "blockers": [],
        },
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
