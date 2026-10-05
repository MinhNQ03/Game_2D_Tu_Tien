extends Node2D
## Main bootstrap / application coordinator for Aetheria.
##
## Foundation + Core wiring — NOT gameplay and NOT a God object. It only:
##   1. validates the Main/Systems/World/UI shell (D-010),
##   2. drives the boot lifecycle (BOOT → INITIALIZING → READY → MENU) via GameState,
##   3. gives SceneRouter its content host (the World node) and registers Phase-1 scenes,
##   4. shows the main-menu shell and connects its intents to GameState + SceneRouter.
##
## It must never become a combat/inventory/quest/save/world/character manager. Systems
## attach under Systems/World/UI in their own files as later phases add them.

const CONTAINER_SYSTEMS := "Systems"
const CONTAINER_WORLD := "World"
const CONTAINER_UI := "UI"
const REQUIRED_CONTAINERS := [CONTAINER_SYSTEMS, CONTAINER_WORLD, CONTAINER_UI]

const MENU_SCENE := "res://src/presentation/menus/main_menu.tscn"

## The settings screen (D-035). Like the menu it is a plain `Control` parented under
## `Main/UI`, NOT a SceneRouter scene: the router owns the CONTENT scene under `Main/World`
## (the map), while menus/overlays are UI. It is shown INSTEAD of the menu and hands control
## back via `close_requested`, so the lifecycle phase never changes (we stay in MENU).
const SETTINGS_SCRIPT := "res://src/presentation/menus/settings_menu.gd"

## Player preferences on disk (D-035). Read here at boot to restore the chosen language;
## written by the settings screen. A RefCounted helper, NOT a new autoload — the D-017
## autoload budget stays at five.
const SettingsStoreScript := preload("res://src/infrastructure/settings_store.gd")

## PHASE 03: New Game now enters the WORLD via `WorldRuntime` (a node under `Main/Systems`),
## which owns the per-session persistent Player and loads the first MAP (the hub) through
## SceneRouter. This replaces the Phase-02 single `FIRST_SCENE_KEY` wiring — maps are now
## catalog-driven in WorldRuntime, not a hard-coded first scene here (`docs/ARCHITECTURE.md`
## §9; D-021). The Phase-02 sandbox + Phase-01 prologue shell are retained in the repo but
## are no longer the first scene.
const WORLD_RUNTIME_SCRIPT := "res://src/gameplay/world/world_runtime.gd"

## PHASE 05 (D-026): the per-session relationship graph lives in a `RelationshipRuntime` node
## under `Main/Systems` — a SIBLING of WorldRuntime, NOT an autoload (the autoload budget
## D-017 is unchanged). It survives map swaps the same way WorldRuntime does. It is a separate
## subsystem so WorldRuntime stays the map/player coordinator (no God object).
const RELATIONSHIP_RUNTIME_SCRIPT := "res://src/gameplay/world/relationship_runtime.gd"

## PHASE 06 (Sect): the per-session sect domain lives in a `SectRuntime` node under
## `Main/Systems` — another SIBLING, also NOT an autoload. It depends on the relationship
## subsystem (it mirrors Sect↔Sect alliances into the relationship graph) and on the player's
## CharacterState (to enroll the player + sync the derived cache), so it starts AFTER both the
## world + relationship sessions. Same no-God-object discipline.
const SECT_RUNTIME_SCRIPT := "res://src/gameplay/world/sect_runtime.gd"

## PHASE 07 (Faction/Politics): the per-session faction domain lives in a `FactionRuntime`
## node under `Main/Systems` — another SIBLING, also NOT an autoload. It is started LAST
## because it reads BOTH of the subsystems before it: the sect store (the single membership
## authority every faction defers to, D-015) and the relationship graph (where Faction↔Faction
## standing actually lives). It is therefore ended FIRST on an unwind.
const FACTION_RUNTIME_SCRIPT := "res://src/gameplay/world/faction_runtime.gd"

## PHASE 08 (World Simulation): the per-session world simulation lives in a
## `WorldSimulationRuntime` node under `Main/Systems` — the FIFTH sibling, also NOT an autoload
## (the D-017 budget stays at 5). It is started LAST because it reads ALL FOUR subsystems
## before it: the character registry (its cast are real `CharacterState`s), the sect store +
## service (its actors enrol, its events move sect influence), the faction service, and the
## relationship graph. It is therefore ended FIRST on every teardown.
const WORLD_SIM_RUNTIME_SCRIPT := "res://src/gameplay/world/world_sim_runtime.gd"

## The five Phase-01 infrastructure autoloads the running application REQUIRES (D-017).
## Main boots the real application; all five are declared in `project.godot [autoload]` and
## are therefore always present when Main actually runs (real app, the runtime boot smoke,
## and the dedicated E2E process — D-019). If ANY is missing, that is a real
## misconfiguration: boot fails loudly and stops. A null autoload is never silently
## tolerated (`.kiro/steering/04-coding-standards.md`: fail loud; no swallowed nulls; no
## silent fallback; no self-created autoload). In-runner unit/integration tests never
## instantiate Main (they test the services directly), so there is no "test-harness without
## autoloads" case to special-case here.
const REQUIRED_AUTOLOADS := [
	"EventBus", "GameState", "Localization", "InputService", "SceneRouter",
]

## The per-session subsystems in START order, which IS their dependency order (D-047).
##
## This is the single source of truth for both directions of the session lifecycle:
##   * New Game starts them in this order, because each one reads what the one before it
##     produced — the relationship graph needs the world's player CharacterState, the sect
##     session mirrors into the relationship graph, and the faction session reads BOTH the
##     sect store and the relationship graph.
##   * EVERY teardown — the failed-start unwind AND the normal return to menu — walks this
##     list BACKWARDS, so a dependency is never dropped while something that reads it is
##     still unwinding through it.
##
## Before D-047 the two teardown paths disagreed: the unwind was correct while the normal
## return-to-menu ended World and Relationship BEFORE Faction and Sect, i.e. it tore out the
## relationship graph and the player's CharacterState while the sect and faction sessions —
## whose state is defined in terms of both — were still live. Driving both paths from this one
## constant is what makes the two orders incapable of drifting apart again.
const SESSION_START_ORDER := [
	&"WorldRuntime", &"RelationshipRuntime", &"SectRuntime", &"FactionRuntime",
	&"WorldSimulationRuntime",
]

## The lifecycle step that owns the session itself. It is ended AFTER every subsystem, because
## a subsystem is only meaningful inside a session: ending the session first would make
## `GameState.is_session_active()` false while sect/faction state was still being unwound.
const SESSION_OWNER_STEP := &"GameState"

var _menu: Control = null
var _settings: Control = null  # settings screen while open (D-035); null otherwise
var _world: Node = null   # WorldRuntime (per-session world/map coordinator), under Systems
# RelationshipRuntime (per-session relationship graph), under Systems (D-026).
var _relationship: Node = null
# SectRuntime (per-session sect domain), under Systems (Phase 06).
var _sect: Node = null
# FactionRuntime (per-session faction domain), under Systems (Phase 07).
var _faction: Node = null
# WorldSimulationRuntime (per-session world simulation), under Systems (Phase 08).
var _world_sim: Node = null

## What the LAST teardown actually ended, in the order it ended it (D-047). Written only by
## `_end_session_stack()`, which is the one path both the failed-start unwind and the normal
## return to menu go through.
##
## It exists because the teardown ORDER is an invariant and an invariant that nothing can
## observe is only a comment: the Phase-07 defect this records was a reversed order sitting in
## plain sight under a correct-sounding comment, with every gate green. Reading this after a
## real return-to-menu is how `tests/e2e/world_flow_case.gd` proves the dependent session was
## ended before its dependency, and it is the first thing to print when a session leaves
## something behind (`docs/DEBUGGING.md`). Same role as `is_settings_open()` below: a small
## read-only window onto bootstrap state, never an input to behaviour.
var _last_teardown_order: Array[StringName] = []


func _ready() -> void:
	assert(_has_required_containers(), "Main scene is missing a required container node.")
	if not _verify_core_autoloads():
		# A required core service is absent → the app is mis-wired. Do not limp on in a
		# broken state (no fake menu, no half-boot): report loudly and stop booting.
		return
	_boot()


## True only when all five required autoloads are present under /root. Otherwise reports
## the missing ones loudly and returns false (boot aborts). No partial-wiring tolerance.
func _verify_core_autoloads() -> bool:
	var missing: Array[String] = []
	for autoload_name in REQUIRED_AUTOLOADS:
		if get_node_or_null("/root/%s" % autoload_name) == null:
			missing.append(autoload_name)
	if missing.is_empty():
		return true
	push_error("[boot] FATAL: required core autoload(s) missing: %s. Check project.godot "
		% str(missing) + "[autoload]. Aborting boot to avoid a half-wired game state.")
	assert(false, "Required core autoload(s) missing: %s" % str(missing))
	return false


## The boot sequence. Each step is an explicit, legal lifecycle transition owned by
## GameState; the bootstrap only sequences them. All five autoloads are verified present
## before this runs, so the service lookups below are non-null; every REQUIRED lifecycle
## transition return value is checked and a rejection aborts boot loudly (no booting on
## through a bad phase).
func _boot() -> void:
	var gs := _game_state()
	var router := _scene_router()

	if not bool(gs.call("begin_initialization")):
		push_error("[boot] begin_initialization rejected; aborting boot")
		return

	# Apply the player's saved language BEFORE any UI is built, so the menu renders in the
	# right language on the first frame (no visible flip). D-035.
	_apply_saved_language()

	# Give the router its content host (the World node). Map scene_keys are registered by
	# WorldRuntime at session start, not here (catalog-driven — D-021).
	router.call("set_scene_host", get_node(CONTAINER_WORLD))

	# Create the WorldRuntime coordinator under Systems (a node, not an autoload — D-017).
	# It is idle until New Game starts a session.
	_create_world_runtime()

	# Create the RelationshipRuntime subsystem under Systems too (sibling of WorldRuntime,
	# also a node not an autoload — D-026). Idle until New Game.
	_create_relationship_runtime()

	# Create the SectRuntime subsystem under Systems too (sibling, node not autoload —
	# Phase 06). Idle until New Game.
	_create_sect_runtime()

	# And the FactionRuntime (Phase 07).
	_create_faction_runtime()

	# And the WorldSimulationRuntime (Phase 08), now the last link in the dependency chain.
	_create_world_sim_runtime()

	if not bool(gs.call("mark_ready")):
		push_error("[boot] mark_ready rejected; aborting boot")
		return

	_event_bus().call("emit_game_booted")

	_show_menu()


## Apply the language the player last chose in Settings (D-035).
##
## The bootstrap reads the preference and the `Localization` service applies it; the service
## itself never touches disk, so unit tests can switch language freely without leaving a
## stale file behind (see the persistence note in `localization.gd`). Absent/invalid values
## are ignored — `Localization.DEFAULT_LANGUAGE` (vi) then stands. Non-fatal by design: a
## preferences problem must never stop the game from booting.
func _apply_saved_language() -> void:
	var loc := get_node_or_null("/root/Localization")
	if loc == null:
		return
	var saved := SettingsStoreScript.new().get_language()
	if saved == "":
		return  # first run: no choice stored yet
	if not bool(loc.call("set_language", saved)):
		push_warning("[boot] saved language '%s' is not supported; keeping default" % saved)


## Instantiate the WorldRuntime node under Systems and connect its return-to-menu intent.
func _create_world_runtime() -> void:
	if _world != null and is_instance_valid(_world):
		return
	var script: Script = load(WORLD_RUNTIME_SCRIPT)
	if script == null:
		push_error("[boot] failed to load WorldRuntime script: %s" % WORLD_RUNTIME_SCRIPT)
		return
	_world = Node.new()
	_world.name = "WorldRuntime"
	_world.set_script(script)
	get_node(CONTAINER_SYSTEMS).add_child(_world)
	if not _world.is_connected("return_to_menu_requested", _on_return_to_menu):
		_world.connect("return_to_menu_requested", _on_return_to_menu)


## Instantiate the RelationshipRuntime subsystem under Systems (D-026). Mirrors
## `_create_world_runtime()`: a script-created node, not an autoload, not a scene. It owns no
## intents to wire — Main just starts/ends its session alongside the world session.
func _create_relationship_runtime() -> void:
	if _relationship != null and is_instance_valid(_relationship):
		return
	var script: Script = load(RELATIONSHIP_RUNTIME_SCRIPT)
	if script == null:
		push_error("[boot] failed to load RelationshipRuntime script: %s"
			% RELATIONSHIP_RUNTIME_SCRIPT)
		return
	_relationship = Node.new()
	_relationship.name = "RelationshipRuntime"
	_relationship.set_script(script)
	get_node(CONTAINER_SYSTEMS).add_child(_relationship)


## Instantiate the SectRuntime subsystem under Systems (Phase 06). Mirrors the other two
## runtime creators: a script-created node, not an autoload, not a scene. It owns no intents
## to wire — Main starts/ends its session alongside the world + relationship sessions.
func _create_sect_runtime() -> void:
	if _sect != null and is_instance_valid(_sect):
		return
	var sect_script: Script = load(SECT_RUNTIME_SCRIPT)
	if sect_script == null:
		push_error("[boot] failed to load SectRuntime script: %s" % SECT_RUNTIME_SCRIPT)
		return
	_sect = Node.new()
	_sect.name = "SectRuntime"
	_sect.set_script(sect_script)
	get_node(CONTAINER_SYSTEMS).add_child(_sect)


## Instantiate the FactionRuntime subsystem under Systems (Phase 07). Same shape as the other
## three: a script-created node, not an autoload (the D-017 budget stays at 5), not a scene.
func _create_faction_runtime() -> void:
	if _faction != null and is_instance_valid(_faction):
		return
	var faction_script: Script = load(FACTION_RUNTIME_SCRIPT)
	if faction_script == null:
		push_error("[boot] failed to load FactionRuntime script: %s" % FACTION_RUNTIME_SCRIPT)
		return
	_faction = Node.new()
	_faction.name = "FactionRuntime"
	_faction.set_script(faction_script)
	get_node(CONTAINER_SYSTEMS).add_child(_faction)


## Instantiate the WorldSimulationRuntime subsystem under Systems (Phase 08). Same shape as
## the other four: a script-created node, not an autoload, not a scene.
func _create_world_sim_runtime() -> void:
	if _world_sim != null and is_instance_valid(_world_sim):
		return
	var sim_script: Script = load(WORLD_SIM_RUNTIME_SCRIPT)
	if sim_script == null:
		push_error("[boot] failed to load WorldSimulationRuntime script: %s"
			% WORLD_SIM_RUNTIME_SCRIPT)
		return
	_world_sim = Node.new()
	_world_sim.name = "WorldSimulationRuntime"
	_world_sim.set_script(sim_script)
	get_node(CONTAINER_SYSTEMS).add_child(_world_sim)


## Instantiates the main-menu shell under the UI layer and wires its intents. Returns
## nothing but reports loudly on any required failure (lifecycle rejection, scene load),
## leaving the app in a reported-broken state rather than a silently half-shown menu.
func _show_menu() -> void:
	var gs := _game_state()

	# enter_menu is a REQUIRED transition (from READY on first boot, or from a running
	# session on return). A rejection means the lifecycle is in an unexpected phase.
	if not bool(gs.call("enter_menu")):
		push_error("[main] enter_menu rejected from phase %s; aborting show_menu"
			% String(gs.call("phase_name")))
		return

	# Any content scene from a previous session is cleared on return to menu.
	_scene_router().call("clear_current_scene")

	if _menu != null and is_instance_valid(_menu):
		return  # menu already shown

	var packed: PackedScene = load(MENU_SCENE) as PackedScene
	if packed == null:
		push_error("[main] failed to load main menu scene: %s" % MENU_SCENE)
		return
	_menu = packed.instantiate() as Control
	get_node(CONTAINER_UI).add_child(_menu)
	_menu.connect("new_game_pressed", _on_new_game_pressed)
	_menu.connect("settings_pressed", _on_settings_pressed)
	_menu.connect("quit_pressed", _on_quit_pressed)


func _hide_menu() -> void:
	# Close settings with the menu: it is a child of the menu flow, so leaving it parented
	# while the session starts would strand a Control over the running game.
	if _settings != null and is_instance_valid(_settings):
		_settings.queue_free()
	_settings = null
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null


## New Game intent from the menu: start the session, load the first scene via the router,
## confirm the session is running. The menu decided nothing about how this happens.
func _on_new_game_pressed() -> void:
	var gs := _game_state()

	if _world == null or not is_instance_valid(_world):
		push_error("[main] cannot start new game: WorldRuntime missing")
		return

	if not bool(gs.call("start_new_game")):
		push_error("[main] start_new_game rejected from current phase")
		return

	_hide_menu()

	# WorldRuntime registers the map catalog, spawns the persistent player, and loads the
	# first map (the hub) through SceneRouter. It owns the "why/when"; the router owns the
	# "how". On any failure, unwind to a usable menu rather than a half-started session.
	if not bool(_world.call("start_session")):
		push_error("[main] world session failed to start; returning to menu")
		_unwind_failed_session()
		return

	# Start the relationship session alongside the world session (D-026). Since Phase 06 this
	# is FATAL, not advisory: the sect session mirrors Sect↔Sect diplomacy INTO this graph, so
	# a missing graph means the sect world would start half-wired (sect state declaring
	# enemies that no relationship edge records). A hard dependency fails the New Game.
	if _relationship == null or not is_instance_valid(_relationship):
		push_error("[main] cannot start new game: RelationshipRuntime missing")
		_unwind_failed_session()
		return
	if not bool(_relationship.call("start_session")):
		push_error("[main] relationship session failed to start; returning to menu")
		_unwind_failed_session()
		return

	# Start the sect session (Phase 06), AFTER the world + relationship sessions: it enrolls
	# the player (from WorldRuntime's CharacterState) into the authored start sect and mirrors
	# Sect↔Sect alliances into the relationship graph. Also FATAL: the player's CharacterState
	# carries a DERIVED sect cache, so letting a failed sect session through could leave the
	# forbidden combination "RUNNING + world active + character.sect_id set + sect session
	# inactive" — a running game whose sect membership no system owns.
	if not _start_sect_session():
		push_error("[main] sect session failed to start; returning to menu")
		_unwind_failed_session()
		return

	# Start the faction session (Phase 07) LAST: it reads the sect store (its membership
	# authority) and the relationship graph (where faction standing lives), so both must
	# already be live. Also FATAL — the player's CharacterState carries a DERIVED
	# `faction_id` cache, so letting a failed faction session through could leave a running
	# game whose internal politics no system owns, the same class of orphaned state the sect
	# session guards against.
	if not _start_faction_session():
		push_error("[main] faction session failed to start; returning to menu")
		_unwind_failed_session()
		return

	# Start the world-simulation session (Phase 08) LAST: it reads all four subsystems above.
	# Also FATAL — the simulation writes `CharacterState.sim_state` for its whole cast and
	# enrols that cast into sects and factions through their services, so a failed start could
	# otherwise leave a running game whose background population is half-registered: on sect
	# rosters, but with no simulation owning what they are doing. Same class of orphaned state
	# the sect and faction sessions guard against.
	if not _start_world_sim_session():
		push_error("[main] world simulation session failed to start; returning to menu")
		_unwind_failed_session()
		return

	# confirm_session_running (STARTING_SESSION -> RUNNING) is a REQUIRED step. If rejected,
	# the first map is up but the lifecycle is wrong, so do not pretend we are RUNNING.
	if not bool(gs.call("confirm_session_running")):
		push_error("[main] confirm_session_running rejected; unwinding to menu")
		_unwind_failed_session()
		return


## Unwind a partially-started New Game back to a usable menu.
##
## Callable from any failure point in `_on_new_game_pressed`: every step of
## `_end_session_stack()` is null-safe and idempotent (`end_session` on all four runtimes is
## safe when no session is active). After it runs there is no session anywhere — no player, no
## map, no graph, no sect store, no faction store — and the lifecycle is back at MENU with the
## menu shown.
func _unwind_failed_session() -> void:
	_end_session_stack()
	_show_menu()


## End EVERYTHING this session owns, in exact reverse dependency order (D-047).
##
## Walks `SESSION_START_ORDER` backwards and then ends the `GameState` session, so the order is
## Faction → Sect → Relationship → World → GameState. That direction is not a preference: each
## subsystem holds state DEFINED IN TERMS OF the ones ended after it. The faction session reads
## the sect store (its membership authority, D-015) and the relationship graph (where
## Faction↔Faction standing lives, D-042); the sect session holds the relationship graph (its
## diplomacy mirror) and the player's `CharacterState` (its derived membership cache). Ending a
## dependency first drops state the dependent is still unwinding through, which is how a
## teardown can leave a sect roster referring to a character that no longer exists.
##
## This is the ONLY teardown path — the failed-start unwind and the normal return to menu both
## go through it, so the two can no longer disagree (the Phase-07 defect was exactly that they
## did). It records what it ended into `_last_teardown_order` so the order is OBSERVABLE rather
## than merely commented.
func _end_session_stack() -> void:
	var ended: Array[StringName] = []
	for i in range(SESSION_START_ORDER.size() - 1, -1, -1):
		var subsystem: StringName = SESSION_START_ORDER[i]
		var node := _session_node(subsystem)
		if node == null or not is_instance_valid(node):
			continue  # never created (boot aborted) or already freed: nothing to end
		node.call("end_session")
		ended.append(subsystem)
	var gs := _game_state()
	if gs != null and bool(gs.call("is_session_active")):
		gs.call("end_session")
		ended.append(SESSION_OWNER_STEP)
	_last_teardown_order = ended


## Resolve a `SESSION_START_ORDER` name to the node Main owns for it.
##
## An explicit `match`, deliberately not reflection over `Main/Systems` children: a name with
## no case here reports loudly instead of being silently skipped, and the teardown can never
## pick up some unrelated node that happens to expose an `end_session` method.
func _session_node(subsystem: StringName) -> Node:
	match subsystem:
		&"WorldRuntime":
			return _world
		&"RelationshipRuntime":
			return _relationship
		&"SectRuntime":
			return _sect
		&"FactionRuntime":
			return _faction
		&"WorldSimulationRuntime":
			return _world_sim
	push_error("[main] SESSION_START_ORDER names '%s', which Main owns no node for; its "
		% subsystem + "session would be silently skipped on teardown")
	return null


## What the last teardown ended, in the order it ended it (empty before the first teardown).
## A copy, so a caller cannot edit the record. See `_last_teardown_order`.
func get_last_teardown_order() -> Array[StringName]:
	return _last_teardown_order.duplicate()


## Start the SectRuntime session (Phase 06). Pulls the shared RelationshipService from the
## RelationshipRuntime (for the Sect↔Sect mirror), builds a character resolver bound to
## WorldRuntime's single player CharacterState (so the service validates membership + syncs
## the player's derived cache without touching /root or the tree, §11), and enrolls the player
## using WorldRuntime's stable instance id.
##
## Returns TRUE only when the sect session is actually live. Every prerequisite the caller
## cannot see from outside is reported as a failure here (missing SectRuntime, missing
## RelationshipService, missing player CharacterState) rather than quietly skipped, because
## New Game treats a sect failure as fatal and must not proceed on a half-wired session.
func _start_sect_session() -> bool:
	if _sect == null or not is_instance_valid(_sect):
		push_error("[main] cannot start sect session: SectRuntime missing")
		return false
	if _relationship == null or not is_instance_valid(_relationship):
		push_error("[main] cannot start sect session: RelationshipRuntime missing")
		return false
	var rel_service: RelationshipService = _relationship.call("get_service")
	if rel_service == null:
		push_error("[main] cannot start sect session: no RelationshipService (graph session "
			+ "not running) to mirror Sect↔Sect diplomacy into")
		return false
	var player_character: CharacterState = null
	if _world != null and is_instance_valid(_world):
		player_character = _world.call("get_player_character")
	if player_character == null:
		push_error("[main] cannot start sect session: WorldRuntime has no player "
			+ "CharacterState to enroll")
		return false
	var player_id: StringName = player_character.instance_id
	# Resolver: the session's ONE character registry (Phase 08). It returns the authoritative
	# `CharacterState` for any id that exists and null otherwise, so the service rejects
	# enrolling a non-existent character and never invents one (§10).
	#
	# It used to be a closure that knew about the player and nothing else, which was correct
	# while the player was the only character in the world. The moment the world gained a cast
	# that would have made the sect service reject characters that demonstrably existed — so
	# the resolver now comes from the collection that actually answers "who exists".
	var registry := _character_registry()
	if registry == null:
		push_error("[main] cannot start sect session: WorldRuntime has no character registry")
		return false
	if not bool(_sect.call("start_session", rel_service, registry.resolver(), player_id)):
		return false
	# The hub map loaded during world start_session (BEFORE the sect session existed), so push
	# the now-available sect view into the already-active map's HUD.
	if _world != null and is_instance_valid(_world) \
			and _world.has_method("refresh_active_map_sect_view"):
		_world.call("refresh_active_map_sect_view")
	return true


## Start the FactionRuntime session (Phase 07).
##
## Hands over the two things the faction domain READS and never duplicates — the sect store
## (the single membership authority, D-015) and the shared RelationshipService (where
## Faction↔Faction standing lives, D-042) — plus the same character-resolver seam the sect
## session uses, so the service can maintain the derived `CharacterState.faction_id` cache
## without touching `/root` (§11).
##
## The player id is passed for the VIEW only: the faction session deliberately enrols nobody,
## because the authored start SECT is a scaffold (C-003) and turning it into an authored
## faction allegiance would hand the player a political identity they never chose. Taking a
## side is a gameplay act from P-17 onward.
##
## Returns TRUE only when the faction session is actually live. Every prerequisite the caller
## cannot see from outside is reported here rather than quietly skipped, because New Game
## treats a faction failure as fatal and must not proceed on a half-wired session.
func _start_faction_session() -> bool:
	if _faction == null or not is_instance_valid(_faction):
		push_error("[main] cannot start faction session: FactionRuntime missing")
		return false
	if _sect == null or not is_instance_valid(_sect):
		push_error("[main] cannot start faction session: SectRuntime missing")
		return false
	var sect_store: SectStore = _sect.call("get_store")
	if sect_store == null:
		push_error("[main] cannot start faction session: no SectStore (sect session not "
			+ "running), so no faction's parent sect or membership could be verified")
		return false
	if _relationship == null or not is_instance_valid(_relationship):
		push_error("[main] cannot start faction session: RelationshipRuntime missing")
		return false
	var rel_service: RelationshipService = _relationship.call("get_service")
	if rel_service == null:
		push_error("[main] cannot start faction session: no RelationshipService (graph "
			+ "session not running) to mirror Faction↔Faction standing into")
		return false
	var player_character: CharacterState = null
	if _world != null and is_instance_valid(_world):
		player_character = _world.call("get_player_character")
	if player_character == null:
		push_error("[main] cannot start faction session: WorldRuntime has no player "
			+ "CharacterState")
		return false
	var player_id: StringName = player_character.instance_id
	# The SAME registry-backed resolver the sect session uses (see `_start_sect_session`).
	var registry := _character_registry()
	if registry == null:
		push_error("[main] cannot start faction session: WorldRuntime has no character "
			+ "registry")
		return false
	if not bool(_faction.call(
			"start_session", sect_store, rel_service, registry.resolver(), player_id)):
		return false
	# Same reason as the sect refresh above: the hub map was already loaded before this
	# session existed, so push the now-available politics view into its HUD.
	if _world != null and is_instance_valid(_world) \
			and _world.has_method("refresh_active_map_politics_view"):
		_world.call("refresh_active_map_politics_view")
	return true


## Start the WorldSimulationRuntime session (Phase 08).
##
## Hands over the four things the simulation READS and never duplicates — the character
## registry (its cast are real `CharacterState`s), the sect service (its actors enrol through
## it and its events move sect influence through it), the faction service, and the shared
## `RelationshipService` — plus the session's map lookup, because the LOD band is a map-graph
## question and a domain service has no business loading the map catalog.
##
## THE WORLD SEED is derived from the run id rather than from the clock: a run must reproduce
## its own world on every load (`docs/SAVE_FORMAT.md` §3b) while two different runs must get
## different worlds, and `MULTIPLAYER_PLAN.md` §7 lists wall-clock-seeded simulation as a
## corner-painting risk. Hashing the run id gives both properties with no randomness at all.
##
## Returns TRUE only when the simulation session is actually live. Every prerequisite the
## caller cannot see from outside is reported here rather than quietly skipped, because New
## Game treats a simulation failure as fatal and must not proceed on a half-wired world.
func _start_world_sim_session() -> bool:
	if _world_sim == null or not is_instance_valid(_world_sim):
		push_error("[main] cannot start world simulation: WorldSimulationRuntime missing")
		return false
	var registry := _character_registry()
	if registry == null:
		push_error("[main] cannot start world simulation: WorldRuntime has no character "
			+ "registry to put its cast in")
		return false
	var sect_service: SectService = null
	if _sect != null and is_instance_valid(_sect):
		sect_service = _sect.call("get_service")
	if sect_service == null:
		push_error("[main] cannot start world simulation: no SectService (sect session not "
			+ "running), so its actors could not enrol and sect influence would have no owner")
		return false
	var faction_service: FactionService = null
	if _faction != null and is_instance_valid(_faction):
		faction_service = _faction.call("get_service")
	if faction_service == null:
		push_error("[main] cannot start world simulation: no FactionService (faction session "
			+ "not running)")
		return false
	var rel_service: RelationshipService = null
	if _relationship != null and is_instance_valid(_relationship):
		rel_service = _relationship.call("get_service")
	if rel_service == null:
		push_error("[main] cannot start world simulation: no RelationshipService (graph "
			+ "session not running) for its relationship events to apply through")
		return false
	var map_lookup: Dictionary = {}
	if _world != null and is_instance_valid(_world):
		map_lookup = _world.call("get_map_lookup")
	if map_lookup.is_empty():
		push_error("[main] cannot start world simulation: WorldRuntime exposed no map "
			+ "catalog, so no LOD band could be computed")
		return false

	if not bool(_world_sim.call("start_session",
			registry, sect_service, faction_service, rel_service, map_lookup,
			_world_seed_for_run())):
		return false
	# The hub map was loaded during the WORLD session, before this one existed, so the
	# arrival beat and the first view push both happened with no simulation listening. Tell
	# it where the player already is and populate the HUD — same pattern as the sect and
	# politics refreshes above.
	if _world != null and is_instance_valid(_world) \
			and _world.has_method("refresh_active_map_world_sim_view"):
		_world.call("refresh_active_map_world_sim_view")
	return true


## The world seed for the current run: a stable hash of the run id, or the simulation's own
## documented default when no run id is available. Never time-based (see
## `_start_world_sim_session`).
func _world_seed_for_run() -> int:
	var gs := _game_state()
	if gs == null:
		return WorldSimulationRuntime.DEFAULT_WORLD_SEED
	var run_id := String(gs.call("get_run_id"))
	if run_id == "":
		return WorldSimulationRuntime.DEFAULT_WORLD_SEED
	# `hash()` is deterministic for a given string within an engine version, and the mask
	# keeps it inside the 32-bit range the RNG seam accepts.
	return hash(run_id) & RngStream.MASK_32


## The session's character registry (or null before the world session starts).
func _character_registry() -> CharacterRegistry:
	if _world == null or not is_instance_valid(_world):
		return null
	return _world.call("get_character_registry")


## The NORMAL end of a session (the player asked to go back to the menu).
##
## Identical teardown to a failed start, through the SAME function: Faction → Sect →
## Relationship → World → GameState, then the menu. It used to have its own hand-written
## sequence, which had drifted into the wrong order (World and Relationship were ended before
## Faction and Sect), so a normal return to menu tore out the relationship graph and the
## player's CharacterState while the two subsystems defined in terms of them were still live.
## Having one path is the fix; `_end_session_stack()` documents why the direction matters.
func _on_return_to_menu() -> void:
	_end_session_stack()
	_show_menu()


## Settings intent from the menu (D-035): show the settings screen OVER the menu.
##
## The menu is HIDDEN, not freed, and `GameState` is not touched at all — we are already in
## the MENU phase and settings is not a lifecycle step. Re-running `_show_menu()` on the way
## back would ask for an `enter_menu` transition we are already in, so this path deliberately
## avoids it: settings opens and closes as pure UI.
func _on_settings_pressed() -> void:
	if _settings != null and is_instance_valid(_settings):
		return  # already open
	var script: GDScript = load(SETTINGS_SCRIPT) as GDScript
	if script == null:
		push_error("[main] failed to load settings screen: %s" % SETTINGS_SCRIPT)
		return
	var screen: Control = script.new() as Control
	if screen == null:
		push_error("[main] settings screen is not a Control")
		return
	_settings = screen
	get_node(CONTAINER_UI).add_child(_settings)
	_settings.connect("close_requested", _on_settings_closed)
	# The menu is HIDDEN, not dimmed. Settings composes its own full backdrop (D-050), so it
	# is a screen rather than a translucent overlay — leaving the menu visible underneath put
	# a second plaque frame around the settings plaque and left the menu's title and Quit
	# label legible around its edges.
	if _menu != null and is_instance_valid(_menu):
		_menu.visible = false


## Back from settings: drop the screen and reveal the menu again (no lifecycle change).
func _on_settings_closed() -> void:
	if _settings != null and is_instance_valid(_settings):
		_settings.queue_free()
	_settings = null
	if _menu != null and is_instance_valid(_menu):
		_menu.visible = true
	else:
		# The menu went away while settings was open (not expected) — rebuild it properly.
		_show_menu()


## Is the settings screen currently open? (for tests)
func is_settings_open() -> bool:
	return _settings != null and is_instance_valid(_settings)





func _on_quit_pressed() -> void:
	get_tree().quit()


# --- Structure validation (kept from D-010 for the smoke test) ---

func has_required_structure() -> bool:
	return _has_required_containers()


func _has_required_containers() -> bool:
	for container_name in REQUIRED_CONTAINERS:
		if get_node_or_null(NodePath(container_name)) == null:
			push_error("[boot] Missing required container: %s" % container_name)
			return false
	return true


# --- Autoload accessors. Non-null once _verify_core_autoloads() has passed in _ready(). ---

func _game_state() -> Node:
	return get_node_or_null("/root/GameState")


func _scene_router() -> Node:
	return get_node_or_null("/root/SceneRouter")


func _event_bus() -> Node:
	return get_node_or_null("/root/EventBus")
