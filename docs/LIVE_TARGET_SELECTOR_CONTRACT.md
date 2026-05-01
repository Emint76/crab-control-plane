# LIVE_TARGET_SELECTOR_CONTRACT

## Purpose

This document defines the boundary for a future live target selector used only for future live-runtime preparation.

It is not:

- the bounded disposable selector
- the live target identity model
- the live-runtime adapter/wrapper
- live runtime apply

The selector boundary exists so future work can point at a reviewed intended live target without turning target selection into execution, approval, rollout, deploy, migration, or a full identity model.

## Status

This is a contract-only document.

Current status:

- no selector-driven live mutation
- no executable live target selection for mutation
- validation-only pre-execution gate exists for reviewed selector, approval, and rollback record shape/binding
- no live runtime apply
- no Crab approval

## Scope

A future live target selector may only identify a reviewed intended live target for a future live-runtime wrapper.

It must not:

- execute mutation
- imply approval
- imply rollout
- imply deploy
- imply migration
- act as the live-runtime adapter/wrapper
- replace the future live target identity model

## Why It Must Be Separate

The live target selector must remain separate from:

- `docs/LOCAL_DISPOSABLE_TARGET_SELECTOR_CONTRACT.md`
- `docs/CONTROLLED_DISPOSABLE_APPLY_CONTRACT.md`
- `docs/LIVE_RUNTIME_ADAPTER_WRAPPER_CONTRACT.md`

The separation is mandatory:

- disposable selector != live selector
- selector != identity
- selector != approval
- selector != execution owner
- selector != approval record
- selector != full target identity model

The bounded disposable selector is for explicitly disposable local workspace/state targets only.
It must not be promoted into a live selector by naming convention, path convention, operator habit, or wrapper reuse.

The controlled disposable apply surface remains local-only and disposable-only.
It must not become a live selector consumer.

The future live-runtime adapter/wrapper, if implemented later, would be the execution owner.
A selector may be one reviewed input to that wrapper, but the selector itself does not own execution.

## Required Selector Properties

At contract level, a future live target selector must provide reviewed semantics for:

- exact intended live target reference
- exact target class is live, not disposable
- exact workspace, state, runtime roots, or equivalent reviewed target-location references
- environment or instance label
- selector label or operator-facing identifier
- local-only storage outside Git
- reviewed human intent

These are conceptual requirements only.
A bounded validation-only schema and parser now exist under `operations/harness-openclaw-live-precheck/` for pre-execution record validation.
That gate validates reviewed selector, approval, and rollback records together, but it does not create selector-driven live mutation or approval.

## Forbidden Selector Content

A future live target selector must not contain:

- secrets
- API keys
- tokens
- OAuth credentials
- provider/model config
- disposable target selectors reused as live selectors
- inferred repo-only target selection
- ambiguous target aliases
- arbitrary extra content hidden inside the selector

The selector must not be used as a place to hide rollout intent, deploy intent, migration intent, credentials, endpoint secrets, or unreviewed local overlay material.

## Outside-Git Requirement

Any future live selector material must remain outside Git.

The repository may document the selector contract, but must not contain real selector material for a live target.
This PR does not implement reading future live selector material.
The validation-only pre-execution gate may read a reviewed selector record from outside Git only for validation with approval and rollback records.

## Relationship to Live Target Identity Model

This contract does not replace the live target identity model defined in `docs/LIVE_TARGET_IDENTITY_MODEL.md`.

It only defines the selector boundary used to point at the intended live target.
The broader live target identity model remains separate and must define exact target identity semantics.

## Relationship to Approval Model

A selector is not approval.

A selector may be an input to a future approval flow, but does not authorize execution.
Approval must remain a separate reviewed record tied to the exact target identity and exact execution attempt.
The operator approval model is defined in `docs/OPERATOR_APPROVAL_MODEL.md`.

## Relationship to Rollback Model

A selector is not rollback material.

Rollback is separately defined in `docs/ROLLBACK_MODEL.md`.
A future live runtime attempt must not infer rollback readiness from selector presence.

## Relationship to Live-Runtime Adapter/Wrapper

A future live-runtime adapter/wrapper may consume a reviewed live selector only after separate gates pass.

Those gates include the live target identity model, operator approval model, rollback model, secret handling contract, evidence retention policy, no-secret redaction policy, and the safety gates defined in `docs/LIVE_RUNTIME_APPLY_CONTRACT.md`.
The validation-only pre-execution gate may validate selector, approval, and rollback record binding before that future wrapper exists.
The gate is not the wrapper and does not authorize live runtime apply.

## Relationship to Crab-Safe Orchestration

Crab is not approved to invoke any future live target selector surface.

Any future Crab use would need separate approval, separate tests, separate CI, and explicit human-control semantics.

## Forbidden Shortcuts

- no promotion of disposable selector into live selector by convention
- no repo-only inference of live target
- no implicit approval from selector presence
- no hidden secrets in selector material
- no selector-driven live mutation without separate wrapper and approval
- no replacement of live target identity with selector labels
- no reuse of controlled disposable apply as a live selector consumer

## Non-Goals

- no selector-driven live target mutation implementation
- no live runtime apply
- no live-runtime adapter/wrapper implementation
- no live target identity implementation
- no approval execution surface
- no rollback execution surface
- no local overlay implementation
- no Crab approval
