# LIVE_RUNTIME_APPLY_CONTRACT

## Purpose

This document defines the contract and safety gates for live runtime apply.

It exists to separate local disposable validation from real runtime mutation.
It does not authorize implementation or execution.

## Status

Bounded live runtime apply now exists in `operations/harness-openclaw-live-wrapper/bin/run_live_runtime_apply.sh`.

It consumes a green wrapper execution-owner run and performs bounded filesystem mutation only inside selected outside-Git live roots.
A first real rollout companion now exists in `operations/harness-openclaw-live-wrapper/bin/run_first_real_rollout.sh`.
It consumes green bounded apply evidence plus a reviewed outside-Git rollout declaration, launches one reviewed runtime command, and runs one reviewed healthcheck.
No deploy, no migration, no Crab approval, no approval granting, no rollback execution, and no rollout orchestration are included.

## Scope

This contract defines the minimum prerequisites, safety gates, evidence expectations, rollback expectations, and forbidden shortcuts for live runtime apply.
The current executable surfaces are bounded apply and first real rollout only; they do not approve rollout orchestration.

A future live-runtime adapter/wrapper is separately governed by `docs/LIVE_RUNTIME_ADAPTER_WRAPPER_CONTRACT.md`.
Live runtime apply must not be driven directly from disposable apply surfaces.

## Live runtime apply definition

Live runtime apply means mutating a real OpenClaw runtime target that is not disposable and not intended to be deleted after validation.

This is categorically different from local disposable apply.

## How live runtime apply differs from disposable apply

Disposable apply is local-only, disposable-only, and rollback-tolerant by design.

Live runtime apply affects a real target with continuity, identity, configuration, and operational consequences.
Passing disposable apply does not by itself authorize live runtime apply.

## Required prerequisites before discussion

Before live runtime apply can even be discussed, these must already exist:

- local overlay contract exists
- disposable workspace contract exists
- controlled disposable apply contract exists
- full local disposable cycle proof exists
- bounded local target selector layer exists
- live target selector contract exists
- no-secret-leakage validation exists
- target path validation exists

The `full local disposable cycle proof exists` prerequisite is now satisfied at the contract level by the dedicated proof surface in `operations/harness-openclaw-local-proof/`.
That proof surface only runs the current local-only disposable contour and does not authorize live runtime apply, live-runtime adapter behavior, or Crab invocation.
Any future live target selector is separately governed by `docs/LIVE_TARGET_SELECTOR_CONTRACT.md`.
The live target selector contract does not replace the future live target identity model, approval model, rollback model, or live-runtime adapter/wrapper.
A validation-only pre-execution gate now exists in `operations/harness-openclaw-live-precheck/` for reviewed selector, approval, and rollback records.
That gate validates record location, schema, binding, and obvious non-secret boundaries only; it does not authorize live runtime apply.
A bounded live retention surface now exists in `operations/harness-openclaw-live-retention/` for source declaration validation and redacted candidate evidence retention.
That surface does not load real secrets, implement full live evidence storage, create a live wrapper, or authorize live runtime apply.
A bounded live execution-prep bundle now exists in `operations/harness-openclaw-live-execution-prep/` for reviewed selector, approval, and rollback records.
That bundle depends on a green pre-execution gate and emits repo-local normalized records only; it does not grant approval, execute rollback, create a live wrapper, or authorize live runtime apply.
A bounded live wrapper-intake bundle now exists in `operations/harness-openclaw-live-wrapper-intake/` for green execution-prep and retention run outputs.
That bundle emits refs and metadata only; it does not load secrets, create a live wrapper, or authorize live runtime apply.
A bounded live wrapper preflight skeleton now exists in `operations/harness-openclaw-live-wrapper/` for green wrapper-intake run outputs.
That skeleton emits preflight evidence and a stub plan only; it does not load secrets, create a live wrapper, or authorize live runtime apply.
A bounded live material-resolution bundle now exists in `operations/harness-openclaw-live-material-resolution/` for green wrapper preflight outputs and reviewed outside-Git source declarations.
That bundle emits refs-only material metadata; it does not load raw secrets, create a live wrapper, or authorize live runtime apply.
A bounded live secret-session bundle now exists in `operations/harness-openclaw-live-secret-session/` for green material-resolution outputs.
That bundle loads already-resolved outside-Git material in-process and emits metadata plus redacted observations only; it does not create a live wrapper or authorize live runtime apply.
A bounded live wrapper execution-owner skeleton now exists in `operations/harness-openclaw-live-wrapper/` for green secret-session outputs.
That skeleton is the first wrapper-owned canonical execution surface and emits an apply-request stub only; it does not perform bounded live apply, mutate targets, or approve Crab invocation.
A bounded live runtime apply surface now exists in `operations/harness-openclaw-live-wrapper/` for green wrapper execution-owner outputs.
That surface re-loads already-approved outside-Git material sources and mutates only the selected outside-Git `workspace`, `state`, and `runtime` roots.
It is not rollout orchestration, not deploy/migration, not Crab approval, not approval granting, and not rollback execution.
A first real rollout companion now exists in `operations/harness-openclaw-live-wrapper/` for green bounded live runtime apply outputs.
That surface validates one reviewed outside-Git rollout declaration, launches one reviewed runtime command, runs one reviewed healthcheck, and emits canonical rollout evidence.
It is not Crab approval, not rollout orchestration, not a supervisor, not deploy/migration, and not rollback execution.

## Required prerequisites before any future expansion

Before any future rollout/deployment or adapter expansion PR, these must be separately defined or extended:

- separate live-runtime adapter/wrapper contract
- explicit live target identity model, backed by `docs/LIVE_TARGET_IDENTITY_MODEL.md`
- explicit operator approval model, backed by `docs/OPERATOR_APPROVAL_MODEL.md`
- explicit rollback model, backed by `docs/ROLLBACK_MODEL.md`
- explicit failure and abort model, backed by `docs/FAILURE_AND_ABORT_MODEL.md`
- explicit secret handling contract, backed by `docs/SECRET_HANDLING_CONTRACT.md`
- explicit evidence retention policy, backed by `docs/EVIDENCE_RETENTION_POLICY.md`
- explicit no-secret redaction policy, backed by `docs/NO_SECRET_REDACTION_POLICY.md`

These documents are pre-execution contracts, models, and policies only.
They do not weaken any live-runtime safety gate and do not create a live-runtime executable surface.

## Required safety gates before execution

Before any bounded execution attempt, all gates must pass:

- human-reviewed target identity
- human-reviewed exact target path(s)
- explicit confirmation that target is not disposable
- explicit confirmation that rollback inputs are present
- validation-only pre-execution gate green for selector, approval, and rollback records when those records are used
- execution-prep bundle green for reviewed selector, approval, and rollback records when a wrapper-ready bundle is prepared
- bounded source declaration and redacted retention checks green when candidate live-adjacent evidence is retained
- wrapper-intake bundle green when execution-prep and retention outputs are composed before a future wrapper
- wrapper preflight skeleton green when a wrapper-intake bundle is validated before any future live wrapper
- material-resolution bundle green when reviewed material references are resolved from a green wrapper preflight run
- secret-session bundle green when already-resolved material is loaded in-process and redacted observations are emitted before any future live wrapper
- wrapper execution-owner skeleton green when wrapper-owned canonical evidence and an apply-request stub are prepared before bounded live apply
- bounded live runtime apply validation green when material source, target root, post-apply, and non-secret evidence checks are evaluated
- first real rollout validation green when rollout consumes a green bounded live apply run and reviewed outside-Git declaration
- explicit confirmation that secrets/config are sourced from local-only material outside Git
- dry-run classification still green
- controlled disposable apply still green
- no-secret-leakage checks green
- artifact/evidence schema validation green
- no pending ambiguity about target surface semantics

## Required evidence before execution

Live runtime apply must require:

- approved placement plan
- reviewed target identity record
- reviewed rollback plan
- reviewed secret/material source declaration
- operator approval record
- pre-apply runtime snapshot reference

## Required evidence during execution

Live runtime apply must emit:

- execution log
- mutation action log
- per-target write log
- failure/abort log if any
- redacted operator evidence

## Required evidence after execution

Live runtime apply must emit:

- post-apply snapshot
- final execution report
- final status
- rollback status if rollback triggered
- no-secret-leakage evidence for retained reports

## Required rollback expectations

Any live runtime apply must have an explicit rollback contract before execution.

Rollback must not be implied, assumed, or deferred.
Rollback inputs, boundaries, and operator decision points must be defined before any live execution is attempted.
The current bounded apply surface emits rollback handoff metadata only; it does not execute rollback.

## Required no-secret-leakage expectations

Any live runtime apply must preserve the existing no-secret-leakage discipline.

Secrets may be consumed only from approved local-only sources outside Git.
Secrets must not be written into repo-local evidence, committed files, or unredacted reports.

## Required target-identity expectations

Any live runtime apply must define exact target identity, including what instance is being changed, why it is the intended target, and how confusion with disposable targets is prevented.

## Relationship to LOCAL_OVERLAY_CONTRACT

Live runtime apply would require broader local-only material than the bounded disposable selector layer.

This PR does not implement or authorize broader overlay reading.

## Relationship to CONTROLLED_DISPOSABLE_APPLY_CONTRACT

Controlled disposable apply is a prerequisite validation stage, not a launch authorization stage.

Live runtime apply remains a separate future class of operation.

## Relationship to local target selector layer

The bounded local disposable target selector layer is not a live target selector.
It must not be reused as-is for live runtime apply.
A future live target selector is separately governed by `docs/LIVE_TARGET_SELECTOR_CONTRACT.md`.
Selector presence is not approval and does not authorize live runtime apply.

## Relationship to validation-only pre-execution gate

The live pre-execution gate validates reviewed selector, approval, and rollback records together before any future live execution discussion.

It is not live runtime apply, not a live-runtime adapter/wrapper, not approval execution, not rollback execution, not secret handling implementation, and not evidence storage implementation.
It does not weaken any gate in this contract.

## Relationship to live secret retention surface

The live secret retention surface validates a reviewed source declaration and retains redacted candidate evidence before any future live execution discussion.

It is not live runtime apply, not a live-runtime adapter/wrapper, not real secret loading, not broader local overlay reading, and not full live evidence storage.
It does not weaken any gate in this contract.

## Relationship to live execution-prep bundle

The live execution-prep bundle creates repo-local normalized selector, approval, and rollback execution-prep records from reviewed outside-Git inputs after the validation-only pre-execution gate passes.

It is not live runtime apply, not a live-runtime adapter/wrapper, not approval granting, not rollback execution, not real secret loading, and not broader local overlay reading.
It does not weaken any gate in this contract.

## Relationship to live wrapper-intake bundle

The live wrapper-intake bundle may exist before any future wrapper to compose green execution-prep and retention outputs into one refs-and-metadata intake bundle.

It is still not live runtime apply, not a live-runtime adapter/wrapper, not approval granting, not rollback execution, not real secret loading, and not broader local overlay reading.
It does not weaken any gate in this contract.

## Relationship to live wrapper preflight skeleton

The live wrapper preflight skeleton may exist before any future live wrapper to validate a green wrapper-intake bundle and emit preflight-only evidence.

It is still not live runtime apply, not a live-runtime execution owner, not approval granting, not rollback execution, not real secret loading, and not broader local overlay reading.
It does not weaken any gate in this contract.

## Relationship to live material-resolution bundle

The live material-resolution bundle may exist before any future live wrapper or live apply to validate reviewed material references from a green wrapper preflight run.

It is still not live runtime apply, not a live-runtime execution owner, not approval granting, not rollback execution, not raw secret loading, and not broader local overlay reading.
It does not weaken any gate in this contract.

## Relationship to live secret-session bundle

The live secret-session bundle may exist before any future live wrapper or live apply to load already-resolved outside-Git material in-process and emit redacted observations.

It is still not live runtime apply, not a live-runtime execution owner, not approval granting, not rollback execution, not broader local overlay reading, and not raw secret persistence.
It does not weaken any gate in this contract.

## Relationship to live wrapper execution-owner skeleton

The live wrapper execution-owner skeleton may exist before bounded live apply to consume a green secret-session run and emit wrapper-owned canonical evidence plus an apply-request stub.

It is still not live runtime apply, not target mutation, not approval granting, not rollback execution, not new raw secret loading, and not Crab approval.
Bounded live apply is a separate companion surface that consumes only green execution-owner output.
It does not weaken any gate in this contract.

## Relationship to bounded live runtime apply

`operations/harness-openclaw-live-wrapper/bin/run_live_runtime_apply.sh` is the first bounded live runtime apply surface.

It consumes a green wrapper execution-owner run, re-loads raw material sources from already-approved refs, maps `workspace`, `state`, and `runtime` source classes into selector roots, emits canonical apply evidence, and emits rollback handoff metadata only.

It is not first real rollout/deployment, not rollout orchestration, not deploy/migration, not Crab approval, not approval granting, and not rollback execution.

## Relationship to first real rollout

`operations/harness-openclaw-live-wrapper/bin/run_first_real_rollout.sh` is the bounded first real rollout companion to green bounded live runtime apply.

It consumes apply evidence, validates a reviewed outside-Git rollout declaration, binds target and execution labels to upstream apply evidence, launches one reviewed runtime command, runs one reviewed healthcheck, and emits canonical rollout evidence.

It is not Crab approval, not approval granting, not rollout orchestration, not a scheduler, not a supervisor, not deploy/migration, and not rollback execution.

## Relationship to Crab-safe orchestration

Crab is not approved to invoke live runtime apply.
Any future Crab invocation would require separate approval, separate tests, separate CI, and explicit human control.

## Forbidden shortcuts

- no direct promotion from disposable apply to live runtime apply
- no implicit reuse of disposable target selectors for live targets
- no rollout driven by repo-only evidence without local-only approval material
- no secret values in Git-tracked files
- no bypass of rollback requirements
- no Crab invocation without separate approval
- no deploy/migration hidden inside apply
- no orchestration loop hidden inside first real rollout

## Non-goals

- no rollout orchestration
- no supervisors
- no retries
- no schedulers
- no deploy
- no migration
- no full live-runtime adapter expansion
- no local overlay implementation
- no secrets handling implementation
- no Crab approval
- no Phase 2/3/4 behavior changes
- no workflow changes
