# DELEGATION_POLICY

## Purpose
Define when work may be delegated as a bounded subtask and what must be fixed in a task packet before execution begins.

## Scope
Applies to every delegated unit of work represented by a task packet, whether initiated by an operator or by the orchestrator.

## Allowed behavior
- Delegate work only when the objective can be stated as a bounded task.
- Delegate using a task packet with explicit inputs, constraints, expected outputs, and acceptance criteria.
- Include provenance requirements when the task may create source-bearing or knowledge assets.
- Use destination hints to guide downstream placement without overriding placement review.

## Forbidden behavior
- Delegating an open-ended request with no bounded scope.
- Delegating work that requires inventing sources, architecture, or policy not present in the source material.
- Using delegation to bypass review or approval checkpoints.
- Treating free-form chat messages as task packets.

## Required checkpoints
1. Confirm the task has a unique identifier and clear title.
2. Confirm inputs are enumerated and refer to stable evidence.
3. Confirm constraints explicitly prohibit architecture drift and unsupported invention when relevant.
4. Confirm expected outputs and acceptance criteria are specific enough to review.
5. Confirm provenance requirements are present if KB admission could follow.

## Interaction with adjacent layers
- **Notion:** stores delegation state, assignee, and queue status.
- **Contracts:** task packet schema defines the minimum machine-readable delegation shape.
- **Obsidian / KB:** may receive outputs from delegated work only after placement review.
- **Observability:** should capture execution linkage to the task identifier.

## Examples
- Allowed: delegate "extract architecture layers from supplied source bundle" with fixed inputs and no permission to invent missing layers.
- Allowed: delegate "prepare review-ready source capture package" with explicit provenance requirements.
- Forbidden: delegate "figure out the best system architecture" when the repo already defines the architecture and the task would invent a new one.

## Failure modes / common mistakes
- Passing broad goals without acceptance criteria.
- Omitting provenance requirements for source-oriented tasks.
- Confusing operational status fields with execution instructions.
- Using delegation for policy changes without a review path.
