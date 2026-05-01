# EVIDENCE_RETENTION_POLICY

## Purpose

This document defines the future evidence retention policy for any possible live-runtime execution attempt.

The policy defines what evidence classes must be retained and how retention must avoid leaking secrets.

## Status

This is a policy-only document.

Current status:

- no storage implementation
- no live runtime apply
- no live-runtime adapter/wrapper implementation
- no Crab approval

evidence retention policy != storage implementation

## Scope

The policy defines future evidence classes, retention boundary expectations, and ownership expectations.

It does not implement storage, redaction, secret handling, rollback, approval, live runtime apply, or a wrapper.

## Evidence Classes That Must Be Retained

Future live-runtime execution must retain:

- pre-execution record
- execution log
- mutation action log
- target identity record
- live target selector reference
- approval record reference
- rollback handoff record
- rollback status record
- secret/material source declaration reference
- redaction/no-secret validation record
- final execution report
- final status record
- failure/abort record when applicable

## Evidence That May Be Redacted

Evidence may be redacted when needed to prevent leakage of:

- raw secrets
- tokens
- API keys
- OAuth credentials
- private keys
- endpoint credentials
- secret-like values
- sensitive local-only paths if policy requires redaction

Retention must not leak secrets.

## Retention Boundary Expectations

Future retained evidence must:

- bind to the exact execution attempt
- bind to the exact reviewed target identity
- reference approval without carrying secrets
- reference rollback readiness/status without carrying secrets
- reference secret/material source review without carrying raw secrets
- preserve enough information for review after execution
- remain separate from implementation-specific storage mechanics

## Canonical Live-Execution Evidence Ownership

A future live-runtime adapter/wrapper must own the canonical live-execution evidence surface for a live mutation attempt.

The evidence retention policy defines what must be retained.
It does not define how storage is implemented.

## Relationship to Approval Model

`docs/OPERATOR_APPROVAL_MODEL.md` defines approval semantics.

Approval records or approval references must be retained and tied to the exact execution attempt.

## Relationship to Rollback Model

`docs/ROLLBACK_MODEL.md` defines rollback semantics.

Rollback handoff records, operator decision points, rollback status, and failure/abort evidence must be retained.

## Relationship to No-Secret Redaction Policy

`docs/NO_SECRET_REDACTION_POLICY.md` defines redaction expectations.

retention != redaction

Retention defines what evidence classes must exist.
Redaction defines what must not appear unredacted in those evidence classes.

## Relationship to Secret Handling Contract

`docs/SECRET_HANDLING_CONTRACT.md` defines allowed secret/material source boundaries.

Retention must record source review and boundary compliance without retaining raw secrets.

## Non-Goals

- no storage implementation
- no live runtime apply
- no live-runtime adapter/wrapper implementation
- no approval execution surface
- no rollback execution surface
- no secret handling implementation
- no no-secret redaction implementation
- no Crab approval
