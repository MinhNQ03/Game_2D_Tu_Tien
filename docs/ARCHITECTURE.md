# ARCHITECTURE — Aetheria

> Narrative design for the module architecture. The short, enforceable rulebook is
> `.kiro/steering/03-architecture.md`; this document explains the *why* and the shape.
>
> Status: **design doc.** Most of the structure below is the **TARGET** to grow into
> (clearly labelled), not an existing tree.
>
> **CURRENT STATE (Phase 01, 2026-10-02):** the repo has a bootable, non-gameplay Core
> runtime skeleton:
> - Bootstrap scene `main.tscn` (root `Main`, script `src/bootstrap/main.gd`, children
>   `Systems`/`World`/`UI`); `Main` only coordinates boot and wiring.
> - 5 infrastructure autoloads (D-017): `EventBus`, `GameState` (lifecycle + session),
>   `Localization` (vi/en), `InputService` (semantic intent + gating), `SceneRouter`
>   (single transition entry).
> - A localized main-menu shell (`src/presentation/menus/`) and a non-gameplay first-scene
>   shell (`src/presentation/scenes/prologue_shell`).
> - Semantic InputMap in `project.godot`; translations in `locale/aetheria.csv`.
> - Custom test runner + framework (`tests/`), parse checker (`tools/parse_check.gd`), CI.
>
> **Not yet present (TARGET):** any gameplay/domain/data system (player, combat, character,
> sect, …), `Config`/`RNG`/`SaveService` autoloads, persistence, and content Resources.
> Those are the TARGET sections below.

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
					  config.gd  rng.gd  logger.gd                     # [TARGET]
	persistence/      save_service.gd  save_migrations/
	domain/           combat/damage_rules.gd  # [exists, Phase 02 slice]
					  progression/  cultivation/  quest/  story/        # [TARGET]
	gameplay/         collision_layers.gd                 # [exists, Phase 02]
					  entities/player.* training_dummy.*  # [exists, Phase 02]
					  components/stats_* health_* movement_component.gd  # [exists, Phase 02]
					  sandbox/player_sandbox.*            # [exists, Phase 02 — temporary]
					  maps/  spawning/                     # [TARGET]
	presentation/     menus/  scenes/              # [exists]  ui/ hud/ fx/  [TARGET]
  data/               stats/player_stats.tres training_dummy_stats.tres  # [exists, Phase 02]
					  items/ skills/ enemies/ bosses/ techniques/        # [TARGET]
					  pets/ realms/ quests/ dialogue/ maps/ chapters/
  assets/             sprites/ tiles/ ui/ audio/ fonts/
  locale/             vi.* en.*            # translation tables
  tools/              parse_check.gd                       # [exists] CI tooling
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
