# OBSIDIAN_ROLE_CONTRACT

## Purpose
Define Obsidian's role as the semantic plane for draft understanding, synthesis, and durable human-readable note structure.

## Scope
Applies to semantic notes stored in the Obsidian vault and to the conventions that govern note metadata and linking.

## Allowed behavior
- Store source notes, concept notes, comparison notes, and permanent notes.
- Use frontmatter and links to preserve note identity, note type, status, tags, and source linkage.
- Keep draft semantic material that may later inform sanctioned KB assets.

## Forbidden behavior
- Using Obsidian as a task queue, approval register, or operational dashboard.
- Treating note status as equivalent to formal review approval.
- Storing mutable workflow assignments, SLAs, or handoff ownership as the note's primary content.
- Presenting draft notes as canonical KB assets.

## Required checkpoints
1. Each note must declare a valid note type and status.
2. Titles and filenames must remain stable enough for humans to retrieve and compare notes.
3. Source-bearing claims should include source links or explicit absence markers.
4. Notes proposed for KB promotion must pass review outside the vault.

## Interaction with adjacent layers
- **Notion:** may reference the note for workflow purposes, but workflow state stays in Notion.
- **KB:** approved notes may be transformed into sanctioned knowledge assets.
- **Contracts:** knowledge note contract defines the minimal structured expectations.
- **Retrieval:** Obsidian notes are useful semantic context but not the highest-trust sanctioned source.

## Examples
- A concept note defining "operational plane versus semantic plane."
- A comparison note contrasting two retrieval strategies.
- A source note summarizing a captured document while linking back to a source-bearing asset.

## Failure modes / common mistakes
- Adding assignee and due date fields to note frontmatter.
- Allowing note statuses like "approved" to stand in for real review decisions.
- Losing source links during synthesis.
- Conflating permanent notes with sanctioned KB assets.
