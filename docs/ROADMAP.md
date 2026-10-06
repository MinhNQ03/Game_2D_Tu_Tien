# ROADMAP — Aetheria

> Phased plan. Phases are ordered by dependency, not by calendar. Each phase has an
> **exit criteria** — the next phase shouldn't start until it's met.
>
> Every phase respects the extensibility invariant (`docs/GAME_FLOW.md`) and the AI
> review protocol (`.kiro/steering/08-ai-review-protocol.md`). "Build passes" is never
> an exit criterion by itself.
>
> **35 phases (00–34).** Phase 00 (Foundation) is **CLOSED** (CI-verified on `651c16f`,
> 2026-10-02). Phase 01 (Core Framework) is **CLOSED** (CI-verified 2026-10-02). Phase 02
> (Player) is **CLOSED** (CI-verified 2026-10-02). Phase 03 (World / Map) is **CLOSED**
> (reopened for hardening — D-022 — then CI-verified 2026-10-03 on `53f342f`, all 9 gates
> green). Phase 04 (Character core + early UI/presentation foundation) is **CLOSED**
> (D-023 character core + D-024 UI hardening, both CI-verified on `7615d88`, all 9 gates
> green, 163 tests passed / 0 failed; D-025 close-out then removed a residual
> 5-ObjectDB / 1-resource test-exit leak and this doc drift). Phase 05 (Relationship core +
> early character visual pipeline) is **CLOSED** (D-026, CI-verified 2026-10-03 on `21ef622`,
> all 9 gates green). Phase 06 (Sect) is **CLOSED** (D-032, CI-verified 2026-10-03 on
> `b3c98cc`, all 9 gates green at the time; **final hardening D-037**, see below).
> **Phase 07 (Faction/Politics) is IMPLEMENTED (D-042)** — faction domain + deterministic politics
> rules + the first usable Faction UI; the §7 standings-representation question is pinned to
> relationship edges. **Hardened in D-047** (see below).
> **Phase 08 (World Simulation) is IMPLEMENTED (D-048)** — the world now evolves on explicit
> gameplay beats, deterministically from a seeded per-subsystem RNG stream, with Near/Mid/Far
> LOD, zero nodes for the background cast and zero per-frame work. It also introduced the
> deterministic RNG seam (D-040/C-010) that Phase 09 onward reuses, and `CharacterRegistry`.
> **Phase 09 (Combat) is IMPLEMENTED** — **D-007 is resolved as REAL-TIME TOP-DOWN ACTION
> COMBAT**, after being Open since Phase 0. A pure-domain `READY -> WINDUP -> ACTIVE ->
> RECOVERY` lifecycle with data-authored timing, ANALYTIC hit resolution against a session
> hurtbox registry (no physics sensors — L-016/L-017), crit from the seeded
> `RngService.STREAM_COMBAT`, `CombatRuntime` as the sixth per-session node, a real target in
> the hub map, the first health gauge on the D-050 UI foundation, and PERF-002.
> **Phase 10 (Enemy AI) is IMPLEMENTED** — `EnemyData` + `AiProfileData` +
> `EnemySpawnTableData` content; a pure-domain `AiBrain` (IDLE/PATROL/ALERT/CHASE/ATTACK/
> RECOVER/RETURN) that returns INTENTS, not vectors; `AIComponent` executing them through
> the same movement/attack seams the player uses; decisions throttled to the profile's
> interval and driven by ONE session callback for all creatures; determinism from
> `RngService`'s `enemy_ai` stream; the **Vụ Lang** frontier mist wolf authored into the
> field map via a spawn table; and the Phase-09 presentation debt paid (a visible swing arc
> plus a target plaque).
> **Phase 11 (Level/XP Progression) is IMPLEMENTED (D-054), hardened and CLOSED in D-055** —
> the first complete player-progression slice: a kill ANNOUNCES itself
> (`CombatRuntime.enemy_defeated`), `ProgressionRuntime` (a 7th per-session node, not an
> autoload) pays for it exactly once through a per-spawn reward ledger, `ProgressionService`
> writes the single stored number (`CharacterState.xp`), and **the level is DERIVED from
> cumulative XP and the authored curve, never stored**. Combat does not know a level exists.
> **Level is never an access gate** (C-002). D-055 added the structural guards the ownership
> model had been asserting only in docstrings, failed `reward_id == ""` closed, and gave the
> basic attack a HUD prompt — it had none, so the game's central verb was the one thing a
> player could not discover from the screen.
> **Phase 12 (Cultivation + Knowledge Core) — DONE (D-058).** **Phase 13 (Item) — DONE (D-059).**
> **Phase 14 (Equipment) — DONE (D-060).** **Phase 15 (Skill/Technique) — DONE (D-061).**
> Phase 16+ (Pet, NPC, Dialogue, Quest, Story, Dungeon, Boss, Save) is NOT STARTED.
> **Foundation hardening before it (not phases, no gameplay):** D-056 froze the
> production/multiplayer contract and the presentation spine; **D-057** froze the motion design
> contract (`MOTION_DESIGN_CONTRACT.md`) and corrected the HUD's composition by measurement;
> **D-057A** froze the xianxia identity contract and the reference library's authority
> (`XIANXIA_IDENTITY_CONTRACT.md`).
>
> **Phase 10 review pass (2026-10-05, D-053 — not a phase, no new scope):** four defects on a
> commit already green on all ten gates, two of them found by opening the playtest captures the
> commit itself had produced. Combat had feedback for the swing you MAKE and none for the hit
> you TAKE, so `DamageFeedback` now marks whatever was damaged (crimson, brighter gold on a
> crit — reading the `is_critical` flag `HurtboxComponent.damaged` had carried unread for a
> phase) and owns the entity's `modulate` channel entirely, which removed a `Color(...)`
> literal from `Enemy` — a gameplay entity authoring a presentation decision. The corpse tint
> was MEASURED and corrected — three times, because the first two corrections were scored
> against the floor's MEAN and the third test measured per fill tile, where a pale player over
> the dimmest moss broke it. The corpse now sits at least 0.12 of luminance below every floor
> tile AND stays blue-shifted, so the mark does not rest on hue alone. The target
> plaque, documented as showing a kill "briefly" while nothing implemented a timeout, now
> retires on a cancellable one-shot timer. And `tools/playtest_flow.gd` reports whether its
> screenshot actually CAUGHT the 0.16s flash, because a capture that silently lacks the thing
> its name promises is worse than a missing one. 586 tests, 0 leaks; every new guard verified
> to fail against the pre-fix code. **This clears `COMBAT_DESIGN.md` §10b entirely.**
>
> **Phase 07 hardening (2026-10-05, D-047 — not a phase, no new scope):** two lifecycle/invariant
> holes a green CI could not see. (1) The normal return-to-menu had drifted to tearing the session
> down in the WRONG order — it ended World and Relationship BEFORE Faction and Sect, freeing the
> player's `CharacterState` and the relationship graph while the two subsystems defined in terms
> of them were still unwinding. Fixed by DELETING the duplicate sequence: `Main.SESSION_START_ORDER`
> is now the single source of truth, one ordered function walks it backwards (**Faction → Sect →
> Relationship → World → GameState**), both entry points delegate, and the order is observable via
> `get_last_teardown_order()`. (2) `FactionService` politics mutation was fail-OPEN — with no
> `RelationshipService` the mirror was skipped and the call returned `true`, declaring a rivalry no
> edge backed and that `clear_politics()` could then never clear; the identical hole in
> `SectService._set_diplomacy()` was fixed with it. Also closed a pre-existing suite leak (a
> `RefCounted` reference cycle in a test fixture) that CI was exiting 0 on, and the existing
> headless gate now fails on the leak lines. No new autoload, **still 10 CI gates**, no Phase 08
> work. CI-verified with `ran 392 test(s): 392 passed, 0 failed`. **Process:** D-009 no longer
> holds — Godot 4.7 runs headless locally, so the whole gate set runs in ~3 minutes (L-031).
>
> **Phase 06 final hardening (2026-10-03, D-037 — not a phase, no new scope):** the sect core
> was audited for failure modes that a green CI cannot see, and six were closed: the Sect↔Sect
> diplomacy mirror now RETYPES an edge in place instead of removing and recreating it (a
> rejected flip used to destroy the edge it was "rolling back" — L-023);
> `SectRuntime.start_session()` is fail-closed and commits nothing until all nine steps succeed
> (it used to warn-and-continue into a half-session — L-025); New Game treats a relationship or
> sect failure as FATAL and unwinds in reverse dependency order (made the SINGLE teardown path
> in D-047);
> `SectState.from_dict()` validates `typeof()` before converting, so a corrupt payload is no
> longer coerced into an accepted state (L-024); the rank ladder's `authority` must increase
> strictly along the authored order; the catalog validates referential integrity of every
> declared ally/enemy (no more silent skipping of a dangling id); and the Sect panel renders
> resource names through `SECT_RESOURCE_*` localization keys instead of raw content ids. No new
> autoload, no new CI gate (**still 10**), no Phase 07 work.
>
> **Phase 06 follow-up (2026-10-03, D-033…D-036 — not a phase):** an engine-free GDScript lint
> gate that runs on save (`tools/gdscript_lint.py`) plus a compile check that actually detects a
> broken `class_name`, so the L-020 class of bug fails locally in a second instead of costing a
> CI round; the Phase-06 HUD made legible from MEASURED asset pixels (dark text plate, drawn
> keycap, text outline, nine-patched frames) and the Sect panel brought back on-screen; the
> camera now FOLLOWS the player with the hub/field maps authored 960×576 so the view fits inside
> the map; and Vietnamese is the default language with an in-game Settings screen whose choice
> persists (no new autoload). **CI gates: 9 → 10; CI-verified green on `d269077`.**
>
> **Visual follow-up (2026-10-03, D-028 — not a phase):** the production UI art was upgraded
> from the self-made prototype set to the CC0 **Xianxia Pixel Pack** UI (`assets/ui/xianxia/`)
> through the existing `UITheme`/`UIPalette` seam (no gameplay/domain change, no new systems).
> A full local asset audit (5 packs classified A/B/C/D) is recorded in `docs/ASSET_LICENSES.md`.
> This did not advance the phase sequence (Phase 06 had not started *at that time*).
>
> **Visual follow-up (2026-10-03, D-029 — not a phase):** the currently-visible WORLD (hub +
> field tileset) and CHARACTER sprite were redrawn in-place from the first flat prototype to a
> **production-foundation** tier (shaded + dithered tiles, a fully-outlined shaded top-down
> figure, and self-made Chinese garden-courtyard props as `Visual/Decor` decorations) — same
> files/dimensions/seams, pure presentation, no gameplay/domain/data change. Still self-made /
> project-owned; a bespoke art pass can replace it later. (Phase 06 had not started *at that
> time*.)
>
> **Close-out (2026-10-03, D-030 — not a phase):** Phase 05 close-out + visual-foundation
> hardening — documentation drift reconciled (this ROADMAP, `ARCHITECTURE`, `GAME_FLOW`,
> `06-art-assets` steering), **Continuous Visual Integration** adopted as policy (below), the
> D-029 visual contracts guarded by tests, and one small UI polish pass through the existing
> `UITheme`/`UIPalette` seam. No gameplay/domain change, no new systems. (Phase 06 had not
> started *at that time*.)
>
> **Reorder note (2026-10-02, Phase 1 kickoff):** the core social/world systems
> (Character / Relationship / Sect / Faction / World Simulation) were moved **earlier** —
> to phases 04–08, immediately after World/Map and **before Combat** — because they are
> the substrate that later systems (NPC, Dialogue, Quest, Story, and even enemy/boss
> flavor) read from (D-011, `docs/GAME_FLOW.md` §1b). This is a planning/sequencing change
> only; it does **not** authorize implementing those systems early. Older documents that
> referenced the previous numbering (Character=11 … Save=22 … MP=27) were updated to this
> numbering.

## Phase 00 — Foundation *(CLOSED — CI-verified 2026-10-02)*
Documentation, standards, process. Project renamed → `Aetheria` (D-006); 2D config cleaned,
3D physics removed (D-002); test framework = custom runner (D-004); bootable bootstrap
`main.tscn` (D-010); real smoke test + runner; core social/world design docs (D-011); CI
(D-012). **Status: MET** — GitHub Actions ran the full pipeline on `651c16f` with
`conclusion=success`. Evidence: `docs/PHASE_0_EXIT_CHECKLIST.md`.

## Phase 01 — Core Framework *(CLOSED — CI-verified 2026-10-02)*
The minimal correct runtime skeleton: application lifecycle + runtime session state
(`GameState`), semantic InputMap + input-gating ownership (`InputService`), `EventBus`,
`SceneRouter` (single safe transition entry), `Localization` (vi/en), a localized
main-menu shell (New Game / Quit), a first-scene/prologue shell, and bootstrap wiring.
Autoloads are the 5 justified in D-017 (`EventBus`, `GameState`, `Localization`,
`InputService`, `SceneRouter`). `Config` / `RNG` / `SaveService` are **deliberately
deferred** (D-017) — not part of Phase 01. No gameplay, no networking.
**Exit (MET):** boot → menu → new game → session init → first scene runs; GameState +
SceneRouter + EventBus + Localization + Input covered by headless tests + a real
application end-to-end flow test; each autoload justified in `DECISIONS.md`; CI green.
Hardened and CI-verified on the Phase 01 commits (see `docs/CHANGELOG.md`).

## Phase 02 — Player *(CLOSED — CI-verified 2026-10-02)*
Player entity via composition (`CharacterBody2D` + StatsComponent/HealthComponent/
MovementComponent) — no inheritance chain, no God object. Semantic input only (via
`InputService`); top-down 8-direction movement with normalized diagonals and collision;
stats from a `StatBlock` Resource (data, not magic numbers); health with enforced
invariants (`0<=hp<=max`, `died` once, DEAD terminal). A minimal, model-agnostic damage
rule lives once in `src/domain/combat/damage_rules.gd` (NOT a combat system — D-007 was still
Open). A Training Dummy (same components, no AI) and a playable **Player Sandbox** scene
prove a bidirectional damage exchange. The player is modeled as a Character conceptually
(Phase 04): authoritative numbers are data, the node is a runtime view, so Phase 04 binds
the same composition to a `CharacterState` without a rewrite (D-020).
**Exit (MET):** player moves and takes/returns damage against a dummy; Stats/Health/Movement
and the damage rule unit-tested; player+dummy integration + a real-application player E2E
(New Game → sandbox → move → attack → death → cleanup) green in CI. The sandbox is a
*temporary Phase-02 gameplay-validation* first scene; Phase 03 replaces it with a real map.
No combat system, no AI, no inventory/equipment/skill/cultivation, no networking, no
save/load, no new autoloads (D-003 / D-005 / D-007 remain Open).

## Phase 03 — World / Map
MapData-driven maps, SceneRouter transitions, a hub map + one field map. Clean
load/unload (no leaked nodes/signals). Uses stable `world_id` / `map_id` / `scene_key`.
**Exit:** move between ≥2 maps repeatedly with no leaks; map-transition tests pass.

**Implementation (2026-10-02, D-003 resolved / D-021):** `MapData` + `MapExit` resources
(`src/data/maps/`), two authored maps `data/maps/map_hub.tres` + `map_field.tres`, a
`WorldRuntime` node under `Main/Systems` (not an autoload) that registers each map's
`scene_key` with SceneRouter, owns ONE persistent per-session Player, and resolves
transitions; two content scenes `src/gameplay/maps/hub_map.tscn` + `field_map.tscn`
(`MapBase` + `MapExitZone`, semantic `interact` exits via InputService, prototype vector
art). New Game now enters the hub map (the Phase-02 sandbox is retained but no longer first
scene). Tests: `tests/unit/world/test_map_data.gd`, `tests/integration/test_map_transitions.gd`
(no-leak), `tests/gameplay/test_map_scenes.gd` (structure), and the dedicated E2E
`tests/e2e/run_world_flow.gd` (9th CI gate).

**Reopen / hardening (2026-10-03, D-022):** `MapData` became the full source of truth
(`scene_path`, `bounds`, `default_spawn_id`, exit `id`s) + a data-driven `MapCatalog`;
`WorldRuntime` loads only the catalog (no hard-coded paths); `MapExitZone` carries only
`exit_id`; camera limits derive from `MapData.bounds`; the spawn contract fails loud; map
transitions are transactional (rollback on failure); real self-made prototype pixel-art
replaces the Polygon2D placeholders (`Sprite2D` player + `TileMapLayer` tileset, 16px); the
world E2E drives the REAL input pipeline across 20 round trips with per-round + no-leak
invariants. **CLOSED** — all 9 CI gates green on `53f342f` (2026-10-03).

> **Core social/world systems come next (Phases 04–08), BEFORE Combat and before
> NPC/Dialogue/Quest/Story**, because those depend on them (D-011, `GAME_FLOW.md` §1b).

## Phase 04 — Character System
Data-driven Characters as core domain state (`docs/CHARACTER_SYSTEM.md`):
`CharacterTemplateData` + `CharacterState`, 3-tier state (persistent/runtime/presentation),
the Player node as a *view* bound to one authoritative `CharacterState`. Phase 04 ALSO lays
the first UI/presentation foundation (shared theme, main-menu presentation pass, in-map HUD
showing the character's identity, input display labels, data-driven camera framing) and makes
the session start map data-driven (`MapCatalog.start_map_id`). See D-023.
Scope guard: cultivation fields are CONTRACT only; NO Relationship/Sect/Faction/WorldSim/
Combat/Inventory/Skill/Quest/Dialogue/Save/Networking.
**Exit (status, D-023):** add a character purely via data ✅ (`player_default.tres`);
`CharacterState` round-trips through `to_dict/from_dict` ✅ (save seam; `SaveService` is
Phase 23); life-state ALIVE→DEAD transitions + round-trip ✅; no presentation leaks into the
persistent tier ✅ (tested); Player bound to ONE state, not recreated on map swap ✅ (world
E2E, 20 round trips); UI never hard-codes keys/user text ✅.
**UI hardening (reopen, D-024):** the menu + HUD now use REAL project-owned pixel-art 9-slice
assets (framed panels, per-state buttons, graphic key badges, title treatment, framed HUD) via
a shared `UITheme`/`UIPalette` + reusable components — no longer default-Godot controls. The
preferred CC0 pack (tiopalada Mana Soul GUI) is recorded but not bundled (itch.io not
auto-downloadable).
**Close-out (D-025):** CI is green on `7615d88` (all 9 gates, 163 tests passed / 0 failed).
A residual the green CI still printed at test-process exit — `5 ObjectDB instances leaked` +
`1 resource still in use` — was root-caused (a `--verbose` CI diagnostic, steering 10 §1.3)
to three un-freed `InputService` Nodes in `tests/unit/core/test_input_display_label.gd` (an
unfreed `Node` pins its GDScript + native class; L-019) and fixed (`svc.free()` in each
method). **Phase 04 is CLOSED.** Phase 05 (Relationship) is NOT STARTED.

## Phase 05 — Relationship System *(CLOSED — CI-verified 2026-10-03 on `21ef622`, D-026)*
Serializable relationship graph (`docs/RELATIONSHIP_SYSTEM.md`): `RelationshipEdge` with
affinity/trust/respect/fear/rivalry/debt + type; Char↔Char, Player↔Char, Char↔Sect.
Data-driven dimension config (`RelationshipConfigData`), a single mutation path
(`RelationshipService`) with clamp + bounded history + a domain `relationship_changed`
signal, a deterministic event→delta rule contract (`RelationshipRuleData`), a canonical
`RelationshipStore` (indexed by edge id + endpoint, symmetric canonicalization, signed-debt
perspective), and a `RelationshipRuntime` node under `Main/Systems` (NOT an autoload) that
survives map swaps. Phase 05 ALSO starts the **early character visual pipeline**
(presentation-only): `CharacterVisualProfileData` + a `CharacterVisualComponent` reading
movement/facing, the Player wired to its template `sprite_set_ref`, 4 archetype visual
profiles, and a preview scene — plus the design anchors `docs/CHARACTER_ART_BIBLE.md` and
`docs/NARRATIVE_DIRECTION.md`.
Scope guard: structural Character+Sect endpoints only (no real SectState — Phase 06); NO
NPC/Dialogue/Quest/Story/Faction/WorldSim/Combat/Inventory/Save/networking; NO new autoload;
the current game flow (Menu → New Game → Hub ↔ Field → Menu) is unchanged and no preview/
sandbox becomes the first scene.
**Exit (MET):** edges create/update/query + round-trip save; event→delta deterministic;
symmetric + debt semantics tested; RelationshipRuntime persists across hub↔field (world E2E,
20 round trips) and is NOT an autoload; character visual pipeline loads 4 profiles from data +
the player renders its `sprite_set_ref`; the current game flow + first scene are unchanged.
All 9 CI gates green on `21ef622` (2026-10-03). No new autoload; SECT endpoints structural-only
(Phase 06 adds the real `SectState` + referential validation).

## Phase 06 — Sect System *(CLOSED — D-032; CI-green on `b3c98cc`, 2026-10-03)*
Core sects (`docs/SECT_SYSTEM.md`): `SectTemplateData` + `SectRankData` + `SectCatalog` (data);
`SectState`/`SectStore`/`SectService` (domain) with membership/ranks, resources/territory/
reputation/influence, and alliances/enemies mirrored (transactionally) as symmetric Sect↔Sect
relationship edges. Canonical membership = sect roster (D-015); `CharacterState.sect_id`/
`sect_rank` are a derived cache the service keeps in sync. `SectRuntime` (node under
`Main/Systems`, NOT an autoload) owns the per-session store+service, enrolls the player into the
authored start sect, and survives map swaps. Continuous Visual Integration: a HUD sect chip + a
toggleable `SectPanel` (semantic `sect_panel` action) + a hub banner, all localized vi+en, no
raw ids, in the live Xianxia UI. Content: `sect_azure_cloud` (player start) + `sect_crimson_flame`
(enemy). Scope guard honored: NO Faction/Politics (Phase 07), WorldSim (Phase 08), Combat, NPC,
Save, networking; no new autoload.
**Exit (MET):** a sect is added via data only (new `.tres` + catalog entry); `SectState`
round-trips through `to_dict`/`from_dict`; membership stays in sync with `CharacterState` and the
roster wins on drift; the alliance/enemy mirror stays consistent with the relationship graph
(rollback on failure); domain + runtime + localization tests pass and the world/map E2E asserts
the player's sect is live + visible + survives map round trips. CLOSED on the CI-green commit.

**Final hardening (D-037):** closed six failure modes a green CI could not see — a
non-destructive in-place diplomacy retype, a fail-closed `start_session()`, a fatal + unwinding
New Game path, strict `typeof()` validation at the `from_dict` boundary, a strictly increasing
rank ladder, catalog referential integrity for declared diplomacy, and localized resource names
in the Sect panel. Tests expanded in place; **CI still 10 gates**; no new scope.

**Follow-up (D-038):** four residual issues — `clear_diplomacy()` made transactional (the
REMOVE leg was still inverted), authored default diplomacy required to be symmetric and
non-conflicting across the pair, a working character resolver required at the runtime boundary,
and **test integrity**: a test method that aborts on a VM error was being reported as PASS, so
the existing headless gate now fails on any `SCRIPT ERROR:`. Still 10 gates, no new scope.
CI-verified green on `1dabdba`: `ran 282 test(s): 282 passed, 0 failed`.

**MASTER GAME DESIGN FREEZE v2.1 (2026-10-04, D-039 — documentation only, NOT a phase):** the
world, narrative, cultivation, combat, economy, social, map/dungeon, UI and dependency design were
audited and frozen BEFORE the content-bearing phases begin. Thirteen documents; master index
`docs/GAME_DESIGN_FREEZE.md`. The audit found **eleven real contradictions already present in the
repository** (`docs/CONTRADICTION_REGISTER.md`) — including the premise-breaking one where the
narrative promised the player "no sect standing" while the build enrolled them into a sect on New
Game (C-003), and the realm ladder, which was still the conventional Luyện Khí/Trúc Cơ *example*
in steering while nothing had actually been authored (C-001). **No gameplay code, no runtime
behaviour change, no new autoload, no networking, no phase renumbering** — the engineering
sequence below was audited (Audit W) and required no correction.

## Phase 07 — Faction / Sect Politics *(IMPLEMENTED — D-042)*
Internal factions + emergent politics (`docs/SECT_SYSTEM.md` §7) in their OWN domain:
`FactionGoalData`/`FactionTemplateData`/`FactionCatalog` (data); `FactionState`/`FactionStore`/
`FactionService` (domain); `FactionRuntime` (a node under `Main/Systems`, started LAST because it
reads the sect store + the relationship graph, ended FIRST on an unwind); `SectPoliticsView` +
`FactionPanel` (presentation, semantic `faction_panel` action, in the D-041 visual language).

**The §7 representation question is PINNED (D-042):** Faction↔Faction and Faction↔Player
standings are **relationship edges** (`RelationshipEndpoint.Kind.FACTION`), NOT inline scalars.
The §7 sketch's `attitude_toward_player`/`attitudes_toward_factions` are dropped — `affinity` and
`rivalry` are two of the six frozen dimensions (CL-12), so a faction-side copy would be a second
source of truth for the same question (the defect D-015 undid for membership). `FactionState`
carries only the DECLARED relation, mirrored transactionally and non-destructively (L-023).

Rules shipped (deterministic, explicit tie-breaks, **no RNG** — that seam is Phase 08's, D-040):
`influence_share`, `dominant_faction_of`, `is_contested`. Membership defers to the sect roster
(D-015) with one seat per sect, which is what makes `CharacterState.faction_id` a valid single
value with exactly one writer. Content: three Thanh Vân Tông factions from `WORLD_BIBLE` §8 — a
real disagreement with no villain (C-005).

Scope guard honored: **Phase 07 enrols nobody** (the C-003 guard — the start sect is a scaffold,
not an authored political identity); NO WorldSim (Phase 08), Combat, NPC, Save or networking; no
new autoload (D-017 budget still 5); `SectState` unchanged.

**Exit (MET):** a multi-faction sect is authored via data only (new `.tres` + catalog entry);
influence changes produce documented, deterministic outcomes asserted by exact value;
`FactionState` round-trips byte-stably and `from_dict` is strictly-typed fail-closed; tests cover
the membership authority, the non-destructive mirror (object identity + surviving dimensions and
history), the determinism, and a no-duplication guard on the serialized shape.
**Hardening (D-047):** closed the two remaining lifecycle/invariant holes — a normal return to
menu that tore the session down in the wrong order (now ONE ordered teardown path, observable and
regression-tested), and a politics mutation that was fail-OPEN without the relationship graph
(now a precondition, with the identical hole in the sect mirror fixed with it). Tests expanded in
place plus one new bootstrap test file; **CI still 10 gates**; no new scope.
**NOT verified:** no runtime screenshot of the faction panel exists — a headless run renders
nothing, so on-screen composition is still asserted structurally and by the gates only.

## Phase 08 — World Simulation *(IMPLEMENTED — D-048)* *(+ the deterministic RNG seam)*
LOD simulation (`docs/WORLD_SIMULATION.md`): Near/Mid/Far from the real `MapData.exits` graph;
schedule/clock/event/state-transition drivers; promotion/demotion; seeded determinism;
save-resumable. Shipped as data (`WorldSimScheduleData`/`WorldSimActorData`/`WorldSimEventData`/
`WorldSimCatalog`), domain (`RngStream`/`RngService`/`WorldClock`/`WorldSimActor`/
`WorldSimulationState`/`WorldSimulationService` + `CharacterRegistry`), runtime
(`WorldSimulationRuntime`, the 5th node under `Main/Systems`, started LAST and ended FIRST), and
a minimal HUD surface (world date + the last world event).
**This phase INTRODUCED the deterministic RNG seam** (D-040 / C-010): one run/world seed fanning
out into per-subsystem streams, injectable, no autoload, no global `rand*()`
(`docs/SYSTEM_DEPENDENCY_MATRIX.md` §4c). Stream isolation is a property of CONSTRUCTION — each
stream's start is derived from `(seed, stream_id)` — and is asserted: 1000 draws on one stream
move another by zero values. Later phases reuse the seam (`stream(id)` is generic; only
`STREAM_WORLD_SIM` is named, so P-09 adds `STREAM_COMBAT` where it draws from it).
**The decision everything rests on:** an actor's activity is a PURE FUNCTION of
`(tick − joined_tick, schedule)`, not a stepped index — so NEAR/MID/FAR compute the same answer,
the band controls only how often the simulation LOOKS, and promotion is lossless by
construction. Zero per-frame work anywhere (guarded by a source-reading test); zero nodes for
the cast in ANY band; events mutate through `SectService`/`FactionService`/`RelationshipService`
and never touch their state directly.
**Exit (MET):** a seeded K-tick run reproduces an identical world twice and a different seed
produces a different one; `save → load → advance K` == `advance K`; FAR → MID → NEAR → MID → FAR
preserves the record and a FAR actor is never behind an observed one; `a + b` ticks == `a+b`
ticks with the clock exactly as old as the time it was given; a malformed snapshot leaves the
simulation byte-identical; 200 actors × 300 ticks creates zero nodes and a 10× FAR population
does not change the per-tick cost (**PERF-001**); and the real application advances the world
across 20 map transitions with a non-empty event feed and no raw id in the HUD.
**NOT verified:** the HUD's two new lines have not been seen on screen (a headless run renders
nothing). **Honest gaps:** the shipped two-map world has no FAR actors (hub and field are
adjacent; FAR arrives with the third map, and all three bands are covered by unit tests), and
nothing renders the simulated cast yet — NPC presentation is P-17.

## Phase 09 — Combat
Single documented damage formula (domain, pure), Hitbox/Hurtbox, basic attack. **Consumes the
deterministic RNG seam established in Phase 08** on its own stream — it does not introduce a
second RNG (D-040 / C-010). Combat emits events only. Timing model decided here (D-007).
**Exit:** deterministic damage from data; damage/combat unit + integration tests pass.

## Phase 10 — Enemy AI
EnemyData-driven enemies, AIComponent with controlled tick rate, spawn tables.
**Exit:** add a new enemy via data only; AI tick-rate measured; no per-frame churn.

## Phase 11 — Progression ✅ IMPLEMENTED (D-054)
XP curve, level. Reacts to combat events.
**Exit:** XP → level works; serializable; tests pass. — **met.** `ProgressionCurveData` authors
the curve as content (the maximum level is a data fact, not a constant); `ProgressionService`
is the single mutator; `CharacterState.xp` is the only stored progression number and the level
is DERIVED from it; `ProgressionRuntime` is the 7th `Main/Systems` sibling (no new autoload),
started last and torn down first; `EnemyData.xp_reward` is the whole reward seam. The player
sees a gold level badge and an XP meter, and a level-up plays a one-shot celebration. Verified
by 664 suite tests, all three E2E processes, and a real-app playtest run that kills a creature
with real attack keys and observes `xp 0 → 25 (level 1 → 2)`.
**Level is NOT a gate** (C-002) — the service exposes no content ids, no unlock list and no
gate query, and `MapData` still has no `min_level`.

## Phase 12 — Cultivation *(+ Knowledge Core substrate)*
Cảnh giới / tu luyện breakthrough rules (the second progression axis, distinct from level).
Gates content/capability, not just numbers (`.kiro/steering/02-game-design.md`). The frozen
hierarchy is `docs/PROGRESSION_CULTIVATION_DESIGN.md` §2 (CL-02).

**Also lands here: the KNOWLEDGE CORE substrate** (D-040 / C-012) — `KnowledgeStore` +
`KnowledgeService` with its own authoritative ownership: named ids, acquired state, a
deterministic grant path, query, the persistence boundary, and a `knowledge_gained` event. No
autoload. It lands here because Cultivation (this phase) and Technique (P-15) **read** it, so an
owner arriving at P-19/20 would be a backwards dependency. **Scope guard: this does NOT mean
building a story or quest engine in Phase 12** — the core is a store, a service, a grant path and
an event; its content producers arrive in P-18/19/20.

**Exit:** cultivation → realm unlocks work; serializable; breakthrough rules tested. Knowledge
Core: grant/query/persist round-trips, only the service mutates the collection, and a
cultivation prerequisite reads it — all tested.

## Phase 13 — Item
InventoryComponent (serializable), item pickup/use, ItemData.
**Exit:** add/use/drop items via data; inventory ops unit-tested; serializes/restores.

## Phase 14 — Equipment
EquipmentData, equip/unequip applying stat modifiers through the damage formula.
**Exit:** equipment changes damage deterministically; covered by tests.

## Phase 15 — Skill / Technique
SkillComponent, SkillData (active/passive), cooldowns, mana/linh khí cost, công pháp
gating of usable skills. **Technique/Skill CONSUMES Knowledge prerequisites** through the
Knowledge Core established in Phase 12 — read-only; it never keeps its own copy (D-040 / C-012).
Technique compatibility **and incompatibility** are authored data
(`docs/COMBAT_DESIGN.md` §5).
**Exit:** add a skill via data; cooldown/cost/gating tested; a knowledge-gated technique is
correctly withheld and then granted when the knowledge is acquired.

## Phase 16 — Pet
PetData, pet as an Entity with ally AIComponent; follows/assists in combat.
**Exit:** add a pet via data; pet state serializes; combat assist tested.

## Phase 17 — NPC
NPC interaction & services (shops) built **on** the Character/Sect/Relationship systems. NPCs and
their content may **expose knowledge opportunities** (a record to read, someone who will explain
something) — exposing an opportunity, not owning knowledge state (D-040 / C-012).
**Exit:** interact + trade; shop state serializes; standing uses the relationship graph.

## Phase 18 — Dialogue
DialogueData (localization keys), dialogue runner, choices feeding story + relationship +
sect state. **PRODUCES knowledge** — a dialogue may grant knowledge, always by calling
`KnowledgeService`, never by writing a private flag (D-040 / C-012). It may also **read**
knowledge to gate lines.
**Exit:** branching dialogue in `vi` + `en`; choices set flags/relationship deltas; a dialogue
grant is visible through the Knowledge Core, not a local copy; tested.

## Phase 19 — Quest
Quest FSM (domain), QuestData, objectives driven by EventBus; quests arise from and affect
characters/sects/politics. **PRODUCES and READS knowledge** through `KnowledgeService`, which is
what enables alternate knowledge-based quest solutions (D-040 / C-012).
**Exit:** add a quest via data; full lifecycle incl. serialize mid-quest; a knowledge-gated
alternate solution works; tested.

## Phase 20 — Story
Story/flag engine; branches read character/sect/faction state + flags; chapter loop +
world-state-change feedback (`docs/GAME_FLOW.md` §1b). **PRODUCES and READS knowledge** through
`KnowledgeService` — **Story does NOT own knowledge** and must not shadow it with story flags
(D-040 / C-012). Historical/record content is the main late-game knowledge producer.
**Exit:** a branch diverges on a prior choice/relationship/faction state; chapter
transition works; tested.

## Phase 21 — Dungeon
DungeonData, instance modifiers on top of map+combat+loot.
**Exit:** add a dungeon via data; clear/exit cleanly; tested.

## Phase 22 — Boss
BossData with phases, boss AI; chapter-gating defeat.
**Exit:** add a boss via data; phases trigger; `boss_defeated` gates chapter; tested.

## Phase 23 — Save / Load
Full versioned save/load across all systems (incl. character/relationship/sect/world-sim);
migration framework. Save format decided here (D-005). See `SAVE_FORMAT.md`.
**Exit:** save/load round-trips every system's state; a v1→v2 migration demonstrated;
save/load tests pass.

## Phase 24 — Localization
Full `vi`/`en` content pass; verify no hard-coded strings; font glyph coverage. (The
localization *foundation* and mechanism land in Phase 01 / D-008; this phase is the full
content sweep.)
**Exit:** key-coverage test green for both languages; no literal UI strings in code.

## Phase 25 — UI Consolidation / Production Polish
**This is NOT where production UI begins.** Under Continuous Visual Integration (below), each
feature phase already ships the first usable visual treatment of its own UI, and the UI
foundation (`UITheme`/`UIPalette` + reusable components + the CC0 Xianxia asset set) is live
from D-024/D-028. Phase 25 is the *final consolidation/polish* pass over everything that was
built incrementally — NOT a rescue rewrite. It covers:
- cross-screen consistency (one coherent tu-tiên language across every screen built so far),
- a UX audit (navigation, modal ownership on the Phase 01 input-gating rule, flow friction),
- accessibility / readability (contrast, font sizing, Vietnamese + English legibility),
- responsive / layout behaviour (anchors, safe-area, resolution scaling),
- asset cleanup (retire leftover placeholders, dedupe, confirm provenance),
- visual rhythm (spacing/margins/hierarchy harmonised project-wide),
- final polish.
**Exit:** every screen built in earlier phases is consistent, navigable and readable; UI never
drives gameplay truth; no placeholder-only screen remains; tests pass.

## Phase 26 — Audio / VFX
Music, SFX, feedback, transition polish.
**Exit:** audio/VFX hooks event-driven; no per-frame waste; smoke pass.

## Phase 27 — Vertical Slice
One cohesive end-to-end slice (prologue → village → quest → combat → progress → save) using
real systems, to validate the whole flow.
**Exit:** the slice is playable start-to-finish offline; no placeholder-only systems in it.

## Phase 28 — Full Audit
Cross-system audit: architecture boundaries, state ownership, determinism, doc consistency,
test coverage of high-risk areas.
**Exit:** audit report with no unresolved critical findings.

## Phase 29 — Performance
Profiler-driven only. Pooling where churn is proven. Each optimization logged in
`PERFORMANCE.md` (problem/cause/solution/impact/measurement).
**Exit:** frame-time/allocation budgets met on target hardware; optimizations logged.

## Phase 30 — Release Candidate
Build pipeline, export presets, credits (asset attributions from `ASSET_LICENSES.md`),
final regression + smoke pass.
**Exit:** reproducible export; all attributions satisfied; regression suite green.

## Phase 31 — Offline Release
Ship the offline game. Offline remains the source of truth.
**Exit:** released build tagged; post-release monitoring/debug playbook in place.

## Phase 32 — Multiplayer Readiness Audit
*Research + readiness only, still no shipped networking.* Validate the Stage-2 seams hold
(serializable player/world/inventory/progression **and** character/relationship/sect/
faction/world-sim state, in persistent/runtime/presentation tiers; command intents;
authoritative-state boundary). See `MULTIPLAYER_PLAN.md`.
**Exit:** documented gap analysis per seam + a go/no-go recommendation. No networking
dependency merged into the offline game.

## Phase 33 — Multiplayer Foundation
*Only if 32 is go.* Transport/authority scaffolding behind the existing command-intent and
authoritative-state seams. Domain rules remain transport-agnostic.
**Exit:** a vertical networked prototype of one seam, domain code unchanged in substance.

## Phase 34 — Multiplayer Gameplay
*Only if 33 succeeds.* Extend networking across the authoritative systems incrementally.
**Exit:** co-op/PvE slice runs authoritatively; offline remains fully playable.

## Continuous Visual Integration

Binding policy (adopted D-030). Visuals are grown incrementally alongside features — they are
NOT deferred to a single late phase.

- **UI and assets are upgraded incrementally.** Do not wait for Phase 25.
- **Each feature phase owns the first usable visual treatment of its own feature.** When a
  gameplay feature actually exposes something to the player, that feature's UI/visual is done
  **in that same phase** — not stubbed now and dressed later.
- **No placeholder chains.** Do not build placeholder UI → placeholder UI → a Phase-25 rewrite.
- **Replace by layer, not by rewrite.** Prefer swapping a single asset/component/theme token
  over rewriting the whole UI; `UITheme` / `UIPalette` / the reusable components remain the
  abstraction seam that makes a per-layer swap possible.
- **Asset replacement never changes gameplay/domain truth.** A visual swap is presentation-only
  (`.kiro/steering/03-architecture.md`); domain/data stay authoritative and untouched.
- **Assets are chosen per domain.** Character / world / UI / VFX / icons are each selected to fit
  the tu-tiên domain; do NOT force one giant asset pack to be the single source for the whole
  game, and never assemble a collage of mismatched packs.
- **Phase 25 is consolidation/polish, not a rescue rewrite** (see Phase 25 above).

Per-phase examples (illustrative — never force a phase to build presentation it doesn't need):
- **Phase 06 (Sect):** sect-related UI/visual treatment *only if* the feature actually exposes
  it to the player.
- **Phase 07 (Faction/Politics):** faction/politics panels if needed.
- **Phase 09 (Combat):** combat HUD / hit feedback / VFX if combat exposes presentation.
- **Phase 13 (Item):** inventory UI. **Phase 14 (Equipment):** equipment UI.
- **Phase 15 (Skill):** skill UI. **Phase 17 (NPC):** NPC/shop UI.
- **Phase 18 (Dialogue):** dialogue UI. **Phase 19 (Quest):** quest UI.
- **Phase 20 (Story):** story UI.

### Strengthened by D-056 — the PRESENTATION gate and the per-phase seeds

Continuous Visual Integration now has a **gate** (`docs/PHASE_EXECUTION_PROTOCOL.md` §7b) and
a **contract** (`docs/PRESENTATION_ARCHITECTURE_CONTRACT.md`).

**Every phase from P12 on is closed across NINE dimensions, and green CI is not one of them:**
DESIGN · CODE · TEST · PLAYER EXPERIENCE · UI · **VISUAL / PRESENTATION** · PERFORMANCE ·
CLEANUP · DOCS (gate-by-gate evidence: `docs/PHASE_EXECUTION_PROTOCOL.md` §1).

Three rules bind every phase from P12 on:

* **Every gameplay phase leaves behind at least one REUSABLE player-facing presentation
  capability** when its feature has a visible gameplay consequence — a seam the next feature
  reuses, not a bespoke effect.
* **FOUNDATION FIRST, CONTENT SECOND.** The phase that introduces a *category* builds the seam
  before the content explosion. First skill → skill presentation seam → second skill reuses it.
  First NPC → locomotion/reaction seam. First boss → phase/telegraph seam. **Never** boss A
  bespoke, boss B bespoke, boss C copies B.
* **Prove reuse with a concrete SECOND consumer** — different assets, different frame counts,
  the same contract. One actor is a feature; two is a seam.

The seam D-056 itself shipped: a **semantic ACTION layer** on `CharacterVisualComponent`
(locomotion and action as two layers, action out-ranking locomotion, driven by the gameplay
lifecycle rather than a clock of its own), proven on the player AND the mist wolf.

**Presentation SEEDS per phase.** These are the capabilities each phase is expected to leave
behind — vocabulary and intent, not a commitment to implement every item:

| Phase | Seeds |
|---|---|
| **P12 Cultivation** | meditation state · subtle breathing idle variation · qi accumulation visual (drawn FROM the place — qi is not ambient) · cultivation feedback · a **breakthrough presentation seam** (reusing the action vocabulary at a larger scale, not a second one) — and, since D-057, the **shared progression-celebration seam**: the shipped level-up is below its REQUIRED bar and breakthrough is its real second consumer, so both are built here, macro for a realm and mid for a level, never the same look |
| **P13 Item** | pickup feedback · use-item feedback · acquisition animation · small item VFX |
| **P14 Equipment** | equip / unequip feedback · an equipment visual-state seam |
| **P15 Skill / Technique** | **the phase that must prove this hardest:** `CAST` — anticipation → hand/body action → release → projectile/VFX → impact → recovery. This is where "tay co ra → duỗi tay → chưởng" becomes a reusable production foundation rather than one skill's effect. `CAST_PREPARE / CHANNEL / RELEASE / RECOVER` are PHASES of ONE action (D-057), and the physical hit reaction (visual recoil, never the body) lands with impact VFX |
| **P16 Pet** | summon · spawn · follow · idle · attack · dismiss |
| **P17 NPC** | idle variation · walk · turn/facing · talk gesture · reaction |
| **P18 Dialogue** | portrait reaction · emotion · gesture · dialogue focus · transition |
| **P19 Quest** | accept · progress · complete · reward · objective feedback |
| **P20 Story** | scene transition · dramatic beat · camera framing · character emphasis · environmental event |
| **P21 Dungeon** | entry · telegraph · encounter transition · environmental reaction |
| **P22 Boss** | phase transition · telegraph · signature attack · arena reaction · death sequence |
| **P23 Save/Load** | save feedback · load transition · failure/recovery UX |
| **P25+** | **consolidate — do not invent a second visual architecture** |

**How a phase designs its presentation (D-057 / D-057A).** The seeds above say WHAT capability a
phase leaves behind. HOW it is designed is owned elsewhere and binding: the motion laws, timing
grammar, deliberation record and self-critique in `docs/MOTION_DESIGN_CONTRACT.md`; the identity
gates, the reference categories each phase studies and the canon traps each must avoid in
`docs/XIANXIA_IDENTITY_CONTRACT.md` §12; the HUD composition budgets in `docs/UI_UX_BIBLE.md` §3c.

**Anti-dead-game scope.** Presentation is not only character animation. The architecture must
avoid closing the door on: NPC movement · idle variation · turning · combat motion · skill
casting · projectiles · hit reactions · death · level-up · cultivation · breakthrough · weather
· environmental and world-simulation events · interactive props · particles · 2D lighting-like
effects · camera motion · screen shake · impact · telegraphing · audio feedback · ambient
motion · UI transitions · dialogue reactions · boss phases · dungeon events · story moments.
Not all of it must be built soon; none of it may be structurally blocked.

## Guardrails across all phases
- Offline is the source of truth until the multiplayer phases are explicitly approved.
- No premature abstraction; content added as data + scenes.
- High-risk logic (damage, combat, inventory, progression, XP, level, cultivation,
  skill, quest, save/load, localization, map transitions) ships with tests.
- Character / Sect / Relationship / Faction / World-Sim are core domain systems, not NPC
  decoration (D-011); their authoritative state is domain-owned and serializable.
