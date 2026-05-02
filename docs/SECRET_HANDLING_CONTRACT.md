# SECRET_HANDLING_CONTRACT

## Purpose

This document defines the future secret handling contract for any possible live-runtime execution work.

It sets the boundary for allowed secret/material sources and forbids raw secret emission into Git-tracked files, repo-local evidence, logs, or reports.

## Status

This is a contract-only document.

Current status:

- bounded source declaration validation exists
- no real secret loading implementation
- no local overlay implementation
- no live runtime apply
- no live-runtime adapter/wrapper implementation
- no Crab approval

secret handling contract != secret handling implementation

## Scope

The contract defines future source classes, forbidden source classes, local-only boundaries, and relationships to redaction and evidence retention.

It does not implement real secret loading, credential storage, broad local overlay reading, full evidence storage, live runtime apply, or a wrapper.

## Allowed Future Secret/Material Source Class

Secrets and sensitive material may come only from approved local-only material outside Git.

Allowed future source classes must be:

- outside the repository
- explicitly declared
- human-reviewed
- tied to the exact execution attempt
- covered by no-secret redaction expectations
- covered by evidence retention expectations
- validated before any future live mutation

## Forbidden Secret Source Class

Future live-runtime work must not consume secrets from:

- Git-tracked files
- repo-local generated evidence
- selectors
- approval records
- rollback records
- placement plans
- docs
- workflow files
- inferred environment defaults
- hidden wrapper internals

## Why Secrets Must Stay Outside Git

Secrets, tokens, API keys, OAuth credentials, private keys, endpoint credentials, and provider/model credentials must never enter Git.

Git-tracked material is reviewable and durable.
Raw secrets in Git would create persistent exposure and would violate the local-only boundary.

## Preservation of Disposable Evidence Rules

Existing disposable evidence rules remain preserved.

Disposable dry-run, safety validation, controlled disposable apply, local selector, and full local disposable proof surfaces must not begin reading broader live secret material because this contract exists.

## Required Local-Only Material Boundaries

Future local-only material boundaries must require:

- explicit outside-Git path declaration
- explicit human review
- explicit no-secret redaction checks
- no raw secret emission into repo-local evidence
- no silent secret ingestion
- no selector-carried secrets
- no approval-record-carried secrets
- no rollback-record-carried secrets

## Relationship to Local Overlay

`docs/LOCAL_OVERLAY_CONTRACT.md` defines the local overlay boundary.

This contract may govern future secret/material classes that live in local overlay or equivalent approved outside-Git material.
This PR does not implement reading local overlay.

## Relationship to No-Secret Redaction Policy

`docs/NO_SECRET_REDACTION_POLICY.md` defines what must be redacted or never emitted.

secret handling != redaction

Secret handling defines allowed source boundaries.
Redaction defines output safety expectations.

`operations/harness-openclaw-live-retention/bin/run_secret_retention_surface.sh` now validates a reviewed source declaration and applies bounded redaction to candidate evidence before retention.
That surface does not load raw secrets from the declared sources and does not implement full secret handling.

`operations/harness-openclaw-live-material-resolution/bin/run_live_material_resolution.sh` now validates declared material paths from a reviewed outside-Git source declaration and emits repo-local refs-only material-resolution evidence.
It records source references and path kinds only; material resolution != raw secret loading.
It does not read broader local overlay material and does not copy raw source material into repo-local outputs.

## Relationship to Evidence Retention

`docs/EVIDENCE_RETENTION_POLICY.md` defines retained evidence classes.

Evidence retention must retain enough proof of source review without retaining raw secrets.

The bounded live retention surface can retain redacted candidate evidence under its own run directory.
It is not full live evidence storage and is not wrapper-owned live execution evidence.

## Relationship to Live-Runtime Adapter/Wrapper

`docs/LIVE_RUNTIME_ADAPTER_WRAPPER_CONTRACT.md` defines the future execution-owner boundary.

A future wrapper may consume approved local-only material only after separate gates pass.
This contract does not create or approve that wrapper.

The bounded material-resolution surface may prepare refs-only material metadata before any future wrapper.
It is not the execution owner and does not implement secret loading.

## Non-Goals

- no secret handling implementation
- no real secret loading implementation
- no local overlay implementation
- no live runtime apply
- no live-runtime adapter/wrapper implementation
- no live target selector implementation
- no approval execution surface
- no evidence storage implementation
- no Crab approval
