# LIVE_RUNTIME_ADAPTER_WRAPPER_CONTRACT

## Purpose

This document defines the contract for a future live-runtime adapter/wrapper.

Its purpose is to ensure that any future live runtime apply is driven only through a dedicated, bounded, human-controlled execution surface.

## Status

This is a contract-only document.

No live-runtime adapter/wrapper implementation, no live runtime apply, no deploy, no migration, and no rollout behavior are included in this PR.

## Scope

This contract defines the future execution-owner boundary for live runtime mutation.
It does not create an executable live-runtime surface, approve rollout, approve deploy, approve migration, or approve Crab invocation.

## Live-runtime adapter/wrapper definition

A future live-runtime adapter/wrapper is the only allowed execution-owner surface for any live runtime mutation.

It is not the dry-run adapter.
It is not the controlled disposable apply surface.
It is not the bounded disposable selector wrapper.
It is a separate future class of operation.

## Why a separate execution surface is required

Live runtime mutation must not be driven by repurposing disposable apply entrypoints.

A separate surface is required so that live target identity, approval, rollback, evidence retention, redaction, and fail-closed behavior are explicit and reviewable.

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

Secret handling requires its own separate future implementation contract.

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

## Relationship to Crab-safe orchestration

Crab is not approved to invoke the future live-runtime adapter/wrapper.

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

- no live-runtime adapter/wrapper implementation
- no live runtime apply
- no deploy
- no migration
- no live target selector implementation
- no local overlay implementation
- no secrets handling implementation
- no Crab approval
- no Phase 2/3/4 behavior changes
- no workflow changes
