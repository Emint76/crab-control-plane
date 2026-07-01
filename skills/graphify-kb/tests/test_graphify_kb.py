from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


verify_graph = load_module("verify_graph", ROOT / "scripts/verify_graph.py")
rebuild_graph = load_module("rebuild_graph", ROOT / "scripts/rebuild_graph.py")


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value) + "\n", encoding="utf-8")


def formulation_text() -> str:
    return """---
asset_id: "formulation-1"
knowledge_type: "formulations"
review_status: "approved"
knowledge_profile_id: "source_to_formulation.v1"
source_id: "source-1"
---
# Fixture

## Composition

| ingredient_ref |
| --- |
| ingredient-1 |
"""


class VerifyGraphTests(unittest.TestCase):
    def fixture(self, root: Path) -> argparse.Namespace:
        formulations = root / "formulations"
        (formulations / "one").mkdir(parents=True)
        (formulations / "one/index.md").write_text(formulation_text(), encoding="utf-8")
        registry = root / "registry.jsonl"
        registry.write_text(json.dumps({"ingredient_id": "ingredient-1", "path": "ingredients/one.md"}) + "\n", encoding="utf-8")
        graph = root / "graph.json"
        write_json(graph, {
            "nodes": [
                {"id": "formulation-1", "type": "Formulation"},
                {"id": "ingredient-1", "type": "Ingredient", "properties": {"reference_path": "ingredients/one.md"}},
                {"id": "source-1", "type": "Source"},
            ],
            "links": [
                {"source": "formulation-1", "target": "ingredient-1", "relation": "USES"},
                {"source": "formulation-1", "target": "source-1", "relation": "DERIVED_FROM"},
            ],
        })
        return argparse.Namespace(graph=graph, registry=registry, formulation_root=formulations, formulation_sha_before=None, out=None)

    def test_duplicate_registry_ingredient_id_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            args = self.fixture(Path(temp))
            row = json.dumps({"ingredient_id": "ingredient-1", "path": "ingredients/one.md"})
            args.registry.write_text(row + "\n" + row + "\n", encoding="utf-8")
            result = verify_graph.verify(args)
            self.assertEqual("FAIL", result["status"])
            self.assertIn("duplicate registry ingredient_id", str(result["errors"]))

    def test_count_mismatch_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            args = self.fixture(Path(temp))
            graph = json.loads(args.graph.read_text(encoding="utf-8"))
            graph["links"].pop()
            write_json(args.graph, graph)
            result = verify_graph.verify(args)
            self.assertEqual("FAIL", result["status"])
            self.assertIn("graph_count_mismatch", [error["code"] for error in result["errors"]])


class RebuildGraphTests(unittest.TestCase):
    def make_output(self, path: Path, status: str = "pass") -> None:
        path.mkdir(parents=True)
        for name in rebuild_graph.OUTPUT_FILES:
            (path / name).write_text("fixture\n", encoding="utf-8")
        graph_sha = hashlib.sha256((path / "graph.json").read_bytes()).hexdigest()
        model_sha = hashlib.sha256((path / "_deterministic_model.json").read_bytes()).hexdigest()
        write_json(path / "determinism.json", {
            "status": status,
            "first_graph_sha256": graph_sha, "second_graph_sha256": graph_sha,
            "first_model_sha256": model_sha, "second_model_sha256": model_sha,
        })

    def test_failed_determinism_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "output"
            self.make_output(output, status="fail")
            self.assertEqual("FAIL", rebuild_graph.validate_determinism(output)["status"])

    def test_post_apply_failure_restores_complete_previous_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            active = root / "output"
            candidate = root / "candidate"
            run_dir = root / "run"
            run_dir.mkdir()
            active.mkdir()
            (active / "old.txt").write_text("old\n", encoding="utf-8")
            self.make_output(candidate)
            with mock.patch.object(rebuild_graph, "ACTIVE_OUTPUT", active), \
                 mock.patch.object(rebuild_graph, "ACTIVE_GRAPH", active / "graph.json"), \
                 mock.patch.object(rebuild_graph, "run_verify", side_effect=[{"status": "PASS"}, {"status": "FAIL"}]):
                result = rebuild_graph.transactional_replace(candidate, run_dir, root / "before.json")
            self.assertEqual("FAIL", result["status"])
            self.assertFalse(result["active_replaced"])
            self.assertEqual("old\n", (active / "old.txt").read_text(encoding="utf-8"))
            self.assertEqual(["old.txt"], sorted(path.name for path in active.iterdir()))


if __name__ == "__main__":
    unittest.main()
