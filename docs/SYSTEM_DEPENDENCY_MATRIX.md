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
| **Faction / politics** | DONE | `FactionService` / `FactionStore` | influence/goals/members/declared politics (persistent) | sect roster, relationship graph, sim ticks | `member_*`, `leader_changed`, `influence_changed`, `politics_changed` | Sect roster (authority, D-015), Relationship store | own + `CharacterState.faction_id` cache | Sect (**hard**), Relationship (**hard**, D-047), Character | World Sim, Quest, Story, Map access | `FactionTemplateData`, `FactionGoalData`, `FactionCatalog` | yes (P-23) | faction panel (D-042) | server resolves politics | **High** |
| **World Simulation** | DONE | `WorldSimulationService` / `WorldSimulationState` | clock, per-actor sim state (band/routine/location/`joined_tick`), pending event queue, carry-over debt, bounded event feed, **RNG stream state** (persistent) | explicit gameplay beats, schedules, scheduled events | `world_tick`, `world_event_triggered`, `actor_state_changed`, `actor_band_changed` | `CharacterRegistry`, Sect, Faction, Relationship | own + `CharacterState.sim_state` (derived cache, D-015 shape); everything else **via its owner's service** | Character registry, Sect, Faction, Relationship + **it INTRODUCED the deterministic RNG seam (C-010, first consumer)** | Quest, Story, Economy, Map, **Combat (reuses the seam)** | `WorldSimScheduleData`, `WorldSimActorData`, `WorldSimEventData`, `WorldSimCatalog` | yes | world date + last-event lines in the HUD (D-048); chronicle (P-20) | server advances the world | **High** |
| **Deterministic RNG** | **DONE** (introduced with World Sim, D-048) | `RngService` + `RngStream` (injected, **not** an autoload) | world seed + each stream's position **and draw count** (persistent) | a seed, a stream id | deterministic values | — | own stream state | — | **World Sim (P-08)**, Combat (P-09), Enemy AI (P-10), Economy drops, Dungeon | — | yes (seed + per-stream state) | never | server owns the seed | **High** |
| **Character registry** | **DONE** (D-048) | `CharacterRegistry` (owned by `WorldRuntime`) | `instance_id -> CharacterState` (persistent) | characters built from templates | — (no rules, no signals) | — | own collection only ("who exists") | Character | Sect, Faction, World Sim — all take their resolver from it | `CharacterTemplateData` | yes (`characters.by_instance_id`) | no | server owns the population | Med |
| **Map / World** | DONE | `WorldRuntime` + `MapCatalog` | active map, player instance (runtime); location (persistent) | map data, exits, transitions | `map_entered/exited` | `MapData` | `GameState` location | SceneRouter, Character | Dungeon, Quest, Economy, Combat | `MapData`, `MapExit`, `MapCatalog` | location | map/atlas UI | server owns world placement | Med |
| **Combat** | **DONE** (P-09, D-007) | `DamageRules` + `AttackStateMachine` + `CombatService` (pure domain) · `AttackComponent`/`HurtboxComponent`/`CombatHurtboxRegistry` (gameplay) · `CombatRuntime` (per-session node). **ANALYTIC HURTBOX MODEL** — no Area2D sensors (`COMBAT_DESIGN.md` §10a) | combatant runtime state; **no persistent state of its own** | **combat command (intent)**, stats, technique/equipment mods | `hit`, `damaged`, `enemy_died`, `xp_gained` | Character, Equipment, Technique, `DATA_SCHEMA` formula | nothing directly | Character, Data, **the RNG seam established in P-08** (own stream) | Progression, Quest, Economy, Boss | `SkillData`, `EnemyData` | no (derived) | health gauge on the D-050 foundation (P-09); target panel (P-10) | **command intent + server resolves** | **High** |
| **Enemy AI** | **DONE** (P-10) | `AiBrain` (pure domain state machine) + `AIComponent` (executes intents) + `Enemy` entity; spawned and ticked by `CombatRuntime` | AI runtime only — **no `CharacterState`**, nothing persistent | perception (scalars), spawn tables | movement/attack **intents** (never direct mutation) | Map, Combat, `RngService` (`enemy_ai` stream) | own runtime | Combat, Map, the P-08 RNG seam | Dungeon, Boss, Pet | `EnemyData`, `AiProfileData`, `EnemySpawnTableData` | no | target plaque + health gauge on the D-050 foundation | server owns the AI decision AND its resolution | Med |
| **Level / XP** | **DONE** (P-11, D-054) | `ProgressionService` (pure domain, the ONLY XP mutator) + `ProgressionRuntime` (7th `Main/Systems` sibling, no new autoload) | **`CharacterState.xp` only** — cumulative, persistent; **level is DERIVED, never stored** | `CombatRuntime.enemy_defeated(reward_id, xp_reward)` | `xp_gained(amount, reward_id)`, `level_changed(previous, current)` (one per grant, even across several thresholds) | `ProgressionCurveData` (max level is a data fact) | own `xp` only — writes nothing else | Combat (defeat event), Character (the subject) | Combat stats, Quest, Story | `ProgressionCurveData`, `EnemyData.xp_reward` | yes (`xp`; level re-derived on load) | gold level badge + XP meter in the HUD, one-shot level-up effect | **seam ready** — grant → authoritative result → event; `grant_for_defeat()` is where a server message would land | Med |
| **Cultivation** | **DONE** (P-12, D-058) | `CultivationService` (sole decider) + `CultivationRuntime` (per-session; signals `realm_advanced`, `meditation_*`) | realm, layer, progress (persistent) | tu luyện actions, breakthrough attempts | `realm_changed` | realm data, **Knowledge Core (P-12, read-only)** | own | Character, Level (parallel), **Knowledge Core (same phase)** | **Map/Dungeon/World access**, Sect rank, Technique, Quest, Story | realm + breakthrough data | yes | cultivation UI (P-12) | server owns realm | **High** |
| **Knowledge Core** | **DONE** (P-12, D-058) | **`KnowledgeService` / `KnowledgeStore`** (its own domain owner — NOT Story/Quest) + `KnowledgeRuntime` (`knowledge_gained`) | acquired knowledge ids (persistent) | grant intents from content producers | `knowledge_gained` | `KnowledgeData` ids | **own only** | Character (for the owning run) | **Cultivation, Technique**, Crafting, Dialogue, Quest, Story, access gates | `KnowledgeData` ids on content | yes | journal/chronicle UI (P-20) | per-player personal state | **High** |
| **Item / Inventory** | **DONE** (P-13, D-059) | `InventoryState` + `InventoryRuntime` (per-session; `item_gained`/`item_used`/`use_refused`) | items (persistent) | pickup/use/drop | `item_*` | `ItemData` | own | Character | Equipment, Economy, Crafting, Quest | `ItemData` | yes | inventory UI (P-13) | server validates inventory | Med |
| **Equipment** | **DONE** (P-14, D-060) | `EquipmentState` + `EquipmentRuntime` (`equipment_changed`) | equipped set (persistent) | equip/unequip | `equipment_changed` | `EquipmentData` | own | Item, Character | Combat (via formula) | `EquipmentData` | yes | equipment UI (P-14) | server owns loadout | Med |
| **Skill** | **DONE** (P-15, D-061) | `SkillRuntime` + `CastStateMachine` (`cast_started`/`cast_released`/…) | known skills, cooldowns (runtime) + unlocks (persistent) | skill intents | `skill_used` | `SkillData`, Technique gates | own | Combat, Cultivation | Combat, Pet, Boss | `SkillData` | unlocks only | skill UI (P-15) | intent + server resolve | Med |
| **Technique (công pháp)** | **DONE** (P-15, D-061) | `TechniqueService` (sole writer of `technique_ids`; `technique_learned` via `SkillRuntime`) | known techniques, compatibility (persistent) | learning, cultivation | `technique_learned` | `TechniqueData`, **Knowledge Core (read-only)** | own | Cultivation (P-12), **Knowledge Core (P-12)** | Skill, Combat, Economy, Story | `TechniqueData` | yes | technique UI (P-15) | server owns techniques | **High** |
| **Pet** | **DONE** (P-16, D-064) | `PetRuntime` (session) + `PetService` (rules) + the `Pet` entity with the shared `AIComponent` | `PetStore`: owned ids, XP per pet, active id (persistent); the body, health, recall cooldown (runtime) | befriend (interact), `pet_summon` | `pet_acquired` / `pet_summoned` / `pet_dismissed` / `pet_refused` / `pet_level_changed` | `PetData`, `PetCatalogData` | own (`PetStore.to_dict`) | Combat, AI, World (map signals), Input | Combat (reads `enemy_defeated`) | `PetData` | yes | one HUD prompt row (no pet panel) | server owns pets | Low |
| **NPC / Shop** | **DONE** (P-17, D-065) | `NpcRuntime` (session) + `ShopService` (rules) + `WorldNpc` bodies bound to registry `CharacterState`s | `ShopState`: remaining finite stock (persistent); the open shop, a gesture clock (runtime). Funds are NOT here: the currency item in `InventoryState` | interact (talk), buy / sell / close from the shop panel | local signals: `shop_opened` / `shop_closed` / `trade_done` / `trade_refused` / `npc_greeted` (no EventBus event: no cross-system consumer yet) | `ShopData`, `ShopCatalogData`, `CharacterTemplateData` | own (`ShopState.to_dict`) | Character registry, Inventory (`exchange`), Relationship (read-only), World (map signals) | Dialogue, Quest | shop content | yes | shop panel + named interact prompt | server owns stock and validates range | Low |
| **Dialogue** | P-18 (contract: D-066) | a per-session dialogue runtime + a pure-domain dialogue service | the open conversation: dialogue, node, speaker (runtime). **No persistent state, no flags** | interact (talk), choose / continue / leave | a local signal; an EventBus `dialogue_chosen` arrives with its first consumer (Quest, P-19) | Relationship (read), **Knowledge Core** (read) — NOT flags (Story's, P-20) | **via owners only**: `RelationshipService`, the Knowledge Core, `NpcRuntime` (shop handoff). Sect / Faction effects deferred to their first consumer | NPC, Localization, Relationship, **Knowledge Core** | Quest, Story | `DialogueData` (keys) | **no** (consequences are saved by their owners) | dialogue UI (P-18) | client-local cursor; the choice is an id-only intent the authority re-validates | Med |
| **Quest** | P-19 | a quest FSM domain service | quest states + objective progress (persistent) | EventBus gameplay events | `quest_state_changed`, `reward_granted` | everything | own + grants via owners (**knowledge via `KnowledgeService`**) | Character, Relationship, Sect, Faction, World Sim, Map, Combat, **Knowledge Core** | Story, Economy | `QuestData` | yes | journal UI (P-19) | per-player personal state | **High** |
| **Story** | P-20 | a story/flag engine | chapter, flags, choices, **origin_id** (persistent) — **NOT knowledge** | quest/world outcomes, choices | `story_beat`, `chapter_entered` | all social + world + cultivation + knowledge | own flags only (**knowledge via `KnowledgeService`**) | Quest + all social, **Knowledge Core** | World state changes | chapter/`OriginData` | yes | chronicle UI (P-20) | **personal story state — never shared** | **High** |
| **Dungeon** | P-21 | dungeon instance coordinator | run progress (runtime) | enter/clear | `dungeon_*` | `DungeonData`, Map, Combat | instance only | Map, Combat, Loot | Boss | `DungeonData` | checkpoint only | dungeon UI (P-21) | **party/instance state** | Med |
| **Boss** | P-22 | boss entity + phase logic | phase (runtime); defeat flag (persistent) | combat events | `boss_defeated` | `BossData` | defeat flag | Combat, AI, Dungeon | Story gating | `BossData` | defeat flag | boss presentation (P-22) | party/instance | Med |
| **Economy / Crafting** | P-13+ | a crafting/market domain service | player currency + recipes known (persistent) | gather/craft/trade intents | economy events | Item, **Knowledge Core (read-only, when a recipe is knowledge-gated)**, Relationship, Sect | own | Item, Map, NPC, World Sim, **Knowledge Core (P-12) for gated recipes** | Equipment, Sect contribution | recipes, resources, price data | yes | crafting/shop UI | server validates trades | Med |
| **Save / Load** | P-23 | `SaveService` | the snapshot itself | all persistent tiers | save/load events | every system's `to_dict` | every system's `from_dict` | all | all | migration data | **owns the format** | save/load UI (P-23) | same snapshots feed server storage | **High** |
| **UI** | DONE (foundation) | `UITheme` / `UIPalette` + screens | presentation only | views + intents | intents | views | **nothing gameplay** | Localization, Input | — | theme/asset paths | no | itself | client-local, never authoritative | Med |
| **Audio / VFX** | P-26 | audio/VFX services | presentation only | presentation cues | — | cues | nothing | the cue's own tier: direct signals for entity/session cues, EventBus only for world-scale cues (`PRESENTATION_ARCHITECTURE_CONTRACT.md` §10, D-057) | — | asset refs | no | settings | client-local | Low |
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

## 4b. Dependency topology audit (D-040)

A matrix can list dependencies that are individually sensible and collectively impossible. This
audit checks the one property the matrix cannot show at a glance: **does any phase depend on
authoritative state that only arrives in a LATER phase?** Two such defects were found and fixed
in D-040 (`CONTRADICTION_REGISTER.md` C-012, C-010).

| Edge | Direction | Verdict |
|---|---|---|
| P-07 Faction → P-08 World Sim | sim consumes faction state | OK |
| P-08 World Sim → P-09 Combat | combat reuses the RNG seam P-08 established | OK (fixed, C-010) |
| P-11 Level → P-12 Cultivation | parallel axes; neither blocks the other | OK |
| **P-12 Knowledge Core → P-12 Cultivation** | same phase; core lands first *within* the phase | **OK (fixed, C-012)** |
| **P-12 Knowledge Core → P-15 Technique** | technique reads a core that already exists | **OK (fixed, C-012)** |
| P-12 Cultivation → P-15 Technique | technique gates on realm | OK |
| P-15 Technique → P-16 Pet | pet skills reuse the technique/skill model | OK |
| P-17 NPC → P-18 Dialogue | dialogue needs someone to talk to | OK |
| P-18 Dialogue → P-19 Quest | quest choices surface through dialogue | OK |
| P-19 Quest → P-20 Story | story reads quest outcomes | OK |
| P-20 Story → P-21 Dungeon | dungeon content is story-placed | OK |
| P-12 Knowledge Core ← P-18/19/20 producers | **producers are later; that is correct** | OK — the core does not depend on them |

**The two defects that were real:**
1. **Knowledge was listed as owned by Story/Quest at P-19/20 while Cultivation (P-12) and
   Technique (P-15) already read it.** That is a backwards edge: P-12 cannot depend on P-19. Fixed
   by giving Knowledge its **own** owner (`KnowledgeService`/`KnowledgeStore`) landing in **P-12**.
   The content *producers* stay in P-18/19/20 — a core existing before its producers is the normal
   direction, and the inverse is what was broken.
2. **The RNG first consumer was named as Combat (P-09) while World Simulation (P-08) already
   required determinism.** Fixed: the seam is introduced in **P-08**, and P-09 reuses it.

**The rule this audit enforces from now on:** an earlier phase may never require authoritative
state owned by a later phase. If a design wants that, either the owner moves earlier (what
happened to Knowledge) or the dependency is not real.

## 4c. The deterministic RNG seam (frozen shape, D-040)

Introduced in **P-08**, consumed by P-09 onward. Not implemented by this document.

```
RUN / WORLD SEED
   ├── World Simulation stream
   ├── Combat stream
   ├── Enemy AI stream
   ├── Loot / Economy stream
   └── future subsystem / instance streams
```

Frozen properties: **deterministic · seeded · injectable · subsystem/stream-scoped · serializable
where required · presentation-independent · no global `rand*()` anywhere in domain code.**

**Why streams and not one generator.** With a single shared generator, adding one extra random
call in combat silently shifts every subsequent world-simulation roll — so a bug fix in one
subsystem changes unrelated outcomes, and "same seed → same world" stops being true. Per-stream
state makes each subsystem's sequence reproducible **independently**, which is what makes a
seeded replay, a regression test and (later) a server-advanced world all possible.

Deliberately NOT frozen: class names, the stream-id vocabulary, the generator algorithm, and the
serialized shape of stream state — those belong to the implementing phase.

**IMPLEMENTED in P-08 (D-048).** The decisions that were left open are now made:
- **Classes:** `RngService` (the seam, holding the world seed) + `RngStream` (one stream).
  Injected `RefCounted`s, not an autoload.
- **Stream ids:** `stream(StringName)` is generic and only `STREAM_WORLD_SIM` is named as a
  constant — a constant for a stream nothing draws from would be the speculative surface L-005
  forbids, so P-09 adds `STREAM_COMBAT` in the file that draws from it.
- **Algorithm:** a 32-bit Weyl counter through the `lowbias32` finalizer. Chosen over the
  engine's `RandomNumberGenerator` for ONE reason — the generator's state is part of our save
  format (§3b below), and an engine-internal state blob would tie a player's world to an
  implementation detail we cannot migrate.
- **Serialized shape:** `{ world_seed, streams: { stream_id -> { state, draws } } }`. The draw
  count is not needed to reproduce the sequence; it is kept because it is the one number that
  makes a determinism failure diagnosable — it distinguishes "a different value was drawn" from
  "a different NUMBER of values was drawn" (an extra call somewhere), which is the exact failure
  per-stream state exists to prevent.
- **Isolation is structural, not disciplinary:** each stream's starting state is derived by
  folding its id through the same mixer, so two ids under one seed are unrelated sequences
  rather than one sequence read at two offsets. A test drains one stream 1000 times and asserts
  another moves by zero values.

## 5. Cross-cutting invariants

- **One owner per state.** If two systems can write the same field, that is a defect (D-015 is the
  worked precedent: the sect roster is authoritative, `CharacterState.sect_id` is a derived cache).
- **Emitters never import listeners.** Everything crosses via `EventBus` or a domain signal.
- **Presentation never writes gameplay state.** UI reads views and sends intents.
- **Persistent tier only is saved.** Runtime/presentation are rebuilt (L-001).
- **No new autoload** without a `DECISIONS.md` entry. Budget: **5**. Neither the Knowledge Core
  nor the RNG seam is an autoload — both are injected domain objects, like `RelationshipService`.
- **No domain code calls a global `rand*()`.** Randomness is injected, seeded and stream-scoped
  (§4c, C-010).
- **No system mutates another system's authoritative collection.** Knowledge is the newest case:
  Dialogue/Quest/Story *grant* knowledge by calling `KnowledgeService`, and none of them keeps a
  private copy or a parallel flag (C-012). This is the same rule D-015 established for the sect
  roster vs. the character's derived cache.
- **No earlier phase may require state owned by a later phase** (§4b).
- **Per-session subsystems are torn down in exact REVERSE of the order they start in** — one
  ordered path in the bootstrap, never a second hand-written sequence (D-047 / L-030). The
  dependency column above *is* that order: a subsystem's state is defined in terms of the ones
  ended after it, so ending a dependency first drops state a dependent is still unwinding
  through.
- **A mutation that writes ONE fact into TWO stores may not "skip" the second store when its
  service is absent** — it fails closed (D-047). A skipped mirror that returns success
  manufactures exactly the divergence the "one owner per state" rule above exists to prevent,
  and the clearing path then refuses to act on the diverged state, making it permanent.
