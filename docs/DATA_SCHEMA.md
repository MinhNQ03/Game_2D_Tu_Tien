# DATA_SCHEMA — Aetheria

> The data-driven content model. All content is authored as `Resource` subclasses so
> adding content = new `.tres`, no code change (the extensibility invariant,
> `docs/GAME_FLOW.md`). All user-facing text is a **localization key**, never a literal
> (`.kiro/steering/07-localization.md`).
>
> Status: **schema design.** No Resource scripts exist yet; these are the intended
> shapes. Field names are the proposed contract — pin changes in `docs/DECISIONS.md`.

## 0. Conventions

- Every content Resource has a stable `id: StringName` (unique within its type) used by
  saves, quests, and story — **ids never change once shipped** (changing one is a
  breaking content change → `DECISIONS.md`).
- Display text fields hold **localization keys** (e.g. `name_key`, `desc_key`), not
  strings.
- Numbers that tune balance live here, not in scripts (no magic numbers in code).
- Resources are **data only** — no gameplay behavior lives in them.

## 1. Core stats (shared shape)

```
StatBlock:
  max_hp: int
  max_mana: int          # Linh khí
  attack: int
  defense: int
  resistances: Dictionary # { element: StringName -> value: int }
  crit_chance: float
  crit_mult: float
  speed: float
```

## 2. Damage formula (the single source of truth)

> Combat math is defined **only here** and implemented once in the `domain` layer.
> It must be deterministic given a seeded RNG.

Baseline (tunable, to be balanced; keep the shape, tune the numbers in data):

```
raw        = attacker.attack * skill.power_mult + skill.flat_power
mitigated  = raw * (defense_factor) * (1 - resist[element])
            where defense_factor = attacker.attack_scale / (attacker.attack_scale + target.defense)
crit       = rng.chance(attacker.crit_chance) ? attacker.crit_mult : 1.0
final      = max(1, round(mitigated * crit * technique_mult * equipment_mult))
```

Inputs: attacker stats · công pháp (`technique_mult`) · skill def · equipment mods ·
target defense/resist. Output: integer damage + effects to apply + events to emit.
Any change to this formula is logged in `DECISIONS.md` and re-tested (high-risk area).

## 3. Content resource schemas

### ItemData (`item_*`)
```
id, name_key, desc_key, icon
category: enum { CONSUMABLE, MATERIAL, QUEST, EQUIPMENT_REF }
stack_max: int
use_effects: Array[EffectData]   # for consumables
value: int                        # shop base price
```

### EquipmentData (`equip_*`)
```
id, name_key, desc_key, icon
slot: enum { WEAPON, ARMOR, ACCESSORY, ... }
stat_modifiers: StatBlock-delta
required_realm: StringName        # cảnh giới gate (optional)
required_level: int               # optional
```

### SkillData (`skill_*`)
```
id, name_key, desc_key, icon
kind: enum { ACTIVE, PASSIVE }
power_mult: float
flat_power: int
element: StringName
mana_cost: int                    # Linh khí
cooldown: float
effects: Array[EffectData]
required_technique: StringName    # công pháp gate (optional)
required_realm: StringName        # optional
```

### EffectData (`effect_*`)  — buffs/debuffs/status
```
id, name_key
kind: enum { DAMAGE_OVER_TIME, STAT_MOD, STUN, HEAL, SHIELD, ... }
magnitude: float
duration: float
stacking: enum { NONE, REFRESH, STACK }
```

### TechniqueData — công pháp (`tech_*`)
```
id, name_key, desc_key
stat_modifiers: StatBlock-delta
resource_profile: Dictionary      # how it shapes mana/regen
unlocked_skills: Array[StringName]
required_realm: StringName
```

### RealmData — cảnh giới (`realm_*`)
```
id, name_key, desc_key
order: int                        # tier ordering
breakthrough_cost: int            # tu luyện required to advance
breakthrough_rule: StringName     # which domain rule evaluates the attempt
unlocks: Array[StringName]        # skills / techniques / zones gated by this realm
```

### EnemyData (`enemy_*`)
```
id, name_key
stats: StatBlock
skills: Array[StringName]
ai_profile: StringName            # which AIComponent behavior preset
xp_reward: int
loot_table: Array[LootEntry]      # { item_id, weight, min, max }
sprite_set: ...
```

### BossData (`boss_*`) — extends enemy with phases
```
(all EnemyData fields)
phases: Array[PhaseData]          # { hp_threshold, skills, ai_profile, intro_beat }
story_flags_on_defeat: Array[StringName]
chapter_gate: StringName          # chapter this defeat may advance
```

### PetData — linh thú (`pet_*`)
```
id, name_key, desc_key
stats: StatBlock
skills: Array[StringName]
ai_profile: StringName            # ally behavior preset
progression: ...                  # pets can level (ProgressionComponent)
```

### QuestData (`quest_*`)
```
id, title_key, desc_key
objectives: Array[ObjectiveData]  # { kind, target_id, count }
rewards: { xp, items: Array[LootEntry], flags: Array[StringName] }
prerequisites: Array[StringName]  # flags/quests required to offer
```

### DialogueData (`dlg_*`)
```
id
lines: Array[DialogueLine]        # { speaker_key, text_key, choices }
choices: Array[Choice]            # { text_key, set_flags, goto_line, requires }
```

### MapData (`map_*`)  — IMPLEMENTED (`src/data/maps/map_data.gd`, D-021 + D-022)
```
id: StringName                    # stable map identity (never changes once shipped)
name_key: String                  # localization key for the display name
scene_key: String                 # SceneRouter registry key for this map's content scene
scene_path: String                # resource path of the content scene (registered under scene_key)
bounds: Rect2                     # playable area; the active Camera2D's limits derive from this
default_spawn_id: StringName      # spawn marker used when an exit gives no entry_point
exits: Array[MapExit]             # outgoing edges, each { id, to_map_id, entry_point }
tileset_ref: ...                  # (deferred: maps render via the shared prototype TileSet now)
spawn_tables: Array[SpawnEntry]   # (deferred to Enemy/AI phase; no spawns yet)
music: StringName                 # (deferred to the audio pass)
```

### MapExit  — IMPLEMENTED (`src/data/maps/map_exit.gd`, D-022)
```
id: StringName                    # stable, unique within the owning MapData
to_map_id: StringName             # destination map (a MapData.id in the same catalog)
entry_point: StringName           # destination spawn marker ("" = destination default_spawn_id)
```

### MapCatalog  — IMPLEMENTED (`src/data/maps/map_catalog.gd`, D-022)
```
maps: Array[MapData]              # every map in a world grouping; the data-driven source of truth
```

> **Phase 03 source-of-truth (D-021 + D-022):** `MapData` is AUTHORITATIVE for its identity,
> content scene, playable bounds, default spawn, and exits. It references the scene by a
> stable `scene_key` + a `scene_path` (the one place the map↔scene binding is authored),
> **not** a direct `scene: PackedScene` — so `MapData` stays a pure data resource and
> `SceneRouter` owns *how* a scene loads. A `MapCatalog` resource
> (`data/maps/map_catalog.tres`) lists all maps; `WorldRuntime` loads ONLY the catalog path,
> validates it, and registers `scene_key -> scene_path` with the router. Adding a map =
> author `MapData` + a content scene + add to the catalog, with NO core-code edit. A map
> scene's `MapExitZone` references a `MapExit` by `id` only; the destination is never
> duplicated in the scene. `tileset_ref`/`spawn_tables`/`music` are declared as the intended
> shape but not yet implemented (they land with the art/audio/combat passes).

### ChapterData (`chapter_*`)
```
id, title_key
start_map: StringName
required_flags_to_complete: Array[StringName]
next_chapter: StringName
```

### NewGameConfig (`newgame_default`)
```
starting_stats: StatBlock
starting_realm: StringName
starting_items: Array[{ item_id, count }]
starting_skills: Array[StringName]
start_chapter: StringName
start_character_template: StringName   # the player's CharacterTemplateData (see §3b)
```

## 3b. Core social / world systems (Character · Relationship · Sect · Faction · World Sim)

> These are **core** systems (D-011). Full design: `docs/CHARACTER_SYSTEM.md`,
> `docs/RELATIONSHIP_SYSTEM.md`, `docs/SECT_SYSTEM.md`, `docs/WORLD_SIMULATION.md`.
> The schemas below are the data contract; the player is itself a Character.
>
> **Status (Phase 04, D-023):** `CharacterTemplateData` and `CharacterState` are IMPLEMENTED
> (`src/data/characters/character_template_data.gd`, `src/domain/character/character_state.gd`);
> the player uses `data/characters/player_default.tres`. `CharacterState` serializes its
> persistent tier via `to_dict`/`from_dict` (the save seam; cultivation fields are stored as
> CONTRACT only — no mechanics yet). The Relationship/Sect/Faction/WorldSim schemas below
> remain design-only contracts for their phases.

### CharacterTemplateData — definition (`char_*`)
```
id, name_key, title_key, portrait_ref, sprite_set_ref
gender, origin_key, bloodline_key
age, age_category                     # CHILD/YOUTH/ADULT/ELDER/ANCIENT (optional)
profession                            # CULTIVATOR/ALCHEMIST/BLACKSMITH/MERCHANT/...
starting_realm: StringName            # cảnh giới (reuses progression/cultivation rules)
starting_technique_ids: Array[StringName]
base_stats: StatBlock
default_traits: Array[StringName]     # PROUD/LOYAL/GREEDY/CAUTIOUS/... personality
motivation_key: StringName
default_goals: Array                  # { kind, target_id, priority }
default_sect_id: StringName           # optional
default_faction_id: StringName        # optional
schedule_ref: StringName              # data-defined routine (world sim)
```

### CharacterState — runtime instance (serialized; persistent tier only)
```
instance_id: StringName               # unique per save
template_id: StringName               # -> CharacterTemplateData.id
realm_id, cultivation_progress, technique_ids
stats_current                         # current vs. StatBlock max
traits, goals                         # may diverge from template over play
sect_id, faction_id, sect_rank        # DERIVED read cache; authority = SectState roster (D-015)
reputation: Dictionary                # { scope -> value }
secrets: Array[{ secret_id, known_by: Array[instance_id] }]
story_flags: Dictionary
life_state                            # ALIVE/DEAD/MISSING/ASCENDED
sim_state                             # where/what when off-screen (world sim)
```
Runtime/presentation tiers (pathing, animation, portrait frame) are NOT serialized.

### RelationshipEdge (`rel_*`) — one graph, serialized
```
id: StringName
from_ref, to_ref                      # Character instance_id OR Sect id
relationship_type: StringName         # MASTER_DISCIPLE/RIVAL/ALLY/ENEMY/FAMILY/...
dimensions: { affinity, trust, respect, fear, rivalry, debt }   # scalars (tuning data)
symmetric: bool
known: bool
history: Array                        # optional capped change log
```
Covers Character↔Character, Player↔Character (player is a Character), Character↔Sect.

### SectTemplateData — definition (`sect_*`)
```
id, name_key, emblem_ref, type, tier
doctrine_key
rank_ladder: Array[{ rank_id, name_key, authority }]
default_factions: Array[FactionState-seed]
starting_resources: Dictionary
starting_territory: Array[StringName]
technique_ids: Array[StringName]
rules: Array[{ rule_id, text_key, penalty }]
default_ally_sect_ids, default_enemy_sect_ids: Array[StringName]
reputation_seed, influence_seed
secrets: Array[{ secret_id, known_by }]
event_hooks: Array[StringName]
```

### SectState — runtime instance (serialized)
```
id: StringName                        # -> SectTemplateData.id
leader_ref: instance_id
elder_refs, disciple_refs: Array[instance_id]
factions: Array[FactionState]
resources: Dictionary
territory: Array[StringName]
reputation: Dictionary
influence: int
ally_sect_ids, enemy_sect_ids: Array[StringName]
discovered_secrets: Array[StringName]
story_flags: Dictionary
```

### FactionState (serialized, inside SectState)
```
id, name_key
leader_ref: instance_id
member_refs: Array[instance_id]
goals: Array
influence: int
resources: Dictionary
stance: StringName                    # LOYALIST/REFORMIST/RADICAL/NEUTRAL/...
attitude_toward_player: int           # scalar (data, not hard-coded)
attitudes_toward_factions: Dictionary # { other_faction_id -> scalar }
```

### WorldSimState (serialized) — see `docs/WORLD_SIMULATION.md`
```
world_clock: int                      # coarse tick count / in-game time
pending_transitions: Array            # scheduled state changes to apply on catch-up
rng_seed: int                         # deterministic background simulation
```

> Save sections for the above (`characters`, `relationships`, `sects`, `world_sim`) are
> listed in `docs/SAVE_FORMAT.md`. All references are ids/instance_ids so saves survive
> as long as the referenced content ids exist.

## 4. Validation

Content Resources are validated at load (a data test asserts: required fields non-null,
referenced ids resolve, `name_key`/`desc_key` exist in both `vi` and `en`). Invalid data
fails loudly in development (`push_error`), never silently. See `docs/TEST_PLAN.md`.

## 5. Why this shape

- **Keys, not strings** → localization is structural, not retrofitted.
- **Ids everywhere** → saves/quests/story reference content stably across versions.
- **Stat deltas on equipment/technique** → the one damage formula consumes them; no
  parallel math.
- **Phases/AI as data** → bosses and enemies scale by authoring, not by new classes.
