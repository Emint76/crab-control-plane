---
name: source-admission
description: Prepare and route external source material for canonical crab-control-plane/OpenClaw workspace KB admission. Use by default for source-bearing inputs intended for capture, preservation, ingestion, or KB admission. Standalone policy preflight checks source admission inputs, an accepted reusable Phase2 baseline covers repo/control-plane readiness, Phase4 is the default operator-facing wrapper, and Phase3 workspace/kb_admission remains the sole canonical execution owner.
---

# Source Admission

Prepare **source-bearing** assets for canonical KB admission. This skill is a preparation and routing policy; it does not admit anything by itself.

Canonical rule:

```text
external source
→ source-admission preparation
→ standalone admission policy preflight
→ accepted reusable Phase2 baseline
→ Phase4 wrapper by default
→ Phase3 workspace/kb_admission
→ canonical Phase3 evidence
```

**Standalone preflight checks concrete source admission inputs. A generic accepted Phase2 baseline covers repo/control-plane readiness and may be reused only when its recorded repository Git HEAD exactly equals the current repository Git HEAD. Phase4 is the default operator-facing entrypoint. Phase3 performs admission and remains the only canonical execution owner.**

A source is not admitted until Phase3 `workspace/kb_admission` runs, freezes inputs, performs byte-for-byte copy, and emits canonical Phase3 evidence.

## Default activation

Enter source-admission mode by default when an external source-bearing input is intended for capture, preservation, ingestion, or KB use, including:

- URL or webpage
- document or uploaded file
- pasted text or HTML
- PDF
- image or screenshot
- table, export, or dataset
- archive, collection, section, feed, sitemap, or other source container

Do not wait for the user to name this skill explicitly.

Do not start admission when the user explicitly limits the task to transient analysis, summary, translation, or discussion and says not to save, ingest, preserve, or admit the material.

When intent is ambiguous, distinguish clearly between:

- transient analysis only
- source capture preparation
- canonical source admission

Never silently claim canonical admission from transient analysis.

## Collection and container handling

Before preparing admission artifacts, classify the input as either:

1. a single source; or
2. a container that represents multiple independently addressable sources.

Examples of containers include:

- a website section
- category or tag archive
- sitemap or feed
- folder or archive file
- multi-document export
- index page linking to multiple articles
- source list or batch manifest

For a container:

1. enumerate the child source candidates;
2. preserve the container/index as discovery evidence when useful;
3. create a separate source identity and source-capture package for each independently addressable child source;
4. validate and admit each child source separately;
5. report discovered, prepared, skipped, failed, and admitted counts;
6. preserve the reason for every skipped or failed child.

Do not collapse a source collection into one admitted source merely because it arrived as one URL, file, archive, or task.

A container-level manifest or index may be admitted as its own source only when it is itself a meaningful source artifact. It never substitutes for admission of its child sources.

## Non-negotiables

- State execution ownership precisely:
  - pre-Phase capture/preparation is agent-owned preparation;
  - standalone admission policy preflight checks concrete source inputs;
  - Phase2 provides reusable repo/control-plane baseline evidence;
  - Phase4 provides wrapper metadata and invokes Phase3;
  - Phase3 owns canonical execution and admission evidence.
- Use Phase4 as the default invocation path for canonical source admission.
- Do not invoke Phase3 directly as the normal source-admission path.
- Direct Phase3 invocation is allowed only when:
  - the operator explicitly requests it; or
  - Phase4 is unavailable or defective, the limitation is reported, and the operator explicitly approves the fallback.
- Prefer the canonical repo checkout: `/home/node/.openclaw/workspace/repos/crab-control-plane`.
- Source of truth: GitHub `Emint76/crab-control-plane` plus the local canonical checkout above.
- Treat repo `knowledge/kb/` as layout/docs/examples, not the live corpus.
- Treat the live KB corpus as the configured workspace KB root, usually `OPENCLAW_WORKSPACE_KB_ROOT` or `/home/node/.openclaw/workspace/kb`.
- Do not use `freeze` for pre-Phase work. Only Phase3 freezes `execution_target`, `admission_manifest`, and `kb_integration` into its run input directory.
- Do not call standalone preflight pass, Phase2 baseline pass, Phase4 wrapper success, schema validation, approval evidence, or copied working files “admitted”.
- Only Phase3 `kb_admission` evidence can support the claim that a source was admitted.
- This skill is source-only. Do not use it for semantic distillation or generic knowledge-asset admission.
- Preserve source bytes and provenance. Do not rewrite source content into a knowledge claim during source admission.
- Fail closed on missing provenance, missing expected hashes, invalid manifests, unresolved placement, or hash mismatch.

## Path and placement discipline

Pre-Phase workflow and staging paths must be domain-first:

```text
<domain-area>/<publisher-id-or-source-family-id>/workflow/<run-id>/
```

Example:

```text
cosmetics-household-chemistry/humblebee-and-me/workflow/<run-id>/
```

New live assets must not use the legacy role-first workflow form:

```text
workflow/<domain-area>/<publisher-id-or-source-family-id>/...
```

Final admitted source assets normally use:

```text
<domain-area>/<publisher-id-or-source-family-id>/sources/<asset-slug-or-source-id>/
```

New live assets must not use the legacy role-first source form:

```text
sources/<domain-area>/<publisher-id-or-source-family-id>/...
```

Keep these surfaces distinct:

- `<domain-area>/<publisher-id-or-source-family-id>/workflow/...` = pre-Phase working and staging material
- repo-contained target directory = Phase3 target inputs
- `operations/harness-phase2/runs/...` = Phase2 evidence
- `operations/harness-phase4/runs/...` = wrapper-only metadata
- `operations/harness-phase3/runs/...` = canonical execution evidence
- `<domain-area>/<publisher-id-or-source-family-id>/sources/...` under the live KB root = admitted source corpus

Do not treat `runtime-ready/`, wrapper output, or a working copy as an admitted source destination.

## Required inputs

### Pre-Phase source preparation

Prepare stable source material under the workspace KB workflow/staging area:

- raw capture, readable extraction, or other stable representation
- retrieval timestamp, status, content type, source locator, and SHA-256 hash
- stable source identifier
- parent/container reference when the source was discovered inside a collection
- `task-packet.json` with source-capture/source-ingest intent only; avoid `knowledge-extraction` for source admission
- `source-capture-package.json` validating against `source_capture_package.schema.json`
- `result-packet.json` whose `evidence` includes `type: source-package`
- `review-decision.json` with `decision: approve`, `approved_destination: kb`
- `admission-decision.json` with `decision: approved`, `blockers: []`
- `placement-decision.json` with `target_layer: kb`
- `admission-fixture.json` for Phase2 `check_admission_policy.py`
  - fixture `target_layer: kb`
  - fixture `placement.artifact_type: source-capture-package`
  - fixture `placement.artifact_id` must match `source_capture_package.source_id`

For a collection, repeat the source-specific package and admission evidence per child source. Do not reuse one child source ID for multiple documents.

### Phase3 workspace/kb_admission preparation

Prepare repo-contained Phase3 target inputs:

- `execution_target.json` validating against `operations/harness-phase3/contracts/execution_target.schema.json`
- `admission_manifest.json` validating against `operations/harness-phase3/contracts/kb_admission_manifest.schema.json`
- `kb_integration.yaml`, usually `control-plane/runtime/integrations/kb.template.yaml`, validating against `kb_runtime_integration.schema.json`

For live workspace KB admission, `execution_target.json` must use:

```json
{
  "target_runtime": "workspace",
  "target_kind": "kb_admission",
  "kb_integration_ref": "control-plane/runtime/integrations/kb.template.yaml",
  "admission_manifest_ref": "<repo-contained-source-admission-target-dir>/admission_manifest.json",
  "invoked_by": "agent://source-admission"
}
```

The Phase3 admission manifest must use:

- `admission_type: source_capture`
- `copy_operation.operation_type: copy`
- `copy_operation.content_mode: byte_for_byte`
- `copy_operation.overwrite_policy: fail_closed_on_hash_mismatch`
- artifact `input_workspace_path` values relative to the configured KB root
- artifact `expected_sha256` values matching the prepared source files
- artifact `destination_kb_path` values relative to the KB root, normally under `<domain-area>/<publisher-id-or-source-family-id>/sources/...`

For batch/container admission, the manifest may contain multiple source artifacts, but each independently addressable source must retain its own identity, expected hash, provenance, and destination path.

## Standalone preflight and Phase2 baseline semantics

Source admission readiness has two distinct pre-Phase checks:

1. Standalone admission policy preflight: `check_admission_policy.py` validates the concrete `admission-fixture.json` and source admission semantics.
2. Generic Phase2 repo-native baseline: `run_phase2_bundle.sh <PHASE2_RUN_ID>` validates the current repo/control-plane baseline and produces reusable baseline evidence.

Reuse an existing accepted Phase2 baseline only when all of the following are true:

1. the Phase2 run completed successfully;
2. its canonical report and handoff-readiness result are passing;
3. the tracked repository working tree is clean;
4. the operator or batch runner recorded the exact repository Git HEAD when the baseline was accepted;
5. the current repository Git HEAD exactly equals that recorded HEAD.

Any new repository commit makes the previous Phase2 baseline stale. After any merge into `main`, including merge of the corrective admission contract PR, create a new Phase2 baseline before the next admission pilot or batch.

The recorded relationship `phase2_run_id -> repo_head` belongs to operator or batch-runner operational state/logging. It is not canonical Phase2 evidence, admission handoff evidence, Phase3 frozen input, or a second canonical evidence surface.

Do not claim that `run_phase2_bundle.sh` consumed, approved, froze, or checked a specific source-admission fixture. Batch runners may reuse one accepted Phase2 baseline for many source and knowledge admissions. Historical generated Phase2/3/4 runs are not per-asset governance inputs.

Standalone preflight pass and Phase2 baseline pass do not mean:

- admitted
- copied into the canonical source corpus
- approved by Phase3
- semantically distilled
- promoted to canonical knowledge

## Phase4 default invocation semantics

Phase4 is the default operator-facing invocation path for source admission.

Phase4:

- validates wrapper arguments;
- records operator metadata;
- invokes `operations/harness-phase3/bin/run_phase3_bundle.sh`;
- preserves Phase3 exit status;
- points to Phase3 canonical outputs.

Phase4 does not:

- perform admission itself;
- own canonical execution;
- create competing `report.json`, `report.md`, `exit_code`, or `execution_result.json`;
- mutate Phase2 or Phase3 evidence;
- make Phase2 baseline readiness equivalent to admission.

Canonical evidence remains under:

```text
operations/harness-phase3/runs/<PHASE3_RUN_ID>/
```

Wrapper metadata remains under:

```text
operations/harness-phase4/runs/<PHASE4_RUN_ID>/
```

If Phase4 and Phase3 evidence disagree, Phase3 canonical report and `exit_code` win.

## Workflow

1. Inspect repo contracts if uncertain:
   - `control-plane/contracts/schemas/source_capture_package.schema.json`
   - `control-plane/contracts/schemas/task_packet.schema.json`
   - `control-plane/contracts/schemas/result_packet.schema.json`
   - `control-plane/contracts/schemas/review_decision.schema.json`
   - `control-plane/contracts/schemas/admission_decision.schema.json`
   - `control-plane/contracts/schemas/placement_decision.schema.json`
   - `control-plane/contracts/schemas/kb_runtime_integration.schema.json`
   - `operations/harness-phase3/contracts/execution_target.schema.json`
   - `operations/harness-phase3/contracts/kb_admission_manifest.schema.json`
   - `operations/harness-phase4/PHASE4_WRAPPER_CONTRACT.md`
   - `control-plane/policy/ADMISSION_POLICY.md`
   - `control-plane/policy/KB_ROLE_CONTRACT.md`
   - `knowledge/kb/KB_LAYOUT.md`
2. Determine whether the input is a single source or a collection/container.
3. For a collection, enumerate child sources and establish one stable identity per child.
4. Prepare stable source representations under the domain-first workspace KB workflow/staging path.
5. Create source admission evidence artifacts and the Phase2 admission fixture for every source.
6. Create Phase3 `admission_manifest.json` and `execution_target.json` in a repo-contained target directory.
   - Do not place pre-Phase target inputs under a canonical Phase3 run directory unless following an explicit existing test fixture.
   - Canonical Phase3 run evidence lives under `operations/harness-phase3/runs/<PHASE3_RUN_ID>/`.
7. Run standalone admission policy preflight with `check_admission_policy.py` against each concrete `admission-fixture.json`.
8. Reuse an accepted Phase2 baseline only when its recorded repository Git HEAD exactly equals the current repository Git HEAD and the tracked working tree is clean; otherwise run the generic Phase2 repo-native scaffold with `run_phase2_bundle.sh <PHASE2_RUN_ID>` to create a new baseline.
9. Invoke Phase4 with the accepted Phase2 baseline run directory and repo-contained execution target. Phase4 must invoke Phase3.
10. Inspect both:
    - Phase4 wrapper metadata;
    - Phase3 canonical report, canonical `exit_code`, frozen inputs, and copy evidence.
11. Verify admitted destination files and expected SHA-256 values.
12. Report exact paths, hashes, source counts, skipped/failed items, standalone preflight status, Phase2 baseline status, Phase4 wrapper status, Phase3 evidence, and limits.

## Commands

From repo root:

```bash
python3 operations/harness-phase2/bin/check_admission_policy.py \
  /home/node/.openclaw/workspace/repos/crab-control-plane \
  /path/to/source-admission-proof/admission-fixture.json

PHASE2_PYTHON_BIN=python3 \
bash operations/harness-phase2/bin/run_phase2_bundle.sh <PHASE2_RUN_ID>

OPENCLAW_WORKSPACE_KB_ROOT=/home/node/.openclaw/workspace/kb \
PHASE4_PYTHON_BIN=python3 \
PHASE3_PYTHON_BIN=python3 \
bash operations/harness-phase4/bin/run_phase4_wrapper.sh \
  --phase2-run-dir operations/harness-phase2/runs/<PHASE2_RUN_ID> \
  --execution-target-json <repo-contained-source-admission-target-dir>/execution_target.json \
  --phase3-run-id <PHASE3_RUN_ID> \
  --operator agent:source-admission \
  --wrapper-run-id <PHASE4_RUN_ID>
```

Use `PHASE2_PYTHON_BIN=python3`, `PHASE3_PYTHON_BIN=python3`, and `PHASE4_PYTHON_BIN=python3` if the environment lacks `python`.

### Exceptional direct Phase3 fallback

Direct Phase3 invocation is not the default and must not be used merely for convenience.

Use it only after satisfying the explicit fallback rule in **Non-negotiables**:

```bash
OPENCLAW_WORKSPACE_KB_ROOT=/home/node/.openclaw/workspace/kb \
PHASE3_PYTHON_BIN=python3 \
bash operations/harness-phase3/bin/run_phase3_bundle.sh \
  --phase2-run-dir operations/harness-phase2/runs/<PHASE2_RUN_ID> \
  --execution-target-json <repo-contained-source-admission-target-dir>/execution_target.json \
  --run-id <PHASE3_RUN_ID>
```

When fallback is used, report:

- why Phase4 was not used;
- who approved direct Phase3 invocation;
- the exact Phase3 command;
- the canonical Phase3 run directory;
- the limitation that no Phase4 wrapper metadata exists.

## Final claim discipline

Allowed:

- “Prepared source admission inputs.”
- “Enumerated N child source candidates from the source container.”
- “Prepared separate source admission packages for N child sources.”
- “Standalone admission-policy preflight passed for `<admission-fixture.json>`.”
- “Accepted Phase2 baseline <RUN_ID> was created for and reused at repository HEAD <SHA>.”
- “Phase4 wrapper invoked Phase3 and recorded wrapper metadata under `<PHASE4_RUN_DIR>`.”
- “Phase3 `workspace/kb_admission` copied N source artifacts and emitted canonical evidence under `<PHASE3_RUN_DIR>`.”
- “N source artifacts were verified at their admitted destinations with matching SHA-256 values.”

Forbidden:

- “Phase2 admitted the source.”
- “Phase2 bundle consumed or approved the source fixture.”
- “Phase2 baseline is current” without exact recorded and current Git HEAD equality.
- “Phase4 admitted the source.”
- “Phase4 is the canonical execution owner.”
- “Schema validation admitted the source.”
- “The skill admitted the source.”
- “Approval evidence alone means admitted.”
- “The whole collection was admitted” when only its index/container or only some children were admitted.
- “The source was distilled into canonical knowledge” as part of this source-only process.

## Required final report

The final report must include:

- input type: single source or collection/container
- source locator or container locator
- discovered child count
- prepared child count
- skipped child count and reasons
- failed child count and reasons
- standalone admission preflight paths and statuses
- accepted Phase2 baseline run directory and status
- Phase4 wrapper run directory and wrapper exit status
- Phase3 canonical run directory and canonical exit status
- Phase3 report path
- admitted destination paths
- expected and observed SHA-256 values
- explicit limits and unresolved blockers

Do not report aggregate success when any child source is unresolved without stating the partial status.

## Reference example

Read `references/source-admission-example.md` when you need a concrete Phase2 + Phase4 + Phase3 file layout, manifest shape, execution target, wrapper invocation, and final-report pattern.
