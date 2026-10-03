# GAME_FLOW — Aetheria

> **This is the central document of the project.** It describes the game flow from
> start to end and how each major system fits in. Every code change starts by reading
> this (see `.kiro/steering/08-ai-review-protocol.md`).
>
> Status (as of Phase 04): the player is now a real **Character** (one authoritative
> `CharacterState` bound to the Player node, D-023), the in-map **HUD** shows the character's
> identity + map name + localized control hints, and the main menu has a presentation pass.
> UI hardening (D-024) dressed the menu + HUD in REAL pixel-art 9-slice panels/buttons with
> graphic key badges ([E]/[Esc]) — a game UI, not default Godot controls.
> The runnable flow is unchanged (START → MAIN MENU → NEW GAME → WORLD SESSION → HUB ↔ FIELD);
> the start map is now data-driven (`MapCatalog.start_map_id`). Below:
>
> Status (as of Phase 03): **early gameplay implemented.** `main.tscn` is the **bootstrap**
> scene (`Main → Systems / World / UI`, script `src/bootstrap/main.gd`; D-010). The CURRENT
> runnable flow is: START → MAIN MENU → NEW GAME → WORLD SESSION (`WorldRuntime`) → **HUB
> MAP** → the player moves (semantic input) and uses map exits to travel **HUB ↔ FIELD**,
> then `open_menu` returns to the menu. Combat exists only in the Phase-02 player sandbox
> (not reachable from New Game now). The branching-story / dialogue / quest / NPC flow below
> is still the *design target* for later phases; the "Prologue" box in §3 is a future story
> scene, NOT the current first gameplay scene. Everything beyond world/map traversal remains
> the intended flow + the contracts implementation must satisfy.

## 1. High-level flow

```
START
  ↓
MAIN MENU
  ↓
NEW GAME ─────────────► (or LOAD GAME → resume at saved state)
  ↓
PROLOGUE
  ↓
VILLAGE  ◄──────────────┐
  ↓                     │
QUEST                   │
  ↓                     │
FOREST (map)            │
  ↓                     │
COMBAT                  │
  ↓                     │
LEVEL UP  (XP, cảnh giới / tu luyện)
  ↓                     │
DUNGEON                 │
  ↓                     │
BOSS                    │
  ↓                     │
STORY (branching)       │
  ↓                     │
CHAPTER PROGRESSION ────┘  (loop into next chapter's village/maps)
  ↓
SAVE   (can occur at many points, not only here)
  ↓
END GAME
```

The vertical line is the **player's first-playthrough path**. The loop-back arrow is
the key architectural truth: after a chapter, the game returns to the explore → quest →
combat → progress loop with *new content*, not new systems. SAVE is drawn once for
clarity but is a cross-cutting capability available throughout.

## 1b. World & social flow (Character / Sect are CORE, not quest decoration)

The play path above sits on top of a living world. Characters, relationships, sects, and
their politics are **core systems** (D-011), simulated and persistent — not NPCs spawned
by a quest. The world/social dependency flow:

```
PLAYER                      (a Character; the authoritative actor)
  ↓
WORLD                       (maps + world simulation; LOD by distance)
  ↓
CHARACTERS                  (NPCs = data-driven Characters, authoritative domain state)
  ↓
RELATIONSHIPS               (affinity/trust/respect/fear/rivalry/debt graph)
  ↓
SECT                        (membership, rank, resources, territory, reputation)
  ↓
FACTION / POLITICS          (internal factions, influence, attitudes, intrigue)
  ↓
QUEST                       (objectives arise from characters/sects/politics)
  ↓
STORY                       (branches read character/sect/faction + flags)
  ↓
WORLD STATE CHANGE          (outcomes mutate characters/sects/world → feeds back up)
```

The bottom arrow feeds back to the top: story/quest outcomes change world, character, and
sect state, which the world simulation carries forward (even off-screen), which produces
new situations. Quests and story **consume** these systems; they do not **own** the
characters/sects. Full contracts: §3b below and the dedicated docs
(`CHARACTER_SYSTEM.md`, `RELATIONSHIP_SYSTEM.md`, `SECT_SYSTEM.md`, `WORLD_SIMULATION.md`).

## 2. Extensibility invariant (read this before anything else)

> Adding a **chapter / map / quest / enemy / boss / pet / skill / item / cultivation
> tier / dungeon / event / character / sect / faction / relationship** must be done by
> authoring **data (Resources) + content scenes**, routed through the existing systems
> below. It must **not** require rewriting any system in this document.

Each box in the flow is a *system* with a stable contract. Content flows *through* the
systems; the systems don't grow per content item. If a planned content addition can't
be expressed as data + a content scene, that's a design bug → `docs/DECISIONS.md`.

## 3. Systems — contracts

For every major system: **Input · State · Processing · Output · Dependencies ·
Events/Signals**. Layer names refer to `.kiro/steering/03-architecture.md`.

---

### 3.1 Boot / START  *(implemented in Phase 01)*
- **Input:** app launch → `src/bootstrap/main.gd` (the `Main` coordinator).
- **State:** `GameState` owns the lifecycle: `BOOT → INITIALIZING → READY → MENU`
  (then `STARTING_SESSION → RUNNING → TRANSITIONING/PAUSED`). Infrastructure autoloads that
  exist now (D-017): `EventBus`, `GameState`, `Localization`, `InputService`, `SceneRouter`.
  `Config`/`RNG`/`SaveService` are still *planned* (added when first needed).
- **Processing:** `Main._ready()` validates the shell, drives the lifecycle via `GameState`,
  gives `SceneRouter` its content host (`Main/World`) + registers Phase-1 scenes, emits
  `game_booted`, then shows the Main Menu shell. Language defaults to `en` via
  `Localization` (vi/en available).
- **Output:** Main Menu scene active.
- **Dependencies:** infrastructure layer only.
- **Events:** `game_booted`.

### 3.2 MAIN MENU
- **Input:** player selection (New Game, Load Game, Language, Quit).
- **State:** menu selection; list of existing save slots (from SaveService).
- **Processing:** on New Game → initialize a fresh run; on Load → ask SaveService to
  load a slot and hydrate GameState.
- **Output:** transition to Prologue (new) or to saved scene/state (load).
- **Dependencies:** presentation (UI) → gameplay (new-run init) → persistence (load),
  infrastructure (Localization, SceneRouter).
- **Events:** `new_game_requested`, `load_game_requested(slot)`, `language_changed`.

### 3.3 NEW GAME → PROLOGUE
- **Input:** `new_game_requested`.
- **State:** fresh GameState — chapter = prologue, empty inventory, base stats, level 1,
  starting cảnh giới, empty quest log, story flags cleared.
- **Processing:** create the run from starting data (a `NewGameConfig` Resource), load
  the Prologue scene via SceneRouter, play intro story beats.
- **Output:** player in the Prologue; first dialogue/tutorial beats.
- **Dependencies:** gameplay, domain (initial progression), data (starting config),
  infrastructure.
- **Events:** `run_started`, `chapter_entered(chapter_id)`, `story_beat(id)`.
- **Implementation status (as of Phase 03):** this box is the *design* target. Today New
  Game enters the **World/Map**: `WorldRuntime` (a node under `Main/Systems`) spawns one
  persistent Player and loads the **hub map** as the first scene; the player walks to a
  `MapExitZone` and presses the semantic `interact` action to move between the hub and a
  field map (traversal only — no story, NPCs, or combat yet). Phase 04+ (Character /
  Dialogue / Story) fill in this Prologue box; the Phase-02 Player Sandbox is retained for
  combat validation but is no longer the first scene. Maps are data-driven (`MapData` +
  content scene registered by `scene_key`), so adding a map is data + content, not a core
  edit (D-003 resolved / D-021).

### 3.4 VILLAGE (hub map)
- **Input:** player movement/interaction; arrival from SceneRouter.
- **State:** current map id, player position, active NPCs, available quests, shop state.
- **Processing:** top-down movement; interact with NPCs (dialogue), quest givers, shops.
  Village is a *map* like any other — just authored as hub content.
- **Output:** quests accepted, items traded, dialogue advanced, exits to other maps.
- **Dependencies:** presentation (map scene, UI), gameplay (map/NPC coordination),
  domain (quest/inventory rules), data (map, NPC, dialogue, quest resources).
- **Events:** `map_entered(map_id)`, `npc_interacted(npc_id)`, `quest_offered(quest_id)`.

### 3.5 QUEST
- **Input:** `quest_offered` / accept; world events that satisfy objectives.
- **State:** quest log — each quest has a state machine
  (`AVAILABLE → ACTIVE → COMPLETED → TURNED_IN`, plus `FAILED` where relevant) and
  objective progress. All serializable.
- **Processing:** domain quest engine listens to gameplay events (enemy killed, item
  collected, location reached, dialogue chosen) and advances objectives; grants rewards
  on turn-in.
- **Output:** updated objectives, rewards (XP, items, story flags), unlocked content.
- **Dependencies:** domain (quest engine) ← reacts to events from combat/world; data
  (quest definitions store localization keys + objective + reward data).
- **Events (listens):** `enemy_died`, `item_collected`, `map_entered`, `dialogue_chosen`.
  **(emits):** `quest_state_changed(quest_id, state)`, `reward_granted`.

### 3.6 FOREST / maps (field maps)
- **Input:** map transition request (from an exit, quest, or router).
- **State:** current map id, spawned entities, player position, encounter state.
- **Processing:** load map scene, spawn enemies/items from the map's data, run top-down
  exploration; map transition unloads previous map cleanly.
- **Output:** encounters, loot, exits to further maps/dungeons.
- **Dependencies:** gameplay (spawning, map lifecycle), presentation (tilemap scene),
  data (map resource: tileset ref, spawn tables, exits), infrastructure (SceneRouter).
- **Events:** `map_entered`, `map_exited`, `encounter_started`.
- **Map-transition safety** is a high-risk area (see `docs/TEST_PLAN.md`): no leaked
  nodes, no dangling signals, state carried via GameState not via the old scene.

### 3.7 COMBAT
- **Input:** combat command (attack / cast skill / use item), target(s). In Stage 2 this
  "combat command" is the multiplayer seam — keep it an explicit, serializable intent.
- **State:** combatant stats (HP, Linh khí/mana, buffs/debuffs), cooldowns, aggro.
- **Processing:** resolve a hit through the **single documented damage formula**
  (`docs/DATA_SCHEMA.md`) using attacker stats + công pháp modifiers + skill def +
  equipment modifiers + target resist. Deterministic given a seeded RNG.
- **Output:** damage applied, effects applied, deaths, loot/XP triggers.
- **Dependencies:** domain (damage rules, pure/testable) ← gameplay orchestrates;
  data (skill/equipment/enemy resources). Combat does **not** know about UI, quests, or
  save — it only emits.
- **Events (emits):** `hit`, `damaged(target, amount)`, `enemy_died(enemy_id)`,
  `xp_gained(amount)`, `combatant_died`.

### 3.8 LEVEL UP (progression: XP, level, cảnh giới, tu luyện)
- **Input:** `xp_gained`, `tu_luyện` actions, breakthrough attempts.
- **State:** XP, level, current cảnh giới + cultivation progress, unlocked skills/công
  pháp slots. Two distinct axes (see `.kiro/steering/02-game-design.md`).
- **Processing:** apply XP curve → level ups (fine power); accumulate cultivation →
  breakthrough rules gate realm advances (content/capability unlocks). All in domain,
  pure and testable.
- **Output:** new stats, newly unlocked skills/zones/công pháp, breakthrough events.
- **Dependencies:** domain (XP curve, breakthrough rules), data (curves/realm defs),
  reacts to combat events.
- **Events:** `level_changed`, `realm_changed`, `skill_unlocked`, `stat_changed`.

### 3.9 DUNGEON
- **Input:** enter dungeon (from map/quest).
- **State:** dungeon instance (rooms, encounters, modifiers), run progress.
- **Processing:** a dungeon is authored content (a specialized map/sequence) running on
  the same map + combat + loot systems, optionally with instance-scoped modifiers.
- **Output:** rewards, boss gate, exit back to field/hub.
- **Dependencies:** gameplay (map/combat orchestration), data (dungeon resource).
- **Events:** `dungeon_entered`, `dungeon_cleared`.

### 3.10 BOSS
- **Input:** reach boss trigger.
- **State:** boss combatant (richer stat/skill set, phases), arena state.
- **Processing:** combat system drives it; boss behavior/phases are data + an AI
  component — a boss is "a strong enemy with phase data", not a new combat system.
- **Output:** on defeat → major rewards, story flags, chapter gate.
- **Dependencies:** combat (domain/gameplay), data (boss resource, phase/skill data).
- **Events:** `boss_engaged(boss_id)`, `boss_phase_changed`, `boss_defeated(boss_id)`.

### 3.11 STORY (branching)
- **Input:** story flags, completed quests, player choices, `boss_defeated`, etc.
- **State:** chapter id, story flags, choices made, branch taken — explicit data.
- **Processing:** domain story engine evaluates flag/branch conditions to decide next
  beat/branch. Branches are data-driven; no scattered booleans across unrelated nodes.
- **Output:** next story beat, branch selection, chapter transition triggers.
- **Dependencies:** domain (story/flag engine), data (story/dialogue resources with
  localization keys), infrastructure (SceneRouter for scene changes).
- **Events:** `story_beat`, `branch_taken(branch_id)`, `flag_set(flag)`.

### 3.12 CHAPTER PROGRESSION
- **Input:** chapter completion conditions met (`boss_defeated` + required flags).
- **State:** completed chapters, current chapter, unlocked chapters/maps.
- **Processing:** advance to next chapter → load its hub/maps and new content; loops
  back into VILLAGE/QUEST/FOREST with new data. Adding a chapter = new data + scenes.
- **Output:** new chapter active; new maps/quests/enemies/bosses available.
- **Dependencies:** story + SceneRouter + data; no system rewrite.
- **Events:** `chapter_completed(chapter_id)`, `chapter_entered(next_id)`.

### 3.13 SAVE (cross-cutting)
- **Input:** save request (auto at checkpoints, manual, on quit).
- **State:** a serializable snapshot — player state, inventory, progression (level + XP +
  cảnh giới), quest log, story flags, current map/position, pet state, equipment.
  Includes `save_version`.
- **Processing:** SaveService collects each system's serializable state (each system
  owns its own `to_dict`/`from_dict`; SaveService orchestrates, enemies/UI do not touch
  save). Versioned + migratable. See `docs/SAVE_FORMAT.md`.
- **Output:** persisted save slot; successful load reconstructs GameState.
- **Dependencies:** persistence (SaveService) ← reads from gameplay/domain state. No
  system except SaveService knows the on-disk format.
- **Events:** `save_requested`, `save_completed(slot)`, `load_completed(slot)`.

### 3.14 END GAME
- **Input:** final chapter/story terminal condition.
- **State:** ending reached / branch outcome, final save.
- **Processing:** play ending beats, record completion, offer continue/new game+ (future).
- **Output:** credits (with asset attributions), return to Main Menu.
- **Events:** `game_completed(ending_id)`.

## 3b. Core social / world systems — contracts

> These underpin §1b. They are domain-authoritative, data-driven, serializable, and
> simulated. Full design in the dedicated docs; contracts summarized here so they're part
> of the central flow, not an afterthought.

### 3b.1 CHARACTER (`docs/CHARACTER_SYSTEM.md`)
- **Input:** spawn/promotion requests (player enters region), events affecting a character,
  simulation ticks.
- **State:** authoritative `CharacterState` (persistent tier: identity, origin, age,
  profession, cultivation, stats, personality, motivation, goals, sect/rank, reputation,
  secrets, story flags, life-state, schedule/sim state). Runtime + presentation tiers are
  derived and not saved.
- **Processing:** near the player a `CharacterEntity` renders a *view* of the state; far
  away only abstract state advances (world sim). Domain owns the truth.
- **Output:** character behavior, state changes, events.
- **Dependencies:** domain (authoritative), data (`CharacterTemplateData`), infrastructure
  (EventBus, RNG), presentation (view only).
- **Events:** `character_spawned/despawned/died/realm_changed/reputation_changed/secret_revealed`.

### 3b.2 RELATIONSHIP (`docs/RELATIONSHIP_SYSTEM.md`)
- **Input:** domain events (combat, gifts, dialogue choices, betrayals, sect actions,
  sim ticks).
- **State:** one serializable graph of `RelationshipEdge`s with scalar dimensions
  (affinity/trust/respect/fear/rivalry/debt) + `relationship_type`. Covers Char↔Char,
  Player↔Char, Char↔Sect.
- **Processing:** event → documented dimension deltas via the Relationship service (single
  source of truth).
- **Output:** updated edges; relationships gate dialogue, prices, aid, hostility.
- **Dependencies:** domain store; reacts to EventBus.
- **Events:** `relationship_changed(edge_id, dimension, old, new)`.

### 3b.3 SECT (`docs/SECT_SYSTEM.md`)
- **Input:** membership/rank changes, resource/territory changes, alliance/war, sim ticks.
- **State:** serializable `SectState` (leader, elders, disciples, ranks, resources,
  territory, reputation, influence, alliances/enemies, techniques, rules, secrets, story
  flags) incl. internal `FactionState`s.
- **Processing:** domain rules over data; membership kept in sync with `CharacterState`
  via events; alliances mirrored as Sect↔Sect relationship edges.
- **Output:** sect-level behavior, services, gating, events.
- **Dependencies:** domain; data (`SectTemplateData`); Relationship store; EventBus.
- **Events:** `sect_leader_changed/rank_changed/resource_changed/alliance_changed/war_declared/event_triggered`.

### 3b.4 FACTION / POLITICS (`docs/SECT_SYSTEM.md` §7)
- **Input:** faction goals, influence/attitude shifts, member relationships, sim ticks,
  story events.
- **State:** `FactionState` per internal faction (leader, members, goals, influence,
  resources, stance, attitude toward player, attitudes toward other factions).
- **Processing:** emergent politics (succession, schism, purge, coup) resolved as rules
  over data on sim ticks — never scattered booleans.
- **Output:** political outcomes that change sect/character/world state.
- **Dependencies:** Sect + Relationship + World Simulation.
- **Events:** `faction_shift`, plus the sect events it triggers.

### 3b.5 WORLD SIMULATION (`docs/WORLD_SIMULATION.md`)
- **Input:** world clock ticks, schedules, events; player region changes (promotion/demotion).
- **State:** world clock, each actor's `sim_state`, pending transitions, seeded RNG — all
  persistent.
- **Processing:** LOD — Near = real-time entities; Far = abstract state advanced on ticks
  (no nodes, no per-frame cost). Deterministic (seeded). Save-resumable with bounded
  catch-up.
- **Output:** an evolving world that feeds new situations back into quest/story (§1b loop).
- **Dependencies:** Character/Sect/Relationship state; infrastructure (clock, RNG, EventBus).
- **Events:** `world_tick`, `world_event_triggered`, `character_promoted/demoted`.
- **Performance:** governed by `.kiro/steering/05-performance-testing.md` — never full AI
  for hundreds of NPCs per frame.

## 4. Cross-cutting services (always available in the flow)

- **EventBus** — the backbone of the loose coupling above. Emitters never import
  listeners.
- **Localization** — every string shown in any box resolves through here (`vi`/`en`).
- **SceneRouter** — all map/scene transitions go through one place (testable, no leaks).
- **SaveService** — snapshot/restore across the flow.
- **Config / RNG** — tunables and *seeded* randomness (seeding makes combat testable and
  is a prerequisite for deterministic multiplayer later).

## 5. Where multiplayer plugs in later (no code now)

The seams already named above — **combat command** (intent), **player state**,
**world state**, **inventory**, **progression**, **persistence**, **authoritative
state**, plus the core social/world state (**character**, **relationship**, **sect**,
**faction**, **world-event/sim**) — are kept serializable and presentation-free, split
into persistent/runtime/presentation tiers, so Stage 2 can add authority and replication
with minimal changes to these systems (a design goal, not a guarantee). Detail in
`docs/MULTIPLAYER_PLAN.md`.

## 6. Open design questions

Tracked in `docs/DECISIONS.md`. Notably: real-time vs. turn-based combat resolution;
scene-instanced vs. single-scene map streaming; final save file format. These are
**not** decided here and must be resolved before the relevant system is built.
