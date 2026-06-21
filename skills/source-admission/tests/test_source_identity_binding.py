#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
HELPER_PATH = REPO_ROOT / "skills/source-admission/scripts/check_source_admission_inputs.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("check_source_admission_inputs", HELPER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load helper: {HELPER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HELPER = load_helper()


class SourceIdentityBindingTest(unittest.TestCase):
    def write_json(self, path: Path, payload: dict[str, object]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    def write_fixture(self, proof_dir: Path, *, artifact_id: str | None, source_id: str | None) -> None:
        source_payload: dict[str, object] = {
            "canonical_pointer": "https://example.com/source",
            "retrieval_status": "success",
        }
        if source_id is not None:
            source_payload["source_id"] = source_id
        self.write_json(proof_dir / "source-capture-package.json", source_payload)

        placement: dict[str, object] = {
            "target_layer": "kb",
            "artifact_type": "source-capture-package",
        }
        if artifact_id is not None:
            placement["artifact_id"] = artifact_id
        self.write_json(
            proof_dir / "admission-fixture.json",
            {
                "target_layer": "kb",
                "source_capture_package_ref": "source-capture-package.json",
                "placement": placement,
            },
        )

    def check_fixture(self, proof_dir: Path) -> list[str]:
        return HELPER.check_phase2_fixture(REPO_ROOT, proof_dir, "admission-fixture.json")

    def test_matching_artifact_id_and_source_id_passes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="source-identity-binding-") as tmp:
            proof_dir = Path(tmp)
            self.write_fixture(proof_dir, artifact_id="source-example-001", source_id="source-example-001")
            self.assertEqual(self.check_fixture(proof_dir), [])

    def test_mismatching_artifact_id_and_source_id_fails(self) -> None:
        with tempfile.TemporaryDirectory(prefix="source-identity-binding-") as tmp:
            proof_dir = Path(tmp)
            self.write_fixture(proof_dir, artifact_id="source-example-001", source_id="source-other-001")
            failures = self.check_fixture(proof_dir)
            self.assertIn(
                "admission-fixture placement.artifact_id must exactly match source_capture_package.source_id: "
                "source-example-001 != source-other-001",
                failures,
            )

    def test_missing_identity_fails(self) -> None:
        with tempfile.TemporaryDirectory(prefix="source-identity-binding-") as tmp:
            proof_dir = Path(tmp)
            self.write_fixture(proof_dir, artifact_id="source-example-001", source_id=None)
            failures = self.check_fixture(proof_dir)
            self.assertIn("source_capture_package.source_id must be a non-empty string", failures)

        with tempfile.TemporaryDirectory(prefix="source-identity-binding-") as tmp:
            proof_dir = Path(tmp)
            self.write_fixture(proof_dir, artifact_id=None, source_id="source-example-001")
            failures = self.check_fixture(proof_dir)
            self.assertIn("admission-fixture placement.artifact_id must be a non-empty string", failures)


if __name__ == "__main__":
    unittest.main()
