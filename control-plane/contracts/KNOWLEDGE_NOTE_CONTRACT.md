# KNOWLEDGE_NOTE_CONTRACT

Minimum structured expectations for semantic notes.

## Purpose
Define the minimal structured metadata and content expectations for semantic notes in Obsidian so they remain auditable, linkable, and distinct from workflow state.

## Field semantics
- `note_type`: semantic note class: source-note, permanent-note, concept-note, or comparison-note.
- `title`: human-readable note title.
- `summary`: short description of the note's semantic content.
- `status`: note maturity within the semantic plane, such as working, stable, or archived.
- `tags`: constrained topical tags.
- `source_links`: identifiers or pointers to supporting source-bearing assets or source notes.
- `conceptual_links`: links to related concepts or notes in the semantic graph.
- `frontmatter_guidance`: note-author instruction about how to keep metadata disciplined.
- `filename_slug`: optional stable filename form when title and filename differ.

## Required fields
- `note_type`
- `title`
- `summary`
- `status`
- `tags`

## Optional fields
- `source_links`
- `conceptual_links`
- `frontmatter_guidance`
- `filename_slug`

## Validation notes
- `note_type` and `status` use enumerated vocabularies to keep note semantics comparable.
- This contract does not include assignee, due date, or approval state because those belong to the operational plane.
- `source_links` are strongly expected for source-bearing or evidence-based notes; if absent, the note should read as working synthesis rather than sanctioned knowledge.
- The schema permits empty link arrays but not arbitrary extra metadata fields.

## Example object explanation
See `examples/sample-knowledge-note.json`.
- The example is a concept note explaining a core architecture boundary.
- Its status is `working`, which marks it as draft semantic content rather than approved KB knowledge.
- The source and conceptual links show how the note stays connected to both evidence and neighboring concepts.

## Workflow relation
- Used when creating or checking semantic notes in Obsidian.
- May be referenced by placement review when deciding whether a note stays in Obsidian or is ready for KB promotion.
- Does not itself authorize admission or approval.
