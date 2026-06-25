# knowledge-admission non-live example

This example is illustrative only. It is not a live KB asset, not a Humblebee pilot, and not a repository-owned knowledge taxonomy.

Example values:

```text
domain_area          = example-domain
source_family_id     = example-source-family
source_asset_id      = example-source-article-001
profile_contract_id  = knowledge_extraction.v1
knowledge_profile_id = <instance-defined-knowledge-profile-id>
knowledge_type       = <instance-local-knowledge-type>
asset_id             = example-knowledge-asset-001
asset_slug           = example-knowledge-asset
destination_root     = example-domain/example-source-family/knowledge/example-knowledge-type/example-knowledge-asset
```

`knowledge_type` is instance-local placement taxonomy only. Real values come from outside-repository local config.

The concrete `knowledge_profile_id`, instruction, and output template are instance-local. The canonical repository supplies only the generic `knowledge_extraction.v1` contract.

## Route

```text
accepted provenance-bearing source
→ instance profile registry
→ instance instruction
→ agent-owned extraction
→ working candidate
→ admission-authorized knowledge package
→ admission_package.json
→ review-decision.json
→ admission_manifest.json
→ execution_target.json
→ admission_handoff.json
→ standalone admission preflight
→ exact-HEAD Phase2 baseline
→ Phase4 wrapper
→ Phase3 kb_admission
→ canonical Phase3 evidence
→ later semantic review in wiki layer
```

Never run standalone preflight before the files referenced by `admission_handoff.json` exist.

## Accepted Source Reference

The source is already accepted:

```text
example-domain/example-source-family/sources/example-source-article-001/
```

The knowledge asset must use a new knowledge `asset_id`; do not reuse the source asset ID.

## Candidate Discipline

The agent prepares a working candidate using the instance-local instruction and selected output template referenced by the active instance profile registry. The generic repository contract is:

```text
knowledge/kb/extraction-profiles/knowledge-extraction.v1.md
```

The candidate separates directly source-stated content, agent interpretation, inferred content, not stated, and not validated.

Permitted final claims:

- source-stated formula facts with evidence pointers;
- agent interpretations clearly labelled as interpretation;
- inferred content clearly labelled as inferred;
- explicit `not stated in source` and `not validated` boundaries.

Forbidden final claims:

- unsupported safety, stability, preservative, regulatory, manufacturing, shelf-life, or expert-validation claims;
- source facts that are actually agent inference;
- temporary candidate status that would become false after Phase admission.

## Stage 1 Package

`<repo-contained-knowledge-admission-target-dir>/stage1/admission_package.json`:

```json
{
  "admission_kind": "knowledge_asset",
  "profile_id": "knowledge_asset.v1",
  "knowledge_profile_id": "<instance-defined-knowledge-profile-id>",
  "asset_id": "example-knowledge-asset-001",
  "payload_path": "../payload/example-knowledge-asset.md",
  "review_status": "approved",
  "profile_data": {
    "prepared_by": "agent://knowledge-admission",
    "profile_contract_id": "knowledge_extraction.v1",
    "instruction_ref": "<instance-local-instruction-ref>",
    "output_template_ref": "<instance-selected-output-template-ref>"
  },
  "provenance": {
    "source_id": "example-source-article-001",
    "source_asset_path": "example-domain/example-source-family/sources/example-source-article-001/"
  }
}
```

## Admission Authorization

`<repo-contained-knowledge-admission-target-dir>/review/review-decision.json`:

```json
{
  "artifact_id": "example-knowledge-asset-001",
  "decision": "approve",
  "rationale": "Example final prepared bytes are authorized for controlled KB placement.",
  "approved_destination": "kb"
}
```

This authorizes admission and placement only. It is not semantic review and does not prove the extracted claims are correct.

## Phase3 Admission Manifest

`<repo-contained-knowledge-admission-target-dir>/phase3/admission_manifest.json`:

```json
{
  "admission_type": "knowledge_asset",
  "artifacts": [
    {
      "input_workspace_path": "example-domain/example-source-family/workflow/knowledge-admission-example-001/example-knowledge-asset-001/payload/example-knowledge-asset.md",
      "expected_sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "destination_kb_path": "example-domain/example-source-family/knowledge/example-knowledge-type/example-knowledge-asset/example-knowledge-asset.md",
      "copy_metadata": {
        "content_role": "admission_authorized_knowledge_package",
        "example_only": true
      }
    }
  ],
  "copy_operation": {
    "content_mode": "byte_for_byte",
    "operation_type": "copy",
    "overwrite_policy": "fail_closed_on_hash_mismatch"
  },
  "lineage": {
    "admission_package_ref": "<repo-contained-knowledge-admission-target-dir>/stage1/admission_package.json",
    "asset_id": "example-knowledge-asset-001",
    "knowledge_profile_id": "<instance-defined-knowledge-profile-id>"
  }
}
```

`asset_slug` and `knowledge_type` do not appear in lineage.

## Execution Target

`<repo-contained-knowledge-admission-target-dir>/phase3/execution_target.json`:

```json
{
  "target_runtime": "workspace",
  "target_kind": "kb_admission",
  "kb_integration_ref": "control-plane/runtime/integrations/kb.template.yaml",
  "admission_manifest_ref": "<repo-contained-knowledge-admission-target-dir>/phase3/admission_manifest.json",
  "invoked_by": "agent://knowledge-admission"
}
```

## Stage 2 Handoff

`<repo-contained-knowledge-admission-target-dir>/admission_handoff.json`:

```json
{
  "handoff_version": "admission_handoff.v1",
  "admission_package_ref": "<repo-contained-knowledge-admission-target-dir>/stage1/admission_package.json",
  "admission_package_sha256": "<actual-stage1-package-sha256>",
  "admission_kind": "knowledge_asset",
  "profile_id": "knowledge_asset.v1",
  "asset_id": "example-knowledge-asset-001",
  "knowledge_profile_id": "<instance-defined-knowledge-profile-id>",
  "placement": {
    "domain_area": "example-domain",
    "source_family_id": "example-source-family",
    "asset_layer": "knowledge",
    "asset_slug": "example-knowledge-asset",
    "knowledge_type": "<instance-local-knowledge-type>",
    "destination_root": "example-domain/example-source-family/knowledge/example-knowledge-type/example-knowledge-asset",
    "placement_policy_id": "kb_knowledge_domain_first.v1"
  },
  "review_evidence": {
    "review_status": "approved",
    "approval_ref": "<repo-contained-knowledge-admission-target-dir>/review/review-decision.json"
  },
  "phase_inputs": {
    "phase3_execution_target_ref": "<repo-contained-knowledge-admission-target-dir>/phase3/execution_target.json",
    "phase3_admission_manifest_ref": "<repo-contained-knowledge-admission-target-dir>/phase3/admission_manifest.json"
  }
}
```

## Standalone Preflight

Use an outside-repository local taxonomy config:

```bash
ADMISSION_KNOWLEDGE_PROFILE_REGISTRY=/path/to/instance/knowledge-profile-registry.json \
ADMISSION_KB_TAXONOMY_CONFIG=/absolute/outside-repository/kb-taxonomy-config.json \
python3 operations/harness-phase2/bin/check_admission_policy.py \
  /home/node/.openclaw/workspace/repos/crab-control-plane \
  <repo-contained-knowledge-admission-target-dir>/admission_handoff.json
```

The selected instance registry must contain the chosen concrete profile and resolve its instruction/template references from the registry file's directory. The selected local taxonomy config must allow:

```text
<instance-defined-knowledge-profile-id> -> <instance-local-knowledge-type>
```

That mapping is example-only. It is not repository taxonomy.

## Phase2 Baseline

Use an accepted Phase2 baseline only when its recorded repository HEAD exactly equals the current repository HEAD and the tracked working tree is clean.

Allowed claim:

```text
Accepted Phase2 baseline <RUN_ID> was created for and reused at repository HEAD <SHA>.
```

## Phase4 Invocation

Phase4 is the default wrapper:

```bash
OPENCLAW_WORKSPACE_KB_ROOT=/home/node/.openclaw/workspace/kb \
PHASE4_PYTHON_BIN=python3 \
PHASE3_PYTHON_BIN=python3 \
bash operations/harness-phase4/bin/run_phase4_wrapper.sh \
  --phase2-run-dir operations/harness-phase2/runs/<PHASE2_RUN_ID> \
  --execution-target-json <repo-contained-knowledge-admission-target-dir>/phase3/execution_target.json \
  --phase3-run-id <PHASE3_RUN_ID> \
  --operator agent:knowledge-admission \
  --wrapper-run-id <PHASE4_RUN_ID>
```

## Evidence Boundary

Do not claim admission until Phase3 succeeds and emits canonical evidence under:

```text
operations/harness-phase3/runs/<PHASE3_RUN_ID>/
```

Phase3 evidence proves runtime intake, hashes, byte-for-byte copy, destination mutation, and canonical execution evidence. It does not prove semantic correctness.
