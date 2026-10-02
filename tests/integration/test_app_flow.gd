extends TestCase
## End-to-end APP flow test — the real boot path, not a hand-rolled stand-in.
##
## Unlike test_boot_flow.gd (which drives GameState + SceneRouter directly), this test
## stands up the ACTUAL core autoloads under /root with their real names, instantiates the
## real main.tscn, lets Main's own _ready()/_boot() run, then drives the real MainMenu's
## `new_game_pressed` signal — exactly what a player click does. It asserts the whole chain
## wired itself: menu intent -> GameState session -> SceneRouter loaded the first content
## scene -> phase RUNNING. Then it tears everything down with no orphan nodes.
##
## This is the test that would catch a regression where Main stops wiring the menu, the
## router host is never set, or the lifecycle never reaches RUNNING — none of which the
## direct-driving integration test can see.

const MAIN_SCENE_PATH := "res://main.tscn"

const EventBusScript := preload("res://src/infrastructure/event_bus.gd")
const GameStateScript := preload("res://src/infrastructure/game_state.gd")
const LocalizationScript := preload("res://src/infrastructure/localization.gd")
const InputServiceScript := preload("res://src/infrastructure/input_service.gd")
const SceneRouterScript := preload("res://src/infrastructure/scene_router.gd")

# Autoloads we spin up for the test, by their canonical /root names.
var _autoloads: Array[Node] = []


## Create the five Phase-01 autoloads as named /root children so Main's
## get_node_or_null("/root/<Name>") lookups resolve exactly as in the shipped app.
func _spawn_autoloads() -> void:
	var specs := {
		"EventBus": EventBusScript,
		"GameState": GameStateScript,
		"Localization": LocalizationScript,
		"InputService": InputServiceScript,
		"SceneRouter": SceneRouterScript,
	}
	for node_name in specs.keys():
		var node: Node = specs[node_name].new()
		node.name = node_name
		scene_tree.root.add_child(node)
		_autoloads.append(node)


func _despawn_autoloads() -> void:
	for node in _autoloads:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_autoloads.clear()


func after_each() -> void:
	_despawn_autoloads()


func test_new_game_click_boots_a_running_session() -> void:
	_spawn_autoloads()

	var packed: PackedScene = load(MAIN_SCENE_PATH)
	assert_not_null(packed, "main scene loads")
	if packed == null:
		return
	var main: Node = packed.instantiate()
	assert_not_null(main, "main scene instantiates")
	if main == null:
		return

	# Entering the tree runs Main._ready() -> _verify_core_autoloads() -> _boot() -> menu.
	add_to_tree(main)
	await scene_tree.process_frame  # let _ready() across the shell + menu run

	var gs: Node = scene_tree.root.get_node_or_null("GameState")
	var router: Node = scene_tree.root.get_node_or_null("SceneRouter")
	assert_not_null(gs, "GameState autoload present")
	assert_not_null(router, "SceneRouter autoload present")

	# Boot should have reached the MENU phase and shown the real menu under UI.
	assert_eq(gs.get_phase(), gs.Phase.MENU, "boot settled at MENU before input")
	var ui: Node = main.get_node_or_null("UI")
	assert_not_null(ui, "UI container exists")
	assert_eq(ui.get_child_count(), 1, "exactly one menu shown under UI")
	var menu: Node = ui.get_child(0)
	assert_true(menu.has_signal("new_game_pressed"), "menu exposes new_game_pressed")

	# Drive the REAL player intent: emit the menu's New Game signal.
	menu.emit_signal("new_game_pressed")
	await scene_tree.process_frame  # let the first content scene's _ready() run

	# The whole chain should now be wired: session running + first scene loaded.
	assert_true(gs.is_session_active(), "a session is active after New Game")
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "lifecycle reached RUNNING")
	assert_eq(router.get_current_key(), "prologue",
		"SceneRouter loaded the first content scene (prologue)")
	assert_not_null(router.get_current_scene(), "a live content scene instance exists")

	var world: Node = main.get_node_or_null("World")
	assert_not_null(world, "World container exists")
	assert_eq(world.get_child_count(), 1, "exactly one content scene under World (no leak)")

	# Clean teardown — Main and all its children leave the tree with no orphans.
	free_node(main)
