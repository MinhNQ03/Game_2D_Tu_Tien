# GAME_FLOW — Aetheria

> **This is the central document of the project.** It describes the game flow from
> start to end and how each major system fits in. Every code change starts by reading
> this (see `.kiro/steering/08-ai-review-protocol.md`).
>
> **Status: through Phase 18 (Dialogue, D-066).** Phase state is owned by `docs/ROADMAP.md`;
> this block only says what the FLOW is today.
> Split three ways on purpose — the old block mixed them, which is how it came to say
> "combat exists only in the Phase-02 sandbox" three phases after combat went live. (It then
> drifted again: until D-066 it still read "through Phase 11" and called cultivation, items,
> equipment, skills and pets design-only, six phases after they shipped.)
>
> ---
>
> **① CURRENT — what actually runs today.**
> The runnable flow is START → MAIN MENU → NEW GAME → WORLD SESSION → HUB ↔ FIELD → MENU, plus
> **MAIN MENU → SETTINGS → MAIN MENU** (language vi/en, D-035). The start map is data-driven
> (`MapCatalog.start_map_id`) and the camera FOLLOWS the player across maps authored larger
> than the screen (D-036).
> - **COMBAT IS LIVE IN THE REAL APPLICATION** (Phase 09) — no longer sandbox-only. D-007 is
>   resolved as REAL-TIME TOP-DOWN ACTION: a `READY → WINDUP → ACTIVE → RECOVERY` lifecycle
>   with data-authored timing, analytic hit resolution against a session hurtbox registry, and
>   crits rolled from the seeded `STREAM_COMBAT`. The player attacks with the semantic `attack`
>   action, which the HUD now ADVERTISES as a control prompt (D-055-G).
> - **ENEMY AI IS LIVE** (Phase 10) — two **Vụ Lang** mist wolves authored into the field map
>   by a spawn table; a pure-domain `AiBrain` (IDLE/PATROL/ALERT/CHASE/ATTACK/RECOVER/RETURN)
>   returning intents, executed through the same movement/attack seams the player uses, with a
>   throttled tick and `enemy_ai`-stream determinism. They hunt, they hit back, they die.
> - **LEVEL / XP PROGRESSION IS LIVE** (Phase 11) — a kill pays XP, XP derives a level, and the
>   HUD shows both. See §3.8 for the exact chain and ownership.
> - **SECT MEMBERSHIP IS LIVE** — New Game enrols the player into the authored start sect
>   (Azure Cloud, at Outer Disciple) through `SectRuntime`; the HUD carries a localized sect
>   chip; `sect_panel` (`T`) toggles a Sect detail panel (name, doctrine, type/tier, rank,
>   reputation, influence, territory, a localized resource summary); the hub shows a sect
>   banner. **Faction politics** (Phase 07, D-042/D-047) is live behind `faction_panel` (`Y`).
>   None of it displays a raw id.
> - **THE WORLD EVOLVES OFF-SCREEN** (Phase 08) — Near/Mid/Far LOD simulation on explicit
>   gameplay beats, deterministic from seeded per-subsystem RNG streams.
> - The player is a real **Character** (one authoritative `CharacterState` bound to the Player
>   node, D-023) and the HUD shows identity + map name + localized control hints.
> - **CẢNH GIỚI / TU LUYỆN AND THE KNOWLEDGE CORE ARE LIVE** (Phase 12, D-058) — `cultivate`
>   seats the player (tọa thiền), a breakthrough is decided by `CultivationService`, and a stele
>   teaches through `KnowledgeService`, the one owner of what the player knows (§3.8).
> - **ITEMS, EQUIPMENT, TECHNIQUES AND SKILLS ARE LIVE** (Phases 13–15, D-059/D-060/D-061) — a
>   bag (`inventory`, a modal panel), slots that change real stats, and knowledge-gated công
>   pháp cast from the technique dock (`skill_1..4`) for linh khí.
> - **A LINH THÚ FOLLOWS AND FIGHTS** (Phase 16, D-064) — the stray Hoàng Khuyển in Lạc Hà can
>   be befriended; `pet_summon` calls and dismisses it; it fights on the player's team.
> - **PEOPLE STAND IN THE WORLD AND ONE OF THEM TRADES** (Phase 17, D-065) — Kha Thản's body at
>   the edge of Rừng Vỡ Mạch is his registry `CharacterState`; his shop (a modal panel) is paid
>   in the linh thạch in the bag and priced by his regard for the player.
> - **PEOPLE CAN BE TALKED TO** (Phase 18, D-066) — `interact` on Kha Thản or on Thẩm Bất Kỳ (in
>   Lạc Hà) opens an authored, branching conversation in a modal box. What a line offers
>   depends on what the player knows and how the speaker regards them; an answer may move that
>   regard (through `RelationshipService`), teach something (through the Knowledge Core) or
>   hand over to the speaker's shop. Dialogue owns no state of its own.
> - A failure of ANY per-session runtime ABORTS New Game and unwinds back to the menu
>   (D-037/D-047/D-054) rather than entering a half-wired world.
>
> **② FUTURE — design target, NOT implemented.**
> - **Quests (19), the story / chapter / flag engine (20), dungeons (21), bosses (22) and
>   file-level save (23) do not exist.** Nothing sets or reads a story flag: a conversation
>   branches on knowledge and regard only, and remembers nothing itself (D-066).
> - The branching-story / quest flow below is the design target for those phases. The
>   "PROLOGUE" box in §1 is a future story scene, **not** the current first gameplay scene — it
>   is specified beat-by-beat in `docs/NARRATIVE_MASTER_PLAN.md` §5 (D-039).
> - Crafting, professions, a regional market and the wider economy are design only
>   (`docs/ECONOMY_CRAFTING_DESIGN.md`); the one shop is the only trade that exists.
> - `dodge` has a keyboard binding and no consumer — **a binding is not a system**.
> - `MapData` has no `min_level` and never will (C-002). Level is not cultivation; see §3.8.
> - Everything beyond the CURRENT list is the intended flow plus the contracts implementation
>   must satisfy.
>
> **③ HISTORICAL — settled context, kept because it still explains decisions.**
> `main.tscn` is the **bootstrap** scene (`Main → Systems / World / UI`, script
> `src/bootstrap/main.gd`; D-010). Phase 05 (Relationship core + early character visual
> pipeline) is **CLOSED** (D-026); Phase 06 (Sect) is **CLOSED** (D-032, hardened in D-037).
> The live UI is the CC0 **Xianxia Pixel Pack** 9-slice set (D-028, superseding the self-made
> prototype of D-024) with graphic key badges — a tu-tiên game UI, not default Godot controls.
> The visible world + player art is at the **production-foundation** tier (D-029,
> presentation-only), and the player sprite is data-driven via `CharacterVisualProfileData` +
> `CharacterVisualComponent` (D-026), not a hard-coded sprite. The Phase-02 **Player Sandbox**
> still exists as a harness for isolated combat validation, but it is no longer the first scene
> and is not how combat reaches the player.
>
> **ONE status block only.** This is it. Per-system implementation status lives inside each
> §3.x contract, where it cannot be mistaken for the global state; phase state lives in
> `docs/ROADMAP.md` (`CONTRADICTION_REGISTER.md` C-006).
>
> **Design canon** (what the content flowing through these systems must be) is frozen by D-039:
> start at `docs/GAME_DESIGN_FREEZE.md`.

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
LEVEL UP  (XP / Level)  │   ← frequent, numerical, combat-derived   [LIVE, Phase 11]
  ↓                     │
CẢNH GIỚI / TU LUYỆN    │   ← rare, qualitative, unlocks capability [FUTURE, Phase 12]
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

> **The two progression boxes are two AXES, not two steps** (D-055-C). The diagram is vertical
> because it traces one playthrough, but levelling is not a prerequisite for a breakthrough and
> a breakthrough is not a reward for levelling. **LEVEL / XP ≠ CẢNH GIỚI / TU LUYỆN**: level is
> the frequent numerical axis that tunes power and **is never an access gate** (C-002); cảnh
> giới is the rare qualitative axis that gates content and capability, and a realm advance must
> answer "what can I do now that I could not before?" with something other than a bigger
> number. Collapsing them into one bar is forbidden by
> `docs/PROGRESSION_CULTIVATION_DESIGN.md` §1. Only the first axis exists today.

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
  `game_booted`, then shows the Main Menu shell. Language defaults to **`vi`** via
  `Localization` (vi/en available, D-035); if the player previously chose a language in
  Settings, `Main` applies that saved choice BEFORE any UI is built, so the first frame is
  already in the right language.
- **Output:** Main Menu scene active.
- **Dependencies:** infrastructure layer only.
- **Events:** `game_booted`.

### 3.2 MAIN MENU
- **Input:** player selection (New Game, Load Game, **Settings**, Quit). Settings is LIVE
  (D-035) and opens a language screen (vi/en) OVER the menu: the menu is hidden, not freed,
  and closing Settings reveals it again, so the lifecycle never leaves the `MENU` phase.
  Load Game stays disabled until SaveService (Phase 23).
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
- **Design (D-039):** the prologue's twelve beats, its causal chain (`ĐÊM VỠ MẠCH`), the five
  Origins and the five things the player must leave holding are specified in
  `docs/NARRATIVE_MASTER_PLAN.md` §4–§6. New Game also selects an `origin_id` (run-scoped data,
  not a character subclass).
- **Implementation status:** the PROLOGUE STORY above is the *design* target; the WORLD it
  would open into is live. Today New Game enters the **World/Map**: `WorldRuntime` (a node
  under `Main/Systems`) spawns one persistent Player — a real **Character** with an
  authoritative `CharacterState` (Phase 04) — and loads the **hub map** as the first scene; the
  player walks to a `MapExitZone` and presses the semantic `interact` action to move between
  the hub and a field map. What is live in that world: **combat** in the real application
  (Phase 09, D-007), **enemy AI** in the field (Phase 10 — two authored Vụ Lang that hunt, hit
  back and die), **level/XP progression** off those kills (Phase 11, §3.8), **cultivation and
  knowledge** (Phase 12), **items, equipment and techniques** (Phases 13–15), **a companion**
  (Phase 16), **one NPC who trades** (Phase 17) and **two who talk** (Phase 18).
  **Still future, and genuinely not implemented:** the prologue beats themselves, story flags
  and quests — nothing in the running game produces or consumes any of them, so
  this box stays a design box until the phases that own them land.
  *(Historical: the Phase-02 Player Sandbox is retained as an isolated combat harness; it is
  neither the first scene nor how combat reaches the player.)* Maps are data-driven (`MapData`
  + content scene registered by `scene_key`), so adding a map is data + content, not a core
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
- **Events — IMPLEMENTED (Phase 09/10/11), corrected in D-055-D.** Combat **ANNOUNCES**; it
  never pays and it does not know a level exists. The live contract is:

  | Owner | Emits | Listener |
  |---|---|---|
  | `HurtboxComponent` | `damaged(amount, is_critical)` | `DamageFeedback` (presentation) |
  | `Enemy` | `died()` | `CombatRuntime`, `DamageFeedback` |
  | `CombatRuntime` | `enemy_defeated(reward_id, xp_reward)` | **`ProgressionRuntime`** |
  | `CombatRuntime` | `combat_target_changed(view)` | `WorldRuntime` → HUD |
  | `ProgressionRuntime` | `xp_gained(amount, reward_id)` | `WorldRuntime` → HUD |
  | `ProgressionRuntime` | `level_changed(previous, current)` | `WorldRuntime` → HUD |

  **`xp_gained` is emitted by PROGRESSION, not by combat.** Earlier revisions of this section
  listed it under combat, which inverted the dependency: it would have made combat a writer of
  permanent progression state. `reward_id` is per **SPAWN** (`instance_id#serial`), which is
  what lets a re-cleared map pay again instead of the ledger degrading into a "has ever been
  killed" flag.
  The names `hit` and `combatant_died` were design sketches and have **no implementation** —
  the real surface is the table above.

### 3.8 LEVEL UP — two distinct axes (both LIVE: XP/Level since Phase 11, cảnh giới / tu luyện since Phase 12)
> **The LEVEL/XP half is IMPLEMENTED (Phase 11, D-054).** The live path is
> `enemy dies → CombatRuntime.enemy_defeated(reward_id, xp_reward) → ProgressionRuntime →
> ProgressionService.grant_xp() → CharacterState.xp → xp_gained / level_changed → WorldRuntime
> → MapBase → GameplayHUD`. Combat ANNOUNCES and does not pay; `ProgressionService` is the only
> writer of XP; **the level is DERIVED from cumulative XP and the authored curve, never stored**.
> The defeat event is `CombatRuntime.enemy_defeated`, not an EventBus `enemy_died` (§3.7 holds
> the full table since D-055-D). The **cảnh giới / tu luyện** half is IMPLEMENTED too (Phase 12,
> D-058): `CultivationRuntime` + `CultivationService` own it, and it did not reimplement,
> duplicate or replace the XP/Level axis (the D-055 handoff contract).
>
> **OWNERSHIP, in one table, because this is where the next phase will look:**
>
> | | AXIS 1 — Level / XP (LIVE) | AXIS 2 — Cảnh giới / tu luyện (LIVE, Phase 12) |
> |---|---|---|
> | Stored state | `CharacterState.xp` — cumulative, the ONLY stored number | `CharacterState.realm_id` + `cultivation_progress` |
> | Derived | **level** = f(xp, curve); never stored | — |
> | Authority | `ProgressionService.grant_xp()` | `CultivationService` (through `CultivationRuntime`) |
> | Content | `ProgressionCurveData` (`.tres`) | realm defs, breakthrough rules |
> | What it does | tunes POWER, frequently | unlocks CAPABILITY and CONTENT, rarely |
> | Gates content? | **NEVER** (C-002) | yes, that is its purpose |
>
- **Input:** `enemy_defeated`; the `cultivate` action and breakthrough attempts (both live).
- **State:** XP (persistent) → level (DERIVED); current cảnh giới + cultivation progress;
  learned công pháp. Two distinct axes that must not be
  collapsed (see `.kiro/steering/02-game-design.md`).
- **Processing:** apply the authored XP curve → level ups (fine power); accumulate
  cultivation → breakthrough rules gate realm advances (content/capability unlocks). All in
  domain, pure and testable.
- **Design (D-039/D-040):** the frozen realm hierarchy is `docs/PROGRESSION_CULTIVATION_DESIGN.md`
  §2 (CL-02), and **level is never an access gate** (C-002). Phase 12 also landed the
  **Knowledge Core** (`KnowledgeStore`/`KnowledgeService`, its own owner, no autoload) because
  cultivation breakthroughs and techniques READ knowledge — Dialogue/Quest/Story *produce* it
  later but never own it (§7a, C-012, D-066).
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
- **Config / RNG** — tunables and *seeded* randomness. The deterministic RNG seam is
  **stream-scoped** (one run/world seed → per-subsystem streams) and is **introduced in Phase 08
  with World Simulation**, the first genuine consumer; Combat (09) reuses it rather than adding a
  second source (D-040 / C-010, `docs/SYSTEM_DEPENDENCY_MATRIX.md` §4c). No domain code calls a
  global `rand*()`.

## 5. Where multiplayer plugs in later (no code now)

The seams already named above — **combat command** (intent), **player state**,
**world state**, **inventory**, **progression**, **persistence**, **authoritative
state**, plus the core social/world state (**character**, **relationship**, **sect**,
**faction**, **world-event/sim**) — are kept serializable and presentation-free, split
into persistent/runtime/presentation tiers, so Stage 2 can add authority and replication
with minimal changes to these systems (a design goal, not a guarantee). Detail in
`docs/MULTIPLAYER_PLAN.md`.

## 6. Open design questions

Tracked in `docs/DECISIONS.md`. Notably: scene-instanced vs. single-scene map streaming;
final save file format (D-005). These are **not** decided here and must be resolved before
the relevant system is built.

**Resolved since this section was written:** real-time vs. turn-based combat resolution
(D-007) is **Accepted as real-time top-down action combat** (Phase 09).

The *content* design questions that used to sit here — what the world is, what the realms are,
what the prologue is, how access is gated — were closed by the **Master Game Design Freeze**
(D-039). Eleven contradictions found during that audit, with their resolutions and owners, are in
`docs/CONTRADICTION_REGISTER.md`. Two of them concern this flow directly: C-006 (this file used to
carry two status blocks) and C-007 (the PROLOGUE box was named here but defined nowhere).

## Phase 05 note (D-026) — relationship substrate + character visuals, flow unchanged

The runnable flow is UNCHANGED (START → MAIN MENU → NEW GAME → WORLD SESSION → HUB ↔ FIELD →
MENU). Phase 05 adds, underneath that flow:
- a **relationship graph** owned by a new `RelationshipRuntime` under `Main/Systems` (a
  sibling of `WorldRuntime`, not an autoload) that starts with New Game, survives map swaps,
  and ends on return to menu — it has no gameplay surface yet (no NPC/dialogue/quest produces
  real events in-game), it is the substrate those later systems will drive;
- a **data-driven character sprite** on the Player (resolved from its template
  `sprite_set_ref` via `CharacterVisualProfileData` + `CharacterVisualComponent`) replacing the
  hard-coded prototype sprite.
A dev-only `character_preview` scene showcases the four archetypes; it is NOT the first scene
and nothing in the flow loads it. No new first scene, no new autoload.

## Phase 06 note (D-032) — Sect substrate + sect UI, flow unchanged

The runnable flow is UNCHANGED (START → MAIN MENU → NEW GAME → WORLD SESSION → HUB ↔ FIELD →
MENU). Phase 06 adds, underneath + on top of that flow:
- a **sect domain** owned by a new `SectRuntime` under `Main/Systems` (sibling of
  `WorldRuntime`/`RelationshipRuntime`, not an autoload) that starts with New Game, enrolls the
  player into the authored start sect (**roster is authoritative**, D-015), survives map swaps,
  and ends on return to menu;
- declared sect **alliances/enemies mirrored** into the one relationship graph (transactional);
- a **visible sect UI**: a HUD sect chip (emblem + name + rank + reputation), a toggleable
  `SectPanel` opened via the semantic `sect_panel` action, and a sect banner in the hub — all
  localized (vi + en), no raw ids, in the live Xianxia UI.

No new first scene, no new autoload. Faction/internal-politics (SECT_SYSTEM §7) is Phase 07.

## Phase 07 note (D-042, hardened D-047) — internal politics substrate, flow unchanged

The runnable flow is UNCHANGED (START → MAIN MENU → NEW GAME → WORLD SESSION → HUB ↔ FIELD →
MENU). Phase 07 adds, underneath + on top of it:
- a **faction domain** owned by a new `FactionRuntime` under `Main/Systems` (sibling of the
  other three, not an autoload) that starts LAST with New Game — it reads the sect store and
  the relationship graph — survives map swaps, and ends FIRST on the way out;
- a toggleable `FactionPanel` on the semantic `faction_panel` action, rendering a read-only
  `SectPoliticsView` (localized vi + en, no raw ids);
- **Phase 07 enrols nobody** (the C-003 guard): taking a side is a gameplay act from P-17
  onward, so the player leaves the menu with no political identity.

**What SESSION END actually does (D-047).** Both ways out of a session — a failed New Game and
a normal return to menu — run the SAME ordered teardown in `Main`, the exact reverse of the
start order:

```
FactionRuntime -> SectRuntime -> RelationshipRuntime -> WorldRuntime -> GameState -> MAIN MENU
```

Each subsystem's state is defined in terms of the ones ended after it, so this direction is a
correctness requirement, not a preference (the rule and the defect it fixed: D-047 / L-030).
No new first scene, no new autoload. World Simulation (`WORLD_SIMULATION.md`) is Phase 08.

## Phase 06 follow-up note (D-033…D-036) — one new flow branch, two in-map fixes

The gameplay flow is UNCHANGED (START → MAIN MENU → NEW GAME → WORLD SESSION → HUB ↔ FIELD →
MENU). What changed around it:

- **A new menu branch: MAIN MENU → SETTINGS → MAIN MENU** (D-035). Settings is UI under
  `Main/UI`, NOT a routed scene — `SceneRouter` owns the content scene under `Main/World`
  (the map), while menus/overlays are UI. Opening it HIDES the menu rather than freeing it,
  so no `enter_menu` transition is re-requested and the lifecycle stays in `MENU`. It offers
  one setting today (language vi/en), built from `Localization.available_languages()`; the
  choice is written to `user://settings.cfg` and re-applied by `Main` at the next boot.
  **Vietnamese is now the default** (per-phase beta builds are play-tested in Vietnamese).
- **The in-map camera FOLLOWS the player** (D-036). Previously every map's `Camera2D` was a
  static child parked at the map centre and nothing moved it — which looked correct only
  while the whole map fitted on screen. `MapBase` now tracks the player each physics frame
  (eased by `position_smoothing`), still clamped by the camera limits derived from
  `MapData.bounds`, so following can never reveal anything past the map edge.
- **The hub/field maps are authored 960×576** instead of 448×288, so the view fits inside the
  map and the camera has room to travel on both axes at a comfortable zoom. Open ground for
  now — that space is deliberate room for the NPC/encounter content of later phases.
- **The HUD is legible** (D-034): text sits on the dark ink plate (the jade plate measured
  near-white behind a light-only text palette), key prompts are solid chips, labels carry a
  dark outline, and the Sect panel opens INSIDE the screen when `T` is pressed (it was
  anchored off-screen, which read as "the key does nothing").

## Phase 16 note (D-064) — the linh thú, one new in-map branch

```
hub map: walk within reach of the stray (PetEncounter, a WorldInteractable)
   └─ HUD interact prompt: "Befriend"
        └─ interact → MapBase.interactable_used(kind, id) → WorldRuntime routes by kind
             └─ PetRuntime.befriend → PetService.acquire + activate → the pet appears beside
                the player; the stray is hidden from then on

anywhere in gameplay context: pet_summon (G)
   ├─ pet away  → appears beside the player (first free spot) | refusal answered on the HUD
   └─ pet out   → dismissed (body freed)

while out: follows its owner (walks, never teleports) · attacks the nearest living hostile
           near its owner through CombatService · earns its share of each defeat once
map change: body freed before the old map goes, re-summoned beside the player on arrival
pet falls:  withdraws, can be called again after recall_seconds
owner falls / return to menu: body freed; PetRuntime is the first session ended
```
No new game phase, no new screen, no modal context.

## Phase 17 note (D-065) — people and shops, one modal branch

```
field map: walk within reach of Kha Thản (WorldNpc, bound to his CharacterState)
   └─ HUD interact prompt names him: "Gặp Kha Thản"
        └─ interact → MapBase.interactable_used(&"npc", id) → WorldRuntime → NpcRuntime.interact
             ├─ range re-validated; he turns and gestures (ACTION_TALK)
             ├─ keeps no shop → a HUD line; nothing else
             └─ keeps a shop  → ShopView(open) → HUD shows ShopPanel, input context UI_MODAL
                    ├─ move_up / move_down: choose a row    move_left / move_right: Buy / Sell
                    ├─ interact: request ONE → NpcRuntime.buy / sell
                    │     plan (no mutation) → InventoryRuntime.exchange (all-or-nothing)
                    │     → stock committed → new view + HUD result  |  refusal: reason, no change
                    └─ Esc: request close → NpcRuntime.close_shop → ShopView(closed)
                          → panel hidden, context popped, gameplay input restored
a fight starting or a map change closes the shop the same way
```
No new game phase. Esc with a shop open never returns to the menu.
*(Since Phase 18 this direct path is what someone with NO authored conversation does. Kha Thản
has one, so his shop is reached through its "Trade" answer — next note.)*

## Phase 18 note (D-066) — conversations, one more modal branch

```
walk within reach of a person (WorldNpc) → HUD prompt names them
   └─ interact → MapBase.interactable_used(&"npc", id) → WorldRuntime → DialogueRuntime.talk
        ├─ nobody authored for them → NpcRuntime.interact (the Phase-17 path above, unchanged)
        └─ NpcRuntime.engage: in this map, bound, in reach? they turn to the player
             └─ DialogueView(open) → HUD shows DialoguePanel, input context UI_MODAL
                  the prompt strip and technique dock stand down; the announcement band
                  rides above the box; the player turns to the speaker
                  ├─ a line with no answers:  interact → continue (or end)
                  ├─ a line with answers:     move_up / move_down choose, interact says it
                  │     DialogueRuntime.choose(node, choice)
                  │       → range asked of NpcRuntime again; conditions asked again
                  │       → ONE effect, in its owner:
                  │            regard     RelationshipService.apply_delta (edge made if absent)
                  │            knowledge  KnowledgeRuntime.grant → knowledge_gained (announced)
                  │            trade      conversation CLOSES, then NpcRuntime.open_shop_of
                  │       → next line  |  refusal: a reason in the band, nothing changed
                  └─ Esc → DialogueRuntime.leave → DialogueView(closed)
                        → box hidden, context popped, strip and dock back, gameplay input restored
a fight starting, a map change or the session ending closes the conversation the same way
```
No new game phase. Esc with a conversation open never returns to the menu. The key press that
opens a conversation, or that leads to a new line, never also answers that line.
