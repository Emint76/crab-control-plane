# KB_LAYOUT

## Purpose
Define the high-level layout and discipline for sanctioned assets in the KB.

## Layout
- `sources/` for sanctioned source-bearing assets and source capture packages
- `knowledge/` for sanctioned knowledge assets
- `collections/` for curated groupings over sanctioned assets

## Asset classes

### Source-bearing assets
Primary purpose: preserve external source material and provenance in stable form.

Minimum required provenance:
- canonical pointer
- retrieval status
- retrieval timestamp
- content type
- stable representation
- human identifier
- linkage to related note, task, or review identifiers where relevant

### Knowledge assets
Primary purpose: express reusable understanding, synthesis, or structured knowledge for retrieval.

Minimum expectations:
- clear knowledge role or type
- intelligible content without hidden workflow context
- source linkage where claims depend on external evidence
- review outcome suitable for KB placement
- stable identifier for retrieval and maintenance

## Collections
Collections organize sanctioned assets for retrieval or navigation. They do not represent tasks, queues, approvals, or mutable operational ownership.

## Discipline
- KB stores sanctioned assets only.
- Raw workflow and task objects do not belong in the KB because they encode transient operational state, not reusable sanctioned knowledge.
- Draft semantic notes stay in Obsidian until reviewed and admitted.
- Source-bearing and knowledge assets must stay distinguishable; a synthesis note is not a source package, and a captured page is not a final knowledge asset simply because it is useful.
