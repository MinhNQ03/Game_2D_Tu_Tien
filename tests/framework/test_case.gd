extends RefCounted
class_name TestCase
## Minimal test-case base for Aetheria's custom headless runner (decision D-004).
##
## A test file extends this class and defines methods named `test_*`. The runner
## instantiates the class, calls every `test_*` method, and records failures.
##
## Assertions record a failure (they do NOT throw). GDScript has no try/catch, so the
## harness cannot catch a hard runtime error inside a test method — that will abort the
## engine process with a non-zero exit, which the runner/CI still surfaces as failure
## (documented limitation, see docs/TEST_PLAN.md and DECISIONS.md D-004). Recorded
## assertion failures are the normal, catchable failure path and keep output useful.

## Failures recorded during the currently running test method.
var _failures: Array[String] = []

## The live SceneTree, injected by the runner. Lets a test add a Node to the tree so
## real node lifecycle (`_ready`, `_enter_tree`) runs. Null when run outside the runner.
var scene_tree: SceneTree = null


## Optional per-test setup/teardown hooks a subclass may override.
func before_each() -> void:
	pass


func after_each() -> void:
	pass


# --- Runner-facing API (public on purpose; called by run_tests.gd across class scope) ---

## Injected by the runner before methods run.
func set_scene_tree(tree: SceneTree) -> void:
	scene_tree = tree


## Resets failure state before a test method runs.
func reset_failures() -> void:
	_failures = []


## Returns the failures recorded during the last test method.
func get_failures() -> Array[String]:
	return _failures


# --- SceneTree helpers (real Godot lifecycle) --------------------------------

## Adds `node` to the scene tree root so `_enter_tree`/`_ready` actually run. Returns
## true on success. The caller must later call `free_node(node)` to avoid orphan nodes.
func add_to_tree(node: Node) -> bool:
	if scene_tree == null:
		_fail("add_to_tree failed: no SceneTree injected (run via run_tests.gd)")
		return false
	if node == null:
		_fail("add_to_tree failed: node is null")
		return false
	scene_tree.root.add_child(node)
	return true


## Removes `node` from the tree and frees it immediately (no orphan). Safe on null.
func free_node(node: Node) -> void:
	if node == null:
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _fail(message: String) -> void:
	_failures.append(message)


# --- Assertions -------------------------------------------------------------

func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		_fail("assert_true failed: %s" % (message if message != "" else "expected true"))


func assert_false(condition: bool, message: String = "") -> void:
	if condition:
		_fail("assert_false failed: %s" % (message if message != "" else "expected false"))


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		_fail("assert_eq failed: expected %s but got %s. %s" % [
			str(expected), str(actual), message])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if actual == unexpected:
		_fail("assert_ne failed: value should not equal %s. %s" % [str(unexpected), message])


func assert_not_null(value: Variant, message: String = "") -> void:
	if value == null:
		_fail("assert_not_null failed: %s" % (message if message != "" else "value was null"))


func assert_null(value: Variant, message: String = "") -> void:
	if value != null:
		_fail("assert_null failed: %s" % (message if message != "" else "value was not null"))
