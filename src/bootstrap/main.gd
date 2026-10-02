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
const PROLOGUE_SCENE_KEY := "prologue"
const PROLOGUE_SCENE_PATH := "res://src/presentation/scenes/prologue_shell.tscn"

## Core autoloads the running application REQUIRES. If any is missing when the app is
## actually running, boot is a hard failure — a null autoload must never be silently
## tolerated at runtime (`.kiro/steering/04-coding-standards.md`: fail loud; no swallowed
## nulls). See `_verify_core_autoloads()` for the test-harness exception.
const REQUIRED_AUTOLOADS := ["GameState", "SceneRouter", "EventBus"]

var _menu: Control = null


func _ready() -> void:
	assert(_has_required_containers(), "Main scene is missing a required container node.")
	if not _verify_core_autoloads():
		# Real-app misconfiguration: a required core service is absent. Do not limp on in a
		# broken state — report loudly and stop booting. (In the headless unit-test harness
		# NO autoloads exist, which `_verify_core_autoloads` treats as test mode, not a fail.)
		return
	_boot()


## Returns false (and reports loudly) only when the app is clearly running for real yet a
## required core autoload is missing. When ZERO project autoloads are present we are in the
## headless test harness (run_tests.gd is a bare SceneTree with no autoloads), so Main is
## allowed to run its null-safe paths for structural tests — that is NOT a misconfiguration.
func _verify_core_autoloads() -> bool:
	var present := 0
	var missing: Array[String] = []
	for autoload_name in REQUIRED_AUTOLOADS:
		if get_node_or_null("/root/%s" % autoload_name) != null:
			present += 1
		else:
			missing.append(autoload_name)
	if missing.is_empty():
		return true
	if present == 0:
		# Test-harness context (no autoloads at all). Proceed null-safe; do not fail-fast.
		return true
	# Partially wired real app: some core services exist but required ones are missing.
	push_error("[boot] FATAL: required core autoload(s) missing: %s. Check project.godot "
		% str(missing) + "[autoload]. Aborting boot to avoid a half-wired game state.")
	assert(false, "Required core autoload(s) missing: %s" % str(missing))
	return false


## The boot sequence. Each step is an explicit, legal lifecycle transition owned by
## GameState; the bootstrap only sequences them.
func _boot() -> void:
	var gs := _game_state()
	var router := _scene_router()

	# Lifecycle transitions return false on an illegal move; surface that loudly rather
	# than booting on through a rejected transition into an inconsistent phase.
	if gs != null and not bool(gs.call("begin_initialization")):
		push_error("[boot] begin_initialization rejected; aborting boot")
		return

	# Give the router its content host and register the Phase-1 content scenes (by key).
	if router != null:
		router.call("set_scene_host", get_node(CONTAINER_WORLD))
		router.call("register_scene", PROLOGUE_SCENE_KEY, PROLOGUE_SCENE_PATH)

	if gs != null and not bool(gs.call("mark_ready")):
		push_error("[boot] mark_ready rejected; aborting boot")
		return

	var bus := _event_bus()
	if bus != null:
		bus.call("emit_game_booted")

	_show_menu()


## Instantiates the main-menu shell under the UI layer and wires its intents.
func _show_menu() -> void:
	var gs := _game_state()
	if gs != null:
		gs.call("enter_menu")

	# Any content scene from a previous session is cleared on return to menu.
	var router := _scene_router()
	if router != null:
		router.call("clear_current_scene")

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
	var router := _scene_router()
	if gs == null or router == null:
		push_error("[main] cannot start new game: core services missing")
		return

	if not gs.call("start_new_game"):
		push_error("[main] start_new_game rejected from current phase")
		return

	_hide_menu()
	var ok: bool = router.call("request_transition", PROLOGUE_SCENE_KEY)
	if not ok:
		# Transition failed — recover to a usable state rather than a half-started session.
		push_error("[main] first-scene transition failed; returning to menu")
		gs.call("end_session")
		_show_menu()
		return

	gs.call("confirm_session_running")
	_connect_prologue_return()


## The prologue shell asks to return to the menu via its signal (event-driven).
func _connect_prologue_return() -> void:
	var router := _scene_router()
	if router == null:
		return
	var scene: Node = router.call("get_current_scene")
	if scene != null and scene.has_signal("return_to_menu_requested"):
		if not scene.is_connected("return_to_menu_requested", _on_return_to_menu):
			scene.connect("return_to_menu_requested", _on_return_to_menu)


func _on_return_to_menu() -> void:
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


# --- Autoload accessors (null-safe so headless tests can run Main without autoloads) ---

func _game_state() -> Node:
	return get_node_or_null("/root/GameState")


func _scene_router() -> Node:
	return get_node_or_null("/root/SceneRouter")


func _event_bus() -> Node:
	return get_node_or_null("/root/EventBus")
