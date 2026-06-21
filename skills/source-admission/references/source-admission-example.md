# Source admission example

Example request: “Admit `https://example.com/article` as a sanctioned source-bearing KB asset.”

Core rule: this example prepares inputs; canonical admission happens only after Phase3 `workspace/kb_admission` succeeds.

## Layout

Workspace KB preparation area, relative to `/home/node/.openclaw/workspace/kb`:

```text
domain/web/workflow/source-admission-example-001/
├── raw/source.html
├── raw/source-readable.txt
├── task-packet.json
├── source-capture-package.json
├── result-packet.json
├── review-decision.json
├── admission-decision.json
├── placement-decision.json
└── admission-fixture.json
```

Repo-contained Phase3 target area:

```text
<repo-contained-source-admission-target-dir>/
├── admission_manifest.json
└── execution_target.json
```

Do not place pre-Phase target inputs under canonical Phase3 run-dir unless following existing test fixtures. Canonical Phase3 run evidence lives under `operations/harness-phase3/runs/<PHASE3_RUN_ID>/`.

Final KB destination is created only by Phase3:

```text
/home/node/.openclaw/workspace/kb/domain/web/sources/source-example-article-001/
├── source-capture-package.json
├── source.html
└── source-readable.txt
```

## Source package

`domain/web/workflow/source-admission-example-001/source-capture-package.json`:

```json
{
  "source_id": "source-example-article-001",
  "canonical_pointer": "https://example.com/article",
  "retrieval_status": "success",
  "retrieval_timestamp": "2026-06-03T05:00:00Z",
  "content_type": "text/html; charset=UTF-8",
  "stable_representation": "domain/web/workflow/source-admission-example-001/raw/source.html",
  "human_identifier": "Example — Article",
  "provenance_notes": "Captured by controlled web fetch into workspace KB workflow area.",
  "linkage": ["task-source-example-article-001"],
  "capture_method": "web-capture",
  "hash": "sha256:replace-with-real-hash"
}
```

## Result packet

`domain/web/workflow/source-admission-example-001/result-packet.json`:

```json
{
  "task_id": "task-source-example-article-001",
  "result_summary": "Prepared a source capture package for KB source admission.",
  "produced_artifacts": [
    {
      "artifact_id": "source-example-article-001",
      "artifact_type": "source-capture-package",
      "artifact_role": "source-bearing",
      "ref": "domain/web/workflow/source-admission-example-001/source-capture-package.json"
    }
  ],
  "unresolved_issues": [],
  "confidence": "high",
  "evidence": [
    {
      "type": "source-package",
      "ref": "domain/web/workflow/source-admission-example-001/source-capture-package.json",
      "description": "Validated source capture package"
    }
  ],
  "suggested_placement": "kb",
  "suggested_followups": []
}
```

## Review / admission / placement evidence

`review-decision.json`:

```json
{
  "artifact_id": "source-example-article-001",
  "decision": "approve",
  "rationale": "Source package preserves canonical pointer, retrieval metadata, stable representation, and provenance suitable for KB source admission.",
  "blocking_issues": [],
  "required_changes": [],
  "approved_destination": "kb"
}
```

`admission-decision.json`:

```json
{
  "run_id": "source-example-article-kb-admission",
  "generated_at": "2026-06-03T05:00:00Z",
  "engine_mode": "scaffold",
  "evaluation_mode": "static-v1",
  "decision": "approved",
  "checklist": [
    "candidate_class=source-bearing",
    "source_capture_package_schema=pass",
    "stable_representation=present",
    "review_decision_approves_kb=pass",
    "blockers=none"
  ],
  "blockers": []
}
```

`placement-decision.json`:

```json
{
  "run_id": "source-example-article-kb-placement",
  "generated_at": "2026-06-03T05:00:00Z",
  "engine_mode": "scaffold",
  "evaluation_mode": "static-v1",
  "decision": "approved",
  "target_layer": "kb",
  "target_path": "domain/web/sources/source-example-article-001/source-capture-package.json",
  "rationale": "Approved source-bearing package belongs in workspace KB sources, not repo knowledge/kb or draft workflow storage."
}
```

## Phase2 admission fixture

`admission-fixture.json`:

```json
{
  "target_layer": "kb",
  "result_packet_ref": "result-packet.json",
  "source_capture_package_ref": "source-capture-package.json",
  "review_decision_ref": "review-decision.json",
  "admission_decision": {
    "run_id": "source-example-article-kb-admission",
    "generated_at": "2026-06-03T05:00:00Z",
    "engine_mode": "scaffold",
    "evaluation_mode": "static-v1",
    "decision": "approved",
    "checklist": ["candidate_class=source-bearing", "blockers=none"],
    "blockers": []
  },
  "placement": {
    "target_layer": "kb",
    "artifact_id": "source-example-article-001",
    "artifact_type": "source-capture-package"
  }
}
```

This fixture is for Phase2 readiness semantics only. It is not an apply/admission engine.

## Phase3 admission manifest

`<repo-contained-source-admission-target-dir>/admission_manifest.json`:

```json
{
  "admission_type": "source_capture",
  "lineage": {
    "task_packet_ref": "domain/web/workflow/source-admission-example-001/task-packet.json",
    "result_packet_ref": "domain/web/workflow/source-admission-example-001/result-packet.json",
    "review_decision_ref": "domain/web/workflow/source-admission-example-001/review-decision.json",
    "admission_decision_ref": "domain/web/workflow/source-admission-example-001/admission-decision.json",
    "placement_decision_ref": "domain/web/workflow/source-admission-example-001/placement-decision.json"
  },
  "copy_operation": {
    "operation_type": "copy",
    "content_mode": "byte_for_byte",
    "overwrite_policy": "fail_closed_on_hash_mismatch",
    "requested_by": "agent://source-admission"
  },
  "artifacts": [
    {
      "input_workspace_path": "domain/web/workflow/source-admission-example-001/source-capture-package.json",
      "expected_sha256": "replacewith64lowercasehexsha256sourcepackage",
      "destination_kb_path": "domain/web/sources/source-example-article-001/source-capture-package.json",
      "copy_metadata": {"artifact_type": "source-capture-package"}
    },
    {
      "input_workspace_path": "domain/web/workflow/source-admission-example-001/raw/source.html",
      "expected_sha256": "replacewith64lowercasehexsha256sourcehtml",
      "destination_kb_path": "domain/web/sources/source-example-article-001/source.html",
      "copy_metadata": {"artifact_type": "stable-source-representation"}
    },
    {
      "input_workspace_path": "domain/web/workflow/source-admission-example-001/raw/source-readable.txt",
      "expected_sha256": "replacewith64lowercasehexsha256readabletxt",
      "destination_kb_path": "domain/web/sources/source-example-article-001/source-readable.txt",
      "copy_metadata": {"artifact_type": "readable-source-representation"}
    }
  ]
}
```

`input_workspace_path` and `destination_kb_path` are relative to the configured KB root. Do not prefix them with `/home/...` or `kb/`.

## Phase3 execution target

`<repo-contained-source-admission-target-dir>/execution_target.json`:

```json
{
  "target_runtime": "workspace",
  "target_kind": "kb_admission",
  "kb_integration_ref": "control-plane/runtime/integrations/kb.template.yaml",
  "admission_manifest_ref": "<repo-contained-source-admission-target-dir>/admission_manifest.json",
  "invoked_by": "agent://source-admission"
}
```

Phase3 freezes this target plus the manifest and KB integration into `operations/harness-phase3/runs/<RUN_ID>/input/`.

## Final report pattern

```text
Execution owner:
- pre-Phase preparation: agent-owned preparation
- Phase2 readiness: Phase-owned
- Phase3 admission: Phase-owned

repo-defined:
- source contracts: source_capture_package, task_packet, result_packet, review_decision, admission_decision, placement_decision
- Phase3 target: target_runtime=workspace, target_kind=kb_admission
- Phase3 manifest: admission_type=source_capture, byte_for_byte copy, fail_closed_on_hash_mismatch

pre-Phase preparation:
- stable source files prepared under workspace KB workflow path

Phase-owned evidence:
- Phase2 admission fixture: pass/fail
- Phase2 scaffold/handoff run: <run-id>, handoff_ready=<ready|not ready>
- Phase3 kb_admission run: <run-id>, exit_code=<0|nonzero>, evidence=<path>
- copied destination paths and hashes

limits:
- Phase2 did not admit anything; it only checked readiness
- the skill did not admit anything
- canonical admission claim depends on Phase3 `kb_admission` evidence
- no semantic/distillation knowledge asset admission is claimed
```
