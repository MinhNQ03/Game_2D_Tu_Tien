# 02 — Game Design

> Steering: always included. Shared vocabulary and the design rules every system
> must respect. This is design intent, **not** an implementation spec.
>
> **The full design is FROZEN (D-039).** This file stays the short enforceable rulebook; the
> master index of who owns which design rule is `docs/GAME_DESIGN_FREEZE.md`, frozen facts are in
> `docs/CANON_LEDGER.md` (cite `CL-nn`), and known contradictions with their resolutions are in
> `docs/CONTRADICTION_REGISTER.md` (cite `C-nnn`). Changing critical canon requires a
> `docs/DECISIONS.md` entry.

## Canonical glossary (use these exact terms in code & docs)

| Term (vi) | Term (en) | Meaning |
|---|---|---|
| Cảnh giới | Realm | A major cultivation tier. Gates **capability and content access**, not smooth power. The frozen hierarchy is **PHÀM → HẬU THIÊN → TIÊN THIÊN → NGỰ THIÊN → TRỌNG THIÊN** (+ structural THÁI THIÊN / VÔ THIÊN), nine layers per numbered realm — owned by `docs/PROGRESSION_CULTIVATION_DESIGN.md`, names frozen in `docs/CANON_LEDGER.md` CL-02. The conventional Luyện Khí / Trúc Cơ / Kim Đan ladder is **NOT** Aetheria canon (D-039, C-001). |
| Tri thức | Knowledge | A third progression concept, distinct from XP and realm: named, discrete, permanent facts the player has LEARNED. Gates techniques, world gates, dialogue and alternate quest solutions (CL-14). |
| Đạo cơ | Dao seed | Layer 7 of any numbered realm — where the player's personal Dao forms. The build-defining layer (CL-03). |
| Tà đạo | Heterodox | A **political** category: what the orthodox institutions have proscribed. Distinct from **Ma đạo** (a named tradition) and **Cấm pháp** (methods that are genuinely self-destructive). Never a synonym for "evil" (CL-01). |
| Thiên Khế | Heaven Covenant | The ancient covenant that rations and protects the spiritual veins — and the institutions that administer it. Aetheria's central mystery (CL-06). |
| Tà Đế | Heretic Emperor | A historical title, and an **emergent** identity the player may earn, accept, reject or redefine. Never a class, score, alignment or mandatory ending (CL-07). |
| Tu luyện | Cultivation | The act of accumulating cultivation progress toward the next realm. |
| Công pháp | Technique / Art | A cultivation method that shapes stats, resource, and which skills are usable. |
| Linh khí / Mana | Spiritual energy | The combat/skill resource pool. |
| Skill | Skill | An active or passive combat/utility ability. |
| Trang bị | Equipment | Wearable gear that modifies stats. |
| Vật phẩm | Item | Consumables, materials, quest items. |
| Linh thú | Pet | A companion entity with its own stats/skills. |
| Nhiệm vụ | Quest | A tracked objective with states and rewards. |
| Nhân vật | Character | Any person in the world (incl. the player & NPCs); authoritative, data-driven, serializable state. |
| Quan hệ | Relationship | Serializable edge between characters/sects: affinity, trust, respect, fear, rivalry, debt. |
| Tông môn | Sect | A core organization: doctrine, ranks, factions, resources, territory, reputation. |
| Phe phái | Faction | An internal group within a sect with its own leader, goals, influence, attitudes. |
| Mô phỏng thế giới | World simulation | Off-screen evolution of characters/sects via LOD (near real-time / far abstract). |

> When a new domain term appears, add it here first, then use it everywhere.

## Core loops

- **Moment-to-moment:** move (top-down) → encounter → combat (skills + equipment +
  pet) → loot/XP → heal/manage.
- **Session:** quest → explore map → dungeon → boss → story beat → save.
- **Long-term:** XP/level + tu luyện → break through a **cảnh giới** → unlock công
  pháp / skills / zones → advance **chapter** / branching story.

## Progression model (design contract)

Two parallel, intentionally distinct axes — do **not** collapse them into one number:

1. **Level / XP** — granular, combat-derived, smooth power growth.
2. **Cảnh giới / tu luyện** — chunky, gated breakthroughs that unlock *content and
   capability* (new skills, công pháp slots, zones), not just numbers.

Design rule: content gating keys off **cảnh giới**; fine power tuning keys off
**level**. Both must be serializable and testable (see `docs/TEST_PLAN.md`).

**Level is NEVER an access gate** (D-039, C-002) — not for maps, dungeons, worlds, quests,
techniques or dialogue. Where a number must communicate difficulty, that is an advisory
**threat rating**, not permission. Access is a LAYERED gate (realm + quest/story + knowledge +
sect/faction standing + world state + key item/technique), owned by
`docs/MAP_DUNGEON_DESIGN.md` §3. `MapData` must never gain a `min_level` field.

A realm advance must always answer *"what can I do now that I could not before?"* with something
other than a bigger number (`docs/PROGRESSION_CULTIVATION_DESIGN.md` §1).

## Combat (design contract)

- Deterministic, data-driven damage. A single documented damage formula lives in
  `docs/DATA_SCHEMA.md` and is the only place that math is defined.
- Inputs to a hit: attacker stats, công pháp modifiers, skill definition, equipment
  modifiers, target stats/resistances. Output: damage + applied effects + events.
- Combat emits events/signals (hit, damaged, died, xp_gained) so UI, quests, and
  progression react **without** combat knowing about them.

## Branching story (design contract)

- Story state is explicit data: flags, chapter id, completed quests, choices made.
- Branches are decided by querying story/flag state, never by scattered booleans in
  unrelated nodes.
- A new chapter = new content/data + new scenes; it must not require editing the
  story engine itself.

## Extensibility rule (the most important design rule)

Adding **map / chapter / quest / enemy / boss / pet / skill / item / cultivation
tier / event / dungeon** must be achievable by authoring **data (Resources) +
content scenes**, not by modifying core system code. If a new content type forces a
core rewrite, that is a design bug — raise it in `docs/DECISIONS.md`.

## Balance & tuning

All tunable numbers live in data (Resources / config), never as magic numbers in
scripts. See `.kiro/steering/04-coding-standards.md`.
