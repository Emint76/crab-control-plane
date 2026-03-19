# PLACEMENT_POLICY

## Purpose
Define how artifacts are routed across Notion, Obsidian, KB, and observability based on role, maturity, and provenance.

## Scope
Applies to every artifact produced, captured, reviewed, or moved within the control-plane workflow.

## Allowed behavior
- Place workflow state in Notion.
- Place semantic notes in Obsidian when they are useful for understanding but not yet sanctioned KB assets.
- Place sanctioned assets in the KB only after required review and admission checks.
- Place logs, traces, eval outputs, and operational diagnostics in observability.
- Split mixed outputs into multiple artifacts when one object would otherwise blur layer boundaries.

## Forbidden behavior
- Treating the tool used to create an artifact as the placement rule.
- Storing approval state as the primary content of an Obsidian note.
- Storing raw workflow packets in the KB.
- Using markdown policy docs as a substitute for active operational state.
- Copying secrets or live environment values into any layer.

## Required checkpoints
1. Identify the artifact's primary role.
2. Check whether the artifact is draft, reviewable, or sanctioned.
3. Check whether provenance is sufficient for KB placement.
4. Record a placement decision when destination is non-obvious or mixed.
5. Update the operational plane to reflect the current state after placement.

## Interaction with adjacent layers
- **Decision model:** provides routing logic and tie-break rules.
- **Contracts:** placement decision records rationale, preconditions, and actions.
- **Notion:** reflects current state of routing and pending actions.
- **Retrieval:** consumes sanctioned outputs from KB and supportive context from other layers under policy.

## Examples
- A task packet and its assignee belong in Notion.
- A concept note comparing storage layers belongs in Obsidian.
- An approved source capture package belongs in the KB source-bearing area.
- A failed validation report belongs in observability, with a Notion row noting the failure state.

## Failure modes / common mistakes
- Putting semantic prose into Notion and then treating the row as durable knowledge.
- Skipping decomposition of mixed outputs.
- Promoting draft notes to KB because they are well written, even though review is incomplete.
- Forgetting that observability artifacts explain behavior rather than define sanctioned knowledge.
