# LIVE_TARGET_IDENTITY_MODEL

## Purpose

This document defines the future live target identity model for any possible live-runtime execution discussion.

The model describes how a real live OpenClaw runtime target must be identified before any future implementation or execution attempt can be considered.

## Status

This is a contract/model-only document.

Current status:

- no implementation
- no live runtime apply
- no live target selector implementation
- no live-runtime adapter/wrapper implementation
- no Crab approval

## Scope

The live target identity model defines exact identity semantics for a reviewed live target.

It does not execute mutation, select targets by itself, approve execution, perform rollback, retain evidence, redact secrets, or own a live-runtime wrapper.

## Required Live Target Identity

A future reviewed live target identity must include:

- exact instance identity
- exact target class = live
- exact workspace, state, runtime roots, or equivalent reviewed location set
- exact environment or instance label
- exact operator-facing label
- exact anti-confusion rules for disposable, test, and live targets
- exact reason this target is the intended target
- exact relationship between the target and any reviewed selector input

The identity record must be precise enough that another reviewer can distinguish the intended live target from any disposable target, test target, stale target, or similarly named local path.

## Live vs Disposable/Test Targets

Live targets have continuity, identity, configuration, and operational consequences.

Disposable targets are explicitly local-only, disposable-only, and intended to be deleted after validation.
Test targets may prove behavior but must not be treated as live targets by naming convention, path shape, or successful disposable execution.

The identity model must prevent confusion between:

- disposable targets
- test targets
- live targets

## Selector Is Not Identity

selector != identity

selector != identity model

A live target selector may point at an intended live target, but the selector does not define the complete target identity.
The identity model must independently define exact reviewed semantics for the target.

The identity model must not be inferred from a selector label alone.

## Identity Is Not Approval Or Execution

identity != approval

identity model != approval

identity model != execution owner

A reviewed identity record does not authorize execution.
It may be an input to the future operator approval model and future live-runtime adapter/wrapper, but it is not approval and does not own mutation.

## Required Reviewed Identity Semantics

Before any future live-runtime implementation discussion, the identity model must require:

- human-reviewed instance identity
- human-reviewed target class confirmation
- human-reviewed target-location set
- human-reviewed anti-confusion rules
- human-reviewed selector-to-identity relationship
- explicit statement that the target is not disposable
- explicit statement that identity presence does not approve execution

## Forbidden Ambiguity

The identity model must forbid:

- inferred repo-only identity
- ambiguous aliases
- path guessing
- selector-only identity
- reusable shorthand that could point at multiple targets
- disposable selector reuse as live identity
- implicit promotion from disposable/test to live
- identity hidden inside approval text
- identity hidden inside wrapper configuration

## Relationship to Live Target Selector Contract

`docs/LIVE_TARGET_SELECTOR_CONTRACT.md` defines how a future selector may point at the intended live target.

This document defines what exact identity semantics must exist for that target.
The selector remains a pointer; the identity model remains the reviewed target definition.

## Relationship to Operator Approval Model

`docs/OPERATOR_APPROVAL_MODEL.md` defines future human approval semantics.

Approval must bind to the exact reviewed target identity.
Identity does not imply approval.

## Relationship to Rollback Model

`docs/ROLLBACK_MODEL.md` defines rollback semantics.

Rollback inputs must bind to the exact reviewed target identity.
Identity does not imply rollback readiness.

## Relationship to Live-Runtime Adapter/Wrapper

`docs/LIVE_RUNTIME_ADAPTER_WRAPPER_CONTRACT.md` defines the future execution-owner boundary.

A future wrapper may consume a reviewed live target identity record only after separate gates pass.
This document does not create or approve that wrapper.

## Non-Goals

- no live target selector implementation
- no live runtime apply
- no live-runtime adapter/wrapper implementation
- no operator approval model implementation
- no rollback implementation
- no secret handling implementation
- no evidence retention implementation
- no no-secret redaction implementation
- no Crab approval
