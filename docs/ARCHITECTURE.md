# ARCHITECTURE — Aetheria

> Narrative design for the module architecture. The short, enforceable rulebook is
> `.kiro/steering/03-architecture.md`; this document explains the *why* and the shape.
>
> Status: **design doc.** Most of the structure below is the **TARGET** to grow into
> (clearly labelled), not an existing tree.
>
> **CURRENT STATE (through Phase 06 final hardening, 2026-10-03):** Phase 05 (Relationship
> core + early character visual pipeline) is **CLOSED** (D-026) and Phase 06 (Sect) is
> **CLOSED** (D-032, hardened in D-037). Phase 07 (Faction/Politics) is **NOT STARTED**.
> The live UI is the CC0 Xianxia Pixel Pack set (D-028) and the visible world/character art is
> at the **production-foundation** tier (D-029) — both presentation-only, no gameplay/domain
> change. The repo boots to a playable world/map slice where the player is a real Character,
> with a UI foundation:
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
> - Phase-02 Player Sandbox (`src/gameplay/sandbox/`) is retained for combat validation but
>   is not reachable from New Game. The `prologue_shell` is retained but no longer first.
> - Semantic InputMap in `project.godot`; translations in `locale/aetheria.csv`;
>   production-foundation pixel-art under `assets/` (self-made world/character, D-029) + the
>   CC0 Xianxia UI set (`assets/ui/xianxia/`, D-028).
> - Custom test runner + framework (`tests/`), an engine-free static linter
>   (`tools/gdscript_lint.py`, runs on save + as the first CI gate — D-033), a compile checker
>   (`tools/parse_check.gd`: load + `can_instantiate` + `class_name` registration), CI
>   (10 gates incl. a dedicated world/map E2E process).
> - Player preferences on disk: `SettingsStore` (`src/infrastructure/settings_store.gd`, a
>   `RefCounted` over `user://settings.cfg` — NOT an autoload) + a `SettingsMenu` language
>   screen; the game defaults to Vietnamese (D-035).
>
> **Not yet present (TARGET):** Faction/World-Sim domain systems, Combat,
> Inventory/Equipment/Skill/Cultivation mechanics (Character holds cultivation fields as
> CONTRACT only), Dialogue/Quest/Story, non-player Character spawning + the EventBus character
> events, `Config`/`RNG`/`SaveService` autoloads, persistence, and most content Resources.
> Those are TARGET below.

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
chosen partly because it is also what a future authoritative server needs. Full plan:
`docs/MULTIPLAYER_PLAN.md`. No networking dependency enters Stage 1.

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
