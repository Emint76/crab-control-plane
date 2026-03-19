# DECISION_MODEL

## Purpose
This document defines how the orchestrator or reviewer decides where a new artifact belongs and what checkpoint must happen before the artifact moves again.

## Primary routing rule
Route by the artifact's current role, not by where it was produced.

- If the artifact primarily represents workflow state, place it in Notion.
- If the artifact primarily represents semantic understanding, place it in Obsidian.
- If the artifact is approved for durable reuse, place it in the KB.
- If the artifact primarily explains runtime behavior, place it in observability.

## Operational routing table

| Artifact role | Default destination | Required checkpoint before move |
|---|---|---|
| Intake request | Notion inbox | Basic completeness check |
| Delegated task object | Notion task queue | Task packet validation |
| Result awaiting review | Notion review queue | Result packet validation |
| Working semantic note | Obsidian | Placement decision confirming semantic role |
| Source capture package | KB source-bearing area | Admission + provenance check |
| Approved knowledge asset | KB knowledge area | Review decision with approval |
| Run trace, eval, report | Observability | Identifier linkage to task or run |

## Routing procedure
1. Identify the artifact's primary role.
2. Check whether the artifact is operational, semantic, sanctioned, or observational.
3. Check whether mandatory contract fields are present.
4. Check whether provenance is sufficient for the target layer.
5. Route to the lowest-maturity valid layer first; do not skip review checkpoints.

## Mixed routing logic
Some outputs must be split rather than placed as one object.

### Common mixed cases
- A task produces both a workflow update and a semantic note.
  - Put queue state and assignment metadata in Notion.
  - Put the semantic note in Obsidian.
- A source is captured and also summarized.
  - Put the captured source package in KB only after admission.
  - Put the synthesis note in Obsidian unless it has already passed KB review.
- A review produces a decision and reviewer reasoning.
  - Put the active review state in Notion.
  - Put long-form operational evidence in observability if needed.
  - Put approved final asset in KB only when the decision is `approve`.

## Tie-break rule
If an artifact appears to fit more than one layer, choose the layer that matches the artifact's least-derived role.

Order of precedence:
1. **Operational state beats semantic convenience.** A task row stays in Notion even if it contains rich text.
2. **Source-bearing evidence beats synthesis.** A captured source package stays source-bearing even if it includes notes.
3. **Sanctioned KB status beats draft note status.** Once approved and admitted, the reusable asset belongs in KB.
4. **Observability beats explanation copies.** Logs and run evidence belong in observability even if summarized elsewhere.

## Escalation conditions
Escalate to manual review when:
- provenance is incomplete but the artifact is proposed for KB placement
- the artifact mixes workflow and semantic content in one object
- approval status and placement target disagree
- the result packet suggests a destination that conflicts with placement policy

## Non-rules
- Production of an artifact in a tool does not force that tool to be the storage destination.
- Obsidian notes are not task objects.
- Notion pages are not canonical policy.
- KB collections are not review queues.

## Examples
- A delegated extraction request with assignee, due date, and status belongs in Notion.
- A concept explanation comparing operational and semantic planes belongs in Obsidian.
- An approved source package with stable representation and provenance belongs in the KB.
- A run failure report with timestamps and evaluator notes belongs in observability.
