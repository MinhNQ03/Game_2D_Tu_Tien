extends TestCase
## Unit tests for SceneRouter (src/infrastructure/scene_router.gd).
##
## Uses a fresh router instance + a host node added to the live SceneTree so real
## instantiation/cleanup happens. Does not assert on the GameState singleton (kept to
## router behavior for isolation).

const RouterScript := preload("res://src/infrastructure/scene_router.gd")
const PROLOGUE_PATH := "res://src/presentation/scenes/prologue_shell.tscn"

var _router: Node
var _host: Node


func before_each() -> void:
	_router = RouterScript.new()
	_host = Node.new()
	add_to_tree(_router)
	add_to_tree(_host)
	_router.set_scene_host(_host)
	_router.register_scene("prologue", PROLOGUE_PATH)


func after_each() -> void:
	free_node(_router)
	free_node(_host)
	_router = null
	_host = null


func test_valid_transition_loads_scene() -> void:
	var ok: bool = _router.request_transition("prologue")
	assert_true(ok, "valid transition returns true")
	assert_eq(_router.get_current_key(), "prologue", "current key updated")
	assert_not_null(_router.get_current_scene(), "a content scene is active")
	assert_eq(_host.get_child_count(), 1, "exactly one content scene under host")


func test_invalid_target_fails() -> void:
	var ok: bool = _router.request_transition("does_not_exist")
	assert_false(ok, "unregistered scene_key fails")
	assert_eq(_router.get_current_key(), "", "no scene became current")
	assert_eq(_host.get_child_count(), 0, "host stays empty on failure")


func test_no_host_fails() -> void:
	var bare: Node = RouterScript.new()
	add_to_tree(bare)
	bare.register_scene("prologue", PROLOGUE_PATH)
	var ok: bool = bare.request_transition("prologue")
	assert_false(ok, "transition without a scene host fails")
	free_node(bare)


func test_second_transition_replaces_and_cleans_up() -> void:
	_router.request_transition("prologue")
	var first: Node = _router.get_current_scene()
	# Register a second key pointing at the same scene and transition again.
	_router.register_scene("prologue_b", PROLOGUE_PATH)
	var ok: bool = _router.request_transition("prologue_b")
	assert_true(ok, "second transition succeeds")
	assert_eq(_host.get_child_count(), 1, "old scene removed; only one remains (no leak)")
	assert_ne(_router.get_current_scene(), first, "current scene is the new instance")


func test_clear_current_scene() -> void:
	_router.request_transition("prologue")
	_router.clear_current_scene()
	assert_eq(_router.get_current_key(), "", "key cleared")
	# queue_free is deferred; the host child is freed by end of frame. The router's own
	# reference is cleared immediately, which is what callers rely on.
	assert_null(_router.get_current_scene(), "router no longer holds a current scene")


func test_not_transitioning_initially() -> void:
	assert_false(_router.is_transitioning(), "router idle after construction")
