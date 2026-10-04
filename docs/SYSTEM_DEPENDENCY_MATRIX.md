# SYSTEM_DEPENDENCY_MATRIX — Aetheria

> **Owner of:** "what breaks if I change this?" — per system: the authoritative owner, where its
> state lives, what it reads and writes, what it depends on, its content input, its save and UI
> exposure, its future multiplayer seam, its phase, and its risk.
> Phase numbers are `docs/ROADMAP.md`'s (C-009). Layer names are
> `.kiro/steering/03-architecture.md`'s.
>
> **Two different dependency graphs exist and must not be confused** (§3). This matrix is the
> ENGINEERING one.

---

## 1. How to read this

- **AUTHORITATIVE OWNER** — the single class/service that may mutate the state. Everything else
  reads a view or sends an intent.
- **STATE TIER** — persistent (saved) / runtime (derived, per session) / presentation (visual
  only). Mandatory for every core system (`MULTIPLAYER_PLAN.md` §2b).
- **MP SEAM** — what a Stage-2 server would own. No networking now.
- **RISK** — cost of getting the design wrong, not difficulty of coding it.
- Status: **DONE** = implemented + CI-verified · **P-nn** = planned for that phase.

## 2. The matrix

| System | Status | Authoritative owner | Authoritative state (tier) | Inputs | Outputs / Emits | Reads | Writes | Depends on | Depended on by | Content input | Save | UI | MP seam | Risk |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Lifecycle / Session** | DONE | `GameState` (autoload) | phase (runtime), run id + location (persistent) | boot, menu intents, router | `phase_changed` | — | own | — | everything | `NewGameConfig` (P-20) | identity + location only; **never phase** (L-001) | menu, HUD context | server owns session | Med |
| **Input** | DONE | `InputService` (autoload) | context + gating (runtime) | device events | semantic intent, display labels | InputMap | own | — | all gameplay, UI | `project.godot` actions | no | key prompts | **intent = the command seam** | Low |
| **Localization** | DONE | `Localization` (autoload) | language (runtime) | CSV, saved pref | resolved strings | `locale/aetheria.csv` | own | — | all UI/content | CSV rows | pref via `SettingsStore` | every screen | client-local | Low |
| **Scene routing** | DONE | `SceneRouter` (autoload) | current scene key (runtime) | transition requests | `scene_changed` | registry | own, `GameState` location | — | Map, Main | `scene_key` registry | location only | loading/transition | client-local | Med |
| **Events** | DONE | `EventBus` (autoload) | none | emitters | global signals | — | — | — | all | — | no | no | replication subscribes here | Low |
| **Character** | DONE | `CharacterState` + template | identity/stats/realm/sect cache (persistent); view (presentation) | templates, domain events | `character_*` | template data | own | Data | Relationship, Sect, Combat, Quest, Story | `CharacterTemplateData`, `OriginData` (P-20) | yes | HUD, character screen | server owns characters | **High** |
| **Relationship** | DONE | `RelationshipService` / `RelationshipStore` | edge graph incl. bounded history (persistent) | domain events, authored rules | `relationship_changed` | config, rules | own | Character ids | Sect diplomacy, Dialogue, Quest, Story, Economy | `RelationshipConfigData`, `RelationshipRuleData` | yes | relationship screen (P-17+) | server owns the social graph | **High** |
| **Sect** | DONE | `SectService` / `SectStore` | roster/resources/territory/reputation/diplomacy (persistent) | membership + economy intents, catalog | `member_*`, `diplomacy_changed`, … | templates, Relationship store | own + `CharacterState` sect cache (derived, D-015) | Relationship (**hard**, D-037), Character | Faction, Quest, Story, Economy, Map access | `SectTemplateData`, `SectRankData`, `SectCatalog` | yes (P-23) | HUD chip, sect panel | server owns sects | **High** |
| **Faction / politics** | P-07 | `FactionState` + a faction service | influence/attitudes/goals/members (persistent) | sect state, relationships, sim ticks | `faction_shift` | Sect, Relationship | own | Sect, Relationship | World Sim, Quest, Story, Map access | faction data on sect templates | yes | faction UI (P-07) | server resolves politics | **High** |
| **World Simulation** | P-08 | a world-sim service | clock, per-actor sim state, pending transitions (persistent) | clock ticks, schedules, events | `world_tick`, `world_event_triggered` | Character, Sect, Faction, Relationship | their state via owners | all social systems + **seeded RNG (C-010)** | Quest, Story, Economy, Map | schedules, event data | yes | server advances the world | **High** |
| **Map / World** | DONE | `WorldRuntime` + `MapCatalog` | active map, player instance (runtime); location (persistent) | map data, exits, transitions | `map_entered/exited` | `MapData` | `GameState` location | SceneRouter, Character | Dungeon, Quest, Economy, Combat | `MapData`, `MapExit`, `MapCatalog` | location | map/atlas UI | server owns world placement | Med |
| **Combat** | P-09 | a pure-domain damage resolver | combatant runtime state; **no persistent state of its own** | **combat command (intent)**, stats, technique/equipment mods | `hit`, `damaged`, `enemy_died`, `xp_gained` | Character, Equipment, Technique, `DATA_SCHEMA` formula | nothing directly | Character, Data, **seeded RNG** | Progression, Quest, Economy, Boss | `SkillData`, `EnemyData` | no (derived) | combat HUD (P-09) | **command intent + server resolves** | **High** |
| **Enemy AI** | P-10 | `AIComponent` | AI runtime only | perception, spawn tables | movement/attack intents | Map, Character | own runtime | Combat, Map | Dungeon, Boss | `EnemyData`, spawn tables | no | no | server-authoritative AI | Med |
| **Level / XP** | P-11 | a progression domain service | xp, level (persistent) | `xp_gained` | `level_changed` | curve data | own | Combat | Combat stats, Quest | XP curve data | yes | progression UI (P-11) | server owns power | Med |
| **Cultivation** | P-12 | a cultivation domain service | realm, layer, progress (persistent) | tu luyện actions, breakthrough attempts | `realm_changed` | realm data, Knowledge | own | Character, Level (parallel) | **Map/Dungeon/World access**, Sect rank, Technique, Quest, Story | realm + breakthrough data | yes | cultivation UI (P-12) | server owns realm | **High** |
| **Knowledge** | P-19/20 | the story/quest state owner | discovered knowledge ids (persistent) | exploration, dialogue, records, purchase | `knowledge_gained` | — | own | Quest/Story | access gates, Technique, Crafting, Dialogue | knowledge ids on content | yes | journal/chronicle UI | server owns per-player knowledge | Med |
| **Item / Inventory** | P-13 | `InventoryComponent` | items (persistent) | pickup/use/drop | `item_*` | `ItemData` | own | Character | Equipment, Economy, Crafting, Quest | `ItemData` | yes | inventory UI (P-13) | server validates inventory | Med |
| **Equipment** | P-14 | an equipment component | equipped set (persistent) | equip/unequip | `equipment_changed` | `EquipmentData` | own | Item, Character | Combat (via formula) | `EquipmentData` | yes | equipment UI (P-14) | server owns loadout | Med |
| **Skill** | P-15 | `SkillComponent` | known skills, cooldowns (runtime) + unlocks (persistent) | skill intents | `skill_used` | `SkillData`, Technique gates | own | Combat, Cultivation | Combat, Pet, Boss | `SkillData` | unlocks only | skill UI (P-15) | intent + server resolve | Med |
| **Technique (công pháp)** | P-15 | a technique domain service | known techniques, compatibility (persistent) | learning, cultivation | `technique_learned` | `TechniqueData`, Knowledge | own | Cultivation, Knowledge | Skill, Combat, Economy, Story | `TechniqueData` | yes | technique UI (P-15) | server owns techniques | **High** |
| **Pet** | P-16 | a pet entity + ally AI | pet state (persistent) | taming/commands | pet events | `PetData` | own | Combat, AI | Combat | `PetData` | yes | pet UI (P-16) | server owns pets | Low |
| **NPC** | P-17 | reuses Character + shop service | shop stock (persistent) | interaction | `npc_interacted` | Character, Relationship, Sect | shop state | Character, Relationship, Sect | Dialogue, Quest, Economy | NPC content + shop data | yes | shop/NPC UI (P-17) | server owns stock | Med |
| **Dialogue** | P-18 | a dialogue runner | current node (runtime); choices → others' state | `npc_interacted`, player choice | `dialogue_chosen` | Relationship, Sect, Faction, Knowledge, flags | **via owners only** | NPC, Localization, all social | Quest, Story | `DialogueData` (keys) | no (choices land in owners) | dialogue UI (P-18) | client-local; outcomes authoritative | Med |
| **Quest** | P-19 | a quest FSM domain service | quest states + objective progress (persistent) | EventBus gameplay events | `quest_state_changed`, `reward_granted` | everything | own + grants via owners | Character, Relationship, Sect, Faction, World Sim, Map, Combat | Story, Economy | `QuestData` | yes | journal UI (P-19) | per-player personal state | **High** |
| **Story** | P-20 | a story/flag engine | chapter, flags, choices, **origin_id** (persistent) | quest/world outcomes, choices | `story_beat`, `chapter_entered` | all social + world + cultivation + knowledge | own flags | Quest + all social | World state changes | chapter/`OriginData` | yes | chronicle UI (P-20) | **personal story state — never shared** | **High** |
| **Dungeon** | P-21 | dungeon instance coordinator | run progress (runtime) | enter/clear | `dungeon_*` | `DungeonData`, Map, Combat | instance only | Map, Combat, Loot | Boss | `DungeonData` | checkpoint only | dungeon UI (P-21) | **party/instance state** | Med |
| **Boss** | P-22 | boss entity + phase logic | phase (runtime); defeat flag (persistent) | combat events | `boss_defeated` | `BossData` | defeat flag | Combat, AI, Dungeon | Story gating | `BossData` | defeat flag | boss presentation (P-22) | party/instance | Med |
| **Economy / Crafting** | P-13+ | a crafting/market domain service | player currency + recipes known (persistent) | gather/craft/trade intents | economy events | Item, Knowledge, Relationship, Sect | own | Item, Map, NPC, World Sim | Equipment, Sect contribution | recipes, resources, price data | yes | crafting/shop UI | server validates trades | Med |
| **Save / Load** | P-23 | `SaveService` | the snapshot itself | all persistent tiers | save/load events | every system's `to_dict` | every system's `from_dict` | all | all | migration data | **owns the format** | save/load UI (P-23) | same snapshots feed server storage | **High** |
| **UI** | DONE (foundation) | `UITheme` / `UIPalette` + screens | presentation only | views + intents | intents | views | **nothing gameplay** | Localization, Input | — | theme/asset paths | no | itself | client-local, never authoritative | Med |
| **Audio / VFX** | P-26 | audio/VFX services | presentation only | events | — | events | nothing | EventBus | — | asset refs | no | settings | client-local | Low |
| **Multiplayer readiness** | P-32 | — (audit only) | — | all seams | gap analysis | all | nothing | everything above | P-33/34 | — | — | — | the audit itself | **High** |
| **Multiplayer foundation** | P-33 | — | transport/authority scaffolding | intents | replicated state | persistent tiers | via owners | P-32 go | P-34 | — | — | — | the seam itself | **High** |

## 3. Implementation dependency ≠ content dependency

Two graphs, deliberately different. Confusing them is how teams build a story engine before the
systems its branches read.

**A. ENGINEERING dependency** (what must exist to compile and run): the matrix above. Example:
Combat needs Character + the damage formula + seeded RNG. It does **not** need Quest.

**B. PLAYER-FACING CONTENT dependency** (what must exist for a beat to be playable): Example: the
Act-II "choose a sect" beat needs Sect (06 ✔), Relationship (05 ✔), NPC (17), Dialogue (18) and
Quest (19) — five systems across four phases, even though no one of them depends on the others to
*run*.

Practical consequence: **narrative order does not dictate engineering order.** The roadmap is
sequenced by graph A; the acts are sequenced by graph B. Phase 27 (Vertical Slice) is the first
point where a graph-B path is fully walkable, which is exactly why it sits where it does.

## 4. Audit: the roadmap order (Audit W)

The brief's expected conceptual order was compared against `ROADMAP.md` phase by phase. It matches,
with one note worth recording: **Combat (09) and Enemy AI (10) sit before Level/XP (11) and
Cultivation (12)**. That is correct per graph A — XP has no source until combat emits `xp_gained`,
and cultivation gates content that does not exist until there is gameplay to gate. **No correction
to the engineering sequence was required.** (The poster's phase bands are not a planning source —
C-009.)

## 5. Cross-cutting invariants

- **One owner per state.** If two systems can write the same field, that is a defect (D-015 is the
  worked precedent: the sect roster is authoritative, `CharacterState.sect_id` is a derived cache).
- **Emitters never import listeners.** Everything crosses via `EventBus` or a domain signal.
- **Presentation never writes gameplay state.** UI reads views and sends intents.
- **Persistent tier only is saved.** Runtime/presentation are rebuilt (L-001).
- **No new autoload** without a `DECISIONS.md` entry. Budget: **5**.
- **No domain code calls a global `rand*()`.** Randomness is injected and seeded (C-010).
