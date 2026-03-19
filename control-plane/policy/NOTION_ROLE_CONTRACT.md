# NOTION_ROLE_CONTRACT

## Purpose
Define Notion's role as the operational plane for intake, queue state, review movement, and coordination metadata.

## Scope
Applies to all Notion databases, templates, and operational properties referenced by this control plane.

## Allowed behavior
- Store intake items, task rows, project tracking rows, review queue entries, assignees, priorities, statuses, and next actions.
- Link operational rows to task packet IDs, result packet IDs, review decisions, and note identifiers.
- Use views and formulas to support triage and review throughput.

## Forbidden behavior
- Treating Notion as canonical policy, sanctioned KB storage, or semantic graph.
- Storing secrets, production credentials, or raw environment values.
- Using Notion rows as substitutes for source-bearing assets.
- Encoding normative approval rules only in Notion properties without a corresponding policy document.

## Required checkpoints
1. Every operational row must have a clear title, item type, and status.
2. Rows that correspond to packets must preserve the packet identifier.
3. Review-related rows must make current review state explicit.
4. Operational notes should summarize, not replace, the canonical artifact stored elsewhere.

## Interaction with adjacent layers
- **Task and result packets:** Notion rows reference them and track state transitions.
- **Obsidian:** Notion may link to note identifiers but does not own note semantics.
- **KB:** admission and review state may be tracked in Notion, but sanctioned assets live in the KB.
- **Observability:** run identifiers may be linked for investigation.

## Examples
- An inbox row representing a new research request.
- A task queue row linked to `task-extraction-001`.
- A review queue row waiting on provenance fixes for a proposed KB asset.

## Failure modes / common mistakes
- Turning Notion into a long-form knowledge repository.
- Copying the full content of knowledge assets into operational rows.
- Leaving packet linkage blank, which breaks auditability.
- Treating database status names as canonical policy definitions.
