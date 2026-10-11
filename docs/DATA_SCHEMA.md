# DATA_SCHEMA — Aetheria

> The data-driven content model. All content is authored as `Resource` subclasses so
> adding content = new `.tres`, no code change (the extensibility invariant,
> `docs/GAME_FLOW.md`). All user-facing text is a **localization key**, never a literal
> (`.kiro/steering/07-localization.md`).
>
> Status: **partly implemented, partly schema design.** Two tiers live in this document and
> they must not be confused:
>
> - **IMPLEMENTED** (real `Resource` scripts + authored `.tres` content, validated at the
>   boundary and covered by tests): stats (`src/data/stats/`), maps (`src/data/maps/`),
>   characters (`src/data/characters/`), character visuals, relationship config/rules
>   (`src/data/relationship/`), and **sects** (`src/data/sects/`:
>   `SectTemplateData` · `SectRankData` · `SectCatalog`, authored in `data/sects/*.tres`).
>   For these, the shapes below are the SHIPPED contract — changing a field is a code +
>   content change, and the field names here must match the scripts (a doc that contradicts
>   the code is a bug, L-014/L-018).
> - Also IMPLEMENTED since this block was first written: factions and world-simulation data
>   (Phases 07–08), attacks/enemies/AI profiles (09–10), the progression curve (11),
>   realms/cultivation and knowledge (12), items (13), equipment (14), techniques/skills (15),
>   pets (16) and shops (17). Their scripts under `src/data/` are the contract. Only the
>   sections below headed IMPLEMENTED were re-verified against those scripts; an unmarked
>   sketch (ItemData, EquipmentData, SkillData, TechniqueData, RealmData, EnemyData) is the
>   ORIGINAL design shape and where it differs from the script, the script wins.
> - **DESIGN ONLY** (no script exists yet; these are intended shapes): story/chapters,
>   dungeons and bosses. (Dialogue is IMPLEMENTED — Phase 18, D-066; quests and rewards are
>   IMPLEMENTED — Phase 19, D-070.) Field
>   names are the proposed contract — pin changes in `docs/DECISIONS.md`.

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

**IMPLEMENTED SO FAR** (`src/domain/combat/damage_rules.gd`, the one owner of this math):

```
compute_hit(attacker_attack, target_defense, power_multiplier = 1.0, critical_multiplier = 1.0)
  raw        = attacker_attack * power_multiplier
  mitigated  = raw * ATTACK_SCALE / (ATTACK_SCALE + target_defense)
  final      = max(MIN_DAMAGE, round(mitigated * critical_multiplier))
```

- `power_multiplier` and `critical_multiplier` arrived in **Phase 09** and are DEFAULTED, so
  the Phase-02 two-argument behaviour is unchanged (asserted).
- `power_multiplier` is `AttackData.power_multiplier`; `skill.flat_power` does not exist yet.
- The function does NOT roll. `CombatService` owns the seeded roll (`RngService.STREAM_COMBAT`)
  and passes `AttackData.critical_multiplier` in when it crits, `1.0` otherwise — a rule that
  drew its own randomness could not be unit-tested without also pinning an RNG.
- `ATTACK_SCALE` is a named constant here, not yet `attacker.attack_scale` from data.
- Still absent, each waiting for the phase with a real consumer: `skill.flat_power`,
  `resist[element]`, `technique_mult`, `equipment_mult`.

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

### PetData — linh thú (`pet_*`) — IMPLEMENTED (Phase 16, D-064)
```
id: StringName                    # must start with "pet_"
name_key, desc_key
stats: StatBlock                  # at the curve's first level
growth: StatBlock                 # added per level above the first (max_hp/attack/defense)
progression_curve: ProgressionCurveData   # XP -> level; the same curve math as the player
xp_share_percent: int             # 0..100: its share of a defeated enemy's xp_reward
skills: Array[StringName]         # technique ids (validated against the technique catalog)
ai_profile: AiProfileData         # an ALLY profile: follow_radius > 0
attack: AttackData
engage_distance: float            # <= attack.reach_pixels
hurt_radius: float
visual_profile: CharacterVisualProfileData
recall_seconds: float             # before a fallen pet can be called again
```
Level and stats are DERIVED (`level_for_xp`, `stats_at`) and never stored. A pet is not a
`CharacterState`. Listed in `PetCatalogData` (`data/pets/pet_catalog.tres`: non-empty, no null,
unique ids, every entry valid).

`AiProfileData` (shared with enemies) gained three ally fields: `follow_radius` (0 = does not
follow; must exceed `home_arrival_radius` and stay under `leash_radius`), `home_arrival_radius`,
`return_speed_scale` (0 = use `patrol_speed_scale`).

### ShopData (`shop_*`) — IMPLEMENTED (Phase 17, D-065)
```
id: StringName                    # must start with "shop_"
name_key
keeper_id: StringName             # a character instance_id in the CharacterRegistry
entries: Array[ShopEntryData]     # { item: ItemData, base_price: int > 0,
                                  #   stock: int (-1 unlimited | >= 0), buys: bool }
price_dimension: StringName       # ONE relationship dimension ("" = prices never move)
max_discount_percent: int         # 0..90, at the dimension's maximum
max_markup_percent: int           # 0..200, at the dimension's minimum
sell_percent: int                 # 1..100: what the shop pays, as a share of base
```
`ShopCatalogData` (`data/shops/shop_catalog.tres`): `currency_item: ItemData` + the shops
(unique ids, one shop per keeper, no shop trades the currency, no arbitrage at any standing).
Remaining stock is NOT here — it is `ShopState` (SAVE_FORMAT `shops`).

An NPC needs no schema of its own: it is a `CharacterTemplateData` realized as a
`CharacterState`. `CharacterVisualProfileData` gained the optional `talk_sheet`.
`CharacterTemplateData.portrait_ref` (a path, "" = none) is read since Phase 18: the medallion
the dialogue box shows for that speaker.

### QuestData (`quest_*`) — IMPLEMENTED (Phase 19, D-070)
Scripts: `src/data/quest/`, `src/data/reward/`. Content: `data/quests/quest_catalog.tres`.
```
QuestCatalogData
  entries: Array[QuestData]               # unique ids; authored order = reading order

QuestData
  id: StringName                          # quest_*
  title_key, summary_key                  # the name, and WHY it matters (the journal)
  lead_key, goal_key, return_key          # the plaque's one line: on offer / taken / ready
  giver_id, receiver_id: StringName       # CharacterRegistry instance ids
  completion: enum { ALL, ANY }           # every objective, or any one of them
  objectives: Array[QuestObjectiveData]
  reward: RewardData

QuestObjectiveData
  id: StringName                          # unique within the quest
  kind: enum { KNOW, HOLD_ITEM, DEFEAT }  # CLOSED set
  target_id: StringName                   # a knowledge id / an item id / an EnemyData id
  count: int                              # 1 for KNOW; 1..99 otherwise
  consumed: bool                          # HOLD_ITEM only: handed over at turn-in
  text_key: StringName

RewardData                                # paid by its owners, in this order
  items: Array[RewardItemData{ item: ItemData, count: 1..99 }]   # the bag
  xp: int                                 # 0..1000, through ProgressionService
  regard_character_id, regard_dimension, regard_delta   # all three or none; |delta| <= 50
```
`KNOW` and `HOLD_ITEM` are STATE (asked of the Knowledge Core / the bag every time, so what
is already true when the quest is taken counts at once); `DEFEAT` is EVENTS (counted only
while the quest is active). There are no flags, no prerequisites and no quest-id branches:
what gates an offer is a condition on the conversation choice that offers it.

**Validated structurally:** ids and the `quest_` prefix, every text key, giver and receiver,
a non-empty objective list with unique ids, a payload each kind uses and no other, a known
completion mode, a reward that pays something inside its bounds.
**Validated against the owners** (`QuestService.content_errors`, at session start): every
text has a translation in every language; giver, receiver and whoever's regard moves resolve
in the character registry; knowledge ids are in the knowledge catalog; items are in the item
catalog; a `DEFEAT` target is a creature some map spawns; a regard dimension exists.

### DialogueData (`dlg_*`) — IMPLEMENTED (Phase 18, D-066)
Scripts: `src/data/dialogue/`. Content: `data/dialogue/dialogue_catalog.tres`.
```
DialogueCatalogData
  entries: Array[DialogueData]            # unique ids; ONE dialogue per speaker

DialogueData
  id: StringName                          # dlg_ prefix
  speaker_id: StringName                  # a CharacterRegistry instance id (as ShopData.keeper_id)
  start_node_id: StringName
  nodes: Array[DialogueNodeData]

DialogueNodeData                          # one thing the speaker says
  id: StringName                          # unique within the dialogue
  text_key: StringName
  mood: Mood                              # CALM | WARM | STERN | WARY   (presentation only)
  gesture: StringName                     # "" | "talk"  — a CharacterVisualComponent action
  choices: Array[DialogueChoiceData]
  next_node_id: StringName                # choice-less nodes only: "continue" target, "" = end

DialogueChoiceData                        # one thing the player may answer
  id: StringName                          # unique within the dialogue
  text_key: StringName
  conditions: Array[DialogueConditionData]  # ALL must pass; asked again on submit
  effect: DialogueEffectData              # ONE, or null
  next_node_id: StringName                # "" = the conversation ends

DialogueConditionData
  kind: Kind                              # KNOWS | RELATIONSHIP_AT_LEAST | QUEST_PHASE | FLAG | ORIGIN
  flag_id: StringName                     # FLAG: a declared story flag, at least `value` (>= 1)
  origin_id: StringName                   # ORIGIN: the run's Origin
  knowledge_id: StringName                # KNOWS
  dimension: StringName, value: int       # RELATIONSHIP_AT_LEAST (the speaker's regard for the player)
  negate: bool

DialogueOpeningData                       # Phase 20: DialogueData.openings, asked in order
  conditions: Array[DialogueConditionData]  # ALL must hold; the first opening that does is the first line
  node_id: StringName                     # else DialogueData.start_node_id

DialogueEffectData
  kind: Kind                              # … | QUEST_* | SET_FLAG | STORY_CHOICE (the story owner applies both)
  flag_id: StringName, flag_value: int    # SET_FLAG
  story_choice_id, story_option_id        # STORY_CHOICE: StoryService.choose is the transaction
  dimension: StringName, delta: int       # RELATIONSHIP_DELTA (1..50 in magnitude)
  knowledge_id: StringName                # GRANT_KNOWLEDGE
```
**Validated structurally** (`validation_errors`, no other system needed): empty / duplicate
ids, the `dlg_` prefix, a missing or unknown start node, dangling `next_node_id`s, a node with
both choices and a continue target, a node whose choices are ALL conditional, a chain of
choice-less lines that never ends, a node unreachable from the start, an unknown kind / mood /
gesture, a payload a kind does not use, an `OPEN_SHOP` choice that claims to continue, and a
`RELATIONSHIP_DELTA` choice with no condition on its own dimension that the delta eventually
makes false (raise only while below a value; lower only while at or above one).

**Validated against the owners** (`DialogueService.content_errors`): every `speaker_id`
resolves to a `CharacterState` REGISTERED in the session's `CharacterRegistry` when the
dialogue session starts (D-069 — registration, not a body in the current map: reach stays
`NpcRuntime`'s question at the talk. In practice a speaker is a member of the world-simulation
cast, which the session registers before Dialogue starts; a person who exists only as a body
on a map that has not been entered is not registered yet and may not be given a conversation);
every knowledge id is in the knowledge catalog; every dimension is one the relationship config defines and every
threshold is inside its range; an `OPEN_SHOP` speaker keeps a shop; every `text_key` has a
non-empty value in every supported language (`Localization.is_translated`).

**Phase 19 (D-070) added, to the same closed sets:** a condition `QUEST_PHASE` (`quest_id` +
`quest_phase`: AVAILABLE / ACTIVE / READY / COMPLETED, answered by `QuestService`) and the
effects `QUEST_ACCEPT`, `QUEST_TURN_IN`, `QUEST_ABANDON` (payload: `quest_id`, carried out by
`QuestRuntime`). Checked at session start: the quest exists; accept and abandon are said by
its giver and turn-in by its receiver; a turn-in choice requires `QUEST_PHASE READY`; and
every quest in the catalog is offered, answered and taken back by SOME conversation.

No `set_flags` and no flag condition: Dialogue owns no flag (D-066). Nothing here is saved.

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

### Story data (`chapter_*` / `beat_*` / `flag_*` / `choice_*` / `origin_*`) — IMPLEMENTED (Phase 20, D-072)

`src/data/story/`. Two catalogs, generated by ONE tool (`tools/author_story_data.py`;
`--check` fails when the `.tres` on disk are stale). Every id is stable ASCII (`StoryIds`:
`[a-z][a-z0-9_]*`). All player-facing text is a key into `locale/aetheria.csv`.

```
StoryCatalogData        data/story/story_catalog.tres
  chapters: Array[StoryChapterData]
  flags:    Array[StoryFlagData]        # the DECLARATIONS; values live on the player's CharacterState
  choices:  Array[StoryChoiceData]
  start_beat_id: StringName

StoryChapterData   id, title_key, act (0 = prologue), max_reveal_layer, beats: Array[StoryBeatData]
StoryBeatData      id, objective_key (the purpose line), record_key (the Chronicle),
                   reveal_layer, source (canon reference), trigger: StoryTriggerData,
                   branches: Array[StoryBranchData], terminal
StoryTriggerData   kind, subject_id, subjects, count
                     EVENTS (count only while the beat is current): SCENE_ENDED, ARRIVED, CULTIVATED
                     STATES (asked on entry and whenever the record changes): FLAG, MET, CHOICE, KNOWS
StoryBranchData    conditions: Array[StoryConditionData], next_beat_id   # first match; last is unconditional
StoryConditionData kind FLAG | ORIGIN | CHOICE | KNOWS, payload, negate
StoryFlagData      id, kind BOOL | INT, max_value, purpose
StoryChoiceData    id, beat_id (when it may be answered), title_key, options: Array[StoryOptionData]
StoryOptionData    id, record_key, consequences: Array[StoryConsequenceData]
StoryConsequenceData  kind SET_FLAG | REGARD | GRANT_KNOWLEDGE, payload (a regard move is at most 50)

OriginCatalogData       data/story/origin_catalog.tres   # EXACTLY the five ids of CL-09
OriginData         id, name_key, problem_key, edge_key, cost_key, goal_key, grants: Array[OriginGrantData]
OriginGrantData    kind ITEM | KNOWLEDGE | REGARD, payload, reason
                   (an item grant is 1..3; a regard grant is at most 20 either way)
```

```
StorySceneCatalogData   data/story/story_scene_catalog.tres   (the same generator)
StorySceneData     id, elsewhere (the map behind it is covered), steps: Array[StorySceneStepData]   # at most 6
StorySceneStepData kind CARD (place + time) | CAPTION | LINE (speaker_id), text_key, sub_key
StoryBeatData      + entry_scene_id | plays_origin_vignette      OriginData  + vignette_scene_id

PlayerAppearanceCatalogData   data/characters/player_appearances.tres
PlayerAppearanceData   id, name_key, template: CharacterTemplateData
                       (valid only if the template has a gender, a body and a portrait that
                        exist, and no default sect; two looks may not draw the same body)

EquipmentData      body_visuals_by_base: { base visual id -> CharacterVisualProfileData }
                   (replaces the single `body_visual`: a garment is drawn per BODY)
```

A scene is PRESENTATION data: it says what is shown and changes nothing. The beat that plays
it was committed first.

The catalog checks what no entry can check alone: unique ids, every reference resolving,
every beat reachable from the start, no loop (a beat is entered once), a last branch that
always applies, no beat above its chapter's reveal layer, no two consequences of one answer
writing the same value. What it asks of OTHER owners (text in both languages, knowledge,
people, relationship dimensions, items, maps) is `StoryService.content_errors`.

### NewGameConfig (`newgame_default`)
```
starting_stats: StatBlock
starting_realm: StringName
starting_items: Array[{ item_id, count }]
starting_skills: Array[StringName]
start_chapter: StringName
start_character_template: StringName   # the player's CharacterTemplateData (see §3b)
```

> **Phase 20 note (D-072).** No `NewGameConfig` resource was built: the three things a new
> run needs to be told — the Origin, and the appearance the player's character is built with
> — are chosen on the identity screen, and what an Origin starts with is `OriginData.grants`.
> The block above stays as the sketch it was; it is not shipped schema.

## 3b. Core social / world systems (Character · Relationship · Sect · Faction · World Sim)

> These are **core** systems (D-011). Full design: `docs/CHARACTER_SYSTEM.md`,
> `docs/RELATIONSHIP_SYSTEM.md`, `docs/SECT_SYSTEM.md`, `docs/WORLD_SIMULATION.md`.
> The schemas below are the data contract; the player is itself a Character.
>
> **Status (Phase 04, D-023):** `CharacterTemplateData` and `CharacterState` are IMPLEMENTED
> (`src/data/characters/character_template_data.gd`, `src/domain/character/character_state.gd`);
> the player uses `data/characters/player_default.tres`. `CharacterState` serializes its
> persistent tier via `to_dict`/`from_dict` (the save seam; cultivation fields are stored as
> CONTRACT only at Phase 04; cultivation mechanics arrived in Phase 12). *(HISTORICAL: at
> Phase 04 the Relationship/Sect/Faction/WorldSim schemas below were design-only; all four are
> implemented — Phases 05–08.)*

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

### World simulation DATA (`schedule_*` / `actor_*` / `wevent_*`) — IMPLEMENTED, D-048
```
WorldSimScheduleData (schedule_*)     # a cyclic background routine
  id
  phases: Array[Dictionary]           # [{ activity: int ordinal, ticks: int > 0 }]
                                      # Activity is CLOSED: TRAINING/MISSION/RETURNING/RESTING

WorldSimActorData (actor_*)           # one authored background character the world simulates
  id                                  # ALSO the CharacterState.instance_id (one identity)
  character_template: CharacterTemplateData   # required — a real Character, not a second model
  schedule: WorldSimScheduleData      # required — the activity is a pure function of it
  home_map_id: StringName             # -> MapData.id; drives the LOD band
  sect_id, sect_rank_id               # both or neither; enrolled THROUGH SectService (D-015)
  faction_id                          # optional; requires sect_id (a faction is inside a sect)

WorldSimEventData (wevent_*)          # one recurring world event
  id                                  # also the scheduling key, so it must be unique
  kind                                # CLOSED: SECT_INFLUENCE/FACTION_INFLUENCE/
                                      #         RELATIONSHIP_SHIFT — one per owning service
  target_id                           # sect id | faction id | first character endpoint
  secondary_id, dimension             # RELATIONSHIP_SHIFT only; REFUSED on the other kinds
  first_tick: int > 0                 # tick 0 would fire before the world advanced at all
  period_ticks: int >= 0              # 0 = fire once
  magnitude_min, magnitude_max        # INCLUSIVE, may be negative; [0,0] is invalid
                                      # (an event that cannot be felt is cost without content)

WorldSimCatalog                       # the whole authored simulation + its tuning
  ticks_per_hour, hours_per_day, days_per_season, seasons_per_year   # the calendar (data)
  ticks_per_map_transition, ticks_on_session_start                   # the explicit beats
  catch_up_budget_ticks                                              # the load-spike cap
  schedules, actors, events
  event_log_capacity                  # bounds the player-facing feed inside the save
```
> No world seed is authored: the seed belongs to a RUN (hashed `GameState.run_id`), not to
> content, so two players get different worlds from the same catalog.

### WorldSimState (serialized) — the REAL shape, D-048
```
schema: int                           # this block's own version (migration-independent)
world_clock: { tick, ticks_per_hour, hours_per_day, days_per_season, seasons_per_year }
                                      # the CALENDAR travels with the tick, or retuning the
                                      # catalog would silently change a save's in-world date
rng_seed: int                         # the world seed
rng_streams: { stream_id -> { state, draws } }    # REQUIRED: a seed alone only reproduces a
                                      # world from tick 0 (SAVE_FORMAT §3b)
pending_transitions: Array            # [{ due_tick, event_id }], sorted by (due_tick, id);
                                      # a recurring event's NEXT due tick is computed when it
                                      # fires, so it cannot be re-derived from the catalog
carry_over_ticks: int                 # promised-but-unspent simulation time (bounded catch-up)
actors: { instance_id -> { instance_id, schedule_id, location_map_id,
                           joined_tick, band, activity } }
                                      # joined_tick is the ORIGIN of the derived activity
event_log: Array                      # bounded feed [{ tick, event_id, kind, target_id,
                                      #                 magnitude }]
event_log_capacity: int
```
> `CharacterState.sim_state` is a DERIVED CACHE of the matching `actors` row (band + activity +
> location), in the same relationship `sect_id` has with the sect roster (D-015). The record
> wins; the simulation reports drift rather than trusting the cache.

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

## Relationship data (Phase 05, D-026)

Relationships are authored/tuned as DATA (`docs/RELATIONSHIP_SYSTEM.md`):

- **`RelationshipConfigData`** (`src/data/relationship/relationship_config_data.gd`,
  `data/relationship/relationship_config.tres`) — the single source of truth for dimension
  tuning. `dimensions: Array[Dictionary]`, each `{ id, default, min, max }`, plus
  `history_capacity: int`. Default ranges: `affinity` −100..100, `trust`/`respect`/`fear`/
  `rivalry` 0..100, `debt` −100..100 (signed), history capacity 32. Validation enforces
  `min ≤ default ≤ max`, unique ids, capacity ≥ 0. The relationship service reads ranges from
  here — no range is hard-coded in logic.
- **`RelationshipRuleData`** + **`RelationshipRuleCatalog`**
  (`src/data/relationship/*`, `data/relationship/relationship_rules.tres`) — the deterministic
  event→delta contract: a rule is `{ event_kind, dimension_deltas: { dimension: int }, optional
  required_relationship_type }`; the catalog is a validated array (unique `event_kind`). No DSL.
- **Serialized relationship graph** (`RelationshipStore.to_dict`) — `{ "edges": [ edge... ] }`,
  edges sorted by id; each edge is `{ id, from{kind,id}, to{kind,id}, relationship_type,
  symmetric, known, dimensions{dim:int}, history[...] }`. Plain data; this is the save seam's
  `relationships` section (`SaveService` is Phase 23).

## Character visual data (Phase 05, D-026)

- **`CharacterVisualProfileData`** (`src/data/characters/character_visual_profile_data.gd`,
  `data/characters/visual/*.tres`) — presentation definition referenced by
  `CharacterTemplateData.sprite_set_ref`: `id`, `idle_sheet` (required), `walk_sheet`
  (optional — falls back to idle while moving), `frame_size: Vector2i` (**32×48** baseline,
  D-046), `frame_duration: float` (seconds per animation frame, must be > 0), `anchor_offset`.
  A sheet is a **GRID**: one ROW per cardinal direction (`Direction` order DOWN, UP, LEFT,
  RIGHT) × N animation COLUMNS, so `width = frame_size.x * frames` and
  `height = frame_size.y * 4`. The frame count is **derived** via `frame_count_of(sheet)` from
  the texture width — never authored, so it cannot drift from the art. Validated at the
  boundary: a width that is not a whole multiple of the frame width is REJECTED (and
  `frame_count_of` returns 0) rather than floored to a half-frame slice. It is PRESENTATION
  data — never copied into `CharacterState` (`docs/CHARACTER_SYSTEM.md` §3).

### WorldItem provenance — IMPLEMENTED (Phase 20, D-072 addendum A)

```
WorldItem (a node under <map>/Pickups)
  held_by_flag: StringName      # "" = nobody's, free; else held until this story flag is set
  held_reason_key: StringName   # what walking onto it says while it is held (required if held)
```

### Story-driven world state — IMPLEMENTED (Phase 20, D-072 addendum E–G)

```
StoryBeatData (additions)
  encounter_id: StringName            # data/enemies/spawn_table_<id>.tres (must carry a tag)
  encounter_choice_id: StringName     # the choice the encounter answers
  encounter_cleared_option / encounter_left_option: StringName
  encounter_flag_id: StringName       # optional: raised when the encounter begins

EnemySpawnTableData.tag: StringName   # "" for a map's standing table; part of every instance id
WorldItem.appears_with_flag: StringName   # absent until the flag is set
StoryPresence (child node)  flag_id, present_when_set   # shows / removes its parent, body included

# --- D-073 (post-Phase-20 hardening) ---
StoryBeatData (additions)
  ambience_id: StringName             # "" | "dusk" | "night": data/ambience/ambience_<id>.tres
                                      # (how the maps are LIT while the beat is current; derived
                                      #  every time, stored nowhere)
  completion_hint_key: StringName     # a notice said ONCE when the beat completes...
  completion_hint_action: StringName  # ...naming this input action's key (both or neither)
OriginData (additions)
  observation_flags: Array[StringName]  # index-aligned with...
  observation_keys: Array[StringName]   # ...the record line shown once that flag is set
EnemySpawnTableData.visual_profile: CharacterVisualProfileData   # optional: how THIS table's
                                      # creatures are drawn (same grid as their own look)
AmbienceProfileData (presentation; GENERATED by build.py ambience from the Visual DNA)
  id, tint: Color, lantern_color, lantern_energy, lantern_flicker,
  vein_color, vein_energy, vein_pulse, transition_seconds
StoryOwners (domain seams, not serialized)
  can_teach(knowledge_id) -> bool            # prepare
  can_move_regard(who, dimension, delta) -> bool
  move_regard(...) -> { ok, old_value, new_value }   # was -> bool
Map layout YAML: story_props: [{name, prop, at, flag, present_when_set}]   # written by sync_scene
```
