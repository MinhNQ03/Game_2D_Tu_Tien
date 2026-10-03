# CHANGELOG — Aetheria

All notable changes to this project are recorded here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); the project uses
[Semantic Versioning](https://semver.org/) once it ships builds.

Dates are ISO (YYYY-MM-DD).

## [Unreleased]

### 2026-10-03 — Phase 05 close-out + visual-foundation hardening (D-030)
- **Documentation drift reconciled:** ROADMAP Phase 05 now reads *all 9 gates green* (matches
  `ci.yml`, was "7"); Phase 25 renamed **"UI Consolidation / Production Polish"** (final polish,
  not where production UI begins, not a rescue rewrite). `06-art-assets.md`, `ARCHITECTURE.md`
  and `GAME_FLOW.md` updated: live UI = CC0 Xianxia (D-028, the retired `mana_soul` prototype and
  the "Mana Soul intended upgrade" wording removed), world/character art = production-foundation
  (D-029, not flat prototype, not final), Relationship core CLOSED, Phase 06 NOT STARTED.
- **Continuous Visual Integration adopted** as a binding ROADMAP policy: visuals grow per feature
  phase, replace by asset/component/theme layer (via `UITheme`/`UIPalette`), never change
  gameplay/domain truth, chosen per domain (no giant single pack, no collage); Phase 25 is the
  consolidation/polish endpoint.
- **D-029 visual contracts tested:** `test_map_scenes.gd` now guards `Visual/Decor` (≥1 nearest-
  filtered prop `Sprite2D` with a known texture at authored size — lantern 16×24, tree 32×32,
  rock/planter 16×16), that `Visual/Ground` is still the first child, and ground TileMapLayer is
  nearest-filtered. (+4 test methods; character contracts already covered.)
- **UI polish (seam-only, no new screen):** added a muted-gold `COLOR_TITLE` token for the menu
  title plaque, tightened the type scale (subtitle 18→20, hint 15→14), evened button vertical
  padding (10→12) — all through `UIPalette`/`UITheme`. No gameplay/domain change; UI-theme
  invariants (incl. title > body) stay green.

### 2026-10-03 — Production-foundation world + character art for the playable flow (D-029)
- **World tileset redrawn (in place):** `assets/tiles/prototype/prototype_tileset.png` (same
  48×16 three-column strip, same `prototype_tileset.tres` / `prototype_ground.gd`) upgraded from
  flat colour blocks to shaded, ordered-dithered tiles — mossy jade grass, warm flagstone path,
  blue-grey Chinese roof-tile wall. The hub/field no longer read as one flat green plane.
- **Character redrawn (in place):** the in-game player frame `player_proto.png` (16×24) and the
  four archetype idle sheets (`*_proto_idle.png`, 64×24) now share one drawing routine
  (`_draw_character_frame`) — a fully-outlined, shaded top-down figure (hair sheen, jaw/arm
  shadow, robe hem, per-archetype sash accent, foot contact shadow). Fixed a gap where only the
  idle sheets, not the frame `player.tscn` actually uses, had been upgraded.
- **Decorative props (new):** four self-made Chinese garden-courtyard props — `prop_lantern`
  (16×24), `prop_tree` (32×32), `prop_rock` (16×16), `prop_planter` (16×16) — placed as
  presentation-only `Sprite2D` nodes under a new `Visual/Decor` in `hub_map.tscn` /
  `field_map.tscn`, in open grass clear of the player corridor and exit zones.
- **Seam preserved:** pure presentation. No change to the TileSet resource, ground script,
  `MapData`, camera bounds, wall collision, exit zones, spawns, or any gameplay/domain/data. All
  tests (structural map test, world/player/app E2E, character-visual dims test) keep their
  contracts. Self-made/project-owned (recorded in `ASSET_LICENSES.md` P1/P2 + P14–P17 redrawn,
  P18–P21 new). Visual tier step (prototype → production foundation); Phase 06 NOT started.

### 2026-10-03 — Visual asset audit + production UI art (D-028; CC0 Xianxia UI)
- **Asset audit:** audited 5 local candidate packs for license + fit and classified each
  (recorded in `docs/ASSET_LICENSES.md`): Xianxia Pixel Pack (CC0) = APPROVED primary UI;
  Verdant 00 16×16 tiles (free commercial) = APPROVED terrain but deferred; Foozle Lucifer RPG
  UI (CC0) + Tiny RPG Mana Soul GUI (CC0) = candidate/supporting (not used, avoid collage);
  Ancient Chinese Characters Pack 1 = UNVERIFIED (no license file) → NOT imported.
- **Production UI art:** replaced the self-made prototype UI (`assets/ui/mana_soul/` +
  `tools/gen_ui_assets.py`, D-024) with the CC0 **Xianxia Pixel Pack** UI set under
  `assets/ui/xianxia/` — jade panel, ink inset, jade buttons (normal/hover/pressed), silk
  disabled/focus, rosewood portrait frame, corner key-badge, jade title divider. The menu/HUD
  now read as a wuxia dark-ink/jade game UI instead of flat prototype plates.
- **Seam preserved:** only `UIPalette` (asset dir + per-slot 9-slice margins) and `UITheme`
  (margin wiring + doc) changed; the `UITheme`/`UIPalette`/component/9-slice abstraction, slot
  names, `UI_TEXTURES` contract, and flat fallbacks are unchanged, so `MainMenu`/`GameplayHUD`
  consume the new look with no code edits. The menu background is now a flat deep-ink fill
  (the framed inset texture is not a seamless tile).
- **Scope:** UI art layer only — NO gameplay/domain change, NO new systems/screens, NO
  character/terrain change (top-down CharacterArtBible untouched; no side-view assets). No test
  count change (`test_ui_theme` asset-contract now verifies the xianxia textures). Docs synced
  (ASSET_LICENSES, ARCHITECTURE, ROADMAP). Phase 06 NOT started.

### 2026-10-03 — Phase 05 (D-026; Relationship core + early character visual pipeline + narrative anchor)
- **Relationship domain graph (core system):** added `RelationshipEndpoint` (typed
  `{kind,id}` CHARACTER|SECT), `RelationshipEdge` (id/from/to/type/dimensions/symmetric/known/
  history), `RelationshipStore` (owns edges; indexes by edge id + endpoint; symmetric canonical
  ordering; deterministic `to_dict`/fail-closed `hydrate` with index rebuild), and
  `RelationshipService` (the SINGLE mutation path: validate → clamp to config range → bounded
  history on a real change → domain signal `relationship_changed`; zero-delta no-op; missing
  edge fails loud; debt perspective flips only on a symmetric reverse query). `CharacterState`
  is deliberately NOT given a relationship dict (single source of truth).
- **Data-driven relationship tuning:** `RelationshipConfigData`
  (`data/relationship/relationship_config.tres`, 6 dimensions with the documented ranges +
  history capacity) and `RelationshipRuleData` + `RelationshipRuleCatalog`
  (`data/relationship/relationship_rules.tres`, 6 deterministic event→delta rules). No range or
  rule is a magic number in code.
- **Runtime ownership:** `RelationshipRuntime` node under `Main/Systems` (sibling of
  `WorldRuntime`, NOT an autoload) owns the per-session store+service and survives map swaps;
  started on New Game, ended on return to menu. Autoload budget unchanged (D-017).
- **Early character visual pipeline (presentation):** `CharacterVisualProfileData` +
  `CharacterVisualComponent` (4-direction sheet, nearest filter, feet-anchored, movement-driven
  facing; `MovementComponent` stays the movement authority). The Player resolves its template's
  `sprite_set_ref` into a data-driven sprite (missing/invalid → loud + static fallback). Four
  self-made prototype archetype sheets (player/female cultivator/elder/merchant) via
  `tools/gen_prototype_assets.py` + four `CharacterVisualProfileData` `.tres`. A dev-only
  `character_preview` scene (NOT the first scene). `CharacterState` still carries NO presentation
  data (tested).
- **Design anchors:** `docs/CHARACTER_ART_BIBLE.md` (16px grid, 16×24 baseline, feet anchor,
  collision independent of sprite height, palette/direction/animation rules) and
  `docs/NARRATIVE_DIRECTION.md` (original tu-tiên premise + relationship-driven first arc; no
  story engine, no copyrighted content).
- **Tests:** `tests/unit/relationship/*` (config validity; the full B–U graph matrix incl.
  symmetric/debt perspective, deterministic event→delta, serialize round-trip + fail-closed
  hydrate + index rebuild; rules), `tests/integration/test_relationship_runtime.gd`, extended
  `tests/e2e/world_flow_case.gd` (RelationshipRuntime persists across 20 map swaps, not an
  autoload, session ends on menu), and `tests/unit/presentation/test_character_visual.gd`.
- **Scope:** no NPC/Dialogue/Quest/Story/Sect/Faction/WorldSim/Combat/Inventory/Save/networking;
  no new autoload; game flow + first scene unchanged. SECT endpoints structural-only (Phase 06
  adds the real `SectState` + referential validation). Docs synced; D-026 recorded.

### 2026-10-03 — Phase 04 close-out (D-025; residual test-exit leak fixed + doc drift)
- **Residual leak root-caused and fixed.** The green headless suite still printed
  `WARNING: 5 ObjectDB instances were leaked at exit` + `ERROR: 1 resources still in use at
  exit`. A one-time `--verbose` CI diagnostic (steering 10 §1.3, commit `906e4ef`, then
  removed) named the leaked instances: 3× `Node`, 1× `GDScript`
  (`src/infrastructure/input_service.gd`), 1× `GDScriptNativeClass`. Root cause: three un-freed
  `InputService` Nodes in `tests/unit/core/test_input_display_label.gd` (an unfreed `Node`
  pins its GDScript + native class). Fixed by `svc.free()` in each of the three methods; the
  suite now exits with 0 ObjectDB leaked / 0 resources in use. No production code changed, no
  assertion lowered, D-019 isolation untouched. Added lesson **L-019**.
- **Doc drift corrected (L-014).** `ROADMAP.md` Phase 04 → **CLOSED** with evidence (`7615d88`,
  9 gates green, 163 tests). Corrected the D-024 "resource-in-use" bullet (it wrongly assumed a
  green run was leak-free). Added **D-025** to `DECISIONS.md`.
- **Scope:** close-out only — no Character/UI/Combat/Quest/Dialogue/Save/networking work; no new
  autoloads; Phase 05 (Relationship) still NOT STARTED.

### 2026-10-02 — Phase 04 reopen / UI hardening (D-024; asset-backed pixel-art UI)
- **Real pixel-art UI assets:** added `tools/gen_ui_assets.py` (pure-Python PNG writer, no
  download) producing a project-owned 9-slice UI set under `assets/ui/mana_soul/` — framed
  `panel`/`panel_inset`, button states `normal/hover/pressed/disabled/focus`, a `key_badge`
  keycap, a `portrait_frame`, and a `title_divider`. Self-made/CC0-equivalent because the
  preferred pack (tiopalada "Tiny RPG - Mana Soul GUI", CC0) is not auto-downloadable here
  (itch.io 403); recorded in `docs/ASSET_LICENSES.md` with the intended upgrade noted.
- **Asset-backed theme + components:** `UIPalette` gains the texture paths + 9-slice margins
  (single source of truth); `UITheme` now builds `StyleBoxTexture` panels/buttons/badge with
  the authored border margins (crisp corners, graceful flat fallback). New reusable
  `src/presentation/ui/components/` — `UIKeyBadge` (graphic keycap) + `UIPromptRow` (badge +
  action label).
- **Main menu redesign:** tiled pixel background + centered framed `PanelContainer`, title +
  subtitle + ornamental divider, four buttons with real states; Load Game and Settings are
  distinct disabled placeholders. Signals/localization/input-context unchanged. Added
  `UI_MENU_SETTINGS` (vi/en).
- **HUD redesign:** three framed panels — identity (portrait-frame slot + name/title from
  `CharacterState`), map name, and a control-prompt panel showing graphic `[E] Interact` /
  `[Esc] Menu` badges (via `InputService.get_action_display_label`, never raw keycodes). No
  fake HP/mana/cultivation bars (reserved for a later phase). Added `UI_HUD_INTERACT_ACTION`
  / `UI_HUD_MENU_ACTION` (vi/en). Public HUD API unchanged.
- **Map exit visual:** added a gold directional arrow ornament to the hub/field exit gates
  (still a gameplay marker; no VFX system).
- **Tests:** rewrote the UI-theme test (distinct button states, panel/badge build, PanelContainer
  panel style, **asset-contract: all 10 UI textures exist**, asset-backed `StyleBoxTexture`
  when present); rewrote the HUD prompt test (graphic badges + E/Esc/Interact/Menu, no raw
  keycode/action name, ≥2 badge panels); added a main-menu structural test (shared theme, 4
  buttons, Load Game + Settings disabled, emits intents, localized text). All existing tests
  stay green.
- **Resource-in-use warning:** investigated per steering 10 — the earlier `resources still in
  use at exit` + leaked physics body/texture came from the `default_goals` crash aborting the
  character tests before their `free_node` (fixed in D-023), not a UI leak. Documented in
  D-024; no assertions lowered.
- Docs synced: ASSET_LICENSES (UI rows + source), 06-art-assets (UI baseline), ARCHITECTURE,
  GAME_FLOW, TEST_PLAN, PERFORMANCE, ROADMAP, DECISIONS (D-024). Character core unchanged; no
  new autoloads; Phase 05 still NOT STARTED.

### 2026-10-02 — Phase 04 (D-023; Character core + early UI/presentation foundation)
- **Character core (domain + data):** added `CharacterTemplateData`
  (`src/data/characters/character_template_data.gd`, `char_*`) — the data definition with
  identity/origin/age/profession/cultivation-contract/base-stats/traits/affiliation fields +
  validation — and the player template `data/characters/player_default.tres`. Added
  `CharacterState` (`src/domain/character/character_state.gd`, `RefCounted`): the AUTHORITATIVE,
  serializable, presentation-free character instance with a life-state machine
  (ALIVE→DEAD once, DEAD terminal), current-HP authority, and persistent-tier-only
  `to_dict`/`from_dict` (boundary-validated; a SAVE SEAM — `SaveService` is still Phase 23).
- **Player is a view of one authoritative state:** `WorldRuntime` builds ONE player
  `CharacterState` (fixed `instance_id="player"`) and binds it to the persistent Player before
  it enters the tree. `StatsComponent` reads its numbers from the bound state (falls back to
  the authored `StatBlock` only when unbound); `HealthComponent` syncs HP/death back
  (`set_current_hp`/`mark_dead`). Composition kept; state NOT recreated on map swap.
- **Data-driven start map:** `MapCatalog` gains validated `start_map_id`; `WorldRuntime`
  reads it (removed the hard-coded `START_MAP_ID`).
- **Early UI/presentation foundation:** `UIPalette` design tokens + `UITheme.build()`
  (code-built shared Theme). Main-menu presentation pass (background, title/subtitle, uniform
  styled buttons, focus) — signals/localization/context unchanged. New `GameplayHUD`
  (owned by MapBase) shows the character's name/title + localized map name + control hints.
  New `InputService.get_action_display_label` resolves real key labels (interact→E,
  open_menu→Esc); the UI never reads keycodes. Shared data-driven camera zoom (2× for 16px);
  exit zones show a jade prototype gate instead of the yellow debug block.
- **Localization:** added `CHARACTER_PLAYER_NAME/TITLE/ORIGIN`, `UI_MENU_SUBTITLE`,
  `UI_HUD_INTERACT_HINT`, `UI_HUD_MENU_HINT` (vi + en).
- **Tests:** character unit (template validation, state construction/life-state/HP/round-trip),
  player↔state binding integration, UI theme + HUD structural, input-display-label, Phase-04
  localization-key coverage. The world E2E now asserts the SAME `CharacterState` instance
  across 20 round trips (not recreated on map swap). All diagnostics clean (only the known
  cross-file `class_name` LSP cache false-positives, resolved by CI `--import`).
- Docs synced: CHARACTER_SYSTEM (status §10), DATA_SCHEMA, ARCHITECTURE, GAME_FLOW, TEST_PLAN,
  PERFORMANCE, ROADMAP (Phase 04 IN PROGRESS), DECISIONS (D-023). No new autoloads; scope held.
- CI triage (steering 10): the first Phase-04 push failed the headless suite — `CharacterState`
  read `template.default_goals` which `CharacterTemplateData` never declared (parse-clean,
  runtime crash). Root-caused via a one-time `::error::` diagnostic on the gate, then fixed by
  declaring `default_goals` and adding `MapCatalog.start_map_id` coverage to the catalog unit
  test; diagnostic scaffolding removed. New lesson L-018 (parse-clean ≠ fields exist).

### 2026-10-03 — Phase 03 reopen / hardening (D-022; data-driven maps, transactional transitions, real prototype art)
- **MapData is the full source of truth:** added `scene_path`, `bounds: Rect2`,
  `default_spawn_id`, and stable exit `id`s with full validation (`scene_path` exists,
  positive bounds, unique exit ids). Added a `MapCatalog` resource
  (`src/data/maps/map_catalog.gd` + `data/maps/map_catalog.tres`) that validates unique map
  ids / scene_keys and rejects dangling exits.
- **WorldRuntime is fully data-driven:** it now holds ONLY `MAP_CATALOG_PATH`, loads +
  validates the catalog, and registers `scene_key -> scene_path` with SceneRouter. The old
  hard-coded map/scene-path list is gone — adding a map is data + scene + catalog, no core
  edit.
- **Authoritative exits:** `MapExitZone` carries only `exit_id`; MapBase resolves it to the
  `MapExit` in `MapData` and emits the destination from the DATA (removes scene↔data drift).
- **Data-driven camera + spawns:** `MapBase.apply_map_data` sets Camera2D limits from
  `MapData.bounds`; spawns resolve the `default_spawn_id`, and an explicit missing
  `entry_point` now fails LOUD (no silent fallback).
- **Transactional map transitions:** `WorldRuntime._enter_map` snapshots the player and
  rolls back on router failure (player restored to the still-alive old map, active map /
  GameState unchanged, router not stuck); on success the SAME player instance persists.
- **Real prototype pixel-art (replaces Polygon2D):** self-made `player_proto.png` (16×24) +
  `prototype_tileset.png` (48×16) generated by `tools/gen_prototype_assets.py`; Player uses a
  `Sprite2D`; maps render a `TileMapLayer` via `data/maps/prototype_tileset.tres`. Nearest
  filter, mipmaps off, 16px base tile (06-art-assets.md). Walls stay static collision.
- **E2E hardened:** `world_flow_case.gd` drives interact/open_menu through the REAL input
  pipeline (`Input.parse_input_event`, no direct `_unhandled_input`), does a real movement
  step, and runs 20 round trips with per-round invariants (same player instance, one player,
  one content scene, GameState==router, camera limits, no orphan growth). Added a router
  transactional-rollback integration test. Fixed `run_app_flow.gd` stale "prologue" wording.
- Docs synced: ARCHITECTURE current state + folder, DATA_SCHEMA, GAME_FLOW (removed "no
  gameplay yet"), PERFORMANCE, ASSET_LICENSES, 06-art-assets baseline, DECISIONS (D-021
  amended + D-022 added), lessons (L-016 refined + L-017). No new autoloads; no new scope
  beyond World/Map; Phase 04 NOT STARTED.

### 2026-10-02 — Phase 03 World / Map (traversable maps; D-003 resolved)
- **Map data model (D-021):** added `MapData` + `MapExit` Resources (`src/data/maps/`), with
  validation (`is_valid()` / `validation_errors()`), and two authored maps
  `data/maps/map_hub.tres` + `data/maps/map_field.tres`. A map references its content scene
  by a stable router `scene_key: String` (not a direct `PackedScene`), keeping `MapData` a
  pure data resource — DATA_SCHEMA synced.
- **WorldRuntime (node, not autoload):** `src/gameplay/world/world_runtime.gd` hangs under
  `Main/Systems`. It builds the map catalog, registers each `scene_key` with `SceneRouter`,
  owns ONE persistent per-session Player (parked under WorldRuntime between maps so a router
  content-swap can't free it; re-parented into each map's `PlayerHost` at a named spawn),
  and resolves `request_map_transition(to_map_id, entry_point)` through SceneRouter. The
  autoload budget stays at 5 (D-017).
- **Map scenes:** `src/gameplay/maps/hub_map.tscn` + `field_map.tscn` (`MapBase` +
  `MapExitZone`). The player stands in a `MapExitZone` and presses the semantic `interact`
  action (via `InputService`, never raw keys) to request an exit; `MapBase` emits
  `exit_requested` and WorldRuntime drives the transition. `open_menu` returns to the menu.
  Walls wired from `CollisionLayers.WORLD`. Prototype art = self-made vector placeholders
  (recorded in `ASSET_LICENSES.md`, 32px base tile); real TileSet deferred to the art pass.
- **Boot wiring:** New Game now enters the hub map via WorldRuntime (`main.gd`
  `_create_world_runtime` + `start_session`/`end_session`); the Phase-02 sandbox + Phase-01
  prologue are retained but are no longer the first scene.
- **Tests + CI:** `tests/unit/world/test_map_data.gd`, `tests/integration/test_map_transitions.gd`
  (repeated transitions, no orphan-node leak), `tests/gameplay/test_map_scenes.gd`
  (structural), and the dedicated isolated E2E `tests/e2e/run_world_flow.gd` driving the real
  New Game → hub → interact → field → back → menu flow — added as a **9th CI gate**. The
  Phase-02 player E2E now instantiates the sandbox directly (New Game no longer routes to it);
  the app-flow E2E now expects `map_hub` as the first scene.
- No new scope: no Character/Combat/AI/World-Simulation/Save/Inventory/networking, no new
  autoload, no new EventBus signal (`map_entered`/`map_exited` deferred to Quest/Story —
  L-005). D-005 / D-007 remain Open; **D-003 resolved** (option a).

### 2026-10-02 — Phase 02 Final Hardening (contract/invariant/doc consistency, no new scope)
- **Semantic-input E2E (real boundary):** the player E2E (`tests/e2e/player_flow_case.gd`)
  now drives movement and attack through the actual InputMap → `InputService` → Player
  path (`Input.action_press("move_right")` / `Input.action_press("attack")`), not direct
  `MovementComponent.apply_intent` / `resolve_player_attack()` calls. Added an input-gating
  regression (attack does NOT fire in MENU context, DOES in GAMEPLAY) and a teardown that
  releases pressed actions + asserts no orphan / no duplicate autoload / legal GameState.
- **Collision single source of truth:** Player / Training Dummy / sandbox walls now set
  `collision_layer`/`collision_mask` from `CollisionLayers.*` at runtime (Player =
  PLAYER + mask WORLD|DUMMY; Dummy = DUMMY, mask 0; walls = WORLD). Added an integration
  test that fails if the constants and runtime wiring drift.
- **MovementComponent contract:** `apply_intent(intent, speed, _delta := 0.0)` — the
  Phase-02 contract's `delta` is explicit but intentionally unused (`move_and_slide` owns
  physics integration; no `velocity * delta`). Player passes `delta`; tests updated.
- **Health death/reset invariant made consistent:** reworded from "`died` once, ever" to
  "`died` once PER LIFE (per `initialize()` cycle)", matching `TrainingDummy.reset_dummy()`
  (a new life can die again). Added regression tests (no duplicate `died` within a life;
  re-initialize → second-life death). No resurrection added.
- **Stats fail-closed:** `Player._ready()` / `TrainingDummy._ready()` now branch on
  `StatsComponent.validate()`; an invalid/missing StatBlock reports loudly and the entity
  stays inert (Player disables physics) instead of half-running. `validate()` no longer
  `assert()`-aborts (loud `push_error` + checked return is the robust fail-loud-and-closed
  contract). Added a fail-closed test.
- **Docs sync:** `01-product` core-systems phases 11–15 → 04–08; `SAVE_FORMAT` migration
  references Phase 17 → 23; `TEST_PLAN` status line updated to the post-Phase-02 reality.
- No new scope: no combat system, no AI, no Character/Save/Inventory/networking, no new
  autoload. D-003 / D-005 / D-007 remain Open. Sandbox remains the temporary Phase-02
  validation scene.

### 2026-10-02 — Phase 02 Player Core (first playable; no combat system)
- **Player entity (composition, D-020):** `CharacterBody2D` under `src/gameplay/entities/`
  composed of `StatsComponent` + `HealthComponent` + `MovementComponent`
  (`src/gameplay/components/`). No inheritance chain, no God object; `player.gd` only
  coordinates (reads semantic intent, forwards movement, exposes an attack intent). Reads no
  physical keys — input flows only through `InputService`.
- **Top-down movement:** 8-direction, diagonals normalized (not faster than cardinal),
  collision-aware via `move_and_slide`, speed from stats. `MovementComponent.apply_intent`
  is the intent boundary a future network command reuses (MP seam).
- **Stats as data:** `StatBlock` Resource (`src/data/stats/stat_block.gd`, DATA_SCHEMA §1
  field names) with authored numbers in `data/stats/player_stats.tres` /
  `training_dummy_stats.tres`. Invariants validated at the boundary.
- **Health:** enforced invariants (`0<=hp<=max`), `apply_damage`/`heal` return applied
  amount, non-positive rejected, `died` emitted exactly once, DEAD terminal (no revive).
  Direct signals to owner; no new EventBus signals.
- **Minimal damage rule (NOT a combat system):** one pure domain function
  `src/domain/combat/damage_rules.gd` — a deterministic slice of the DATA_SCHEMA §2 formula
  (no RNG/crit/resist/skill/equipment). D-007 (combat timing) stays Open.
- **Training Dummy:** `StaticBody2D` reusing the same Stats/Health components, no AI, no
  movement, `reset_dummy()`; deterministic retaliation driven by the sandbox coordinator.
- **Player Sandbox (temporary first scene):** `src/gameplay/sandbox/player_sandbox.tscn` —
  Player + Dummy + walls + camera + localized HUD. New Game now routes here
  (`FIRST_SCENE_KEY` in `main.gd`) instead of the prologue shell; documented as a Phase-02
  gameplay-validation scene that Phase 03 replaces. Coordinator owns the range check + the
  bidirectional damage exchange via the domain rule.
- **Collision layers** named constants (`src/gameplay/collision_layers.gd`).
- **Localization:** added `UI_SANDBOX_HINT` / `UI_SANDBOX_PLAYER_HP` / `UI_SANDBOX_DUMMY_HP`
  (vi + en).
- **Tests:** unit (damage rule, health invariants + death-once, movement math, stat
  validation), integration (player wiring + real-physics movement + bidirectional damage
  exchange, fresh instances), gameplay smoke (sandbox structural, no Main boot), and a
  dedicated isolated **player E2E** process (`tests/e2e/run_player_flow.gd` +
  `player_flow_case.gd`) — New Game → sandbox → move → attack → death → cleanup. CI gained an
  8th gate for it; `test_app_flow` updated to expect `player_sandbox` as the first scene.
- No combat system, no AI, no inventory/equipment/skill/cultivation, no save/load, no
  networking, no new autoloads. D-003 / D-005 / D-007 remain Open.

### 2026-10-02 — Phase 01 Test Isolation + Boot Contract Hardening (no gameplay)
- **Fixed — cross-test singleton contamination (D-019):** the previous
  `tests/integration/test_app_flow.gd` spawned duplicate `/root` autoloads and booted Main
  on the REAL `GameState` autoload, leaving it at `RUNNING`. A later in-runner boot then hit
  `illegal transition RUNNING -> INITIALIZING`. Removed that test; the real-application E2E
  now runs in its **own isolated Godot process** (`tests/e2e/run_app_flow.gd` +
  `tests/e2e/app_flow_case.gd`), using the ACTUAL project autoloads and driving the real
  `MainMenu.new_game_pressed` intent — no duplicate autoloads, nothing to contaminate.
- **Added — isolation guard in `tests/run_tests.gd`:** snapshots the shared
  `/root/GameState` phase and FAILS the suite if any test leaves it changed (detection, not
  reset). `tests/e2e/` is excluded from in-runner discovery.
- **Changed — smoke test is structural-only:** `tests/smoke/test_boot.gd` no longer boots
  Main into the shared tree; it validates the static Systems/World/UI shell without running
  the lifecycle. The real boot contract is asserted by the E2E process.
- **Changed — Main requires all 5 autoloads (D-019):** `REQUIRED_AUTOLOADS` =
  EventBus, GameState, Localization, InputService, SceneRouter. Missing any → fail loud,
  abort boot, no silent fallback. Removed the "zero autoloads = tolerate" escape.
- **Changed — Main checks every required lifecycle bool:** `begin_initialization`,
  `mark_ready`, `enter_menu`, `confirm_session_running`. A rejected `confirm_session_running`
  now unwinds to menu instead of faking RUNNING.
- **CI:** added a 7th gate running the dedicated E2E process; no swallowed exit codes.
- **Docs:** D-019 added; TEST_PLAN updated (runner has project autoloads; isolation
  boundary; E2E own process); lesson L-010 recorded. No gameplay, no networking, no Phase 02
  (Config/RNG/SaveService still deferred per D-017).

### 2026-10-02 — Phase 01 Final Hardening (close contract/test/invariant gaps, no gameplay)
- **Fixed — GameState persistence invariant (D-018):** `to_dict()` now serializes only run
  identity + location (never `session_active`, never the lifecycle phase) and returns `{}`
  when no session is active. Loading moved to `hydrate_session(data)` (data-only; does not
  drive the lifecycle) which rejects an invalid snapshot (no `run_id`) and an unsafe phase
  (only `MENU`/`READY`); `from_dict()` is now a `bool`-returning alias. This removes the
  previously-possible invalid `phase==BOOT && session_active==true` reload state.
- **Fixed — magic input ints (D-018):** added semantic `InputService.set_gameplay_context()`
  / `set_menu_context()` / `push_modal_context()`; the raw stack reset is now private
  `_reset_to()`. Menu + first scene no longer pass enum ints.
- **Fixed — input ownership (D-018):** `prologue_shell` resolves `open_menu` via
  `InputService.is_system_action_just_pressed(&"open_menu")` instead of reading the raw
  input event.
- **Fixed — boot fail-fast (D-018):** `Main` aborts boot loudly if a required core autoload
  (`GameState`/`SceneRouter`/`EventBus`) is missing in a real run (headless test harness,
  with zero autoloads, still runs the null-safe path); `_boot()` checks transition results.
- **Removed — speculative EventBus signals (D-018):** `new_game_requested`,
  `session_started`, `session_ended` (no real producer+consumer in Phase 01). Kept
  `game_booted`, the three `scene_transition_*`, and `language_changed`.
- **Tests added/updated:** GameState persistence-invariant suite; InputService semantic
  setters; SceneRouter failure/cleanup cases A–F; EventBus "holds no business state"; and a
  real end-to-end `tests/integration/test_app_flow.gd` that stands up the actual autoloads,
  instantiates `main.tscn`, drives the real `MainMenu.new_game_pressed`, and asserts a
  RUNNING session with the prologue content scene loaded (then tears down with no orphans).
- **Docs:** ROADMAP Phase 01 → CLOSED, Phase 02 NOT STARTED; corrected the one-off
  `2026-10-03` → `2026-10-02` date across docs; D-018 added. No gameplay, no networking,
  no Phase 02 work (Config/RNG/SaveService still deferred per D-017).

### 2026-10-02 — Phase 01 Core Framework (runtime skeleton, no gameplay)
- **Lifecycle + session:** `GameState` autoload — explicit lifecycle state machine
  (`BOOT→INITIALIZING→READY→MENU→STARTING_SESSION→RUNNING→TRANSITIONING/PAUSED`), runtime
  session state (run_id, current world/map/scene ids), intent-revealing methods, illegal
  transitions rejected loudly, `to_dict/from_dict` seam, no disk I/O, no presentation refs.
- **EventBus** autoload — minimal cross-system signals for Phase 1 only (boot, scene
  transition, language). Emitters never reference listeners. *(Speculative session signals
  removed in the hardening pass — see D-018.)*
- **Localization** autoload — vi/en via a CSV table (`locale/aetheria.csv`), `t()`/`t_args()`
  with `{placeholder}` substitution, `set_language/get_language`, missing-key returns the
  key + warns. Backing format decided (D-008: CSV).
- **InputService** autoload — semantic input intent over named InputMap actions + input
  gating ownership (context stack UI_MODAL > MENU > GAMEPLAY). No physical-key leakage.
- **SceneRouter** autoload — the single scene-transition entry point; swaps content under
  `Main/World`, guards duplicate/stale/invalid/leak, explicit success/failure, records
  location in GameState. Keeps map strategy open (D-003).
- **Semantic InputMap** in `project.godot`: move_up/down/left/right, interact, attack,
  skill_1..4, dodge, open_menu, pause.
- **Presentation shells:** localized main menu (New Game / Quit; Load Game disabled) and a
  non-gameplay first-scene (`prologue_shell`) proving router + gamestate + input ownership.
- **Bootstrap** `main.gd` rewired as a thin coordinator (BOOT → MENU → New Game → first
  scene) — not a God object.
- **Autoloads justified** in `DECISIONS.md` D-017 (5 autoloads; Config/RNG/SaveService
  deliberately deferred). **D-008 Accepted** (CSV).
- **Roadmap reordered** to 35 phases (00–34): Character/Relationship/Sect/Faction/World-Sim
  moved to 04–08 (before Combat 09); Save→23; Multiplayer→32–34. Phase-number references in
  `DECISIONS.md` blocking lines updated (D-003→03, D-005→23, D-007→09, D-008→01/24).
- **Tests:** `tests/unit/core/` (GameState, SceneRouter, EventBus, Localization,
  InputService) + `tests/integration/test_boot_flow.gd` (boot→menu→new game→first scene).
- No gameplay, no networking.

### 2026-10-02 — Phase 0 CLOSED (documentation close-out, no gameplay)
- **Foundation hardening verified by CI.** GitHub Actions job "Foundation gates
  (Godot 4.7)" ran on commit `651c16f` with `conclusion=success` (confirmed via the
  GitHub check-runs API).
- **Runtime boot smoke — verified by CI:** project boots `application/run/main_scene`,
  `Main._ready()` runs, clean exit (`--quit-after 2`).
- **Parse check — verified by CI:** `tools/parse_check.gd` found no GDScript parse errors.
- **Headless test suite — verified by CI:** `tests/run_tests.gd` ran green (`RESULT: PASS`).
- **Phase 0 → READY FOR PHASE 1.** `docs/PHASE_0_EXIT_CHECKLIST.md` all blocking items
  [x]; `docs/ROADMAP.md` Phase 0 marked CLOSED, Phase 1 (Core) is next and not started.
- **Docs synced to verified state:** D-012 marked Accepted & verified; D-009 clarified
  (local-agent limitation only, CI ran Godot for real); removed "pending CI"/"first green
  run" wording across ROADMAP/checklist.
- No gameplay, no Phase 1 work.

### Changed / Added — 2026-10-02 — Foundation hardening (Phase 0, no gameplay)
- **Smoke test now really boots:** `tests/smoke/test_boot.gd` adds Main to the live
  SceneTree (runs `_ready`), asserts `is_inside_tree` + Systems/World/UI + bootstrap
  self-validation, cleans up with no orphan nodes; added a negative structure test.
- **Test runner hardened:** `tests/run_tests.gd` rewritten — recursive (nested) discovery,
  deterministic order, SceneTree injection, `await` per method, non-zero exit on
  fail/empty/missing-required. `tests/framework/test_case.gd` gained SceneTree helpers.
- **Nested-discovery + fail-detection proof:** `tests/unit/framework/test_nested_discovery.gd`.
- **Project-wide parse check:** `tools/parse_check.gd` (loads every `.gd` under
  src/tests/tools; CI gate).
- **CI hardened:** `.github/workflows/ci.yml` — removed `|| true`; gates checkout → Godot
  4.7 → import → parse check → runtime boot (`--quit-after 2`) → test suite; no swallowed
  failures.
- **Hooks split (D-016):** PostFileSave runs the lightweight parse check;
  `run-full-tests-on-task.json` (PostTaskExec) runs the full suite.
- **Authority contract (D-015):** sect membership canonical source = `SectState` roster;
  `CharacterState` sect fields are a derived cache. Annotated across CHARACTER/SECT/
  DATA_SCHEMA/SAVE_FORMAT.
- **Doc consistency:** fixed stale "empty `main.tscn`"/"no scripts" (ARCHITECTURE),
  "3D physics enabled" (01-product), and "pending first green CI" (ROADMAP); logged in
  DECISIONS D-013 (items 5–7).
- **New:** `docs/PHASE_0_EXIT_CHECKLIST.md` (gates Phase 0 → READY FOR PHASE 1 on a green CI).

### Changed / Added — 2026-10-02 — Foundation review + fix (Phase 0 completion, no gameplay)
- **Project identity:** `config/name` `New_Game_Project` → `Aetheria` (D-006 Accepted).
- **2D config cleanup:** removed the `[physics]` section (3D `Jolt Physics` leftover) —
  game is 2D-only (D-002 Accepted). Added `textures/canvas_textures/default_texture_filter=0`
  (nearest, for pixel art). Set `run/main_scene="res://main.tscn"`.
- **Bootstrap:** `main.tscn` is now a real bootable scene — `Main` (`Node2D`, script
  `src/bootstrap/main.gd`) with `Systems` / `World` / `UI` children (D-010).
- **Test framework (D-004 Accepted → custom headless runner):**
  `tests/framework/test_case.gd` (`TestCase` + `assert_*`), a real `tests/run_tests.gd`
  (discovers `test_*.gd`, non-zero exit on failure), and a real smoke test
  `tests/smoke/test_boot.gd`. Removed the placeholder behavior and `smoke/.gdkeep`.
- **Core-system design (design only, no gameplay):** new docs `CHARACTER_SYSTEM.md`,
  `RELATIONSHIP_SYSTEM.md`, `SECT_SYSTEM.md`, `WORLD_SIMULATION.md`; updates to
  `GAME_FLOW`, `DATA_SCHEMA`, `MULTIPLAYER_PLAN`, `ROADMAP`, and steering 01/02/03 to make
  Character / Relationship / Sect / Faction / World-Simulation core systems (D-011).
- **CI:** added `.github/workflows/ci.yml` (checkout → Godot 4.7 → import → headless
  tests) (D-012).
- **AI review protocol:** added the `READ → PLAN → IMPLEMENT → TEST → REVIEW → DOCS` loop
  and pre-completion review gates.
- **Decisions resolved:** D-002, D-004, D-006 → Accepted; added D-009 (local Godot
  unavailable to agent), D-010, D-011, D-012, D-013 (doc-review findings).

### Known limitation — 2026-10-02
- The AI agent could not run Godot headless locally (no binary on PATH / common dirs /
  registry — D-009). All scripts validated via the GDScript language server (zero errors);
  authoritative headless run is CI. Manual command:
  `godot --headless --path . -s res://tests/run_tests.gd`.

### Added — 2026-10-02 — Project foundation (docs & process, no gameplay)
- Steering rules in `.kiro/steering/`:
  `01-product`, `02-game-design`, `03-architecture`, `04-coding-standards`,
  `05-performance-testing`, `06-art-assets`, `07-localization`,
  `08-ai-review-protocol`.
- Core docs in `docs/`:
  `GAME_FLOW` (central flow + per-system contracts), `ARCHITECTURE` (layered design),
  `ROADMAP` (22 phases, Foundation → Multiplayer preparation), `TEST_PLAN`,
  `PERFORMANCE`, `ASSET_LICENSES`, `DATA_SCHEMA`, `SAVE_FORMAT`, `MULTIPLAYER_PLAN`,
  `DECISIONS`, `DEBUGGING`, and this `CHANGELOG`.
- `tests/` scaffold: `unit/ integration/ gameplay/ smoke/ performance/`, a `README`,
  and a placeholder headless runner `run_tests.gd`.

### Noted / flagged (from repo audit) — 2026-10-02
- Project still named `New_Game_Project` (rename to `Aetheria` planned — `DECISIONS.md`
  D-006).
- 3D physics engine (`Jolt Physics`) enabled on a 2D game — flagged for cleanup
  (`DECISIONS.md` D-002).
- `icon.svg` is the stock Godot placeholder icon — `ASSET_LICENSES.md`; replace before
  release.
- Open decisions pending: test framework (D-004), map strategy (D-003), save format
  (D-005), combat timing model (D-007), localization format (D-008).

### Not done (by design, as of 2026-10-02)
- No gameplay implemented. `main.tscn` was a single empty `Node2D`.
  *(Superseded 2026-10-02: `main.tscn` is now a non-gameplay bootstrap scene — see the
  2026-10-02 entry above.)*
- No networking / multiplayer code.

---

## How to update
- Add changes under **[Unreleased]** grouped as Added / Changed / Fixed / Removed /
  Deprecated / Security.
- When a build is cut, replace **[Unreleased]** with a version + date and start a fresh
  Unreleased section.
- Keep entries short and factual; link to `DECISIONS.md` / `PERFORMANCE.md` for detail.
