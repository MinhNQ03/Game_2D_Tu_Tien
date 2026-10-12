# Docs Dependency Map — Aetheria

> **What this is:** for each important source document, which downstream
> documents must be impact-reviewed when the source changes — and *why*
> (evidence column). A row is a **verified dependency**, not a related-topic
> link. `unverified` means the relationship is suspected but not evidenced —
> do not act on it as fact.
>
> Authority for "who owns what" is [GAME_DESIGN_FREEZE.md](../GAME_DESIGN_FREEZE.md);
> this map only records the *downstream* direction. Proposals
> (`docs/proposals/`) are indexed separately and are never dependency targets
> of canon.

## How to read a row

`Source` owns a rule/fact. `Destination` must be reviewed when the source
changes. `Relation` is one of: `owns-rule-for`, `depends-on`, `constrains`,
`consumes-data-from`, `implements/verifies`, `supersedes`. `Evidence` cites the
source doc + section that establishes the edge.

## Core authority chain

| Source | Destination | Relation | Evidence |
|---|---|---|---|
| `docs/GAME_DESIGN_FREEZE.md` | `docs/CANON_LEDGER.md`, `docs/WORLD_BIBLE.md`, `docs/NARRATIVE_MASTER_PLAN.md`, + 10 others | owns-rule-for | Freeze §2 ownership table; §3 lists the 13 frozen documents |
| `docs/DECISIONS.md` | every frozen doc | constrains | Freeze §1: frozen change needs a binding `DECISIONS.md` entry |
| `docs/CANON_LEDGER.md` | `docs/WORLD_BIBLE.md`, `docs/NARRATIVE_MASTER_PLAN.md`, `docs/CONTENT_BIBLE.md` | owns-rule-for | Freeze §2: frozen facts cited as `CL-nn` |
| `docs/CONTRADICTION_REGISTER.md` | `docs/ROADMAP.md`, `docs/ARCHITECTURE.md` | depends-on | Register: C-009 (ROADMAP is the only phase vocabulary), C-010/C-012 (resolved in `SYSTEM_DEPENDENCY_MATRIX.md` §4b/§4c) |
| `.kiro/steering/01-product.md` | `docs/MULTIPLAYER_PLAN.md`, `docs/ROADMAP.md` | owns-rule-for | 01: D-074 direction; multiplayer phases 32–34 in ROADMAP |
| `.kiro/steering/02-game-design.md` | `docs/MAP_DUNGEON_DESIGN.md`, `docs/DATA_SCHEMA.md` | owns-rule-for | 02: C-002 layered gates owned by MAP_DUNGEON_DESIGN §3; damage formula lives in DATA_SCHEMA |
| `.kiro/steering/03-architecture.md` | `docs/ARCHITECTURE.md`, `docs/SYSTEM_DEPENDENCY_MATRIX.md` | owns-rule-for | 03: layer boundaries, autoload budget, state partition |
| `.kiro/steering/08-ai-review-protocol.md` | `docs/PHASE_EXECUTION_PROTOCOL.md` | depends-on | 08: "for a full PHASE, PHASE_EXECUTION_PROTOCOL is binding" |
| `docs/PHASE_EXECUTION_PROTOCOL.md` | `docs/ROADMAP.md`, `docs/handoff/*` | constrains | Protocol §12 DOCS: ROADMAP status, handoff evidence required at phase close |

## Narrative and world

| Source | Destination | Relation | Evidence |
|---|---|---|---|
| `docs/NARRATIVE_MASTER_PLAN.md` §14 | `docs/MULTIPLAYER_PLAN.md`, C2 proposal §17 | owns-rule-for | NMP §14: frozen four-way narrative state split |
| `docs/NARRATIVE_MASTER_PLAN.md` §9a | `docs/CONTENT_BIBLE.md` | owns-rule-for | NMP §9a: "the ONE place" the K-series clue ledger is kept |
| `docs/NARRATIVE_MASTER_PLAN.md` §8/§9 | `docs/ROADMAP.md` (Phase 20–22 sections) | constrains | Phase 21/22 defined against acts/ladder; buyer at layer 3 |
| `docs/WORLD_BIBLE.md` §8 | `docs/SOCIAL_DESIGN.md`, `docs/SECT_SYSTEM.md` | owns-rule-for | Freeze §2: factions-in-the-world owned by WORLD_BIBLE |
| `docs/CANON_LEDGER.md` CL-11 | `docs/GAME_FLOW.md` | owns-rule-for | CL-11: `dungeon_survey_shaft` is a lead, not a place; door sealed |

## Systems and data

| Source | Destination | Relation | Evidence |
|---|---|---|---|
| `docs/SYSTEM_DEPENDENCY_MATRIX.md` | `docs/ARCHITECTURE.md`, `docs/GAME_FLOW.md` | owns-rule-for | Freeze §2: system ownership, inputs/outputs, MP seams |
| `docs/DATA_SCHEMA.md` | `docs/CONTENT_BIBLE.md`, `tools/author_story_data.py` | owns-rule-for | Freeze §2: damage formula + data shapes; story catalogs generated |
| `docs/SAVE_FORMAT.md` | `docs/SYSTEM_DEPENDENCY_MATRIX.md` | depends-on | SAVE_FORMAT: each system exposes `to_dict`/`from_dict` |
| `docs/MAP_DUNGEON_DESIGN.md` §3 | `docs/GAME_FLOW.md` §3.9, future Phase 21 | constrains | C-002: layered gates, legible-before-passable, no `min_level` |
| `docs/PROGRESSION_CULTIVATION_DESIGN.md` | `docs/GAME_FLOW.md` §3.8, `docs/ECONOMY_CRAFTING_DESIGN.md` | owns-rule-for | Freeze §2: realm semantics, level≠realm, Knowledge Core §7a |
| `docs/ECONOMY_CRAFTING_DESIGN.md` | `docs/SOCIAL_DESIGN.md` (sect ops) | constrains | Economy: every currency needs a sink; Nhân Lực never a player currency |
| `docs/COMBAT_DESIGN.md` | `docs/MAP_DUNGEON_DESIGN.md` §6 (bosses) | depends-on | Boss tests chapter mechanics; telegraph language shared |
| `docs/SOCIAL_DESIGN.md` | `docs/RELATIONSHIP_SYSTEM.md`, `docs/SECT_SYSTEM.md` | owns-rule-for | Freeze §2: character bible, relationship consequences, sect/faction design |

## Process, quality, and AI workflow

| Source | Destination | Relation | Evidence |
|---|---|---|---|
| `docs/PHASE_EXECUTION_PROTOCOL.md` §12 | `docs/DECISIONS.md`, `docs/CHANGELOG.md`, `docs/ROADMAP.md`, `docs/SYSTEM_DEPENDENCY_MATRIX.md`, `docs/TEST_PLAN.md` | constrains | Protocol §12 DOCS: the exact doc list a phase close must update |
| `.kiro/steering/08-ai-review-protocol.md` | `docs/knowledge/DOCS_SYNC_CONTRACT.md` | owns-rule-for | 08 mandates the sync contract (see §7 integration) |
| `.kiro/steering/09-lessons-learned.md` | `tools/*`, `docs/PERFORMANCE.md` | implements/verifies | L-0xx rules enforced by lint rules / tests / required log entries |
| `.kiro/steering/10-ci-failure-protocol.md` | `.github/workflows/ci.yml` | implements/verifies | Protocol's API-based diagnosis assumes the workflow's annotations |
| `docs/PLAYER_EXPERIENCE_STANDARD.md` | `docs/PHASE_EXECUTION_PROTOCOL.md` | constrains | Protocol §1c wires PX gates A–E into the phase gate chain |
| `docs/TEST_PLAN.md` | `.github/workflows/ci.yml` | implements/verifies | CI's headless suite + E2E gates implement the test plan |
| `.kiro/steering/06-art-assets.md` | `docs/VISUAL_CRAFT_WORKFLOW.md` | owns-rule-for | 06 § Visual craft: the brief is required before a visible change |
| `docs/VISUAL_CRAFT_WORKFLOW.md` | `docs/AETHERIA_ART_PIPELINE.md`, `docs/UI_UX_BIBLE.md`, `docs/MOTION_DESIGN_CONTRACT.md`, `docs/CHARACTER_ART_BIBLE.md` | depends-on | Workflow's owner table: it restates none of their rules |
| `docs/handoff/pre-phase-21-hardening.md` | `docs/ROADMAP.md` | depends-on | Handoff §18.5: gate statement references phase state |

## Production / multiplayer target

| Source | Destination | Relation | Evidence |
|---|---|---|---|
| `docs/PRODUCTION_ARCHITECTURE_CONTRACT.md` | `docs/PRESENTATION_ARCHITECTURE_CONTRACT.md`, `docs/MULTIPLAYER_PLAN.md` | owns-rule-for | Freeze §2: D-056 target — build topology, authority model |
| `docs/DECISIONS.md` D-074 | `.kiro/steering/01-product.md`, `docs/MULTIPLAYER_PLAN.md` | supersedes | D-074: multiplayer-first direction; **Q-08 open**: frozen offline-first line not yet amended |
| `docs/DECISIONS.md` D-056 | `docs/PRODUCTION_ARCHITECTURE_CONTRACT.md` | owns-rule-for | D-056: authoritative dedicated server target |

## Unverified / do-not-infer

- `docs/proposals/*` → canon docs: **no edge**. Proposals never constrain canon.
- Exact per-decision downstream impact: use the [decision index](DECISION_INDEX.md)
  entry's rationale text; do not guess from the title.
- `docs/visual_benchmarks/` → design docs: reference only, no dependency.
- Whether a future multiplayer phase re-scopes the narrative state split: **Q-02
  open** — the map records no edge here.

## Maintenance

Hand-maintained. Add an edge only with an `Evidence` citation. When a real
dependency changes, update the row — and run `python3 tools/validate_docs.py`
so dead targets are caught.
