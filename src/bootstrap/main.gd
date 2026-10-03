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

## PHASE 03: New Game now enters the WORLD via `WorldRuntime` (a node under `Main/Systems`),
## which owns the per-session persistent Player and loads the first MAP (the hub) through
## SceneRouter. This replaces the Phase-02 single `FIRST_SCENE_KEY` wiring — maps are now
## catalog-driven in WorldRuntime, not a hard-coded first scene here (`docs/ARCHITECTURE.md`
## §9; D-021). The Phase-02 sandbox + Phase-01 prologue shell are retained in the repo but
## are no longer the first scene.
const WORLD_RUNTIME_SCRIPT := "res://src/gameplay/world/world_runtime.gd"

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
var _world: Node = null   # WorldRuntime (per-session world/map coordinator), under Systems


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

	# Give the router its content host (the World node). Map scene_keys are registered by
	# WorldRuntime at session start, not here (catalog-driven — D-021).
	router.call("set_scene_host", get_node(CONTAINER_WORLD))

	# Create the WorldRuntime coordinator under Systems (a node, not an autoload — D-017).
	# It is idle until New Game starts a session.
	_create_world_runtime()

	if not bool(gs.call("mark_ready")):
		push_error("[boot] mark_ready rejected; aborting boot")
		return

	_event_bus().call("emit_game_booted")

	_show_menu()


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
	_menu.connect("quit_pressed", _on_quit_pressed)


func _hide_menu() -> void:
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
		_world.call("end_session")
		gs.call("end_session")
		_show_menu()
		return

	# confirm_session_running (STARTING_SESSION -> RUNNING) is a REQUIRED step. If rejected,
	# the first map is up but the lifecycle is wrong, so do not pretend we are RUNNING.
	if not bool(gs.call("confirm_session_running")):
		push_error("[main] confirm_session_running rejected; unwinding to menu")
		_world.call("end_session")
		gs.call("end_session")
		_show_menu()
		return


func _on_return_to_menu() -> void:
	# End the world session (frees the persistent player + clears the active map) before the
	# lifecycle returns to MENU.
	if _world != null and is_instance_valid(_world):
		_world.call("end_session")
	var gs := _game_state()
	if gs != null and gs.call("is_session_active"):
		gs.call("end_session")
	_show_menu()


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
