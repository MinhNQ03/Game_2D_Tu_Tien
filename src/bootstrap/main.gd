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

var _menu: Control = null


func _ready() -> void:
	assert(_has_required_containers(), "Main scene is missing a required container node.")
	_boot()


## The boot sequence. Each step is an explicit, legal lifecycle transition owned by
## GameState; the bootstrap only sequences them.
func _boot() -> void:
	var gs := _game_state()
	var router := _scene_router()

	if gs != null:
		gs.call("begin_initialization")

	# Give the router its content host and register the Phase-1 content scenes (by key).
	if router != null:
		router.call("set_scene_host", get_node(CONTAINER_WORLD))
		router.call("register_scene", PROLOGUE_SCENE_KEY, PROLOGUE_SCENE_PATH)

	if gs != null:
		gs.call("mark_ready")

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
