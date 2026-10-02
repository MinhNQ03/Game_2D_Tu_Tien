extends SceneTree
## Headless test runner for Aetheria (custom runner — decision D-004).
##
## Run with:
##   godot --headless --path . -s res://tests/run_tests.gd
##
## Discovers every `test_*.gd` under the test directories, instantiates each (expected
## to extend TestCase), runs every `test_*` method, and reports results. Exit code:
##   0  -> all discovered tests passed (and at least the required smoke test ran)
##   1  -> one or more assertions/tests failed, a test file was malformed,
##         or the required smoke test was missing
##
## This runner has REAL assertions and REAL non-zero exit on failure. It is not a
## placeholder.

const TEST_DIRS := [
	"res://tests/unit",
	"res://tests/integration",
	"res://tests/gameplay",
	"res://tests/smoke",
	"res://tests/performance",
]

## The suite must always contain at least this smoke test. If it's gone, that's a
## failure (prevents the suite silently shrinking to nothing and reporting green).
const REQUIRED_TEST := "res://tests/smoke/test_boot.gd"


func _init() -> void:
	var total := 0
	var passed := 0
	var failed := 0
	var failures: Array[String] = []
	var found_files: Array[String] = []

	for dir_path in TEST_DIRS:
		for file_path in _list_test_scripts(dir_path):
			found_files.append(file_path)

	if not found_files.has(REQUIRED_TEST):
		push_error("[tests] Required smoke test missing: %s" % REQUIRED_TEST)
		print("[tests] FAIL — required smoke test not found.")
		quit(1)
		return

	for file_path in found_files:
		var script: Script = load(file_path)
		if script == null:
			failed += 1
			failures.append("%s — could not load script" % file_path)
			continue

		var test_case: Object = script.new()
		# Duck-typed check: a valid test exposes the TestCase runner API. Avoids a hard
		# static dependency on the class_name being registered in the global cache.
		if not _is_test_case(test_case):
			failed += 1
			failures.append("%s — does not implement the TestCase API" % file_path)
			continue

		for method_name in _test_methods(test_case):
			total += 1
			test_case.call("reset_failures")
			test_case.call("before_each")
			test_case.call(method_name)
			test_case.call("after_each")
			var method_failures: Array = test_case.call("get_failures")
			if method_failures.is_empty():
				passed += 1
				print("[PASS] %s::%s" % [file_path, method_name])
			else:
				failed += 1
				for f in method_failures:
					var line := "[FAIL] %s::%s — %s" % [file_path, method_name, f]
					print(line)
					failures.append(line)

	print("\n[tests] ran %d test(s): %d passed, %d failed." % [total, passed, failed])

	if total == 0:
		push_error("[tests] No test methods were executed.")
		quit(1)
		return

	if failed > 0:
		print("[tests] RESULT: FAIL")
		quit(1)
		return

	print("[tests] RESULT: PASS")
	quit(0)


## True if the object exposes the TestCase runner API (duck typing).
func _is_test_case(obj: Object) -> bool:
	return obj != null \
		and obj.has_method("reset_failures") \
		and obj.has_method("get_failures") \
		and obj.has_method("before_each") \
		and obj.has_method("after_each")


## Returns the `test_*` method names declared on a test instance.
func _test_methods(test_case: Object) -> Array[String]:
	var names: Array[String] = []
	for m in test_case.get_method_list():
		var n: String = m.get("name", "")
		if n.begins_with("test_"):
			names.append(n)
	names.sort()
	return names


## Returns absolute res:// paths of `test_*.gd` scripts directly inside a directory.
func _list_test_scripts(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.begins_with("test_") and name.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, name])
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
