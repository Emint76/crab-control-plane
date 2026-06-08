# KNOWLEDGE_CANDIDATE_ADMISSION_RUNBOOK

## Purpose

Define the practical workflow for staging an agent-prepared knowledge candidate and admitting it through Phase3 `kb_admission` as `admission_type: knowledge_asset`.

This runbook is documentation only. It does not add a Phase target, schema, validator, runner behavior, admission mechanism, smoke target, live KB asset, or runtime evidence artifact.

## Scope boundary

Knowledge candidate admission starts from reviewed, source-bearing, or provenance-bearing inputs. The agent prepares the semantic candidate before Phase is invoked.

Phase3 admits an already prepared candidate. It does not perform semantic extraction.

## Ownership model

Agent/user-owned work:

- extraction/profile structure approval for the run;
- semantic extraction;
- prepared knowledge candidate;
- candidate review decision.

Phase-owned work:

- `kb_admission` of an already prepared candidate;
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

4. Agent prepares the knowledge candidate in workflow staging.

   The agent performs semantic extraction outside Phase and writes the prepared candidate in the run workflow area.

   Prepared candidate path shape:

   ```text
   <domain>/<source-family>/workflow/<run-id>/prepared/knowledge/<asset-id>.md
   ```

5. Candidate gets reviewed for KB placement.

   Candidate review evaluates whether the prepared candidate may be placed as a knowledge asset, subject to existing admission policy and placement policy.

   Review decision path shape:

   ```text
   <domain>/<source-family>/workflow/<run-id>/review-decision.*
   ```

   Use a review-decision artifact according to the existing `REVIEW_DECISION` contract, for example `review-decision.md` or `review-decision.json` when allowed by repo contract. Do not infer JSON as required unless the applicable contract requires it.

6. Phase3 admits the prepared candidate.

   Phase3 workspace `kb_admission` admits the already prepared candidate as `admission_type: knowledge_asset`. The target performs manifest, hash, and path controls, copies the candidate byte-for-byte, and emits admission evidence.

   Final admitted knowledge asset path shape:

   ```text
   <domain>/<source-family>/knowledge/<asset-id>/...
   ```

## Candidate admission metadata

The run should include candidate admission metadata that identifies the prepared candidate and its intended admission target.

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
- prepared candidate path;
- candidate hash;
- review decision ref;
- intended admission target.

## Admission boundary

Profile approval means the extraction structure is agreed. Profile approval is not KB placement approval.

The review decision authorizes candidate placement, subject to existing admission policy, placement policy, provenance expectations, and asset expectations.

Phase3 does not validate semantic correctness, domain expertise, scientific correctness, regulatory correctness, manufacturing readiness, cosmetic safety, or other domain claims.

Phase3 only admits already prepared artifacts byte-for-byte according to manifest, hash, and path controls.

Knowledge admission and source admission are structurally similar at the Phase layer. The admitted object differs:

- source admission admits a source package or other source-bearing artifacts;
- knowledge admission admits an agent-prepared knowledge candidate.

## Evidence boundary

Phase3 may produce local or runtime admission evidence. That evidence may be cited as local evidence for a run, but it is not a canonical repository artifact unless a later docs change explicitly curates it into the repository.

Do not cite untracked, git-ignored, runtime, or live workspace evidence as repository fact.

## Repository boundary

Use only illustrative domain-first path shapes in repository docs unless a curated example is explicitly added by a later PR.

Do not add runtime/live KB evidence examples, create live KB assets, or write to the workspace KB as part of this runbook.
