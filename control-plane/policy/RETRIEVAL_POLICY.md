# RETRIEVAL_POLICY

## Purpose
Define what layers may be used during retrieval and how trust should be weighted across sanctioned, draft, and operational artifacts.

## Scope
Applies whenever the orchestrator, an operator, or a downstream workflow retrieves material to answer a question or support a new task.

## Allowed behavior
- Prefer sanctioned KB assets for reusable knowledge and source-bearing evidence.
- Use Obsidian notes as semantic aids when sanctioned KB coverage is incomplete.
- Use Notion records to understand workflow state, pending review, or operational ownership.
- Use observability records to diagnose how prior outputs were produced or why they failed.

## Forbidden behavior
- Treating Notion queue rows as canonical knowledge answers.
- Treating draft Obsidian notes as approved KB assets.
- Retrieving observability logs as if they were normative policy.
- Returning a knowledge claim without preserving available provenance links.

## Required checkpoints
1. Identify the purpose of retrieval: knowledge answer, workflow context, provenance check, or runtime diagnosis.
2. Query the highest-trust relevant layer first.
3. Preserve linkage to source-bearing assets when the retrieved content supports substantive claims.
4. Mark draft or provisional material as such when KB coverage is absent.
5. Avoid contaminating the answer with operational noise that does not bear on the question.

## Interaction with adjacent layers
- **KB:** primary retrieval layer for sanctioned assets.
- **Obsidian:** secondary retrieval layer for semantic synthesis and exploration.
- **Notion:** contextual layer for operational state only.
- **Observability:** diagnostic layer for execution evidence.

## Examples
- For "what is the approved architecture boundary," retrieve policy docs and KB knowledge assets first, not task rows.
- For "why was this note not admitted," retrieve the review decision and related observability trail.
- For exploratory research, consult Obsidian notes but label them as draft semantic context unless sanctioned copies exist.

## Failure modes / common mistakes
- Letting availability outrank trust, such as using a convenient Notion page instead of a sanctioned KB asset.
- Returning semantic notes without indicating draft status.
- Ignoring provenance links when synthesizing a response.
- Mixing operational status text into knowledge retrieval results.
