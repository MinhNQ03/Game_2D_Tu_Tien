# Docs Sync Contract — Aetheria

> **Mandatory.** Referenced by `.kiro/steering/08-ai-review-protocol.md`
> (per-change review) and `docs/PHASE_EXECUTION_PROTOCOL.md` §12 (phase close).
> This file owns the detailed knowledge-impact checklist; the protocols own
> their gates and reference here instead of duplicating it.

## Principle

The repo's tracked Markdown is the source of truth; `docs/knowledge/` is the
map. A change that updates code or design without updating the map teaches the
next agent the wrong project. **A green build is not proof of documentation
consistency.**

## Before editing

1. **Read the owner docs in full** — start from the
   [Knowledge Hub](AETHERIA_KNOWLEDGE_HUB.md) §A; never edit a system whose
   owner doc you have not read.
2. **Identify the rule owner** for every concept you will touch
   ([GAME_DESIGN_FREEZE.md](../GAME_DESIGN_FREEZE.md) ownership table).
3. **Search for references**: `grep -rn` the rule name, system name, data
   shape, status string, and decision ID (`D-0nn`) across `docs/` and
   `.kiro/steering/`.
4. **Check the [dependency map](DOCS_DEPENDENCY_MAP.md)** for downstream docs
   that must be impact-reviewed.
5. **Write down the affected-document list with reasons** (a short list in
   your working notes or the change report — not from memory later).
6. **Collect constraints**: relevant decisions ([index](DECISION_INDEX.md)),
   canon entries (`CL-nn`), open questions, gates, and
   [contradictions](../CONTRADICTION_REGISTER.md).
7. **Conflict? Stop.** If the request conflicts with an authoritative doc,
   report the conflict. Do not silently pick an interpretation (L-014).

## After editing

1. **Re-evaluate the affected list against the actual diff** (`git diff` —
   read it, per L-049's CLEANUP rule).
2. **Sweep for stale references**: old terminology, previous behavior, old
   IDs/statuses affected by the change.
3. **Update at the authoritative source**, or fix the reference. Never edit a
   copy while the owner still says the old thing.
4. **Regenerate indices**: `python3 tools/gen_decision_index.py` (if
   `docs/DECISIONS.md` changed).
5. **Adjust dependency edges** if a real dependency changed (with evidence).
6. **For each considered-but-unchanged doc, say why** — one line per doc.
   Skipping silently is not allowed.
7. **Validate**: `python3 tools/validate_docs.py` (links, anchors, index
   currency, labels) and `git diff --check`.
8. **Review the final diff** for contradictions, duplication, accidental canon
   changes, and misleading status claims (never write "accepted"/"closed" for
   something the owner has not accepted/closed).
9. **Report**: documents read · documents changed · documents considered but
   unchanged (with reasons) · checks run · unresolved risks.

## Decision discipline

- A meaningful architectural/design decision follows the freeze change control:
  it needs a `docs/DECISIONS.md` entry. Use the next available `D-...`
  identifier following the existing decision sequence in `docs/DECISIONS.md`
  (check the last `D-nnn` heading; do not hard-code a number here).
  `L-...` identifiers belong to `.kiro/steering/09-lessons-learned.md` —
  they are lessons-learned entries, not decision IDs. Never renumber
  existing records.
- Conflicting docs are surfaced and resolved through the established process,
  never by overwriting whichever file disagrees.
- `PROPOSAL` stays labeled until formally accepted. Writing a proposal does
  not make it canon; committing one does not either.
- Statuses are facts, not aspirations: `OPEN` stays open until its close
  condition is evidenced (H21-14 needs the owner's written playtest, not CI).

## Status vocabulary (for humans and parsers)

`EXISTING CANON` · `ACCEPTED DECISION` · `PROPOSAL` · `OPEN QUESTION` ·
`HISTORICAL` · plus the source's own words where they differ (`DONE`,
`ADOPTED`, `SUPERSEDED`, `Not recorded`). Never infer `Accepted` from silence.

## What this contract does not cover

- Semantic consistency across prose (no link checker proves two paragraphs
  agree — that is the agent's review job, step 8 above).
- Canon changes themselves (those go through `DECISIONS.md` + owner).
- Anything outside `docs/`, `.kiro/steering/`, and `tools/` docs tooling.
