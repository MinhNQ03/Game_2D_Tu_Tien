extends RefCounted
class_name TestCase
## Minimal test-case base for Aetheria's custom headless runner (decision D-004).
##
## A test file extends this class and defines methods named `test_*`. The runner
## instantiates the class, calls each `test_*` method, and records failures.
##
## Assertions record a failure (they do NOT throw) so that one failing assertion
## doesn't abort the rest of the method; the runner reports every failure and sets a
## non-zero exit code if any occurred. This keeps output useful in CI.

## Failures recorded during the currently running test method.
var _failures: Array[String] = []

## Optional per-test setup/teardown hooks a subclass may override.
func before_each() -> void:
	pass


func after_each() -> void:
	pass


## Runner-facing API (public on purpose; called by run_tests.gd across class scope).
## Resets failure state before a test method runs.
func reset_failures() -> void:
	_failures = []


## Returns the failures recorded during the last test method.
func get_failures() -> Array[String]:
	return _failures


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
