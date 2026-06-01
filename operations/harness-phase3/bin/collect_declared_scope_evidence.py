#!/usr/bin/env python3
"""Collect low-level evidence for the declared Phase 3 scope."""

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


def is_allowed_path(path_value: str, allowlist: list[str]) -> bool:
    for pattern in allowlist:
        if pattern.endswith("/**"):
            prefix = pattern[:-3]
            if path_value == prefix or path_value.startswith(f"{prefix}/"):
                return True
        elif path_value == pattern:
            return True
    return False


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

    def build_report(self, evidence: dict[str, Any]) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "generated_at": now_utc(),
            "engine_mode": evidence.get("engine_mode", "scaffold"),
            "evaluation_mode": "phase3-static-v1",
            "status": "fail" if self.error_seen else "pass",
            "checks": self.checks,
            "evidence": evidence,
        }


def collect_repo_admission(repo_root: Path, run_dir: Path, recorder: CheckRecorder) -> dict[str, Any]:
    evidence_path = run_dir / "checks" / "repo_admission_evidence.json"
    apply_log_path = run_dir / "logs" / "apply.log"
    allowlist = ["knowledge/kb/sources/**", "knowledge/kb/knowledge/**"]
    destination_paths: list[str] = []
    actions: list[str] = []

    try:
        admission_evidence = read_json_object(evidence_path)
        items = admission_evidence.get("evidence")
        if not isinstance(items, list):
            raise ValueError("repo_admission_evidence.json must contain evidence array")
        for item in items:
            if isinstance(item, dict):
                destination_path = item.get("destination_path")
                action = item.get("action")
                if isinstance(destination_path, str):
                    destination_paths.append(destination_path)
                if isinstance(action, str):
                    actions.append(action)
        unsafe_destinations = sorted(path for path in destination_paths if not is_allowed_path(path, allowlist))
        if admission_evidence.get("status") == "pass" and not unsafe_destinations:
            recorder.pass_check(
                "declared_scope.repo_admission_evidence.pass",
                "Repo admission evidence passed and all destinations are inside the KB allowlist.",
                source_refs=[path_ref(repo_root, evidence_path)],
                expected={"status": "pass", "allowlist": allowlist},
                actual={"status": admission_evidence.get("status"), "destinations": destination_paths},
            )
        else:
            recorder.fail_check(
                "declared_scope.repo_admission_evidence.pass",
                "Repo admission evidence must pass and destinations must stay inside the KB allowlist.",
                source_refs=[path_ref(repo_root, evidence_path)],
                expected={"status": "pass", "allowlist": allowlist},
                actual={"status": admission_evidence.get("status"), "unsafe_destinations": unsafe_destinations},
            )
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        recorder.fail_check(
            "declared_scope.repo_admission_evidence.present",
            f"Repo admission evidence must be present and parseable: {exc}",
            source_refs=[path_ref(repo_root, evidence_path)],
            expected="parseable repo_admission_evidence.json",
            actual="invalid or unreadable",
        )

    if apply_log_path.is_file():
        recorder.pass_check(
            "declared_scope.apply_log.present",
            "apply.log is present for repo admission execution.",
            source_refs=[path_ref(repo_root, apply_log_path)],
            expected="present",
            actual="present",
        )
    else:
        recorder.fail_check(
            "declared_scope.apply_log.present",
            "apply.log must be present for repo admission execution.",
            source_refs=[path_ref(repo_root, apply_log_path)],
            expected="present",
            actual="missing",
        )

    return {
        "engine_mode": "repo_admission",
        "declared_target_kind": "repo_admission",
        "allowlist": allowlist,
        "destination_paths": destination_paths,
        "actions": actions,
    }


def collect_staging(repo_root: Path, run_dir: Path, recorder: CheckRecorder) -> dict[str, Any]:
    staging_root = run_dir / "staging"
    target_dir = staging_root / "runtime-ready-applied"
    apply_log_path = run_dir / "logs" / "apply.log"
    report_path = run_dir / "checks" / "declared_scope_evidence.json"
    run_root_ref = path_ref(repo_root, run_dir)
    allowlist = [
        f"{run_root_ref}/run_meta.json",
        f"{run_root_ref}/input/**",
        f"{run_root_ref}/staging/runtime-ready-applied/**",
        f"{run_root_ref}/checks/**",
        f"{run_root_ref}/logs/apply.log",
        f"{run_root_ref}/.bundle_state.env",
    ]

    observed_paths = sorted(
        path_ref(repo_root, path)
        for path in run_dir.rglob("*")
        if path.is_file() and path.resolve(strict=False) != report_path.resolve(strict=False)
    )
    writes_outside_scope = sorted(path_value for path_value in observed_paths if not is_allowed_path(path_value, allowlist))

    if target_dir.is_dir():
        recorder.pass_check(
            "declared_scope.target_root.present",
            "Canonical Phase 3-owned staging target is present.",
            source_refs=[path_ref(repo_root, target_dir)],
            expected=f"operations/harness-phase3/runs/{run_dir.name}/staging/runtime-ready-applied",
            actual=path_ref(repo_root, target_dir),
        )
    else:
        recorder.fail_check(
            "declared_scope.target_root.present",
            "Canonical Phase 3-owned staging target must be present.",
            source_refs=[path_ref(repo_root, target_dir)],
            expected=f"operations/harness-phase3/runs/{run_dir.name}/staging/runtime-ready-applied",
            actual="missing",
        )

    if not writes_outside_scope:
        recorder.pass_check(
            "declared_scope.observed_paths.within_allowlist",
            "Observed run files stay within the declared Phase 3 scaffold allowlist at collection time.",
            source_refs=[run_root_ref],
            expected=allowlist,
            actual=observed_paths,
        )
    else:
        recorder.fail_check(
            "declared_scope.observed_paths.within_allowlist",
            "Observed run files include writes outside the declared Phase 3 scaffold allowlist.",
            source_refs=[run_root_ref],
            expected=allowlist,
            actual=writes_outside_scope,
        )

    if apply_log_path.is_file():
        recorder.pass_check(
            "declared_scope.apply_log.present",
            "apply.log is present alongside the canonical staging target evidence.",
            source_refs=[path_ref(repo_root, apply_log_path)],
            expected="present",
            actual="present",
        )
    else:
        recorder.fail_check(
            "declared_scope.apply_log.present",
            "apply.log must be present for declared scope evidence collection.",
            source_refs=[path_ref(repo_root, apply_log_path)],
            expected="present",
            actual="missing",
        )

    return {
        "engine_mode": "scaffold",
        "declared_target_ref": f"operations/harness-phase3/runs/{run_dir.name}/staging/runtime-ready-applied",
        "allowlist": allowlist,
        "observed_paths": observed_paths,
        "writes_outside_scope": writes_outside_scope,
    }


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: collect_declared_scope_evidence.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve(strict=False)
    run_dir = Path(sys.argv[2]).resolve(strict=False)
    report_path = run_dir / "checks" / "declared_scope_evidence.json"
    recorder = CheckRecorder(run_dir.name)
    try:
        execution_target = read_json_object(run_dir / "input" / "execution_target.json")
    except (OSError, ValueError, json.JSONDecodeError):
        execution_target = {}

    if execution_target.get("target_kind") == "repo_admission":
        evidence = collect_repo_admission(repo_root, run_dir, recorder)
    else:
        evidence = collect_staging(repo_root, run_dir, recorder)

    report = recorder.build_report(evidence)
    write_json(report_path, report)
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
