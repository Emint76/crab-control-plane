#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


PHASE3_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = PHASE3_ROOT.parent.parent
PHASE2_RUN_ID = "phase3-kb-admission-phase2-input"
PHASE2_RUN_DIR = REPO_ROOT / "operations" / "harness-phase2" / "runs" / PHASE2_RUN_ID
FIXTURE_DIR = PHASE3_ROOT / "runs" / "phase3-kb-admission-fixtures"
RUN_IDS: list[str] = []


def fail(message: str) -> None:
    raise AssertionError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def repo_ref(path: Path) -> str:
    return path.absolute().relative_to(REPO_ROOT.absolute()).as_posix()


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_integration(path: Path, *, valid: bool = True) -> None:
    target_runtime = "workspace" if valid else "repo"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        f"""version: 1
integration: kb
enabled: true
target_runtime: {target_runtime}
root_path_env: OPENCLAW_WORKSPACE_KB_ROOT
default_root_hint: /home/gennady/.openclaw/workspace/kb
root_path_policy:
  configured_at_runtime: true
  repo_payload: false
  default_root_hint_is_required: false
  repo_owns_root: false
  secrets_allowed: false
layout:
  sources:
    path: sources
    description: Test source layout metadata.
  knowledge:
    path: knowledge
    description: Test knowledge layout metadata.
  collections:
    path: collections
    description: Test collection layout metadata.
""",
        encoding="utf-8",
    )


def manifest_payload(admission_type: str, source_ref: str, expected_sha: str, destination_ref: str) -> dict[str, Any]:
    return {
        "admission_type": admission_type,
        "lineage": {
            "source_ref": f"test://phase3-kb-admission/{admission_type}",
            "captured_from": "workspace-test-fixture",
            "captured_at": "2026-06-02T00:00:00Z",
        },
        "copy_operation": {
            "operation_type": "copy",
            "content_mode": "byte_for_byte",
            "overwrite_policy": "fail_closed_on_hash_mismatch",
            "requested_by": "test://phase3-kb-admission",
        },
        "artifacts": [
            {
                "input_workspace_path": source_ref,
                "expected_sha256": expected_sha,
                "destination_kb_path": destination_ref,
                "copy_metadata": {"label": f"{admission_type} fixture"},
            }
        ],
    }


def write_manifest(path: Path, admission_type: str, source_ref: str, expected_sha: str, destination_ref: str) -> None:
    write_json(path, manifest_payload(admission_type, source_ref, expected_sha, destination_ref))


def write_two_artifact_manifest(path: Path, first: tuple[str, str, str], second: tuple[str, str, str]) -> None:
    payload = manifest_payload("source_capture", first[0], first[1], first[2])
    payload["artifacts"].append(
        {
            "input_workspace_path": second[0],
            "expected_sha256": second[1],
            "destination_kb_path": second[2],
            "copy_metadata": {"label": "blocked overwrite"},
        }
    )
    write_json(path, payload)


def write_invalid_manifest(path: Path) -> None:
    write_json(path, {"admission_type": "source_capture", "lineage": {"source_ref": "test://invalid"}})


def write_target(run_id: str, integration_ref: str, manifest_ref: str) -> None:
    RUN_IDS.append(run_id)
    target_path = PHASE3_ROOT / "runs" / f"{run_id}-target" / "execution_target.json"
    write_json(
        target_path,
        {
            "target_runtime": "workspace",
            "target_kind": "kb_admission",
            "kb_integration_ref": integration_ref,
            "admission_manifest_ref": manifest_ref,
            "invoked_by": "test://phase3-kb-admission",
        },
    )


def make_manifest_and_target(run_id: str, integration_ref: str, admission_type: str, source_ref: str, expected_sha: str, destination_ref: str) -> None:
    manifest = PHASE3_ROOT / "runs" / f"{run_id}-target" / "admission_manifest.json"
    write_manifest(manifest, admission_type, source_ref, expected_sha, destination_ref)
    write_target(run_id, integration_ref, repo_ref(manifest))


def run_phase3(run_id: str, kb_root: Path | str | None, *, expect_success: bool, unset_env: bool = False) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.setdefault("PHASE3_PYTHON_BIN", sys.executable)
    env.setdefault("PHASE2_PYTHON_BIN", sys.executable)
    if unset_env:
        env.pop("OPENCLAW_WORKSPACE_KB_ROOT", None)
    else:
        env["OPENCLAW_WORKSPACE_KB_ROOT"] = "" if kb_root is None else str(kb_root)
    result = subprocess.run(
        [
            "bash",
            str(PHASE3_ROOT / "bin" / "run_phase3_bundle.sh"),
            "--phase2-run-dir",
            f"operations/harness-phase2/runs/{PHASE2_RUN_ID}",
            "--execution-target-json",
            f"operations/harness-phase3/runs/{run_id}-target/execution_target.json",
            "--run-id",
            run_id,
        ],
        cwd=REPO_ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if expect_success and result.returncode != 0:
        fail(f"{run_id} failed unexpectedly:\n{result.stdout}")
    if not expect_success and result.returncode == 0:
        fail(f"{run_id} passed unexpectedly")
    return result


def assert_exit_code(run_id: str, expected: int) -> None:
    path = PHASE3_ROOT / "runs" / run_id / "exit_code"
    if not path.is_file():
        fail(f"missing exit_code for {run_id}")
    actual = path.read_text(encoding="utf-8").strip()
    if actual != str(expected):
        fail(f"unexpected exit_code for {run_id}: {actual}")


def read_evidence(run_id: str) -> dict[str, Any]:
    return json.loads((PHASE3_ROOT / "runs" / run_id / "checks" / "kb_admission_evidence.json").read_text(encoding="utf-8-sig"))


def assert_action(run_id: str, action: str, verdict: str) -> None:
    payload = read_evidence(run_id)
    item = payload["evidence"][0]
    assert payload["target_runtime"] == "workspace", payload
    assert payload["target_kind"] == "kb_admission", payload
    assert payload["kb_root_env"] == "OPENCLAW_WORKSPACE_KB_ROOT", payload
    assert str(payload["kb_root_resolved"]).startswith("redacted:sha256:"), payload
    assert payload["kb_integration_hash"] and payload["manifest_hash"], payload
    for key in ("kb_integration_hash", "manifest_hash", "source_artifact_hash", "destination_kb_path"):
        assert item[key], payload
    assert item["action"] == action, payload
    assert item["overwrite_verdict"] == verdict, payload
    if action != "failed_closed":
        assert item["final_destination_hash"], payload


def assert_pre_apply_failed(run_id: str) -> None:
    payload = json.loads((PHASE3_ROOT / "runs" / run_id / "checks" / "pre_apply_validation.json").read_text(encoding="utf-8-sig"))
    assert payload["status"] == "fail", payload
    assert payload["target_kind"] == "kb_admission", payload


def assert_atomic_evidence(run_id: str) -> None:
    payload = read_evidence(run_id)
    items = payload["evidence"]
    assert payload["status"] == "fail", payload
    assert payload["failure_stage"] == "copy_plan_preflight", payload
    assert len(items) == 2, payload
    assert items[0]["planned_action"] == "would_copy", payload
    assert items[0]["action"] == "failed_closed", payload
    assert items[0]["execution_status"] == "not_executed", payload
    assert items[0]["overwrite_verdict"] == "destination_missing", payload
    assert items[1]["action"] == "failed_closed", payload
    assert items[1]["execution_status"] == "not_executed", payload
    assert items[1]["overwrite_verdict"] == "different_hash_existing", payload


def main() -> None:
    tmp = Path(tempfile.mkdtemp(prefix="phase3-kb-admission-"))
    kb_root = tmp / "workspace-kb"
    outside_root = tmp / "outside"
    try:
        shutil.rmtree(PHASE2_RUN_DIR, ignore_errors=True)
        shutil.rmtree(FIXTURE_DIR, ignore_errors=True)
        kb_root.joinpath("prepared").mkdir(parents=True)
        kb_root.joinpath("cosmetics-household-chemistry").mkdir(parents=True)
        outside_root.mkdir(parents=True)
        FIXTURE_DIR.mkdir(parents=True)
        env = os.environ.copy()
        env.setdefault("PHASE2_PYTHON_BIN", sys.executable)
        subprocess.run(["bash", str(REPO_ROOT / "operations" / "harness-phase2" / "bin" / "run_phase2_bundle.sh"), PHASE2_RUN_ID], cwd=REPO_ROOT, env=env, check=True)

        integration = FIXTURE_DIR / "kb.template.yaml"
        write_integration(integration)
        integration_ref = repo_ref(integration)

        kb_root.joinpath("prepared/source-capture.txt").write_text("source capture bytes\n", encoding="utf-8")
        source_hash = sha256_file(kb_root / "prepared/source-capture.txt")
        kb_root.joinpath("prepared/knowledge.md").write_text("# Knowledge asset\n\nStable bytes.\n", encoding="utf-8")
        knowledge_hash = sha256_file(kb_root / "prepared/knowledge.md")

        make_manifest_and_target("phase3-kb-admission-source-pass", integration_ref, "source_capture", "prepared/source-capture.txt", source_hash, "cosmetics-household-chemistry/source-capture.txt")
        run_phase3("phase3-kb-admission-source-pass", kb_root, expect_success=True)
        assert_exit_code("phase3-kb-admission-source-pass", 0)
        assert sha256_file(kb_root / "cosmetics-household-chemistry/source-capture.txt") == source_hash
        assert (PHASE3_ROOT / "runs" / "phase3-kb-admission-source-pass" / "input" / "admission_manifest.json").is_file()
        assert (PHASE3_ROOT / "runs" / "phase3-kb-admission-source-pass" / "input" / "kb_integration.yaml").is_file()
        assert_action("phase3-kb-admission-source-pass", "copied", "destination_missing")

        make_manifest_and_target("phase3-kb-admission-knowledge-pass", integration_ref, "knowledge_asset", "prepared/knowledge.md", knowledge_hash, "cosmetics-household-chemistry/knowledge.md")
        run_phase3("phase3-kb-admission-knowledge-pass", kb_root, expect_success=True)
        assert_exit_code("phase3-kb-admission-knowledge-pass", 0)
        assert sha256_file(kb_root / "cosmetics-household-chemistry/knowledge.md") == knowledge_hash
        assert_action("phase3-kb-admission-knowledge-pass", "copied", "destination_missing")

        make_manifest_and_target("phase3-kb-admission-idempotent", integration_ref, "source_capture", "prepared/source-capture.txt", source_hash, "cosmetics-household-chemistry/source-capture.txt")
        run_phase3("phase3-kb-admission-idempotent", kb_root, expect_success=True)
        assert_exit_code("phase3-kb-admission-idempotent", 0)
        assert_action("phase3-kb-admission-idempotent", "idempotent", "same_hash_existing")

        kb_root.joinpath("cosmetics-household-chemistry/unsafe-overwrite.txt").write_text("different existing bytes\n", encoding="utf-8")
        make_manifest_and_target("phase3-kb-admission-unsafe-overwrite", integration_ref, "source_capture", "prepared/source-capture.txt", source_hash, "cosmetics-household-chemistry/unsafe-overwrite.txt")
        run_phase3("phase3-kb-admission-unsafe-overwrite", kb_root, expect_success=False)
        assert_exit_code("phase3-kb-admission-unsafe-overwrite", 1)
        assert_action("phase3-kb-admission-unsafe-overwrite", "failed_closed", "different_hash_existing")
        assert (kb_root / "cosmetics-household-chemistry/unsafe-overwrite.txt").read_text(encoding="utf-8") == "different existing bytes\n"

        kb_root.joinpath("prepared/atomic-new.txt").write_text("atomic new bytes\n", encoding="utf-8")
        kb_root.joinpath("prepared/atomic-second.txt").write_text("atomic second new bytes\n", encoding="utf-8")
        kb_root.joinpath("cosmetics-household-chemistry/atomic-blocked.txt").write_text("atomic existing bytes\n", encoding="utf-8")
        atomic_manifest = PHASE3_ROOT / "runs" / "phase3-kb-admission-atomic-preflight-target" / "admission_manifest.json"
        write_two_artifact_manifest(
            atomic_manifest,
            ("prepared/atomic-new.txt", sha256_file(kb_root / "prepared/atomic-new.txt"), "cosmetics-household-chemistry/atomic-would-copy.txt"),
            ("prepared/atomic-second.txt", sha256_file(kb_root / "prepared/atomic-second.txt"), "cosmetics-household-chemistry/atomic-blocked.txt"),
        )
        write_target("phase3-kb-admission-atomic-preflight", integration_ref, repo_ref(atomic_manifest))
        run_phase3("phase3-kb-admission-atomic-preflight", kb_root, expect_success=False)
        assert_exit_code("phase3-kb-admission-atomic-preflight", 1)
        assert not (kb_root / "cosmetics-household-chemistry/atomic-would-copy.txt").exists()
        assert (kb_root / "cosmetics-household-chemistry/atomic-blocked.txt").read_text(encoding="utf-8") == "atomic existing bytes\n"
        assert_atomic_evidence("phase3-kb-admission-atomic-preflight")

        for run_id, root_value, unset in [
            ("phase3-kb-admission-missing-env", kb_root, True),
            ("phase3-kb-admission-empty-env", None, False),
            ("phase3-kb-admission-nonexistent-root", tmp / "does-not-exist", False),
        ]:
            make_manifest_and_target(run_id, integration_ref, "source_capture", "prepared/source-capture.txt", source_hash, f"cosmetics-household-chemistry/{run_id}.txt")
            run_phase3(run_id, root_value, expect_success=False, unset_env=unset)
            assert_exit_code(run_id, 1)
            assert_pre_apply_failed(run_id)

        root_inside_run = "phase3-kb-admission-root-inside-repo"
        root_inside = PHASE3_ROOT / "runs" / f"{root_inside_run}-inside-root"
        root_inside.joinpath("prepared").mkdir(parents=True)
        root_inside.joinpath("prepared/source.txt").write_text("inside repo root bytes\n", encoding="utf-8")
        make_manifest_and_target(root_inside_run, integration_ref, "source_capture", "prepared/source.txt", sha256_file(root_inside / "prepared/source.txt"), "dest.txt")
        run_phase3(root_inside_run, root_inside, expect_success=False)
        assert_exit_code(root_inside_run, 1)
        assert_pre_apply_failed(root_inside_run)

        root_link = tmp / "workspace-kb-link"
        root_link.symlink_to(kb_root)
        make_manifest_and_target("phase3-kb-admission-root-symlink", integration_ref, "source_capture", "prepared/source-capture.txt", source_hash, "cosmetics-household-chemistry/root-symlink.txt")
        run_phase3("phase3-kb-admission-root-symlink", root_link, expect_success=False)
        assert_exit_code("phase3-kb-admission-root-symlink", 1)
        assert_pre_apply_failed("phase3-kb-admission-root-symlink")

        unsafe_destinations = {
            "phase3-kb-admission-absolute-destination": str(tmp / "absolute-bad.txt"),
            "phase3-kb-admission-traversal-destination": "../outside.txt",
            "phase3-kb-admission-windows-destination": "C:/outside.txt",
            "phase3-kb-admission-empty-segment": "bad//segment.txt",
        }
        for run_id, destination in unsafe_destinations.items():
            make_manifest_and_target(run_id, integration_ref, "source_capture", "prepared/source-capture.txt", source_hash, destination)
            run_phase3(run_id, kb_root, expect_success=False)
            assert_exit_code(run_id, 1)
            assert_pre_apply_failed(run_id)

        (kb_root / "link-out").symlink_to(outside_root)
        make_manifest_and_target("phase3-kb-admission-symlink-traversal", integration_ref, "source_capture", "prepared/source-capture.txt", source_hash, "link-out/bad.txt")
        run_phase3("phase3-kb-admission-symlink-traversal", kb_root, expect_success=False)
        assert_exit_code("phase3-kb-admission-symlink-traversal", 1)
        assert_pre_apply_failed("phase3-kb-admission-symlink-traversal")
        assert not (outside_root / "bad.txt").exists()

        (kb_root / "nested").mkdir()
        (kb_root / "nested/link-out").symlink_to(outside_root)
        make_manifest_and_target("phase3-kb-admission-nested-symlink", integration_ref, "source_capture", "prepared/source-capture.txt", source_hash, "nested/link-out/bad.txt")
        run_phase3("phase3-kb-admission-nested-symlink", kb_root, expect_success=False)
        assert_exit_code("phase3-kb-admission-nested-symlink", 1)
        assert_pre_apply_failed("phase3-kb-admission-nested-symlink")
        assert not (outside_root / "bad.txt").exists()

        make_manifest_and_target("phase3-kb-admission-same-source-destination", integration_ref, "source_capture", "prepared/source-capture.txt", source_hash, "prepared/source-capture.txt")
        run_phase3("phase3-kb-admission-same-source-destination", kb_root, expect_success=False)
        assert_exit_code("phase3-kb-admission-same-source-destination", 1)
        assert_pre_apply_failed("phase3-kb-admission-same-source-destination")

        bad_manifest = PHASE3_ROOT / "runs" / "phase3-kb-admission-bad-integration-absolute-target" / "admission_manifest.json"
        write_manifest(bad_manifest, "source_capture", "prepared/source-capture.txt", source_hash, "cosmetics-household-chemistry/bad-integration-absolute.txt")
        write_target("phase3-kb-admission-bad-integration-absolute", "/tmp/bad-kb-template.yaml", repo_ref(bad_manifest))
        run_phase3("phase3-kb-admission-bad-integration-absolute", kb_root, expect_success=False)
        assert_exit_code("phase3-kb-admission-bad-integration-absolute", 1)

        bad_manifest = PHASE3_ROOT / "runs" / "phase3-kb-admission-bad-integration-traversal-target" / "admission_manifest.json"
        write_manifest(bad_manifest, "source_capture", "prepared/source-capture.txt", source_hash, "cosmetics-household-chemistry/bad-integration-traversal.txt")
        write_target("phase3-kb-admission-bad-integration-traversal", "../kb.template.yaml", repo_ref(bad_manifest))
        run_phase3("phase3-kb-admission-bad-integration-traversal", kb_root, expect_success=False)
        assert_exit_code("phase3-kb-admission-bad-integration-traversal", 1)

        outside_integration = tmp / "outside-integration.yaml"
        outside_integration.write_text("version: 1\n", encoding="utf-8")
        integration_link = FIXTURE_DIR / "outside-integration-link.yaml"
        integration_link.symlink_to(outside_integration)
        bad_manifest = PHASE3_ROOT / "runs" / "phase3-kb-admission-bad-integration-symlink-target" / "admission_manifest.json"
        write_manifest(bad_manifest, "source_capture", "prepared/source-capture.txt", source_hash, "cosmetics-household-chemistry/bad-integration-symlink.txt")
        write_target("phase3-kb-admission-bad-integration-symlink", repo_ref(integration_link), repo_ref(bad_manifest))
        run_phase3("phase3-kb-admission-bad-integration-symlink", kb_root, expect_success=False)
        assert_exit_code("phase3-kb-admission-bad-integration-symlink", 1)

        for run_id, manifest_ref in [
            ("phase3-kb-admission-bad-manifest-absolute", "/tmp/bad-manifest.json"),
            ("phase3-kb-admission-bad-manifest-traversal", "../bad-manifest.json"),
        ]:
            write_target(run_id, integration_ref, manifest_ref)
            run_phase3(run_id, kb_root, expect_success=False)
            assert_exit_code(run_id, 1)

        outside_manifest = tmp / "outside-manifest.json"
        write_manifest(outside_manifest, "source_capture", "prepared/source-capture.txt", source_hash, "cosmetics-household-chemistry/bad-manifest-symlink.txt")
        manifest_link = FIXTURE_DIR / "outside-manifest-link.json"
        manifest_link.symlink_to(outside_manifest)
        write_target("phase3-kb-admission-bad-manifest-symlink", integration_ref, repo_ref(manifest_link))
        run_phase3("phase3-kb-admission-bad-manifest-symlink", kb_root, expect_success=False)
        assert_exit_code("phase3-kb-admission-bad-manifest-symlink", 1)

        invalid_integration = FIXTURE_DIR / "invalid-kb.template.yaml"
        write_integration(invalid_integration, valid=False)
        invalid_manifest = PHASE3_ROOT / "runs" / "phase3-kb-admission-invalid-integration-target" / "admission_manifest.json"
        write_manifest(invalid_manifest, "source_capture", "prepared/source-capture.txt", source_hash, "cosmetics-household-chemistry/invalid-integration.txt")
        write_target("phase3-kb-admission-invalid-integration", repo_ref(invalid_integration), repo_ref(invalid_manifest))
        run_phase3("phase3-kb-admission-invalid-integration", kb_root, expect_success=False)
        assert_exit_code("phase3-kb-admission-invalid-integration", 1)
        assert_pre_apply_failed("phase3-kb-admission-invalid-integration")

        invalid_manifest = PHASE3_ROOT / "runs" / "phase3-kb-admission-invalid-manifest-target" / "admission_manifest.json"
        write_invalid_manifest(invalid_manifest)
        write_target("phase3-kb-admission-invalid-manifest", integration_ref, repo_ref(invalid_manifest))
        run_phase3("phase3-kb-admission-invalid-manifest", kb_root, expect_success=False)
        assert_exit_code("phase3-kb-admission-invalid-manifest", 1)
        assert_pre_apply_failed("phase3-kb-admission-invalid-manifest")

        print("PASS kb_admission source_capture pass into temp workspace KB root")
        print("PASS kb_admission knowledge_asset pass into temp workspace KB root")
        print("PASS kb_admission idempotent rerun with same hash")
        print("PASS kb_admission unsafe overwrite fails closed")
        print("PASS kb_admission atomic preflight prevents partial writes")
        print("PASS kb_admission missing/empty/nonexistent env root failures")
        print("PASS kb_admission rejects repo and symlink KB roots")
        print("PASS kb_admission rejects unsafe destination paths and symlink traversal")
        print("PASS kb_admission rejects same source/destination path")
        print("PASS kb_admission rejects bad refs before write")
        print("PASS kb_admission rejects invalid integration and manifest before write")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
        shutil.rmtree(PHASE2_RUN_DIR, ignore_errors=True)
        shutil.rmtree(FIXTURE_DIR, ignore_errors=True)
        for run_id in RUN_IDS:
            shutil.rmtree(PHASE3_ROOT / "runs" / run_id, ignore_errors=True)
            shutil.rmtree(PHASE3_ROOT / "runs" / f"{run_id}-target", ignore_errors=True)
            shutil.rmtree(PHASE3_ROOT / "runs" / f"{run_id}-inside-root", ignore_errors=True)


if __name__ == "__main__":
    main()
