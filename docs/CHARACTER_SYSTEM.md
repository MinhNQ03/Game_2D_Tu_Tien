# CHARACTER_SYSTEM — Aetheria

> **Status: the CORE is IMPLEMENTED (Phase 04, D-023).** This defines the architecture and
> data model for Character as a **core** system (D-011), not a quest-decoration NPC. The
> player is a Character too. Rules: `.kiro/steering/03-architecture.md`, data conventions:
> `docs/DATA_SCHEMA.md`.
>
> **What is live:** `CharacterTemplateData` (data, `src/data/characters/`) and the
> authoritative serializable `CharacterState` (domain, `src/domain/character/`). The **Player
> is bound to ONE `CharacterState`** that `WorldRuntime` owns for the session and does NOT
> recreate on a map swap; `StatsComponent` reads it and `HealthComponent` syncs HP/life-state
> back. `CharacterState` carries no presentation data (the sprite comes from the separate
> `CharacterVisualProfileData` pipeline, D-026).
>
> **Sect fields are a DERIVED CACHE (D-015).** `CharacterState.sect_id`/`sect_rank` are
> written by `SectService` on join/leave/rank and rebuilt from the roster by
> `sync_character_cache()`. The **sect ROSTER is the authority**: on any disagreement the
> roster wins, and nothing outside the sect domain may set these two fields.
>
> **The character registry EXISTS (Phase 08, D-048).** `CharacterRegistry`
> (`src/domain/character/character_registry.gd`) is the session's `instance_id -> CharacterState`
> collection, owned by `WorldRuntime`, and the single source of the
> `(StringName) -> CharacterState` resolver that `SectService`, `FactionService` and
> `WorldSimulationService` all take. It owns only "who exists" — it has no rules and emits no
> signals — and it refuses to REPLACE a live `CharacterState`, because two live answers to "who
> is this character" is the defect it exists to prevent. It maps directly onto
> `docs/SAVE_FORMAT.md`'s `characters.by_instance_id`.
>
> **`sim_state` is LIVE and owned by the world simulation (Phase 08).** §5's `schedule_ref` +
> `sim_state` fields now carry real meaning: `sim_state` is a DERIVED CACHE of the simulation's
> own `WorldSimActor` record (band + activity + location), in exactly the relationship
> `sect_id` has with the sect roster (D-015) — the record wins, and drift is reported by
> `WorldSimulationService.verify_character_caches()` rather than trusted.
>
> **NPC presentation is LIVE (Phase 17, D-065).** A `WorldNpc` is the BODY of a registry
> `CharacterState` in a map (bound by `NpcRuntime`); Kha Thản stands at the edge of Rừng Vỡ
> Mạch, turns to the player, gestures (`ACTION_TALK`) and trades. An NPC has no state class of
> its own.
>
> **What is still design only:** NPC authoring at scale, goals/secrets-driven behaviour, bodies
> that follow the simulation's schedule between maps, and what people SAY — dialogue is
> Phase 18 (ownership boundary: D-066). `CharacterState.story_flags` is a stored CONTRACT field
> no system writes; the story engine (Phase 20) is its only future writer.

## 1. Why Character is core

Aetheria is a living tu tiên world. Elders, disciples, rivals, sect leaders, and the
player are all **Characters** with identity, motivation, relationships, sect membership,
reputation, secrets, and a life state that can change even when off-screen (see
`docs/WORLD_SIMULATION.md`). Treating characters as core — not as props spawned by quests
— is what makes the world feel alive and keeps content extensible.

## 2. Hard boundaries (layering)

- **Authoritative character state lives in the domain layer**, as serializable data.
  Presentation (sprites, portraits, animation) **never owns** it — it only renders a view
  of it. This mirrors the UI/rules boundary in `.kiro/steering/03-architecture.md` and is
  the same discipline the future multiplayer authority needs (`docs/MULTIPLAYER_PLAN.md`).
- A Character does **not** contain save logic; it exposes `to_dict()`/`from_dict()` and
  `SaveService` orchestrates (`docs/SAVE_FORMAT.md`).
- Characters interact with other systems only through the **EventBus** and queryable
  services — never by reaching across the scene tree.

## 3. State model (three tiers — important for save + multiplayer)

Every Character's state is partitioned so persistence and (future) networking are clean:

| Tier | Meaning | Saved? | Example |
|---|---|---|---|
| **Persistent** | authoritative, survives save/load & time | Yes | identity, origin, cultivation, relationships, sect membership/rank, reputation, secrets discovered, alive/dead, story flags |
| **Runtime** | derived or session-scoped; can be recomputed | No (or cached) | current pathfinding target, active animation, aggro, cached stat totals |
| **Presentation** | pure view | No | sprite frame, portrait, floating labels |

This partition is referenced by `docs/MULTIPLAYER_PLAN.md` (what a server would own vs.
replicate vs. render locally) and by `docs/SAVE_FORMAT.md` (only persistent tier is
serialized).

## 4. Data-driven design (no hard-coded NPCs)

A character is **content**, authored as data, not a bespoke script per NPC:

- `CharacterTemplateData` (`char_*`) — the *definition* (archetype/spawn template):
  default identity fields, origin, profession, starting cultivation, base stats,
  personality defaults, default sect/faction, portrait/sprite refs (localization **keys**
  for all display text).
- `CharacterState` — the *runtime instance* of a character in a specific save: a unique
  `instance_id`, a reference to its template `id`, plus the mutable persistent tier
  (current cultivation, relationships, reputation, secrets, alive/dead, schedule state,
  story flags). This is what gets serialized.

Adding a new named NPC or a new generic archetype = author a new `CharacterTemplateData`
`.tres`; no engine change (extensibility invariant, `docs/GAME_FLOW.md`).

## 5. Character fields (the full set this system must support)

Grouped by concern. Display strings are localization **keys** (`07-localization.md`).

- **Identity:** `instance_id`, `template_id`, `name_key`, `title_key`, `gender`,
  `portrait_ref`, `sprite_set_ref`.
- **Origin:** `origin_key` (birthplace/background), `bloodline_key` (optional).
- **Age:** `age`, `age_category` (enum: CHILD/YOUTH/ADULT/ELDER/ANCIENT) — age can matter
  in a cultivation setting (lifespan extends with realm). Optional per template.
- **Profession:** `profession` (enum/StringName: CULTIVATOR, ALCHEMIST, BLACKSMITH,
  MERCHANT, FARMER, SCHOLAR, …) — drives schedule and services.
- **Cultivation:** `realm_id` (cảnh giới), `cultivation_progress`, `technique_ids`
  (công pháp) — reuses the progression + cultivation rules in `docs/DATA_SCHEMA.md`;
  Character does not reinvent that math.
- **Stats:** a `StatBlock` (shared shape from `DATA_SCHEMA.md`).
- **Personality:** `traits` (Array[StringName] from a trait vocabulary, e.g. `PROUD`,
  `LOYAL`, `GREEDY`, `CAUTIOUS`) — influences AI/dialogue selection, not hard-coded.
- **Motivation / Goals:** `motivation_key` (core drive) and `goals`
  (Array of structured goals: `{ kind, target_id, priority, state }`) — fuel for world
  simulation and quest hooks.
- **Relationships:** owned by the Relationship system (`docs/RELATIONSHIP_SYSTEM.md`);
  Character holds a reference/handle, not a duplicate store.
- **Sect membership & rank:** `sect_id`, `faction_id` (optional), `sect_rank`
  (StringName from the sect's rank ladder). **These are a derived read cache, NOT the
  authority** — the canonical membership is the `SectState` roster. See `docs/SECT_SYSTEM.md`
  and the authority contract in `docs/DECISIONS.md` **D-015**.
- **Reputation:** `reputation` (Dictionary `{ scope -> value }`, scope = sect / region /
  world) — how the world regards them.
- **Secrets:** `secrets` (Array of `{ secret_id, known_by: Array[instance_id] }`) —
  hidden facts (true identity, betrayal, hidden technique) that story/relationship logic
  can reveal.
- **Story state:** `story_flags` (Dictionary) local to this character.
- **Life state:** `life_state` (enum ALIVE / DEAD / MISSING / ASCENDED), `death_cause`
  (optional) — world simulation and story read/modify this.
- **Schedule / background state:** `schedule_ref` (a data-defined daily/weekly routine)
  and `sim_state` (where they are, what they're doing when off-screen) — see
  `docs/WORLD_SIMULATION.md`. This is how far-from-player characters "live" cheaply.

## 6. Composition at runtime (presentation/gameplay)

When a Character is on-screen, it is realized as an **Entity** (per
`docs/ARCHITECTURE.md` §3) composed of components that **read from** the authoritative
`CharacterState`:

```
CharacterEntity (CharacterBody2D)        # presentation/gameplay realization
├── bound to -> CharacterState (domain, authoritative)
├── StatsComponent        (reads StatBlock)
├── CultivationComponent  (reads realm/progress; rules in domain)
├── AIComponent           (reads personality/goals/schedule; tick-rate controlled)
├── RelationshipView      (queries Relationship service)
└── Sprite/AnimationComponent (presentation only)
```

Off-screen, there is **no entity** — only `CharacterState` plus abstract simulation
(`WORLD_SIMULATION.md`). On-screen realization is a view; destroying the entity never
destroys the character.

## 7. Events (EventBus)

Character emits/consumes domain events so other systems react without coupling:
- Emits: `character_spawned`, `character_despawned`, `character_died(instance_id)`,
  `character_realm_changed`, `character_reputation_changed`, `character_secret_revealed`.
- Consumes: relationship changes, sect events, world-simulation ticks.

Emitters never import listeners (`.kiro/steering/03-architecture.md`).

## 8. Serialization

Only the **persistent tier** (§3) is written, keyed by `instance_id`, into the save's
`characters` section (`docs/SAVE_FORMAT.md`). Runtime/presentation tiers are rebuilt on
load. Content references are template `id`s, so saves survive as long as those ids exist.

## 9. Testing (high-risk once implemented)

- Character state round-trips `to_dict`/`from_dict` (equal persistent state).
- A character authored purely as data spawns and realizes correctly.
- Life-state transitions (alive→dead) propagate via events and persist.
- No presentation field leaks into the persistent tier.
See `docs/TEST_PLAN.md`.

## 10. Implementation status (Phase 04, D-023)

Phase 04 implemented the **core character data + authoritative state + player binding**
slice of this contract:

- `CharacterTemplateData` (`src/data/characters/character_template_data.gd`) — the §4/§5
  data definition, with the player authored as `data/characters/player_default.tres`.
- `CharacterState` (`src/domain/character/character_state.gd`, `RefCounted`) — the §3
  authoritative, persistent-tier-only, serializable instance. Life-state (§5) implements
  ALIVE→DEAD (once, terminal); MISSING/ASCENDED and the cultivation/relationship/sect/world
  fields are stored as CONTRACT but carry no mechanics yet.
- Player binding (§6) — the Player node is a runtime VIEW bound to ONE `CharacterState`
  owned by `WorldRuntime`; `StatsComponent` reads the authoritative numbers, `HealthComponent`
  syncs HP/death back. Composition kept.

*(HISTORICAL — the Phase-04 list, kept because it shows what Phase 04 itself did not do.)*
Not implemented IN PHASE 04: the §7 EventBus character events, AI/schedule/world simulation,
relationships/sect/faction authority, spawning of non-player characters, dialogue, and save
orchestration.

**Since then:** relationships (Phase 05), sects (06), factions (07), the world simulation and
its cast (08), cultivation mechanics on the stored fields (12) and NPC bodies (17) are
IMPLEMENTED in their own documents. **Still not implemented:** the §7 EventBus character
events, dialogue (Phase 18), and save orchestration (`SaveService`, Phase 23 —
`CharacterState.to_dict/from_dict` is the ready seam).

## 11. Visual pipeline (Phase 05, D-026)

Phase 05 adds the presentation-side **character visual pipeline** (the domain tiers §3 are
unchanged — a `CharacterState` still carries NO sprite/presentation data):

- `CharacterVisualProfileData` (`src/data/characters/character_visual_profile_data.gd`, a
  `Resource`) — the §5 `sprite_set_ref` target: a sprite sheet GRID of one ROW per cardinal
  direction × N animation COLUMNS at a `32×48` baseline (D-046), plus `frame_size`,
  `frame_duration` and a feet anchor. The frame count is derived from the texture width, not
  authored. Authored per archetype under `data/characters/visual/*.tres`. Style rules:
  `docs/CHARACTER_ART_BIBLE.md`.
- `CharacterVisualComponent` (`src/presentation/characters/character_visual_component.gd`, a
  `Node2D`) — renders the profile and reacts to a facing/moving state pushed by the owner. It
  reads NO gameplay rules and never mutates `CharacterState`; `MovementComponent` stays the
  movement authority (the component only picks the direction frame).
- The Player resolves its bound template's `sprite_set_ref` into this component
  (`set_visual_profile_from_ref` → `_apply_visual_profile`), replacing the scene's static
  prototype sprite; a missing/invalid profile fails loud and keeps the static fallback.

The §6 realization diagram's "Sprite/AnimationComponent" is now concretely the
`CharacterVisualComponent`. Since Phase 05 the component gained an ACTION layer (attack,
slash, meditate, cast, talk — D-056/D-058/D-061/D-063/D-065) and the HUD shows the player's
pipeline portrait as a medallion (D-062). Still NOT implemented: layered/modular compositing,
and a portrait for anyone but the player and Lâm Nguyệt. Relationships (§5) are now a
real domain graph (`docs/RELATIONSHIP_SYSTEM.md` §11) that a Character references by
`instance_id`; Character still holds no relationship store of its own.
