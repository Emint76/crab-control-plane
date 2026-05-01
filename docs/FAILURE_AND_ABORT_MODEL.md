# FAILURE_AND_ABORT_MODEL

## Purpose

This document defines the future failure and abort model for live-runtime execution.

It covers:

- pre-mutation abort
- in-flight failure handling
- post-mutation failure classification
- failure evidence expectations
- abort evidence expectations

## Status

This is a model-only document.

Current status:

- no implementation
- no live runtime apply
- no live-runtime adapter/wrapper implementation
- no Crab approval

## Scope

This model defines:

- when execution must abort before mutation
- how failure classes must be distinguished
- what evidence must exist for abort/failure
- how failure/abort relates to approval, rollback, and retention

It does not define:

- wrapper implementation
- rollback implementation
- approval implementation
- storage implementation
- live runtime apply

## Required Pre-Mutation Abort Conditions

Future live execution must abort before mutation if any of these are missing, invalid, or ambiguous:

- target identity
- live selector boundary
- approval record
- rollback readiness inputs
- secret/material source boundary
- evidence-path validation
- no-secret/redaction precheck
- exact target-surface disambiguation

Abort before mutation must be explicit and must not silently fall through to partial execution, disposable apply behavior, or best-effort mutation.

## Required Failure Classes

Future live-runtime execution must distinguish at least these conceptual classes:

- pre-mutation abort
- validation failure before mutation
- mutation-time failure
- post-mutation validation failure
- rollback-triggered failure path
- rollback-unavailable abort/fail-closed path
- partial execution with fail-closed status

The failure class must be explicit in retained evidence.

## Required Abort Semantics

abort != rollback

abort != approval withdrawal

abort != success with warning

Abort evidence must include:

- explicit abort status
- explicit abort reason
- exact execution-attempt binding
- exact target-identity binding
- exact statement that no hidden mutation occurred after abort
- exact gate or condition that caused the abort

## Required Failure Semantics

failure != selector issue alone

failure != approval by default

failure != wrapper availability

Failure evidence must include:

- explicit failure status
- explicit failure class
- exact mutation boundary statement
- exact rollback handoff relationship
- exact retained evidence requirements
- exact execution-attempt binding
- exact target-identity binding

The mutation boundary statement must say whether mutation did not start, partially started, completed but failed validation, or entered a rollback-triggered path.

## Relationship to Rollback Model

failure/abort model != rollback model

`docs/ROLLBACK_MODEL.md` defines rollback semantics.
This model defines failure and abort classification.

Rollback triggering or rollback impossibility must be expressible inside failure handling semantics.
Failure handling must be able to record rollback-triggered paths and rollback-unavailable abort/fail-closed paths without pretending rollback occurred.

## Relationship to Approval Model

failure/abort model != approval model

`docs/OPERATOR_APPROVAL_MODEL.md` defines approval semantics.
Approval must bind to the exact execution attempt, so abort/failure records must reference that exact attempt.

Abort/failure does not withdraw approval by itself and does not create approval for a retry.

## Relationship to Evidence Retention

failure/abort model != evidence retention policy

`docs/EVIDENCE_RETENTION_POLICY.md` defines retained evidence classes.
Failure and abort records must be retained under that future policy.

## Relationship to No-Secret Redaction

Failure/abort evidence must not leak raw secrets.

`docs/NO_SECRET_REDACTION_POLICY.md` defines redaction expectations.
Failure and abort records must not contain raw tokens, keys, OAuth credentials, endpoint credentials, or unredacted secret-like values.

## Relationship to Wrapper Contract

wrapper = future execution owner

failure/abort model = failure semantics only

`docs/LIVE_RUNTIME_ADAPTER_WRAPPER_CONTRACT.md` defines the future execution-owner boundary.
The wrapper may enforce this model later, but this PR does not create that implementation.

## Forbidden Shortcuts

- no silent downgrade from failure to warning
- no silent continuation after failed gate
- no implicit success after partial mutation
- no hidden mutation after abort
- no failure evidence carrying raw secrets
- no treating disposable success as live abort/failure coverage
- no retry authorization inferred from failure evidence
- no rollback claim without rollback handoff/status evidence

## Non-Goals

- no live runtime apply
- no live-runtime adapter/wrapper implementation
- no rollback implementation
- no approval implementation
- no storage implementation
- no secret handling implementation
- no Crab approval
