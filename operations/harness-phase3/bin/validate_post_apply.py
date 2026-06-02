#!/usr/bin/env python3
"""Validate the post-apply Phase 3 state."""

from __future__ import annotations

import argparse
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


def is_string_list(value: Any) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) and item for item in value)


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

    def build_report(self, engine_mode: str) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "generated_at": now_utc(),
            "engine_mode": engine_mode,
            "evaluation_mode": "phase3-static-v1",
            "status": "fail" if self.error_seen else "pass",
            "checks": self.checks,
        }


def validate_apply_completed(repo_root: Path, run_dir: Path, recorder: CheckRecorder, execute_apply_exit_status: int) -> None:
    apply_log_path = run_dir / "logs" / "apply.log"
    if execute_apply_exit_status == 0 and apply_log_path.is_file():
        recorder.pass_check(
            "apply_execution.completed",
            "execute_apply completed successfully and wrote apply.log.",
            source_refs=[path_ref(repo_root, apply_log_path)],
            expected={"exit_status": 0, "apply_log": "present"},
            actual={"exit_status": execute_apply_exit_status, "apply_log": "present"},
        )
    else:
        recorder.fail_check(
            "apply_execution.completed",
            "execute_apply must return 0 and write apply.log.",
            source_refs=[path_ref(repo_root, apply_log_path)],
            expected={"exit_status": 0, "apply_log": "present"},
            actual={"exit_status": execute_apply_exit_status, "apply_log": "present" if apply_log_path.is_file() else "missing"},
        )


def validate_declared_scope(repo_root: Path, run_dir: Path, recorder: CheckRecorder) -> None:
    declared_scope_path = run_dir / "checks" / "declared_scope_evidence.json"
    try:
        declared_scope = read_json_object(declared_scope_path)
        evidence = declared_scope.get("evidence")
        if not isinstance(evidence, dict):
            raise ValueError("declared_scope_evidence.json must contain an evidence object")
        if evidence.get("engine_mode") == "kb_admission":
            destination_paths = evidence.get("destination_paths", [])
            writes_outside_scope = evidence.get("writes_outside_scope", [])
            if declared_scope.get("status") == "pass" and is_string_list(destination_paths) and destination_paths and writes_outside_scope == []:
                recorder.pass_check(
                    "declared_scope.only",
                    "Declared scope evidence confirms KB admission wrote only relative destinations under the configured workspace KB root.",
                    source_refs=[path_ref(repo_root, declared_scope_path)],
                    expected={"status": "pass", "writes_outside_scope": [], "target_runtime": "workspace"},
                    actual={"status": declared_scope.get("status"), "destination_paths": destination_paths},
                )
            else:
                recorder.fail_check(
                    "declared_scope.only",
                    "KB admission declared scope evidence must pass with relative destinations and no writes outside scope.",
                    source_refs=[path_ref(repo_root, declared_scope_path)],
                    expected={"status": "pass", "writes_outside_scope": [], "target_runtime": "workspace"},
                    actual={"status": declared_scope.get("status"), "destination_paths": destination_paths, "writes_outside_scope": writes_outside_scope},
                )
            return

        observed_paths = evidence.get("observed_paths", evidence.get("destination_paths", []))
        allowlist = evidence.get("allowlist")
        writes_outside_scope = evidence.get("writes_outside_scope", [])
        if not is_string_list(observed_paths):
            raise ValueError("evidence observed/destination paths must be an array of non-empty strings")
        if not is_string_list(allowlist):
            raise ValueError("evidence.allowlist must be an array of non-empty strings")
        if not isinstance(writes_outside_scope, list) or any(not isinstance(item, str) for item in writes_outside_scope):
            raise ValueError("evidence.writes_outside_scope must be an array of strings")

        subset_violations = sorted(path_value for path_value in observed_paths if not is_allowed_path(path_value, allowlist))
        if declared_scope.get("status") == "pass" and writes_outside_scope == [] and subset_violations == []:
            recorder.pass_check(
                "declared_scope.only",
                "Declared scope evidence confirms observed paths stayed within the allowed surface.",
                source_refs=[path_ref(repo_root, declared_scope_path)],
                expected={"status": "pass", "writes_outside_scope": [], "observed_paths_subset_of_allowlist": True},
                actual={
                    "status": declared_scope.get("status"),
                    "writes_outside_scope": writes_outside_scope,
                    "subset_violations": subset_violations,
                },
            )
        else:
            recorder.fail_check(
                "declared_scope.only",
                "Declared scope evidence must report pass with no writes outside scope and paths confined to the allowlist.",
                source_refs=[path_ref(repo_root, declared_scope_path)],
                expected={"status": "pass", "writes_outside_scope": [], "observed_paths_subset_of_allowlist": True},
                actual={
                    "status": declared_scope.get("status"),
                    "writes_outside_scope": writes_outside_scope,
                    "subset_violations": subset_violations,
                },
            )
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        recorder.fail_check(
            "declared_scope.only",
            f"Declared scope evidence must be present and parseable: {exc}",
            source_refs=[path_ref(repo_root, declared_scope_path)],
            expected="parseable declared_scope_evidence.json with status=pass",
            actual="invalid or unreadable",
        )


def validate_staging_materialization(repo_root: Path, run_dir: Path, recorder: CheckRecorder) -> None:
    target_dir = run_dir / "staging" / "runtime-ready-applied"
    if target_dir.is_dir():
        recorder.pass_check(
            "staging.materialization.present",
            "Canonical staging materialization is present.",
            source_refs=[path_ref(repo_root, target_dir)],
            expected=f"operations/harness-phase3/runs/{run_dir.name}/staging/runtime-ready-applied",
            actual=path_ref(repo_root, target_dir),
        )
    else:
        recorder.fail_check(
            "staging.materialization.present",
            "Canonical staging materialization must be present.",
            source_refs=[path_ref(repo_root, target_dir)],
            expected=f"operations/harness-phase3/runs/{run_dir.name}/staging/runtime-ready-applied",
            actual="missing",
        )


def validate_repo_admission_evidence(repo_root: Path, run_dir: Path, recorder: CheckRecorder) -> None:
    evidence_path = run_dir / "checks" / "repo_admission_evidence.json"
    try:
        payload = read_json_object(evidence_path)
        items = payload.get("evidence")
        if not isinstance(items, list) or not items:
            raise ValueError("repo_admission_evidence.json must contain a non-empty evidence array")
        actions = [item.get("action") for item in items if isinstance(item, dict)]
        verdicts = [item.get("overwrite_verdict") for item in items if isinstance(item, dict)]
        hash_fields_present = all(
            isinstance(item, dict)
            and item.get("manifest_hash")
            and item.get("source_artifact_hash")
            and item.get("destination_path")
            and item.get("final_destination_hash")
            for item in items
        )
        if payload.get("status") == "pass" and hash_fields_present and all(action in {"copied", "idempotent"} for action in actions):
            recorder.pass_check(
                "repo_admission.evidence.complete",
                "Repo admission evidence records hashes, destination path, action, and overwrite verdict.",
                source_refs=[path_ref(repo_root, evidence_path)],
                expected="complete copied or idempotent evidence",
                actual={"actions": actions, "overwrite_verdicts": verdicts},
            )
        else:
            recorder.fail_check(
                "repo_admission.evidence.complete",
                "Repo admission evidence must pass with copied or idempotent actions and complete hash fields.",
                source_refs=[path_ref(repo_root, evidence_path)],
                expected="complete copied or idempotent evidence",
                actual={"status": payload.get("status"), "actions": actions, "overwrite_verdicts": verdicts},
            )
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        recorder.fail_check(
            "repo_admission.evidence.complete",
            f"Repo admission evidence must be present and parseable: {exc}",
            source_refs=[path_ref(repo_root, evidence_path)],
            expected="parseable repo_admission_evidence.json",
            actual="invalid or unreadable",
        )


def validate_kb_admission_evidence(repo_root: Path, run_dir: Path, recorder: CheckRecorder) -> None:
    evidence_path = run_dir / "checks" / "kb_admission_evidence.json"
    try:
        payload = read_json_object(evidence_path)
        items = payload.get("evidence")
        if not isinstance(items, list) or not items:
            raise ValueError("kb_admission_evidence.json must contain a non-empty evidence array")
        actions = [item.get("action") for item in items if isinstance(item, dict)]
        verdicts = [item.get("overwrite_verdict") for item in items if isinstance(item, dict)]
        hash_fields_present = all(
            isinstance(item, dict)
            and item.get("manifest_hash")
            and item.get("kb_integration_hash")
            and item.get("source_artifact_hash")
            and item.get("destination_kb_path")
            and item.get("final_destination_hash")
            for item in items
        )
        root_fields_present = bool(payload.get("kb_root_env") and payload.get("kb_root_resolved") and payload.get("kb_integration_hash") and payload.get("manifest_hash"))
        if payload.get("status") == "pass" and root_fields_present and hash_fields_present and all(action in {"copied", "idempotent"} for action in actions):
            recorder.pass_check(
                "kb_admission.evidence.complete",
                "KB admission evidence records root metadata, hashes, destination path, action, and overwrite verdict.",
                source_refs=[path_ref(repo_root, evidence_path)],
                expected="complete copied or idempotent workspace KB evidence",
                actual={"actions": actions, "overwrite_verdicts": verdicts},
            )
        else:
            recorder.fail_check(
                "kb_admission.evidence.complete",
                "KB admission evidence must pass with copied or idempotent actions and complete root/hash fields.",
                source_refs=[path_ref(repo_root, evidence_path)],
                expected="complete copied or idempotent workspace KB evidence",
                actual={"status": payload.get("status"), "actions": actions, "overwrite_verdicts": verdicts},
            )
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        recorder.fail_check(
            "kb_admission.evidence.complete",
            f"KB admission evidence must be present and parseable: {exc}",
            source_refs=[path_ref(repo_root, evidence_path)],
            expected="parseable kb_admission_evidence.json",
            actual="invalid or unreadable",
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repo_root")
    parser.add_argument("run_dir")
    parser.add_argument("--execute-apply-exit-status", required=True, type=int)
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve(strict=False)
    run_dir = Path(args.run_dir).resolve(strict=False)
    report_path = run_dir / "checks" / "post_apply_validation.json"
    recorder = CheckRecorder(run_dir.name)
    try:
        execution_target = read_json_object(run_dir / "input" / "execution_target.json")
    except (OSError, ValueError, json.JSONDecodeError):
        execution_target = {}

    validate_apply_completed(repo_root, run_dir, recorder, args.execute_apply_exit_status)
    validate_declared_scope(repo_root, run_dir, recorder)
    if execution_target.get("target_kind") == "repo_admission":
        validate_repo_admission_evidence(repo_root, run_dir, recorder)
        engine_mode = "repo_admission"
    elif execution_target.get("target_kind") == "kb_admission":
        validate_kb_admission_evidence(repo_root, run_dir, recorder)
        engine_mode = "kb_admission"
    else:
        validate_staging_materialization(repo_root, run_dir, recorder)
        engine_mode = "scaffold"

    report = recorder.build_report(engine_mode)
    write_json(report_path, report)
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
