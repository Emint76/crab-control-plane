#!/usr/bin/env python3
"""Emit one Phase 2 sample observability record.

This utility writes only to operations/harness-phase2/reports/.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: emit_observability_record.py <repo-root> <run-id>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve()
    run_id = sys.argv[2]
    if not run_id:
        print("FAIL observability record: run-id must be non-empty", file=sys.stderr)
        return 1

    phase2_root = repo_root / "operations" / "harness-phase2"
    reports_dir = phase2_root / "reports"
    output_path = reports_dir / "observability-sample.jsonl"

    try:
        if not phase2_root.is_dir():
            raise FileNotFoundError(f"missing Phase 2 root: {phase2_root}")
        reports_dir.mkdir(parents=True, exist_ok=True)

        record = {
            "run_id": run_id,
            "actor": "phase2-observability-emitter",
            "task_id": "phase2-observability-sample",
            "action_type": "phase2.check_layer.observability_sample",
            "timestamp": utc_timestamp(),
            "outcome": "sample_emitted",
            "artifact_refs": [],
            "warnings": [],
        }

        with output_path.open("a", encoding="utf-8") as handle:
            json.dump(record, handle, sort_keys=True, separators=(",", ":"))
            handle.write("\n")
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL observability record: {exc}", file=sys.stderr)
        return 1

    print("PASS observability record emitted: operations/harness-phase2/reports/observability-sample.jsonl")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
