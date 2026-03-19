# OBSIDIAN_VAULT_CONVENTIONS

Obsidian is the semantic plane. It stores notes for understanding, synthesis, and semantic linkage. It is not the workflow plane and not the sanctioned KB.

## Minimum frontmatter

```yaml
---
id: ""
title: ""
note_type: ""
status: ""
created: ""
updated: ""
tags: []
source_links: []
conceptual_links: []
---
```

## Note type semantics
- `source-note`: note centered on one source or source-bearing asset; summarizes content and preserves provenance links.
- `concept-note`: note that defines or explains a concept, boundary, or term.
- `comparison-note`: note that contrasts alternatives, approaches, or concepts.
- `permanent-note`: durable synthesis note intended to stand on its own as stable semantic understanding.

## Status meanings
- `working`: draft note still under active development; may be incomplete or unevenly sourced.
- `stable`: semantically coherent note suitable for repeated reference inside the vault.
- `archived`: note retained for history but not preferred for ongoing use.

These statuses describe semantic maturity inside Obsidian only. They are not review decisions and do not imply KB admission.

## Title and filename discipline
- `title` is the human-readable name shown inside the note.
- The filename should be a stable slug derived from the title unless there is a strong reason to preserve an existing filename.
- If the filename and title diverge, record the stable slug in note metadata or surrounding workflow references so links remain audit-friendly.
- Rename notes sparingly; semantic links are preferred over frequent filename churn.

## Required note discipline
- Keep summaries concise and semantically meaningful.
- Use `source_links` whenever the note makes source-bearing claims.
- Use `conceptual_links` to connect related notes instead of embedding workflow state.
- Keep note content intelligible without copying large volumes of operational history.

## Forbidden use
- Do not use Obsidian as a task queue.
- Do not track assignee, due date, sprint status, SLA, or review board state as note semantics.
- Do not mark notes as formally approved inside the vault in place of a review decision.
- Do not treat vault notes as canonical policy documents.
- Do not store secrets, private URLs, or environment values in notes.

## Relationship to adjacent layers
- **Notion:** tracks operational movement of notes, but not note meaning.
- **KB:** receives only sanctioned assets after review and admission; most Obsidian notes remain semantic working material.
- **Observability:** may record note-generation activity, but execution traces belong outside the vault.
