---
name: source-admission
description: Prepare, validate, and route external source material for canonical crab-control-plane/OpenClaw workspace KB admission. Use by default for source-bearing inputs intended for capture, preservation, ingestion, or KB admission. Phase2 checks readiness, Phase4 is the default operator-facing invocation wrapper, and Phase3 workspace/kb_admission remains the sole canonical execution owner.
---

# Source Admission

Prepare **source-bearing** assets for canonical KB admission. This skill is a pre-Phase/Phase input helper and routing policy; it does not admit anything by itself.

Canonical rule:

```text
external source
→ source-admission preparation
→ Phase2 readiness
→ Phase4 wrapper by default
→ Phase3 workspace/kb_admission
→ canonical Phase3 evidence
```

**Phase2 checks readiness. Phase4 is the default operator-facing entrypoint. Phase3 performs admission and remains the only canonical execution owner.**

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
  - pre-Phase capture/preparation is `manual/local proof` or agent-owned preparation;
  - Phase2 provides readiness evidence;
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
- Do not call Phase2 pass, Phase4 wrapper success, schema validation, approval evidence, or copied working files “admitted”.
- Only Phase3 `kb_admission` evidence can support the claim that a source was admitted.
- This skill is source-only. Do not use it for semantic distillation or generic knowledge-asset admission.
- Preserve source bytes and provenance. Do not rewrite source content into a knowledge claim during source admission.
- Fail closed on missing provenance, missing expected hashes, invalid manifests, unresolved placement, or hash mismatch.

## Path and placement discipline

Pre-Phase workflow and staging paths must be prefix-first:

```text
workflow/<domain-area>/<publisher-id-or-source-family-id>/<run-id>/
```

Example:

```text
workflow/cosmetics-household-chemistry/humblebee-and-me/<run-id>/
```

Do not place the workflow prefix below a domain subtree, for example:

```text
cosmetics-household-chemistry/workflow/...
```

Final admitted source assets normally use:

```text
sources/<domain-area>/<publisher-id-or-source-family-id>/<source-id-or-source-path>/
```

Keep these surfaces distinct:

- `workflow/...` = pre-Phase working and staging material
- repo-contained target directory = Phase3 target inputs
- `operations/harness-phase2/runs/...` = Phase2 evidence
- `operations/harness-phase4/runs/...` = wrapper-only metadata
- `operations/harness-phase3/runs/...` = canonical execution evidence
- `sources/...` under the live KB root = admitted source corpus

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
- artifact `destination_kb_path` values relative to the KB root, normally under `sources/...`

For batch/container admission, the manifest may contain multiple source artifacts, but each independently addressable source must retain its own identity, expected hash, provenance, and destination path.

## Phase2 source readiness semantics

Phase2 source readiness has two distinct parts:

1. Source-specific Phase2-local check: `check_admission_policy.py` validates the concrete `admission-fixture.json` and source admission semantics.
2. Generic Phase2 repo-native scaffold: `run_phase2_bundle.sh <PHASE2_RUN_ID>` produces generic Phase2 scaffold/handoff readiness for Phase3 intake.

Do not claim that `run_phase2_bundle.sh` consumed or approved a specific source-admission fixture unless the repo runner is extended to link that fixture into Phase2 outputs.

Phase2 pass means readiness only. It does not mean:

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
- make Phase2 readiness equivalent to admission.

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
4. Prepare stable source representations under the prefix-first workspace KB workflow/staging path.
5. Create source admission evidence artifacts and the Phase2 admission fixture for every source.
6. Create Phase3 `admission_manifest.json` and `execution_target.json` in a repo-contained target directory.
   - Do not place pre-Phase target inputs under a canonical Phase3 run directory unless following an explicit existing test fixture.
   - Canonical Phase3 run evidence lives under `operations/harness-phase3/runs/<PHASE3_RUN_ID>/`.
7. Run local helper validation. Treat it only as `manual/local proof`.
8. Run the source-specific Phase2-local check with `check_admission_policy.py` against each concrete `admission-fixture.json`.
9. Run the generic Phase2 repo-native scaffold with `run_phase2_bundle.sh <PHASE2_RUN_ID>` only as handoff readiness for Phase3 intake. Do not claim it proved a source fixture unless the runner links that fixture into outputs.
10. Invoke Phase4 with the Phase2 run directory and repo-contained execution target. Phase4 must invoke Phase3.
11. Inspect both:
    - Phase4 wrapper metadata;
    - Phase3 canonical report, canonical `exit_code`, frozen inputs, and copy evidence.
12. Verify admitted destination files and expected SHA-256 values.
13. Report exact paths, hashes, source counts, skipped/failed items, Phase2 readiness, Phase4 wrapper status, Phase3 evidence, and limits.

## Commands

From repo root:

```bash
SOURCE_ADMISSION_SKILL_ROOT="${SOURCE_ADMISSION_SKILL_ROOT:-/home/node/.openclaw/workspace/skills/source-admission}"

python3 "$SOURCE_ADMISSION_SKILL_ROOT/scripts/check_source_admission_inputs.py" \
  --repo-root /home/node/.openclaw/workspace/repos/crab-control-plane \
  --proof-dir /path/to/source-admission-proof \
  --fixture admission-fixture.json \
  --execution-target <repo-contained-source-admission-target-dir>/execution_target.json \
  --admission-manifest <repo-contained-source-admission-target-dir>/admission_manifest.json \
  --kb-integration control-plane/runtime/integrations/kb.template.yaml

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
- “Source-specific Phase2-local admission-policy check passed for `<admission-fixture.json>`.”
- “Generic Phase2 repo-native scaffold produced handoff readiness for Phase3 intake.”
- “Phase4 wrapper invoked Phase3 and recorded wrapper metadata under `<PHASE4_RUN_DIR>`.”
- “Phase3 `workspace/kb_admission` copied N source artifacts and emitted canonical evidence under `<PHASE3_RUN_DIR>`.”
- “N source artifacts were verified at their admitted destinations with matching SHA-256 values.”

Forbidden:

- “Phase2 admitted the source.”
- “Phase2 bundle consumed or approved the source fixture” unless the repo runner links that fixture into Phase2 outputs.
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
- Phase2 source-specific check paths and statuses
- Phase2 scaffold run directory and status
- Phase4 wrapper run directory and wrapper exit status
- Phase3 canonical run directory and canonical exit status
- Phase3 report path
- admitted destination paths
- expected and observed SHA-256 values
- explicit limits and unresolved blockers

Do not report aggregate success when any child source is unresolved without stating the partial status.

## Reference example

Read `references/source-admission-example.md` when you need a concrete Phase2 + Phase4 + Phase3 file layout, manifest shape, execution target, wrapper invocation, and final-report pattern.
