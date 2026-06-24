# Source admission example

Example request: "Admit `https://example.com/article` as a sanctioned source-bearing KB asset."

Core rule: this example prepares inputs; canonical admission happens only after Phase3 `workspace/kb_admission` succeeds.

## Layout

Workspace KB preparation area, relative to `/home/node/.openclaw/workspace/kb`:

```text
domain/web/workflow/source-admission-example-001/
├── payload/
│   ├── source.html
│   └── source-readable.txt
└── source-metadata.json
```

Repo-contained preparation area:

```text
<repo-contained-source-admission-target-dir>/
├── stage1/
│   └── admission_package.json
├── review/
│   └── review-decision.json
├── phase3/
│   ├── admission_manifest.json
│   └── execution_target.json
└── admission_handoff.json
```

Do not place pre-Phase target inputs under a canonical Phase3 run directory unless following existing test fixtures. Canonical Phase3 run evidence lives under `operations/harness-phase3/runs/<PHASE3_RUN_ID>/`.

Final KB destination is created only by Phase3:

```text
/home/node/.openclaw/workspace/kb/domain/web/sources/source-example-article-001/
├── source.html
└── source-readable.txt
```

## Preparation order

1. Prepare the producer-reviewed `admission_package.json`.
2. Prepare the canonical review decision.
3. Establish stable `asset_id`.
4. Choose `asset_slug` as the source-family-local destination directory segment.
5. Choose domain-first placement ending in `asset_slug`.
6. Materialize reviewed payload files under the runtime KB-root-relative workflow staging path.
7. Calculate the real runtime payload SHA-256 values.
8. Prepare Phase3 `admission_manifest.json`.
9. Prepare Phase3 `execution_target.json`.
10. Prepare `admission_handoff.json` referencing the already existing package, review decision, execution target, and admission manifest.
11. Calculate and place the real Stage1 package SHA-256 in the handoff.
12. Run standalone admission policy preflight against the handoff.
13. Apply the exact-HEAD Phase2 baseline reuse rule.
14. Invoke Phase4.
15. Verify canonical Phase3 evidence and destination hashes.

Never run standalone preflight before the files referenced by `admission_handoff.json` exist.

## Stage 1 source package

`<repo-contained-source-admission-target-dir>/stage1/admission_package.json`:

```json
{
  "admission_kind": "source_capture",
  "profile_id": "source_capture.v1",
  "asset_id": "web-source-example-article-001",
  "payload_path": "../payload",
  "review_status": "approved",
  "provenance": {
    "source_url": "https://example.com/article",
    "retrieval_timestamp": "2026-06-03T05:00:00Z",
    "content_type": "text/html; charset=UTF-8",
    "stable_representation": "domain/web/workflow/source-admission-example-001/payload/source.html"
  }
}
```

For `source_capture`, do not include `knowledge_profile_id` or `profile_data`.

`asset_id` remains `web-source-example-article-001` across Stage 1, the review decision, the handoff, and Phase3 lineage. `asset_slug` is only the source-family-local destination directory segment `source-example-article-001`. Do not add `asset_slug` to Stage 1, review `artifact_id`, or Phase3 `lineage.asset_id`.

## Review decision

`<repo-contained-source-admission-target-dir>/review/review-decision.json`:

```json
{
  "artifact_id": "web-source-example-article-001",
  "decision": "approve",
  "rationale": "Source package preserves canonical pointer, retrieval metadata, stable representation, and provenance suitable for KB source admission.",
  "blocking_issues": [],
  "required_changes": [],
  "approved_destination": "kb"
}
```

## Phase3 admission manifest

`<repo-contained-source-admission-target-dir>/phase3/admission_manifest.json`:

```json
{
  "admission_type": "source_capture",
  "lineage": {
    "asset_id": "web-source-example-article-001",
    "admission_package_ref": "<repo-contained-source-admission-target-dir>/stage1/admission_package.json",
    "review_decision_ref": "<repo-contained-source-admission-target-dir>/review/review-decision.json"
  },
  "copy_operation": {
    "operation_type": "copy",
    "content_mode": "byte_for_byte",
    "overwrite_policy": "fail_closed_on_hash_mismatch",
    "requested_by": "agent://source-admission"
  },
  "artifacts": [
    {
      "input_workspace_path": "domain/web/workflow/source-admission-example-001/payload/source.html",
      "expected_sha256": "replacewith64lowercasehexsha256sourcehtml",
      "destination_kb_path": "domain/web/sources/source-example-article-001/source.html",
      "copy_metadata": {"artifact_type": "stable-source-representation"}
    },
    {
      "input_workspace_path": "domain/web/workflow/source-admission-example-001/payload/source-readable.txt",
      "expected_sha256": "replacewith64lowercasehexsha256readabletxt",
      "destination_kb_path": "domain/web/sources/source-example-article-001/source-readable.txt",
      "copy_metadata": {"artifact_type": "readable-source-representation"}
    }
  ]
}
```

`input_workspace_path` and `destination_kb_path` are relative to the configured KB root. Do not prefix them with `/home/...` or `kb/`.

## Phase3 execution target

`<repo-contained-source-admission-target-dir>/phase3/execution_target.json`:

```json
{
  "target_runtime": "workspace",
  "target_kind": "kb_admission",
  "kb_integration_ref": "control-plane/runtime/integrations/kb.template.yaml",
  "admission_manifest_ref": "<repo-contained-source-admission-target-dir>/phase3/admission_manifest.json",
  "invoked_by": "agent://source-admission"
}
```

Phase3 freezes this target plus the manifest and KB integration into `operations/harness-phase3/runs/<RUN_ID>/input/`.

## Stage 2 handoff

`<repo-contained-source-admission-target-dir>/admission_handoff.json`:

```json
{
  "handoff_version": "admission_handoff.v1",
  "admission_package_ref": "<repo-contained-source-admission-target-dir>/stage1/admission_package.json",
  "admission_package_sha256": "<real-sha256-of-stage1-admission-package>",
  "admission_kind": "source_capture",
  "profile_id": "source_capture.v1",
  "asset_id": "web-source-example-article-001",
  "knowledge_profile_id": null,
  "review_evidence": {
    "review_status": "approved",
    "approval_ref": "<repo-contained-source-admission-target-dir>/review/review-decision.json"
  },
  "placement": {
    "domain_area": "domain",
    "source_family_id": "web",
    "asset_layer": "sources",
    "asset_slug": "source-example-article-001",
    "destination_root": "domain/web/sources/source-example-article-001",
    "placement_policy_id": "kb_source_domain_first.v1"
  },
  "phase_inputs": {
    "phase3_execution_target_ref": "<repo-contained-source-admission-target-dir>/phase3/execution_target.json",
    "phase3_admission_manifest_ref": "<repo-contained-source-admission-target-dir>/phase3/admission_manifest.json"
  }
}
```

The handoff contains concrete asset contract and mapping data. It does not embed operational routing constants, Phase2 evidence, or canonical admission evidence.

The source-family-local slug may differ from the global `asset_id`. Do not automatically set `asset_slug = asset_id`, and do not repeat a publisher/source-family prefix already represented by `source_family_id`. For Humblebee, use `cosmetics-household-chemistry/humblebee-and-me/sources/citrus-chamomile-liquid-shampoo-20260610`, not `cosmetics-household-chemistry/humblebee-and-me/sources/humblebee-citrus-chamomile-liquid-shampoo-20260610`.

## Standalone policy preflight

From repo root:

```bash
python3 operations/harness-phase2/bin/check_admission_policy.py \
  /home/node/.openclaw/workspace/repos/crab-control-plane \
  <repo-contained-source-admission-target-dir>/admission_handoff.json
```

This validates the package binding, review decision, identity, placement, registered contract shape, and Phase3 target/manifest mapping. It does not run Phase2, Phase3, or Phase4 and does not create canonical evidence.

## Phase2 baseline and Phase4 invocation

Reuse an accepted Phase2 baseline only when all exact-HEAD conditions hold:

```text
Accepted Phase2 baseline <RUN_ID> was created for and reused at repository HEAD <SHA>.
```

Then invoke Phase4 with the accepted baseline and repo-contained execution target:

```bash
OPENCLAW_WORKSPACE_KB_ROOT=/home/node/.openclaw/workspace/kb \
PHASE4_PYTHON_BIN=python3 \
PHASE3_PYTHON_BIN=python3 \
bash operations/harness-phase4/bin/run_phase4_wrapper.sh \
  --phase2-run-dir operations/harness-phase2/runs/<PHASE2_RUN_ID> \
  --execution-target-json <repo-contained-source-admission-target-dir>/phase3/execution_target.json \
  --phase3-run-id <PHASE3_RUN_ID> \
  --operator agent:source-admission \
  --wrapper-run-id <PHASE4_RUN_ID>
```

## Legacy compatibility

Historical source-admission workflows and existing batch runners may still use the older source-specific fixture set:

```text
admission-fixture.json
source-capture-package.json
result-packet.json
admission-decision.json
placement-decision.json
```

That path is supported by `check_admission_policy.py` for compatibility only. It is not the canonical path for new source admissions, and `admission-fixture.json` is not a Stage 2 handoff.

The legacy identity invariant remains:

```text
placement.artifact_id == source_capture_package.source_id
```

## Final report pattern

```text
Execution owner:
- pre-Phase preparation: agent-owned preparation
- standalone admission policy preflight: repo-native preflight utility over admission_handoff.json
- Phase2 baseline: reusable repo/control-plane baseline evidence for exact repository HEAD
- Phase4 wrapper: normal operator-facing invocation
- Phase3 admission: canonical execution and admission evidence

pre-Phase preparation:
- Stage1 package prepared
- review decision prepared
- Phase3 manifest and execution target prepared
- Stage2 handoff prepared
- stable source files prepared under workspace KB workflow path

Phase-owned evidence:
- accepted Phase2 baseline: <run-id>, repo_head=<sha>, handoff_ready=<ready|not ready>
- Phase4 wrapper run: <run-id>, exit_code=<0|nonzero>
- Phase3 kb_admission run: <run-id>, exit_code=<0|nonzero>, evidence=<path>
- copied destination paths and hashes

limits:
- standalone preflight did not admit anything
- Phase2 did not admit anything; it only checked repo/control-plane baseline readiness
- the skill did not admit anything
- canonical admission claim depends on Phase3 `kb_admission` evidence
- no semantic/distillation knowledge asset admission is claimed
```
