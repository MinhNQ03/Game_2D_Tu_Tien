# ARCHITECTURE — Aetheria

> Narrative design for the module architecture. The short, enforceable rulebook is
> `.kiro/steering/03-architecture.md`; this document explains the *why* and the shape.
>
> Status: **design doc.** Most of the structure below is the **TARGET** to grow into
> (clearly labelled), not an existing tree.
>
> **CURRENT STATE (through Phase 17, D-065):** Phase 05 (Relationship
> core + early character visual pipeline) is **CLOSED** (D-026) and Phase 06 (Sect) is
> **CLOSED** (D-032, hardened in D-037). Phase 07 (Faction/Politics) is **IMPLEMENTED**
> (D-042, hardened in D-047) — this block said "NOT STARTED" for five phases, which D-055
> corrected; it is the file `08-ai-review-protocol.md` tells every change to read FIRST, so a
> stale status here is the most expensive drift in the repo.
> Phase 08 (World Simulation + the deterministic RNG seam) is **IMPLEMENTED** (D-048),
> Phase 09 (real-time action Combat) is **IMPLEMENTED**, Phase 10 (Enemy AI) is
> **IMPLEMENTED** (D-052, reviewed in D-053), and Phase 11 (Level/XP Progression) is
> **IMPLEMENTED and CLOSED** (D-054, hardened in D-055).
> Phase 12 (Cultivation + Knowledge Core) is **IMPLEMENTED** (D-058), Phase 13 (Item) is
> **IMPLEMENTED** (D-059), Phase 14 (Equipment) is **IMPLEMENTED** (D-060) and Phase 15
> (Skill/Technique) is **IMPLEMENTED** (D-061), on the D-057B visual foundation (gait, anchors,
> causal strike, hit reaction, ambient motion). **Phase 16 (Pet) is DONE (D-064); Phase 17 (NPC / Shop) is DONE (D-065).**
> The per-session runtimes under `Main/Systems` now start in this order (and end in reverse):
> World → Relationship → Sect → Faction → WorldSimulation → Combat → Progression → Knowledge →
> Cultivation → Inventory → Equipment → Skill → Pet → Npc (`main.gd` `SESSION_START_ORDER`). Still five
> autoloads; no manager.
> D-062 locked the visual identity: the live UI is the ORIGINAL ink-lacquer kit, and every
> humanoid sheet, portrait, icon, world prop and map floor comes from ONE art pipeline
> (`tools/aetheria_art_pipeline/`, Blender as a BUILD tool — `docs/AETHERIA_ART_PIPELINE.md`).
> Runtime additions are data + presentation seams only (see the D-062 section below); no
> gameplay/domain rule changed and still five autoloads. The repo boots to a playable world/map
> slice where the player is a real Character, with a UI foundation:
> - Bootstrap scene `main.tscn` (root `Main`, script `src/bootstrap/main.gd`, children
>   `Systems`/`World`/`UI`); `Main` only coordinates boot and wiring.
> - 5 infrastructure autoloads (D-017): `EventBus`, `GameState` (lifecycle + session +
>   current location), `Localization` (vi/en), `InputService` (semantic intent + gating),
>   `SceneRouter` (single transition entry).
> - A localized main-menu shell (`src/presentation/menus/`). New Game starts a **world
>   session** via `WorldRuntime` (a gameplay NODE under `Main/Systems`, D-021/D-022).
> - **Player** (`src/gameplay/entities/player.*`): a composition `CharacterBody2D` with
>   Stats/Health/Movement components, moved via semantic input, rendered by a `Sprite2D`
>   (production-foundation character art, D-029; presentation-only). The data-driven
>   `CharacterVisualComponent` pipeline (D-026) resolves a `sprite_set_ref` → profile; the
>   authoritative `CharacterState` carries NO presentation data.
> - **Character core (Phase 04, D-023):** `CharacterTemplateData` (data, `src/data/characters/`)
>   + `CharacterState` (domain, `src/domain/character/`, authoritative + serializable). The
>   Player is a VIEW bound to ONE `CharacterState` that `WorldRuntime` owns for the session;
>   StatsComponent reads it, HealthComponent syncs HP/death back. Life-state ALIVE→DEAD.
> - **UI foundation (Phase 04, D-023 + D-024):** `src/presentation/ui/` (`UIPalette` tokens +
>   asset-backed `UITheme` builder + reusable `components/` `UIKeyBadge`/`UIPromptRow`), a
>   framed pixel-art main menu, and `src/presentation/hud/` (`GameplayHUD` showing character
>   identity + map name + graphic key-badge prompts). UI is 9-slice `StyleBoxTexture` from
>   the CC0 Xianxia Pixel Pack UI set (`assets/ui/xianxia/`, D-028; replaced the self-made
>   `mana_soul` prototype of D-024), not flat controls. `InputService`
>   exposes display labels so the UI never reads keycodes. The start map is data-driven
>   (`MapCatalog.start_map_id`).
> - **World/Map (Phase 03, D-022):** `MapData` + `MapExit` + `MapCatalog` data Resources
>   (`src/data/maps/`, authored in `data/maps/*.tres`) are the source of truth; `WorldRuntime`
>   loads the catalog, registers scenes with `SceneRouter`, owns ONE persistent per-session
>   Player, and runs transactional map transitions. Two map scenes (`hub_map`, `field_map`)
>   use `MapBase` + `MapExitZone` + a `TileMapLayer` tileset (production-foundation art, D-029)
>   plus presentation-only `Visual/Decor` garden props; walls are static collision; the camera
>   limits come from `MapData.bounds`.
> - **Relationship (Phase 05, D-026):** a serializable relationship graph owned by a
>   `RelationshipRuntime` node under `Main/Systems` (sibling of `WorldRuntime`, NOT an autoload)
>   that starts with New Game and survives map swaps. Domain-only (`src/domain/relationship/`),
>   single mutation path + domain `relationship_changed` signal.
> - **Sect (Phase 06, D-032):** a roster-authoritative sect domain (`src/domain/sect/`:
>   `SectState`/`SectStore`/`SectService`; data `src/data/sects/`) owned by a `SectRuntime` node
>   under `Main/Systems` (sibling, NOT an autoload) that enrolls the player into the authored
>   start sect and survives map swaps. Membership roster is the source of truth (D-015);
>   `CharacterState.sect_id`/`sect_rank` are a derived cache. Declared alliances/enemies mirror
>   (transactionally and NON-DESTRUCTIVELY — an edge is retyped in place, never removed and
>   recreated, D-037) to Sect↔Sect edges in the ONE relationship graph. A localized Sect HUD
>   chip + `SectPanel` + hub banner render a read-only `SectMembershipView` (presentation owns no
>   sect truth; resource ids render through `SECT_RESOURCE_*` keys, never as raw tokens).
>   SECT relationship endpoints are now backed by real `SectState`s. `SectRuntime.start_session()`
>   is FAIL-CLOSED (D-037): it commits nothing until every step succeeds, and New Game treats a
>   relationship or sect failure as fatal rather than running a half-wired session. **Every
>   teardown — a failed start AND a normal return to menu — runs through ONE ordered function in
>   `Main`, walking `SESSION_START_ORDER` backwards: Faction → Sect → Relationship → World →
>   GameState (D-047).**
> - **Faction / politics (Phase 07, D-042/D-047):** `src/domain/faction/` +
>   `src/data/factions/`, owned by a `FactionRuntime` sibling node. The SECT ROSTER remains the
>   membership authority (D-015) — a faction defers to it rather than keeping a second answer;
>   Faction↔Faction politics mirror transactionally into the ONE relationship graph, and a
>   mirror with no graph installed is a PRECONDITION failure, never a skipped write that still
>   returns success (L-030).
> - **World Simulation (Phase 08, D-048):** `src/domain/worldsim/` with Near/Mid/Far LOD from
>   the real `MapData.exits` graph, advanced on explicit gameplay beats by a
>   `WorldSimulationRuntime` sibling that creates **zero** child nodes and has no `_process`.
>   An actor's activity is DERIVED from `(tick − joined_tick, schedule)`, so a far-away actor is
>   never behind an observed one (L-032). It also introduced the **deterministic RNG seam**
>   (`RngService`, per-subsystem streams, D-040/C-010) that Phase 09 onward reuses, and
>   `CharacterRegistry`.
> - **Combat (Phase 09):** `src/domain/combat/` holds the node-free rules — a
>   `READY → WINDUP → ACTIVE → RECOVERY` machine with data-authored timing (`AttackData`) and
>   analytic hit resolution; `src/gameplay/components/` holds `AttackComponent`/
>   `HurtboxComponent` and `src/gameplay/combat_hurtbox_registry.gd` holds the node collection
>   (it lived under `domain/` until D-053 moved it — a "domain" class typed on a `Node` is an
>   upward dependency nothing in the toolchain flags, L-036). Crits roll from
>   `RngService.STREAM_COMBAT`. `CombatRuntime` is the sixth sibling.
> - **Enemy AI (Phase 10, D-052/D-053):** `src/domain/ai/ai_brain.gd` is a pure state machine
>   returning INTENTS, not vectors; `AIComponent` executes them through the same movement and
>   attack seams the player uses, on a throttled cadence, seeded from the `enemy_ai` stream.
>   `src/presentation/combat/damage_feedback.gd` owns the entity's whole `modulate` channel, so
>   no gameplay entity authors a colour (asserted by a structural walk of `src/gameplay`).
> - **Progression (Phase 11, D-054/D-055):** `CharacterState.xp` is the single stored
>   progression number; **the level is DERIVED** by `ProgressionService` (domain, `RefCounted`,
>   node-free) from the authored `ProgressionCurveData`. `ProgressionRuntime` is the **seventh**
>   sibling — registered LAST in `SESSION_START_ORDER` and therefore torn down FIRST — and holds
>   the per-spawn idempotency ledger. Combat ANNOUNCES (`enemy_defeated`) and never pays, so the
>   dependency runs progression → combat's signal and never the reverse. Two structural walks of
>   `src/` enforce the authority: only the storage boundary and the service may mutate XP, and
>   only the runtime may call `grant_xp` (D-055). **Level is never an access gate** (C-002).
> - Phase-02 Player Sandbox (`src/gameplay/sandbox/`) is retained as an isolated harness for
>   combat validation and is not reachable from New Game — but **combat itself has been live in
>   the real application since Phase 09**, so "the sandbox" is no longer where combat exists.
>   The `prologue_shell` is retained but no longer first.
> - Semantic InputMap in `project.godot`; translations in `locale/aetheria.csv`;
>   production-foundation pixel-art under `assets/` (self-made world/character, D-029) + the
>   CC0 Xianxia UI set (`assets/ui/xianxia/`, D-028).
> - Custom test runner + framework (`tests/`), an engine-free static linter
>   (`tools/gdscript_lint.py`, runs on save + as the first CI gate — D-033), a compile checker
>   (`tools/parse_check.gd`: load + `can_instantiate` + `class_name` registration), CI
>   (12 gates incl. four dedicated E2E processes after the app flow: player, world/map,
>   pet, NPC/shop).
> - Player preferences on disk: `SettingsStore` (`src/infrastructure/settings_store.gd`, a
>   `RefCounted` over `user://settings.cfg` — NOT an autoload) + a `SettingsMenu` language
>   screen; the game defaults to Vietnamese (D-035).
>
> **Not yet present (TARGET):** Dialogue/Quest/Story, Dungeon/Boss, the EventBus character
> events, a `SaveService` and file-level persistence (every persistent owner already exposes
> `to_dict`/`from_dict`), audio. Those are TARGET below. *(HISTORICAL: this list once also
> named Faction, World Simulation, Combat, Inventory, Equipment, Skill, Cultivation and NPC
> bodies — all implemented since, Phases 07–17 — and `Config`/`RNG` autoloads, which were
> deliberately NOT built: the autoload budget is frozen at five and the RNG seam is a
> per-session `RngService`.)*

## 1. Goals

Clean, maintainable, extensible, performant, and structured so a multiplayer layer can be
added later with **minimal changes to core gameplay/domain code** (a design goal, not a
guarantee). We pursue this with layered separation, composition, event-driven coupling,
and data-driven content.

## 2. Layers

```
┌─────────────────────────────────────────────────────────────┐
│ presentation   scenes · UI/HUD · input map · animation ·     │
│                audio · VFX                                    │
├─────────────────────────────────────────────────────────────┤
│ gameplay       scene coordination: spawning, encounters,     │
│                map lifecycle, combat orchestration           │
├─────────────────────────────────────────────────────────────┤
│ domain         pure rules: damage formula, XP curve,         │
│  (game rules)  cultivation/breakthrough, quest FSM, story    │
├─────────────────────────────────────────────────────────────┤
│ data           Resources: items, skills, enemies, công pháp, │
│                dialogue, quests, maps, realms (content)      │
├─────────────────────────────────────────────────────────────┤
│ persistence    save/load, versioning, migration             │
├─────────────────────────────────────────────────────────────┤
│ infrastructure EventBus · Localization · SceneRouter ·       │
│                SaveService · Config · RNG · logging          │
└─────────────────────────────────────────────────────────────┘

Dependency direction: presentation → gameplay → domain → data.
persistence reads state from gameplay/domain. infrastructure is used by all,
depends on none of the game layers.
```

### Why these layers
- **UI must not own rules.** If damage or XP math lived in a HUD script, every balance
  change would risk breaking the UI and vice-versa, and nothing would be testable
  headless. Rules sit in `domain`, pure and unit-testable.
- **Enemies must not own save logic.** Save is a cross-cutting concern owned by
  `persistence`; an enemy only exposes serializable state.
- **Player must not own an inventory database.** The player owns an *inventory
  component* (behavior + state); `persistence` serializes it. This keeps the player node
  small and the save format in one place.

## 3. Composition model

Entities (player, enemy, boss, pet, NPC) are nodes assembled from **components**, not
deep inheritance chains:

```
Entity (CharacterBody2D)
├── StatsComponent        (HP, mana/linh khí, attack, defense, resists)
├── HealthComponent       (damage intake, death; emits health_changed/died)
├── Hurtbox / Hitbox      (Area2D-based damage exchange)
├── InventoryComponent    (owned items; serializable)   [player/some entities]
├── ProgressionComponent  (XP, level, cảnh giới)         [player/pets]
├── SkillComponent        (equipped/known skills, cooldowns)
├── AIComponent           (enemy/boss/pet behavior; tick-rate controlled)
└── Sprite/AnimationComponent (presentation)
```

A boss is "an Entity with richer stat/skill/AI data + phase data" — **not** a new class
tree. A pet is "an Entity with an AIComponent set to ally behavior". This is the
mechanism behind the extensibility invariant in `docs/GAME_FLOW.md`.

## 4. Communication: signals / EventBus

- **Local relationships** (a component to its owning entity) use direct signals.
- **Cross-system reactions** go through the **EventBus** autoload. Combat emits
  `enemy_died`; the quest engine, progression, and HUD listen. Combat holds no
  reference to any of them.
- Rule: an emitter never imports/depends on its listeners. This is what keeps systems
  independently addable and testable, and is the same decoupling multiplayer will need.

## 5. Data-driven content

All content is authored as `Resource` subclasses (see `docs/DATA_SCHEMA.md`):
`ItemData`, `SkillData`, `EnemyData`, `BossData`, `TechniqueData` (công pháp),
`PetData`, `RealmData` (cảnh giới), `QuestData`, `DialogueData`, `MapData`,
`ChapterData`, `NewGameConfig`.

Systems read these resources; they do not hard-code content. Adding a new sword, skill,
enemy, or realm = create a new `.tres`, no code change.

## 6. Dependency inversion (only where it pays)

We invert dependencies at real seams, not everywhere:
- **SaveService** depends on a serialization contract (`to_dict`/`from_dict`), not on
  concrete node types.
- **RNG** is injected as a seeded source so domain logic is deterministic & testable.
- **Localization** is reached through a thin service so call sites stay stable even if
  the backing format changes.

We do **not** create interfaces for things with a single implementation and no seam —
that is the premature abstraction `.kiro/steering/04-coding-standards.md` forbids.

## 7. Autoloads (the singleton budget)

Added only when first needed, each justified in `docs/DECISIONS.md`.
- **[exists, Phase 01, D-017]** `EventBus`, `GameState`, `Localization`, `InputService`,
  `SceneRouter`.
- **[TARGET, added when first needed]** `SaveService` (Phase 23), `Config` / `RNG` (when a
  gameplay system first requires them — e.g. seeded combat/world-sim RNG).

Everything else is a node in the tree or a Resource. There is no catch-all GameManager.

## 8. Folder layout — TARGET (grown incrementally)

> Entries marked `[exists]` are present now; everything else is TARGET, added phase by
> phase. The split itself (src/data/assets/locale) is the intended shape.

```
res://
  main.tscn                      # [exists] bootstrap scene (Main/Systems/World/UI)
  src/
	bootstrap/        main.gd                              # [exists]
	infrastructure/   event_bus.gd  localization.gd  scene_router.gd   # [exists]
					  input_service.gd  game_state.gd                  # [exists]
					  settings_store.gd   # [exists, D-035] player prefs (NOT an autoload)
					  config.gd  rng.gd  logger.gd                     # [TARGET]
	persistence/      save_service.gd  save_migrations/
	domain/           combat/damage_rules.gd  # [exists, Phase 02 slice]
					  progression/  cultivation/  quest/  story/        # [TARGET]
	gameplay/         collision_layers.gd                 # [exists, Phase 02]
					  entities/player.* training_dummy.*  # [exists, Phase 02]
					  components/stats_* health_* movement_component.gd  # [exists, Phase 02]
					  sandbox/player_sandbox.*            # [exists, Phase 02 — temporary]
					  world/world_runtime.gd              # [exists, Phase 03]
					  maps/map_base.gd map_exit_zone.gd prototype_ground.gd hub_map.* field_map.*  # [exists, Phase 03]
					  spawning/                            # [TARGET]
	data/             maps/map_exit.gd map_data.gd map_catalog.gd  # [exists, Phase 03] (map Resources)
					  characters/character_template_data.gd  # [exists, Phase 04]
	domain/           character/character_state.gd         # [exists, Phase 04] (authoritative)
	presentation/     menus/ scenes/ ui/ ui/components/ hud/  # [exists; ui/hud Phase 04]  fx/  [TARGET]
  data/               stats/player_stats.tres training_dummy_stats.tres  # [exists, Phase 02]
					  characters/player_default.tres       # [exists, Phase 04]
					  maps/map_hub.tres map_field.tres map_catalog.tres prototype_tileset.tres  # [exists, Phase 03]
					  items/ skills/ enemies/ bosses/ techniques/        # [TARGET]
					  pets/ realms/ quests/ dialogue/ chapters/
  assets/             sprites/characters/player_proto.png  tiles/prototype/prototype_tileset.png  # [exists, Phase 03 prototype]
					  ui/ audio/ fonts/                    # [TARGET]
  locale/             vi.* en.*            # translation tables
  tools/              parse_check.gd  gen_prototype_assets.py   # [exists] CI + asset tooling
  tests/              [exists] framework/ unit/ integration/ gameplay/ smoke/ performance/
```

The split between `src/` (code by layer), `data/` (content Resources), `assets/`
(art/audio), and `locale/` (translations) is deliberate: it makes the layer boundaries
visible on disk and keeps content additions out of code directories.

## 9. Map / scene lifecycle

All transitions go through **SceneRouter** (one place → testable, no leaked nodes or
signals). Carried state lives in **GameState**, never on the outgoing scene. Whether
maps are separate scene instances or streamed is an open decision (`docs/DECISIONS.md`,
D-003) — the router abstraction lets us change that later without touching callers.

## 10. Multiplayer-ready seams (Stage 2, no code now)

Kept serializable and presentation-free so authority/replication can be layered on:
player state, **combat command (intent)**, world state, inventory, progression,
authoritative state, persistence. The EventBus + command-intent + seeded-RNG design is
chosen partly because it is also what a future authoritative server needs. Per-seam readiness:
`docs/MULTIPLAYER_PLAN.md`. No networking dependency enters Stage 1.

**The TARGET is now frozen (D-056): an authoritative DEDICATED SERVER.**
`docs/PRODUCTION_ARCHITECTURE_CONTRACT.md` owns it — build topology, the five independent
version domains, the twelve boundaries with their ownership answers, the command/intent shape,
the identity/session/reconnect split, the client/server responsibility matrix, the
vendor-neutral adapter slots and the deployment topology. **Target, not implementation:** no
transport, RPC, lobby, matchmaking or backend code exists or may be added before a multiplayer
phase. The invariant that matters for this document is that **offline and online run the same
domain rules and differ only in authority and transport** — so the layer direction below is
what makes the boundary movable, and presentation is the one boundary a server owns nothing of.

Presentation's own contract is `docs/PRESENTATION_ARCHITECTURE_CONTRACT.md`: gameplay decides
WHAT happened, presentation decides HOW it is perceived, and **gameplay timing is authoritative
while presentation timing follows**. Two of the three upward references in the tree are
documented there and in the production contract (`Player`/`Enemy` preloading a visual
component); no gameplay or domain file may join them.

What good motion and feedback ARE — and what makes them Aetheria's — is not an architecture
question and lives beside it: `docs/MOTION_DESIGN_CONTRACT.md` (D-057: governing laws, timing
grammar, hierarchy, the self-critique; one rule of which IS architectural — presentation never
writes the simulation clock, so hit-stop holds an image, not `Engine.time_scale`) and
`docs/XIANXIA_IDENTITY_CONTRACT.md` (D-057A). HUD composition is `docs/UI_UX_BIBLE.md` §3c.

## 11. What this architecture explicitly avoids

- A God `GameManager` that knows combat + inventory + save + UI.
- UI scripts computing gameplay results.
- Entities reaching across the tree with `get_node("../../..")`.
- Interfaces/abstractions with one implementation and no seam.
- Content types that require editing core systems to add.

## Relationship + character-visual layering (Phase 05, D-026)

- **Relationship = domain, single source of truth.** `src/domain/relationship/` holds
  `RelationshipEndpoint`/`RelationshipEdge`/`RelationshipStore`/`RelationshipService` — pure
  `RefCounted`, no Node/scene/presentation dependency. The graph is owned by the store, NOT
  scattered on character nodes or duplicated in `CharacterState`. The service is the ONLY
  mutation path and emits a DOMAIN signal (`relationship_changed`), not an EventBus signal —
  domain stays infra/presentation-free (a bridge, if ever needed, lives in a higher layer).
- **Data drives it.** Dimension ranges + event→delta rules are Resources
  (`src/data/relationship/`), not code constants.
- **Runtime ownership respects the autoload budget.** `RelationshipRuntime`
  (`src/gameplay/world/relationship_runtime.gd`) is a node under `Main/Systems`, a sibling of
  `WorldRuntime` — NOT a new autoload (D-017 unchanged). It survives map swaps because the
  SceneRouter only swaps content under `Main/World`. `WorldRuntime` stays the map/player
  coordinator (no God object).
- **Character visual = presentation only.** `src/presentation/characters/` renders a
  `CharacterVisualProfileData` and reads movement facing; it never owns movement or mutates
  domain state. The dependency direction holds: presentation → gameplay/domain, never upward.


## The art pipeline seams (D-062)

Blender never runs with the game. The pipeline writes PNGs and `.tres`; the game reads them
through these seams, each one data-driven and each with a contract test:

| Seam | Layer | What it carries | Pinned by |
|---|---|---|---|
| `CharacterVisualProfileData` + per-actor `CharacterAnchorData` | data → presentation | sheets, feet row (`anchor_offset (0, 5)`), bone-projected anchors | `test_character_visual`, `test_character_locomotion`, the pipeline's own profile check |
| `GroundLayoutData` → `PaintedGround` (`Visual/Ground`) | data → gameplay (visual) | the painted floor, `fill_rect`, paddy/water cells, materials | `test_map_scenes` (bounds, dry walkway, not one material, props on dry ground) |
| `GroundLayoutData.blockers` → `WaterBlockers` (`Collision/Water`) | data → gameplay | water collision from the SAME data the water was painted from | `test_painted_water_is_the_water_that_blocks` |
| `PropData` → `WorldProp` (`Visual/Decor`, y-sorted) | data → gameplay | sprite + origin (front base = the depth-sort line) + solid footprint; shared sway material | `test_solid_props_never_block_the_play`, `test_pipeline_sprites_stand_on_their_measured_origin` |
| `ItemData.world_icon` → `PickupFeedback` | data → presentation | the 16px item lying in the world | — (fallback to `icon`) |
| `UIPalette` → `UITheme` (`icon_slot`, `fill_color`, five button plates, keycap, band, medallion) | presentation | the ink-lacquer kit | `test_ui_theme` (measured surfaces), `test_gameplay_hud` |

The layout of a map (where houses, trees, roads and water are) is authored in
`tools/aetheria_art_pipeline/designs/maps/<map>.yaml` and written into the scene by
`world/sync_scene.py` (idempotent) — the YAML is the source of truth for placement, the scene
holds the nodes so the editor and the tests see them.
