# GAME_FLOW — Aetheria

> **This is the central document of the project.** It describes the game flow from
> start to end and how each major system fits in. Every code change starts by reading
> this (see `.kiro/steering/08-ai-review-protocol.md`).
>
> Status: **foundation / design only.** No gameplay is implemented yet
> (`main.tscn` is a single empty `Node2D`). Everything below is the intended flow and
> the system contracts that implementation must satisfy.

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

## 2. Extensibility invariant (read this before anything else)

> Adding a **chapter / map / quest / enemy / boss / pet / skill / item / cultivation
> tier / dungeon / event** must be done by authoring **data (Resources) + content
> scenes**, routed through the existing systems below. It must **not** require
> rewriting any system in this document.

Each box in the flow is a *system* with a stable contract. Content flows *through* the
systems; the systems don't grow per content item. If a planned content addition can't
be expressed as data + a content scene, that's a design bug → `docs/DECISIONS.md`.

## 3. Systems — contracts

For every major system: **Input · State · Processing · Output · Dependencies ·
Events/Signals**. Layer names refer to `.kiro/steering/03-architecture.md`.

---

### 3.1 Boot / START
- **Input:** app launch.
- **State:** none persistent; initializes infrastructure autoloads (Config, RNG,
  Localization, EventBus, SaveService, SceneRouter).
- **Processing:** load config, detect/apply language (`vi`/`en`), warm minimal
  services, then route to Main Menu.
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
state** — are kept serializable and presentation-free so Stage 2 can add authority and
replication without rewriting these systems. Detail in `docs/MULTIPLAYER_PLAN.md`.

## 6. Open design questions

Tracked in `docs/DECISIONS.md`. Notably: real-time vs. turn-based combat resolution;
scene-instanced vs. single-scene map streaming; final save file format. These are
**not** decided here and must be resolved before the relevant system is built.
