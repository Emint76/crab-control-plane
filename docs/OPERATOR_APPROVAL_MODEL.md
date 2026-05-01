# OPERATOR_APPROVAL_MODEL

## Purpose

This document defines the future operator approval model for any possible live-runtime execution attempt.

The model ensures that live runtime mutation cannot be inferred from selectors, identity records, repo state, wrapper availability, or successful disposable validation.

## Status

This is a model-only document.

Current status:

- no approval-granting execution surface
- validation-only gate exists for reviewed approval record shape/binding
- repo-local approval execution-prep record surface exists for normalized reviewed records only
- no live runtime apply
- no live-runtime adapter/wrapper implementation
- no Crab approval

## Scope

The operator approval model defines the future semantics of explicit human approval.

It does not select a target, define target identity, execute mutation, perform rollback, retain evidence, redact secrets, or implement a wrapper.

## What Approval Is

Approval is an explicit human decision tied to:

- exact reviewed live target identity
- exact execution attempt
- exact operator-facing execution label
- exact reviewed rollback readiness state
- exact reviewed secret/material source boundary
- exact reviewed evidence and redaction expectations

Approval must be intentional, reviewable, and specific to one future live-runtime attempt.

## What Approval Is Not

approval != selector

approval != identity model

approval != execution owner

approval != rollout by default

Approval is not implied by:

- disposable success
- repo state
- selector presence
- wrapper availability
- local overlay presence
- a previously approved attempt
- a broad operator preference

## Why Approval Must Stay Separate

Approval must be separate from selector, identity, and wrapper contracts because each has a different job:

- selector points at the intended live target
- identity model defines exact target identity semantics
- approval model records exact human authorization semantics
- wrapper contract defines the future execution owner only

Collapsing these concepts would make review ambiguous and could turn configuration presence into execution permission.

## Required Approval Record Semantics

A future approval record must include:

- explicit human approval statement
- exact target identity reference
- exact execution attempt reference
- exact approved operation class
- exact approved time/window or attempt boundary
- exact rollback handoff reference
- exact evidence retention/redaction expectation references
- exact operator identity or reviewed operator-facing label
- explicit non-reusability statement
- explicit statement that approval does not authorize deploy, migration, or rollout beyond the reviewed attempt

## Binding and Non-Reusability

Approval must bind to the exact target identity and exact execution attempt.

Approval must not be reusable across:

- different targets
- different target locations
- different execution attempts
- different operation classes
- different rollback plans
- different secret/material boundaries
- different wrapper implementations

## Relationship to Rollback Model

`docs/ROLLBACK_MODEL.md` defines rollback semantics.

Approval must not be granted unless rollback handoff inputs are reviewed.
Approval is not rollback and does not create rollback readiness.

## Relationship to Failure and Abort Model

`docs/FAILURE_AND_ABORT_MODEL.md` defines failure and abort semantics.

Approval is not failure/abort handling.
Abort/failure records must reference the exact approved execution attempt, but they do not create approval for retry or mutation.

## Relationship to Evidence Retention

`docs/EVIDENCE_RETENTION_POLICY.md` defines future evidence retention expectations.

Approval records or approval references must be retained according to that policy, without leaking secrets.

## Relationship to No-Secret Redaction

`docs/NO_SECRET_REDACTION_POLICY.md` defines redaction expectations.

Approval records must not carry raw secrets, tokens, keys, OAuth credentials, or unredacted secret-like values.

## Relationship to Validation-Only Pre-Execution Gate

`operations/harness-openclaw-live-precheck/bin/run_live_preexecution_gate.sh` validates reviewed approval record shape and binding with selector and rollback records.

That gate does not grant approval, execute approval, authorize live runtime apply, or act as a live-runtime wrapper.

## Relationship to Live Execution-Prep Bundle

`operations/harness-openclaw-live-execution-prep/bin/run_live_execution_prep.sh` creates a bounded repo-local approval execution-prep record from an already reviewed approval record after the validation-only pre-execution gate passes.

approval execution-prep record != approval grant

The execution-prep bundle normalizes reviewed approval metadata only.
It does not grant approval, execute approval, authorize live runtime apply, or act as a live-runtime wrapper.

## Relationship to Crab-Safe Orchestration

Crab is not approved to grant or invoke live-runtime approval.

Any future Crab participation would require separate approval, separate tests, separate CI, and explicit human-control semantics.

## Non-Goals

- no approval-granting execution surface
- no live runtime apply
- no live-runtime adapter/wrapper implementation
- no live target selector implementation
- no live target identity implementation
- no rollback implementation
- no secret handling implementation
- no Crab approval
