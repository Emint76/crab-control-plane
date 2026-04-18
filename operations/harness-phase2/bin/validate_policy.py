#!/usr/bin/env python3
"""v1 minimal validator for Phase 2 policy consistency."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_yaml(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: validate_policy.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve()
    run_dir = Path(sys.argv[2]).resolve()
    run_id = run_dir.name
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)
    report_path = checks_dir / "policy_validation.json"

    checks: list[dict[str, str]] = []
    failed = False

    openclaw = load_json(repo_root / "control-plane" / "runtime" / "openclaw" / "openclaw.template.json")
    routing = load_yaml(repo_root / "control-plane" / "runtime" / "openclaw" / "agent-routing.template.yaml")
    placement_policy = load_yaml(repo_root / "operations" / "harness-phase2" / "policy" / "placement-policy.yaml")
    admission_policy = load_yaml(repo_root / "operations" / "harness-phase2" / "policy" / "admission-policy.yaml")

    def check(name: str, condition: bool, detail: str) -> None:
        nonlocal failed
        checks.append({"name": name, "status": "pass" if condition else "fail", "detail": detail})
        if not condition:
            failed = True

    check(
        "openclaw.apply.live_write_allowed",
        openclaw.get("apply", {}).get("live_write_allowed") is False,
        "openclaw apply.live_write_allowed must be false",
    )
    check(
        "openclaw.validation.surface",
        openclaw.get("validation", {}).get("surface") == "operations/harness-phase2",
        "openclaw validation.surface must equal operations/harness-phase2",
    )
    check(
        "openclaw.apply.mode",
        openclaw.get("apply", {}).get("mode") == "controlled-apply",
        "openclaw apply.mode must equal controlled-apply",
    )
    check(
        "routing.apply.phase2_live_writes_forbidden",
        routing.get("routing", {}).get("apply", {}).get("phase2_live_writes_forbidden") is True,
        "routing.apply.phase2_live_writes_forbidden must be true",
    )

    roots = placement_policy.get("roots", {})
    for layer in ("notion", "obsidian", "kb", "observability"):
        check(
            f"placement_policy.roots.{layer}",
            layer in roots,
            f"placement policy must contain root for {layer}",
        )

    rules = admission_policy.get("rules", {})
    for layer in ("kb", "observability"):
        check(
            f"admission_policy.rules.{layer}",
            layer in rules,
            f"admission policy must contain rule for {layer}",
        )

    report = {
        "run_id": run_id,
        "generated_at": now_utc(),
        "engine_mode": "scaffold",
        "evaluation_mode": "static-v1",
        "status": "fail" if failed else "pass",
        "checks": checks,
    }
    with report_path.open("w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
