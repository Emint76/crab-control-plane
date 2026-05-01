# NO_SECRET_REDACTION_POLICY

## Purpose

This document defines the future no-secret redaction policy for any possible live-runtime execution evidence, logs, reports, and records.

The policy defines what must be redacted or must never appear in repo-local evidence.

## Status

This is a policy-only document.

Current status:

- bounded redaction surface exists for candidate evidence retention
- no wrapper-integrated redaction implementation
- no real secret handling implementation
- no live runtime apply
- no live-runtime adapter/wrapper implementation
- no Crab approval

redaction policy != secret source contract

redaction policy != execution permission

## Scope

The policy defines redaction expectations for future live-runtime evidence surfaces.

It does not define allowed secret sources, implement real secret loading, implement full live evidence storage, approve execution, or create a wrapper.

## What Must Always Be Redacted

Future evidence, logs, reports, approval records, rollback records, and status records must redact:

- raw secrets
- raw tokens
- raw API keys
- raw OAuth credentials
- private keys
- endpoint credentials
- provider/model credentials
- session cookies
- unredacted secret-like values
- local-only material that would reveal secret contents

## What Must Never Appear In Repo-Local Evidence

Repo-local evidence, logs, reports, and retained records must never contain:

- raw secrets
- raw tokens/keys/OAuth credentials
- unredacted secret-like values in logs
- unredacted secret-like values in reports
- approval records carrying raw secrets
- rollback records carrying raw secrets
- failure/abort records carrying raw secrets
- selectors carrying raw secrets
- wrapper output carrying raw secrets

There is no implicit exemption because material is local-only.

## Relationship to Secret Handling Contract

`docs/SECRET_HANDLING_CONTRACT.md` defines allowed secret/material source boundaries.

redaction policy != secret source contract

Secret handling defines where sensitive material may come from.
Redaction defines what must not be emitted.

## Relationship to Evidence Retention Policy

`docs/EVIDENCE_RETENTION_POLICY.md` defines retained evidence classes.

retention != redaction

Retention defines what evidence must be kept.
Redaction defines what must be removed, masked, or excluded before evidence is retained.

`operations/harness-openclaw-live-retention/bin/run_secret_retention_surface.sh` now applies bounded redaction to candidate evidence before retaining copies under its own run directory.
That surface is not full live evidence storage.

`operations/harness-openclaw-live-wrapper-intake/bin/run_live_wrapper_intake.sh` creates a refs-and-metadata-only bundle that may point at retained evidence paths.
It must not inline retained file contents or secret-like values.

## Relationship to Approval and Rollback Records

`docs/OPERATOR_APPROVAL_MODEL.md` defines approval semantics.
`docs/ROLLBACK_MODEL.md` defines rollback semantics.

Approval and rollback records may reference reviewed secret/material source boundaries, but must not carry raw secrets.

## Relationship to Failure and Abort Records

`docs/FAILURE_AND_ABORT_MODEL.md` defines failure and abort semantics.

Failure/abort records must obey no-secret redaction and must not contain raw secrets or unredacted secret-like values.

## Relationship to Live-Runtime Adapter/Wrapper

`docs/LIVE_RUNTIME_ADAPTER_WRAPPER_CONTRACT.md` defines the future execution-owner boundary.

A future wrapper must enforce no-secret redaction before emitting retained evidence.
This policy does not create or approve that wrapper.

The bounded retention surface is separate from the future wrapper.
It does not mutate targets, grant approval, perform rollback, or authorize live runtime apply.

The bounded wrapper-intake surface is also separate from the future wrapper.
It does not load raw secrets, inline retained contents, mutate targets, grant approval, perform rollback, or authorize live runtime apply.

## Non-Goals

- no wrapper-integrated redaction implementation
- no real secret handling implementation
- no live runtime apply
- no live-runtime adapter/wrapper implementation
- no evidence storage implementation
- no approval execution surface
- no rollback execution surface
- no Crab approval
