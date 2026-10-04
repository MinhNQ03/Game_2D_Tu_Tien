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

var _menu: Control = null
var _settings: Control = null  # settings screen while open (D-035); null otherwise
var _world: Node = null   # WorldRuntime (per-session world/map coordinator), under Systems
# RelationshipRuntime (per-session relationship graph), under Systems (D-026).
var _relationship: Node = null
# SectRuntime (per-session sect domain), under Systems (Phase 06).
var _sect: Node = null


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

	# confirm_session_running (STARTING_SESSION -> RUNNING) is a REQUIRED step. If rejected,
	# the first map is up but the lifecycle is wrong, so do not pretend we are RUNNING.
	if not bool(gs.call("confirm_session_running")):
		push_error("[main] confirm_session_running rejected; unwinding to menu")
		_unwind_failed_session()
		return


## Unwind a partially-started New Game back to a usable menu.
##
## Order is REVERSE DEPENDENCY order — Sect → Relationship → World → GameState → menu —
## because the sect session holds the relationship graph (its diplomacy mirror) and the
## player's CharacterState (its derived membership cache), both of which are owned by the
## subsystems ended after it. Ending a dependency first would drop state the dependent is
## still unwinding through.
##
## Every step is null-safe and idempotent (`end_session` on all three runtimes is safe to
## call when no session is active), so this is callable from any failure point in
## `_on_new_game_pressed`. After it runs there is no session anywhere: no player, no map, no
## graph, no sect store, and the lifecycle is back at MENU with the menu shown.
func _unwind_failed_session() -> void:
	if _sect != null and is_instance_valid(_sect):
		_sect.call("end_session")
	if _relationship != null and is_instance_valid(_relationship):
		_relationship.call("end_session")
	if _world != null and is_instance_valid(_world):
		_world.call("end_session")
	var gs := _game_state()
	if gs != null and bool(gs.call("is_session_active")):
		gs.call("end_session")
	_show_menu()


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
	# Resolver: the ONLY character this session knows is the player (no CharacterRegistry yet,
	# §11). It returns the player's CharacterState for the player's id, else null — so the
	# service rejects enrolling any non-existent character and never invents one (§10).
	var resolver := func(cid: StringName) -> CharacterState:
		if cid == player_id:
			return player_character
		return null
	if not bool(_sect.call("start_session", rel_service, resolver, player_id)):
		return false
	# The hub map loaded during world start_session (BEFORE the sect session existed), so push
	# the now-available sect view into the already-active map's HUD.
	if _world != null and is_instance_valid(_world) \
			and _world.has_method("refresh_active_map_sect_view"):
		_world.call("refresh_active_map_sect_view")
	return true


func _on_return_to_menu() -> void:
	# End the world session (frees the persistent player + clears the active map) before the
	# lifecycle returns to MENU.
	if _world != null and is_instance_valid(_world):
		_world.call("end_session")
	# End the relationship session too (drops the per-session graph).
	if _relationship != null and is_instance_valid(_relationship):
		_relationship.call("end_session")
	# End the sect session (drops the per-session sect store/service).
	if _sect != null and is_instance_valid(_sect):
		_sect.call("end_session")
	var gs := _game_state()
	if gs != null and gs.call("is_session_active"):
		gs.call("end_session")
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
