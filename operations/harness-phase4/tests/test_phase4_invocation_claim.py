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
from typing import Any, Callable


PHASE4_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = PHASE4_ROOT.parent.parent
PHASE3_ROOT = REPO_ROOT / "operations" / "harness-phase3"
PHASE2_RUN_ID = "phase4-proof-phase2-input"
PHASE2_RUN_DIR = REPO_ROOT / "operations" / "harness-phase2" / "runs" / PHASE2_RUN_ID
GENERATED_PATHS: list[Path] = []


def fail(message: str) -> None:
    raise AssertionError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def repo_ref(path: Path) -> str:
    return path.resolve(strict=False).relative_to(REPO_ROOT.resolve(strict=False)).as_posix()


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_integration(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        """version: 1
integration: kb
enabled: true
target_runtime: workspace
root_path_env: OPENCLAW_WORKSPACE_KB_ROOT
default_root_hint: /tmp/openclaw-workspace-kb
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


def write_manifest(path: Path, source_ref: str, expected_sha: str, destination_ref: str) -> None:
    write_json(
        path,
        {
            "admission_type": "knowledge_asset",
            "lineage": {
                "source_ref": "test://phase4-invocation-proof",
                "captured_from": "phase4-invocation-proof-fixture",
                "captured_at": "2026-06-20T00:00:00Z",
            },
            "copy_operation": {
                "operation_type": "copy",
                "content_mode": "byte_for_byte",
                "overwrite_policy": "fail_closed_on_hash_mismatch",
                "requested_by": "test://phase4-invocation-proof",
            },
            "artifacts": [
                {
                    "input_workspace_path": source_ref,
                    "expected_sha256": expected_sha,
                    "destination_kb_path": destination_ref,
                    "copy_metadata": {"label": "phase4 proof fixture"},
                }
            ],
        },
    )


def write_target(run_id: str, target_path: Path, integration_ref: str, manifest_ref: str) -> None:
    write_json(
        target_path,
        {
            "target_runtime": "workspace",
            "target_kind": "kb_admission",
            "kb_integration_ref": integration_ref,
            "admission_manifest_ref": manifest_ref,
            "invoked_by": "test://not-proof",
        },
    )


def base_claim(wrapper_run_id: str, run_id: str, target_path: Path) -> dict[str, Any]:
    target_hash = sha256_file(target_path)
    wrapper_ref = f"operations/harness-phase4/runs/{wrapper_run_id}"
    return {
        "schema_name": "phase4_invocation_claim",
        "schema_version": "1.0",
        "claim_id": f"phase4-invocation:{wrapper_run_id}:{run_id}:{target_hash}",
        "wrapper_run_id": wrapper_run_id,
        "wrapper_run_ref": wrapper_ref,
        "phase3_run_id": run_id,
        "phase3_run_ref": f"operations/harness-phase3/runs/{run_id}",
        "target_kind": "kb_admission",
        "execution_target_ref": repo_ref(target_path),
        "execution_target_sha256": target_hash,
        "phase2_run_ref": f"operations/harness-phase2/runs/{PHASE2_RUN_ID}",
        "created_at": "2026-06-20T00:00:00Z",
        "invocation_intent": "phase4_wrapper_invokes_phase3_kb_admission",
        "invariants": {
            "phase3_canonical_execution_owner": True,
            "phase4_thin_wrapper_only": True,
            "phase4_claim_ref": f"{wrapper_ref}/phase4_invocation_claim.json",
            "phase4_owns_canonical_outputs": False,
            "proof_scope": "repo_contained_exact_run_linkage_not_cryptographic_authentication",
        },
    }


def write_claim(wrapper_run_id: str, run_id: str, target_path: Path, mutate: Callable[[dict[str, Any]], None] | None = None) -> Path:
    claim = base_claim(wrapper_run_id, run_id, target_path)
    if mutate:
        mutate(claim)
    claim_path = PHASE4_ROOT / "runs" / wrapper_run_id / "phase4_invocation_claim.json"
    write_json(claim_path, claim)
    GENERATED_PATHS.append(PHASE4_ROOT / "runs" / wrapper_run_id)
    return claim_path


def make_case(tmp: Path, run_id: str) -> tuple[Path, str, Path, str]:
    case_dir = PHASE4_ROOT / "runs" / f"{run_id}-target"
    GENERATED_PATHS.append(case_dir)
    fixture_dir = tmp / run_id
    fixture_dir.mkdir(parents=True)
    source_rel = f"prepared/{run_id}.md"
    source_file = tmp / "workspace-kb" / source_rel
    source_file.parent.mkdir(parents=True, exist_ok=True)
    source_file.write_text(f"# {run_id}\n\nStable bytes.\n", encoding="utf-8")
    integration_path = case_dir / "kb.template.yaml"
    manifest_path = case_dir / "admission_manifest.json"
    target_path = case_dir / "execution_target.json"
    destination_ref = f"knowledge/{run_id}.md"
    write_integration(integration_path)
    write_manifest(manifest_path, source_rel, sha256_file(source_file), destination_ref)
    write_target(run_id, target_path, repo_ref(integration_path), repo_ref(manifest_path))
    return target_path, destination_ref, source_file, sha256_file(source_file)


def run_phase2() -> None:
    env = os.environ.copy()
    env.setdefault("PHASE2_PYTHON_BIN", sys.executable)
    subprocess.run(
        ["bash", "operations/harness-phase2/bin/run_phase2_bundle.sh", PHASE2_RUN_ID],
        cwd=REPO_ROOT,
        env=env,
        check=True,
    )


def run_phase3(run_id: str, target_path: Path, claim_path: Path | str | None, kb_root: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["OPENCLAW_WORKSPACE_KB_ROOT"] = str(kb_root)
    env.setdefault("PHASE3_PYTHON_BIN", sys.executable)
    env.setdefault("PHASE2_PYTHON_BIN", sys.executable)
    command = [
        "bash",
        "operations/harness-phase3/bin/run_phase3_bundle.sh",
        "--phase2-run-dir",
        f"operations/harness-phase2/runs/{PHASE2_RUN_ID}",
        "--execution-target-json",
        repo_ref(target_path),
        "--run-id",
        run_id,
    ]
    if claim_path is not None:
        claim_text = str(claim_path)
        if Path(claim_text).is_absolute():
            try:
                claim_text = repo_ref(Path(claim_text))
            except ValueError:
                claim_text = str(claim_path)
        command.extend(["--phase4-invocation-claim", claim_text])
    return subprocess.run(command, cwd=REPO_ROOT, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)


def assert_failed_before_apply(run_id: str, destination: Path, result: subprocess.CompletedProcess[str]) -> None:
    if result.returncode == 0:
        fail(f"{run_id} unexpectedly passed:\n{result.stdout}")
    if destination.exists():
        fail(f"{run_id} unexpectedly wrote destination {destination}")
    run_dir = PHASE3_ROOT / "runs" / run_id
    if (run_dir / "logs" / "apply.log").exists():
        fail(f"{run_id} reached apply.log unexpectedly")
    if (run_dir / "execution_result.json").exists():
        fail(f"{run_id} emitted execution_result unexpectedly")


def test_positive_phase4_route(tmp: Path) -> None:
    run_id = "phase4-proof-positive-phase3"
    wrapper_run_id = "phase4-proof-positive-wrapper"
    target_path, destination_ref, _source_file, source_hash = make_case(tmp, run_id)
    wrapper_run_dir = PHASE4_ROOT / "runs" / wrapper_run_id
    GENERATED_PATHS.extend([wrapper_run_dir, PHASE3_ROOT / "runs" / run_id])
    env = os.environ.copy()
    env["OPENCLAW_WORKSPACE_KB_ROOT"] = str(tmp / "workspace-kb")
    env.setdefault("PHASE4_PYTHON_BIN", sys.executable)
    env.setdefault("PHASE3_PYTHON_BIN", sys.executable)
    env.setdefault("PHASE2_PYTHON_BIN", sys.executable)
    result = subprocess.run(
        [
            "bash",
            "operations/harness-phase4/bin/run_phase4_wrapper.sh",
            "--phase2-run-dir",
            f"operations/harness-phase2/runs/{PHASE2_RUN_ID}",
            "--execution-target-json",
            repo_ref(target_path),
            "--phase3-run-id",
            run_id,
            "--operator",
            "phase4-proof-test",
            "--wrapper-run-id",
            wrapper_run_id,
        ],
        cwd=REPO_ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode != 0:
        fail(f"positive Phase4 route failed:\n{result.stdout}")

    claim_path = wrapper_run_dir / "phase4_invocation_claim.json"
    frozen_claim_path = PHASE3_ROOT / "runs" / run_id / "input" / "phase4_invocation_claim.json"
    target_hash = sha256_file(PHASE3_ROOT / "runs" / run_id / "input" / "execution_target.json")
    validation = json.loads((PHASE3_ROOT / "runs" / run_id / "checks" / "phase4_invocation_validation.json").read_text(encoding="utf-8-sig"))
    invocation = json.loads((wrapper_run_dir / "phase3_invocation.json").read_text(encoding="utf-8-sig"))

    assert claim_path.is_file(), claim_path
    assert frozen_claim_path.is_file(), frozen_claim_path
    assert claim_path.read_bytes() == frozen_claim_path.read_bytes()
    assert sha256_file(claim_path) == sha256_file(frozen_claim_path)
    assert validation["status"] == "pass", validation
    assert validation["hashes"]["claim_execution_target_sha256"] == target_hash, validation
    assert validation["refs"]["wrapper_run_ref"] == f"operations/harness-phase4/runs/{wrapper_run_id}", validation
    assert invocation["phase3_invoked"] is True, invocation
    assert invocation["phase4_invocation_claim_ref"] == f"operations/harness-phase4/runs/{wrapper_run_id}/phase4_invocation_claim.json", invocation
    assert (tmp / "workspace-kb" / destination_ref).is_file()
    assert sha256_file(tmp / "workspace-kb" / destination_ref) == source_hash
    for forbidden in ["report.json", "report.md", "exit_code", "execution_result.json"]:
        assert not (wrapper_run_dir / forbidden).exists(), forbidden
    for required in ["report.json", "report.md", "exit_code", "execution_result.json"]:
        assert (PHASE3_ROOT / "runs" / run_id / required).is_file(), required


def test_negative_matrix(tmp: Path) -> None:
    cases: list[tuple[str, Callable[[Path, str, Path], Path | str | None]]] = []

    cases.append(("direct-no-claim", lambda _target, _run, _tmp: None))
    cases.append(("missing-claim-path", lambda _target, run, _tmp: f"operations/harness-phase4/runs/{run}-wrapper/phase4_invocation_claim.json"))
    cases.append(("malformed-json", lambda target, run, _tmp: write_malformed_claim(run, target)))
    cases.append(("schema-invalid", lambda target, run, _tmp: write_claim(f"{run}-wrapper", run, target, lambda claim: claim.pop("claim_id"))))
    cases.append(("wrong-phase3-run-id", lambda target, run, _tmp: write_claim(f"{run}-wrapper", run, target, lambda claim: claim.update({"phase3_run_id": f"{run}-other", "phase3_run_ref": f"operations/harness-phase3/runs/{run}-other"}))))
    cases.append(("wrong-wrapper-run-id", lambda target, run, _tmp: write_claim(f"{run}-wrapper", run, target, lambda claim: claim.update({"wrapper_run_id": f"{run}-other", "wrapper_run_ref": f"operations/harness-phase4/runs/{run}-other"}))))
    cases.append(("wrong-target-kind", lambda target, run, _tmp: write_claim(f"{run}-wrapper", run, target, lambda claim: claim.update({"target_kind": "repo_admission"}))))
    cases.append(("target-ref-mismatch", lambda target, run, _tmp: write_claim(f"{run}-wrapper", run, target, lambda claim: claim.update({"execution_target_ref": "operations/harness-phase4/runs/other/execution_target.json"}))))
    cases.append(("target-sha-mismatch", lambda target, run, _tmp: write_claim(f"{run}-wrapper", run, target, lambda claim: claim.update({"execution_target_sha256": "0" * 64, "claim_id": f"phase4-invocation:{run}-wrapper:{run}:{'0' * 64}"}))))
    cases.append(("phase2-ref-mismatch", lambda target, run, _tmp: write_claim(f"{run}-wrapper", run, target, lambda claim: claim.update({"phase2_run_ref": "operations/harness-phase2/runs/other-run"}))))
    cases.append(("claim-from-another-wrapper", lambda target, run, _tmp: write_claim(f"{run}-wrapper", run, target, lambda claim: claim.update({"wrapper_run_id": f"{run}-foreign", "wrapper_run_ref": f"operations/harness-phase4/runs/{run}-foreign", "invariants": {**claim["invariants"], "phase4_claim_ref": f"operations/harness-phase4/runs/{run}-foreign/phase4_invocation_claim.json"}}))))
    cases.append(("claim-from-another-phase3", lambda target, run, _tmp: write_claim(f"{run}-wrapper", run, target, lambda claim: claim.update({"phase3_run_id": f"{run}-foreign", "phase3_run_ref": f"operations/harness-phase3/runs/{run}-foreign"}))))
    cases.append(("replayed-claim", lambda target, run, _tmp: write_claim(f"{run}-wrapper", f"{run}-source", target)))
    cases.append(("path-traversal", lambda target, run, _tmp: traversal_claim(run, target)))
    cases.append(("outside-phase4-surface", lambda target, run, case_tmp: outside_claim(case_tmp, run, target)))
    cases.append(("symlink-substitution", lambda target, run, _tmp: symlink_claim(run, target)))

    for suffix, claim_factory in cases:
        run_id = f"phase4-proof-{suffix}"
        target_path, destination_ref, _source_file, _source_hash = make_case(tmp, run_id)
        claim_path = claim_factory(target_path, run_id, tmp)
        result = run_phase3(run_id, target_path, claim_path, tmp / "workspace-kb")
        GENERATED_PATHS.append(PHASE3_ROOT / "runs" / run_id)
        assert_failed_before_apply(run_id, tmp / "workspace-kb" / destination_ref, result)

    run_id = "phase4-proof-claim-reused-with-another-target"
    target_a, _destination_a, _source_a, _hash_a = make_case(tmp, f"{run_id}-source")
    target_b, destination_b, _source_b, _hash_b = make_case(tmp, run_id)
    claim_path = write_claim(f"{run_id}-wrapper", run_id, target_a)
    result = run_phase3(run_id, target_b, claim_path, tmp / "workspace-kb")
    GENERATED_PATHS.append(PHASE3_ROOT / "runs" / run_id)
    assert_failed_before_apply(run_id, tmp / "workspace-kb" / destination_b, result)


def write_malformed_claim(run_id: str, target_path: Path) -> Path:
    wrapper_run_id = f"{run_id}-wrapper"
    path = PHASE4_ROOT / "runs" / wrapper_run_id / "phase4_invocation_claim.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("{not-json\n", encoding="utf-8")
    GENERATED_PATHS.append(path.parent)
    return path


def traversal_claim(run_id: str, target_path: Path) -> str:
    wrapper_run_id = f"{run_id}-wrapper"
    write_claim(wrapper_run_id, run_id, target_path)
    return f"operations/harness-phase4/runs/{wrapper_run_id}/../{wrapper_run_id}/phase4_invocation_claim.json"


def outside_claim(tmp: Path, run_id: str, target_path: Path) -> Path:
    path = tmp / f"{run_id}-outside-claim.json"
    path.write_text(json.dumps(base_claim(f"{run_id}-wrapper", run_id, target_path), indent=2) + "\n", encoding="utf-8")
    return path


def symlink_claim(run_id: str, target_path: Path) -> str:
    real_wrapper = f"{run_id}-real-wrapper"
    link_wrapper = f"{run_id}-wrapper"
    real_claim = write_claim(real_wrapper, run_id, target_path)
    link_path = PHASE4_ROOT / "runs" / link_wrapper / "phase4_invocation_claim.json"
    link_path.parent.mkdir(parents=True, exist_ok=True)
    link_path.symlink_to(real_claim)
    GENERATED_PATHS.append(link_path.parent)
    return f"operations/harness-phase4/runs/{link_wrapper}/phase4_invocation_claim.json"


def main() -> None:
    tmp = Path(tempfile.mkdtemp(prefix="phase4-invocation-proof-"))
    try:
        shutil.rmtree(PHASE2_RUN_DIR, ignore_errors=True)
        run_phase2()
        test_positive_phase4_route(tmp)
        test_negative_matrix(tmp)
        print("PASS Phase4 wrapper generates and transfers kb_admission invocation proof")
        print("PASS Phase3 freezes and validates Phase4 invocation proof before apply")
        print("PASS mandatory negative Phase4 invocation-proof cases fail before apply")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
        shutil.rmtree(PHASE2_RUN_DIR, ignore_errors=True)
        for path in sorted(set(GENERATED_PATHS), key=lambda item: len(item.parts), reverse=True):
            shutil.rmtree(path, ignore_errors=True)


if __name__ == "__main__":
    main()
