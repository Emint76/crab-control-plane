# EVOLUTION_BOUNDARY

## Purpose
Define what the future evolution loop may observe and propose, and what it must not change automatically.

## Scope
Applies to any workflow that analyzes observability outputs, review outcomes, or repeated failures to suggest control-plane improvements.

## Allowed behavior
- Analyze logs, evals, and review outcomes for repeated routing, quality, or policy failures.
- Propose changes to prompts, schemas, templates, or policy documents.
- Produce draft recommendations with evidence and expected impact.

## Forbidden behavior
- Self-applying policy changes without repository review.
- Modifying live runtime state directly from observability findings.
- Treating evaluation correlation as sufficient reason to bypass human judgment.
- Inventing new architecture layers or collapsing existing ones without explicit review.

## Required checkpoints
1. Tie any proposed change to observed evidence from observability or review outcomes.
2. State the affected policy surface or contract explicitly.
3. Represent the proposed change as a normal repository modification for review.
4. Verify the proposal does not violate layer boundaries.

## Interaction with adjacent layers
- **Observability:** provides evidence for possible improvements.
- **Policy and contracts:** are the allowed change targets, but only through reviewed commits.
- **Notion:** may track proposal workflow, but does not authorize adoption.
- **Runtime:** consumes approved changes after they are merged and deployed elsewhere.

## Examples
- Allowed: propose tightening a schema after repeated invalid result packets appear in review.
- Allowed: propose a prompt update after eval reports show systematic omission of provenance fields.
- Forbidden: automatically rewriting placement policy because a model guessed a more convenient destination.

## Failure modes / common mistakes
- Confusing suggestion generation with authority to change the control plane.
- Optimizing for throughput while eroding provenance requirements.
- Updating prompts without checking contract compatibility.
- Treating observability dashboards as the policy source of truth.
