# KNOWLEDGE_CANDIDATE_ADMISSION_RUNBOOK

## Purpose

Define the practical workflow for staging an agent-prepared knowledge candidate, reviewing it into a KB-ready knowledge package, and admitting that package through Phase3 `kb_admission` as `admission_type: knowledge_asset`.

This runbook is documentation only. It does not add a Phase target, schema, validator, runner behavior, admission mechanism, smoke target, live KB asset, or runtime evidence artifact.

`knowledge package` is a process concept in this runbook. It does not define a new schema-bound artifact type.

## Scope boundary

Knowledge candidate staging starts from reviewed, source-bearing, or provenance-bearing inputs. The agent prepares the semantic candidate before Phase is invoked.

Phase3 admits an already reviewed, KB-ready knowledge package. It does not perform semantic extraction and does not rewrite the artifact.

## Terminology

```text
draft/candidate -> review -> knowledge package -> Phase3 admission -> admitted knowledge asset
```

- `candidate`: pre-review or working semantic extraction output.
- `knowledge package`: reviewed, KB-ready, byte-for-byte artifact prepared for Phase admission.
- `admitted knowledge asset`: sanctioned KB asset after Phase3 admission completes.

Do not rely on Phase to convert candidate metadata into asset metadata. Phase copies bytes, so package bytes must already contain metadata that remains true after admission.

## Ownership model

Agent/user-owned work:

- extraction/profile structure approval for the run;
- semantic extraction;
- working knowledge candidate;
- candidate review decision;
- reviewed knowledge package prepared for Phase admission.

Phase-owned work:

- `kb_admission` of an already prepared knowledge package;
- byte-for-byte copy;
- hash and path verification;
- admission evidence.

## Workflow

1. Select provenance-bearing source assets or reviewed source inputs.

   The run starts from source-bearing assets, reviewed source packages, or other provenance-bearing inputs. Do not treat loose raw material, unreviewed notes, or transient task state as a sanctioned knowledge source.

2. Confirm the reusable extraction profile or source-family override.

   The agent and user identify the extraction profile, domain extraction profile, or source-family override that defines the candidate structure for this run.

3. Record run-specific profile and structure approval.

   Profile approval means the extraction structure is agreed for the run. It is not KB placement approval and does not authorize admission.

   Approved run profile path shape:

   ```text
   <domain>/<source-family>/workflow/<run-id>/extraction-profile.approved.md
   ```

4. Agent prepares the working knowledge candidate in workflow staging.

   The agent performs semantic extraction outside Phase and writes the working candidate in the run workflow area.

   Working candidate path shape:

   ```text
   <domain>/<source-family>/workflow/<run-id>/prepared/knowledge/<asset-id>.md
   ```

5. Candidate gets reviewed for KB placement and finalized as a knowledge package.

   Candidate review evaluates whether the prepared candidate may be placed as a knowledge asset, subject to existing admission policy and placement policy. After approval, the Phase input is the reviewed knowledge package, not an unreviewed working candidate.

   Review decision path shape:

   ```text
   <domain>/<source-family>/workflow/<run-id>/review-decision.*
   ```

   Use a review-decision artifact according to the existing `REVIEW_DECISION` contract, for example `review-decision.md` or `review-decision.json` when allowed by repo contract. Do not infer JSON as required unless the applicable contract requires it.

6. Phase4 invokes Phase3 for the knowledge package.

   New real KB admissions use the governed route:

   ```text
   Phase2 -> Phase4 wrapper -> Phase3 kb_admission
   ```

   Phase4 generates an invocation claim for the exact wrapper run, Phase3 run, execution target, and Phase2 run. Phase3 freezes and validates that claim before any apply step.

   Direct Phase3 `kb_admission` without valid Phase4 proof fails closed.

   Phase3 workspace `kb_admission` still admits the reviewed knowledge package as `admission_type: knowledge_asset`. The target performs manifest, hash, and path controls, copies the package byte-for-byte, and emits admission evidence.

   Final admitted knowledge asset path shape:

   ```text
   <domain>/<source-family>/knowledge/<asset-id>/...
   ```

## Package admission metadata

The run should include admission metadata that identifies the reviewed knowledge package and its intended admission target.

Metadata path shape:

```text
<domain>/<source-family>/workflow/<run-id>/candidate-admission-metadata.*
```

The metadata format is not mandated by this runbook. Acceptable illustrative forms include:

- `candidate-admission-metadata.md`
- `candidate-admission-metadata.json`
- `candidate-admission-metadata.yaml`

Minimum metadata content:

- source asset refs;
- extraction profile refs;
- knowledge package path;
- package hash;
- review decision ref;
- intended admission target.

## Artifact metadata boundary

Transient workflow status belongs in workflow metadata, review-decision artifacts, or admission metadata unless it is intended to remain true inside the admitted artifact.

Phase3 does not rewrite artifact metadata. It copies bytes. Therefore, the bytes submitted as the knowledge package must already contain metadata that remains true after admission.

Bad Phase input example:

```yaml
knowledge_status: candidate
```

This is only appropriate for a working pre-review candidate if the same file will not be copied byte-for-byte into `knowledge/...`.

Acceptable illustrative package metadata examples:

```yaml
artifact_type: knowledge_package
admission_readiness: reviewed_for_kb_placement
```

```yaml
asset_kind: knowledge_asset
admission_state: prepared_for_phase3_admission
```

These examples are illustrative. They do not introduce mandatory schema fields.

## Admission boundary

Profile approval means the extraction structure is agreed. Profile approval is not KB placement approval.

The review decision authorizes candidate placement, subject to existing admission policy, placement policy, provenance expectations, and asset expectations.

Phase3 does not validate semantic correctness, domain expertise, scientific correctness, regulatory correctness, manufacturing readiness, cosmetic safety, or other domain claims.

Phase3 only admits already prepared knowledge packages byte-for-byte according to manifest, hash, and path controls.

For `kb_admission`, Phase3 also requires Phase4 invocation proof. `invoked_by` metadata is not proof. The proof gate validates exact repo-contained run linkage, not cryptographic authentication.

Knowledge admission and source admission are structurally similar at the Phase layer. The admitted object differs:

- source admission admits a source package or other source-bearing artifacts;
- knowledge admission admits an agent-prepared, reviewed knowledge package.

## Evidence boundary

Phase3 may produce local or runtime admission evidence. That evidence may be cited as local evidence for a run, but it is not a canonical repository artifact unless a later docs change explicitly curates it into the repository.

Phase4 produces wrapper evidence and `phase4_invocation_claim.json`. Phase3 remains the canonical execution owner and owns canonical reports, `execution_result.json`, and `exit_code`.

Do not cite untracked, git-ignored, runtime, or live workspace evidence as repository fact.

## Repository boundary

Use only illustrative domain-first path shapes in repository docs unless a curated example is explicitly added by a later PR.

Do not add runtime/live KB evidence examples, create live KB assets, or write to the workspace KB as part of this runbook.
