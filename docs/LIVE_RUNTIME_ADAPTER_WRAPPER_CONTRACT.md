# LIVE_RUNTIME_ADAPTER_WRAPPER_CONTRACT

## Purpose

This document defines the contract for the live-runtime adapter/wrapper boundary.

Its purpose is to ensure that live runtime apply is driven only through a dedicated, bounded, human-controlled execution surface.

## Status

The wrapper execution-owner skeleton and bounded live runtime apply companion now exist under `operations/harness-openclaw-live-wrapper/`.

They remain separate surfaces.
No deploy, no migration, no Crab approval, no approval granting, no rollback execution, and no rollout behavior are included.

## Scope

This contract defines the execution-owner boundary for live runtime mutation.
The current bounded apply surface does not approve rollout, deploy, migration, or Crab invocation.

## Live-runtime adapter/wrapper definition

A live-runtime adapter/wrapper is the only allowed execution-owner boundary for any live runtime mutation.

It is not the dry-run adapter.
It is not the controlled disposable apply surface.
It is not the bounded disposable selector wrapper.
It is a separate future class of operation.

## Why a separate execution surface is required

Live runtime mutation must not be driven by repurposing disposable apply entrypoints.

A separate surface is required so that live target identity, approval, rollback, evidence retention, redaction, and fail-closed behavior are explicit and reviewable.

Those responsibilities remain governed by separate pre-execution documents:

- live target identity: `docs/LIVE_TARGET_IDENTITY_MODEL.md`
- operator approval: `docs/OPERATOR_APPROVAL_MODEL.md`
- rollback: `docs/ROLLBACK_MODEL.md`
- failure and abort: `docs/FAILURE_AND_ABORT_MODEL.md`
- secret handling: `docs/SECRET_HANDLING_CONTRACT.md`
- evidence retention: `docs/EVIDENCE_RETENTION_POLICY.md`
- no-secret redaction: `docs/NO_SECRET_REDACTION_POLICY.md`

The future wrapper must depend on these separate documents and must not absorb them into wrapper availability.
A validation-only pre-execution gate may exist before the wrapper to validate reviewed selector, approval, and rollback records.
That gate is not the execution owner.
A bounded live retention surface may exist before the wrapper to validate source declarations and retain redacted candidate evidence.
That retention surface is not the execution owner.
A wrapper-ready execution-prep bundle may exist before the wrapper to normalize reviewed selector, approval, and rollback records.
That execution-prep bundle is not the execution owner.
A bounded wrapper-intake bundle may exist before the wrapper to compose green execution-prep and retention run references.
That wrapper-intake bundle is not the execution owner.
A bounded repo-local wrapper preflight skeleton may exist before the wrapper to validate wrapper-intake input and emit preflight evidence.
That preflight skeleton is not the execution owner.
A bounded repo-local material-resolution bundle may exist before the wrapper to validate reviewed material references from a green wrapper preflight run.
That material-resolution bundle is not the execution owner.
A bounded repo-local secret-session bundle may exist before the wrapper to load already-resolved material in-process and emit redacted observations.
That secret-session bundle is not the execution owner.
A bounded repo-local live wrapper execution-owner skeleton may exist after a green secret-session run.
It is the first wrapper-owned canonical execution surface, but it still emits an apply-request stub only and does not perform live runtime apply.
A bounded live runtime apply companion may exist after a green wrapper execution-owner run.
It consumes the execution-owner output, re-loads already-approved material sources, and applies only into selected outside-Git live roots.
Execution-owner and apply remain separate surfaces.

## Required execution ownership model

Any future live-runtime adapter/wrapper must be:

- single execution owner
- explicitly human-controlled
- approval-gated
- evidence-producing
- fail-closed

It must own the live mutation entrypoint.
It must not delegate execution ownership to disposable apply.
It may call lower-level components only after gates pass.
It must produce canonical execution evidence for the live mutation attempt.

## Required inputs

Any future live-runtime adapter/wrapper may consume only reviewed and approved inputs such as:

- reviewed live target identity record
- reviewed live target selector governed by `docs/LIVE_TARGET_SELECTOR_CONTRACT.md`
- approved placement plan
- reviewed rollback plan
- reviewed local-only material source declaration
- explicit operator approval record
- explicit execution label / run id

## Forbidden inputs

Any future live-runtime adapter/wrapper must not consume:

- repo-only inferred live target selection
- disposable target selectors reused as live selectors
- implicit target identity
- unreviewed local overlay contents
- secrets from Git-tracked files
- rollout intent hidden inside unrelated commands

## Required pre-execution validations

Before any future live execution, the wrapper must validate:

- live target identity validation
- live target selector boundary validation
- confirmation that target is not disposable
- local-only material location validation
- approval record validation
- rollback input validation
- validation-only pre-execution gate result for selector, approval, and rollback records when present
- execution-prep bundle result for selector, approval, and rollback records when a wrapper-ready bundle is prepared
- bounded source declaration and redacted retention result when candidate evidence is retained
- wrapper-intake bundle result when execution-prep and retention evidence are composed for future wrapper intake
- wrapper preflight skeleton result when a green wrapper-intake bundle is validated before any future wrapper
- material-resolution bundle result when reviewed material references are resolved from a green wrapper preflight run
- secret-session bundle result when already-resolved material is loaded in-process and redacted observations are produced
- wrapper execution-owner skeleton result when wrapper-owned canonical evidence and an apply-request stub are prepared before any bounded live apply
- no-secret-leakage/redaction precheck
- evidence-path validation
- exact target-surface ambiguity check

## Required approval model

Any future live-runtime adapter/wrapper must require explicit human approval tied to the exact target identity and exact execution attempt.

Approval must not be implied from successful disposable runs.
Approval must not be inferred from repo state alone.

## Required evidence surfaces

Any future live-runtime adapter/wrapper must emit evidence such as:

- pre-execution record
- execution log
- mutation action log
- target identity record
- rollback handoff record
- final execution report
- final status record

Evidence may be local-only and redacted as needed.
This PR does not define the final storage location implementation.
The future wrapper must own a canonical live-execution evidence surface.

## Required redaction and secret-handling boundaries

The future live-runtime adapter/wrapper may consume approved local-only materials outside Git, but must not emit raw secrets into repo-local evidence, committed files, or unredacted logs.

Secret/material source boundaries are defined by `docs/SECRET_HANDLING_CONTRACT.md`, while output safety is separately governed by `docs/NO_SECRET_REDACTION_POLICY.md`.
Secret handling implementation remains separate future work.
The bounded retention surface validates source declarations and redacts candidate evidence only; it does not load real secrets or provide wrapper-integrated redaction.
A bounded material-resolution surface may validate declared material paths and emit refs-only metadata before any future live wrapper.
That material-resolution bundle does not load raw secrets and does not provide wrapper-integrated redaction.
A bounded secret-session surface may load already-resolved outside-Git material in-process and persist redacted observations only.
That secret-session bundle does not provide the live execution owner or final wrapper-integrated redaction.
A bounded wrapper execution-owner skeleton may consume a green secret-session bundle and emit wrapper-owned canonical evidence plus an apply-request stub.
That execution-owner skeleton is not bounded live runtime apply and does not authorize target mutation.

## Required rollback handoff expectations

The future live-runtime adapter/wrapper must not begin execution unless rollback handoff inputs are present and operator-reviewed.

Rollback must remain explicit, not assumed.

## Required abort/fail-closed behavior

If any validation or approval gate fails, the future wrapper must abort before live mutation.

It must fail closed.
It must not partially degrade into disposable apply behavior.
It must not silently continue with reduced guarantees.

## Required target-identity protections

The future wrapper must prevent confusion between:

- disposable targets
- test targets
- live targets

It must require exact target identity and must not rely on ambiguous path guessing or reused disposable selectors.

## Relationship to LIVE_RUNTIME_APPLY_CONTRACT

`docs/LIVE_RUNTIME_APPLY_CONTRACT.md` defines whether live runtime apply may ever happen.

This document defines the future execution-owner surface that would be allowed to drive it.

## Relationship to LOCAL_OVERLAY_CONTRACT

Any future live-runtime adapter/wrapper would depend on broader local-only materials outside Git.

This PR does not implement or authorize that reading.

## Relationship to LOCAL_DISPOSABLE_TARGET_SELECTOR_CONTRACT

The bounded disposable target selector layer is not a live target selector and must not be promoted into one by convention.

A future live selector is separately governed by `docs/LIVE_TARGET_SELECTOR_CONTRACT.md`.
That selector does not replace the broader live target identity model and does not act as approval or execution ownership.

## Relationship to LIVE_TARGET_SELECTOR_CONTRACT

`docs/LIVE_TARGET_SELECTOR_CONTRACT.md` defines the boundary for a future selector that may point at the intended live target.

The future live-runtime adapter/wrapper may consume only a reviewed live selector after separate gates pass.
The selector remains distinct from live target identity, approval, rollback, and execution ownership.
This PR does not create or approve a live-runtime wrapper.

## Relationship to Validation-Only Pre-Execution Gate

`operations/harness-openclaw-live-precheck/bin/run_live_preexecution_gate.sh` is a validation-only live-adjacent surface for selector, approval, and rollback records.

preexecution gate != execution owner

The wrapper remains separate.
The gate does not mutate targets, grant approval, perform rollback, read broader local overlay material, or become a live-runtime adapter/wrapper.

## Relationship to Live Secret Retention Surface

`operations/harness-openclaw-live-retention/bin/run_secret_retention_surface.sh` is a bounded live-adjacent surface for source declaration validation and redacted candidate evidence retention.

retention surface != execution owner

The wrapper remains separate.
The retention surface does not load real secrets, read broader local overlay material, mutate targets, grant approval, perform rollback, or become a live-runtime adapter/wrapper.

## Relationship to Live Execution-Prep Bundle

`operations/harness-openclaw-live-execution-prep/bin/run_live_execution_prep.sh` is a bounded live-adjacent surface that reruns the pre-execution gate and emits repo-local normalized selector, approval, and rollback execution-prep records.

execution-prep bundle != execution owner

The wrapper remains separate.
The execution-prep bundle does not mutate targets, grant approval, perform rollback, load secrets, read broader local overlay material, or become a live-runtime adapter/wrapper.

## Relationship to Live Wrapper-Intake Bundle

`operations/harness-openclaw-live-wrapper-intake/bin/run_live_wrapper_intake.sh` is a bounded repo-local surface that composes green execution-prep and retention outputs into a refs-and-metadata intake bundle.

wrapper-intake bundle != execution owner

The wrapper remains separate.
The wrapper-intake bundle does not mutate targets, load raw secrets, grant approval, perform rollback, authorize live runtime apply, or become a live-runtime adapter/wrapper.

## Relationship to Live Wrapper Preflight Skeleton

`operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_preflight.sh` is a bounded repo-local surface that consumes a green wrapper-intake bundle and emits wrapper preflight evidence plus a stub plan.

preflight skeleton != execution owner

The wrapper remains separate.
The preflight skeleton does not mutate targets, load raw secrets, grant approval, perform rollback, authorize live runtime apply, or become the live-runtime execution owner.

## Relationship to Live Material-Resolution Bundle

`operations/harness-openclaw-live-material-resolution/bin/run_live_material_resolution.sh` is a bounded repo-local surface that consumes a green wrapper preflight run and a reviewed outside-Git source declaration to emit refs-only material metadata.

material-resolution bundle != execution owner

The wrapper remains separate.
The material-resolution bundle does not mutate targets, load raw secrets into repo-local artifacts, grant approval, perform rollback, authorize live runtime apply, or become the live-runtime execution owner.

## Relationship to Live Secret-Session Bundle

`operations/harness-openclaw-live-secret-session/bin/run_live_secret_session.sh` is a bounded repo-local surface that consumes a green material-resolution run, loads already-resolved outside-Git material in-process, and emits metadata plus redacted observations.

secret-session bundle != execution owner

The wrapper remains separate.
The secret-session bundle does not mutate targets, write raw secret material into repo-local outputs, grant approval, perform rollback, authorize live runtime apply, or become the live-runtime execution owner.

## Relationship to Live Wrapper Execution-Owner Skeleton

`operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_execution_owner.sh` is a bounded repo-local surface that consumes a green secret-session run and emits wrapper-owned canonical execution evidence plus an apply-request stub.

This is the first wrapper-owned canonical execution surface.

execution-owner skeleton != bounded live runtime apply

It does not mutate targets, grant approval, execute rollback, load new raw secrets, approve Crab invocation, or perform deploy/migration.
Bounded live runtime apply is a separate companion surface that consumes only green execution-owner output.

## Relationship to Bounded Live Runtime Apply

`operations/harness-openclaw-live-wrapper/bin/run_live_runtime_apply.sh` consumes a green wrapper execution-owner run and performs bounded mutation only inside selected outside-Git live roots.

It emits canonical wrapper apply evidence plus rollback handoff metadata.
It remains separate from execution-owner preparation and does not grant approval, execute rollback, approve Crab invocation, deploy, migrate, or orchestrate rollout.

## Relationship to Pre-Execution Contract Stack

The future wrapper is the execution owner only.

It must not collapse the pre-execution contract stack:

- selector -> points at intended live target
- identity model -> defines exact target identity semantics
- approval model -> defines exact human approval semantics
- rollback model -> defines rollback semantics
- failure/abort model -> defines failure and abort semantics
- secret handling contract -> defines allowed secret/material sources and boundaries
- evidence retention policy -> defines what evidence must be retained
- no-secret redaction policy -> defines what must be redacted or never emitted
- wrapper contract -> future execution owner only
- preexecution gate -> validation-only selector/approval/rollback record check
- retention surface -> bounded declaration validation and redacted candidate evidence retention
- execution-prep bundle -> repo-local normalized selector/approval/rollback records after pre-execution validation
- wrapper-intake bundle -> refs-and-metadata composition of green execution-prep and retention outputs
- preflight skeleton -> wrapper preflight evidence and stub plan only
- material-resolution bundle -> refs-only material metadata from green wrapper preflight and reviewed declaration
- secret-session bundle -> in-process material loading with metadata and redacted observations only
- execution-owner skeleton -> wrapper-owned canonical execution evidence plus apply-request stub only
- bounded live runtime apply -> target mutation only inside selected outside-Git live roots

approval != wrapper
preexecution gate != execution owner
retention surface != execution owner
execution-prep bundle != execution owner
wrapper-intake bundle != execution owner
preflight skeleton != execution owner
material-resolution bundle != execution owner
secret-session bundle != execution owner
execution-owner skeleton != bounded live runtime apply
bounded live runtime apply != rollout orchestration
wrapper contract != failure/abort model
secret handling != redaction
retention != redaction
retention != storage implementation

## Relationship to Crab-safe orchestration

Crab is not approved to invoke the live-runtime adapter/wrapper.

Any future Crab approval would require a separate approval decision, separate tests, separate CI, and explicit human control semantics.

## Forbidden shortcuts

- no direct promotion from disposable wrapper to live wrapper
- no direct invocation of live mutation through controlled disposable apply
- no reuse of bounded disposable selector as live selector
- no repo-only live target inference
- no silent secret ingestion
- no rollout hidden inside adapter internals
- no Crab invocation without separate approval

## Non-goals

- no full live-runtime adapter expansion
- no rollout orchestration
- no deploy
- no migration
- no live target selector implementation
- no local overlay implementation
- no secrets handling implementation
- no Crab approval
- no Phase 2/3/4 behavior changes
- no workflow changes
