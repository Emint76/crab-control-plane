# ROLLBACK_MODEL

## Purpose

This document defines the future rollback model for any possible live-runtime execution attempt.

Rollback must be explicit before live mutation begins so that a failed or aborted operation has a reviewed boundary, handoff, and evidence expectation.

## Status

This is a model-only document.

Current status:

- no implementation
- no rollback execution surface
- no live runtime apply
- no live-runtime adapter/wrapper implementation
- no Crab approval

## Scope

The rollback model defines required rollback inputs, boundaries, handoff semantics, operator decision points, and evidence expectations.

It does not select a target, approve execution, implement a wrapper, retain evidence, redact secrets, or perform rollback.

## Required Rollback Inputs

Before any future live execution, rollback inputs must include:

- exact reviewed live target identity reference
- explicit rollback boundary
- explicit rollback handoff record
- explicit pre-execution snapshot or equivalent reference
- explicit rollback decision points
- explicit rollback status/evidence expectations
- explicit abort/failure relationship
- explicit operator review of rollback readiness

## What Rollback Is Not

rollback != selector

rollback != approval

rollback != wrapper implementation

Rollback is not implied by a selector, target identity record, approval record, disposable success, wrapper availability, or local overlay presence.

## Why Rollback Must Be Defined First

Live runtime mutation affects a real target with continuity and operational consequences.

Rollback must not be defined after execution starts.
Rollback must not be assumed, deferred, or inferred from disposable validation.

## Required Rollback Handoff Semantics

A future rollback handoff must define:

- what can be rolled back
- what cannot be rolled back
- who must decide whether rollback is triggered
- what evidence proves rollback readiness
- what evidence records rollback status
- where rollback inputs are sourced
- how rollback avoids leaking secrets
- how rollback binds to the exact target identity

## Required Operator Decision Points

The rollback model must define operator decision points for:

- pre-execution readiness confirmation
- abort before mutation
- partial failure
- post-mutation validation failure
- rollback trigger
- rollback refusal or deferral
- final rollback status

## Failure and Abort Relationship

If rollback readiness is missing or ambiguous, future live execution must abort before mutation.

If a future wrapper detects validation failure, it must fail closed according to the wrapper contract and record status according to the evidence retention policy.

`docs/FAILURE_AND_ABORT_MODEL.md` defines failure and abort classification.
Rollback is not failure/abort classification, and failure/abort evidence must not claim rollback unless rollback handoff/status evidence exists.

## Relationship to Target Identity Model

`docs/LIVE_TARGET_IDENTITY_MODEL.md` defines exact live target identity semantics.

Rollback inputs must bind to the exact target identity.
Rollback readiness must not be inferred from ambiguous target aliases.

## Relationship to Approval Model

`docs/OPERATOR_APPROVAL_MODEL.md` defines future approval semantics.

Approval must not be granted unless rollback handoff inputs are reviewed.
Approval is not rollback readiness.

## Relationship to Evidence Retention

`docs/EVIDENCE_RETENTION_POLICY.md` defines retained evidence classes.

Rollback handoff records, rollback decisions, rollback status, and rollback failure/abort records must be retained without leaking secrets.

## Relationship to Secret Handling

`docs/SECRET_HANDLING_CONTRACT.md` defines allowed secret/material source boundaries.

Rollback material must not carry raw secrets in repo-local evidence, approval records, logs, or reports.

## Non-Goals

- no rollback execution implementation
- no live runtime apply
- no live-runtime adapter/wrapper implementation
- no live target selector implementation
- no approval execution surface
- no secret handling implementation
- no evidence retention storage implementation
- no Crab approval
