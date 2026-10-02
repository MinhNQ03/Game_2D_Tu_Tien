extends SceneTree
## Placeholder headless test runner for Aetheria.
##
## Run with:
##   godot --headless --path . -s res://tests/run_tests.gd
##
## This is a temporary entry point until the test framework decision (D-004 in
## docs/DECISIONS.md) is made. It lets CI be wired early. It currently discovers no
## real tests because no gameplay exists yet, and exits 0 so a green pipeline is
## meaningful once tests are added.
##
## When D-004 is resolved (GUT vs. custom runner), replace or extend this file and
## update tests/README.md + docs/TEST_PLAN.md.

const TEST_DIRS := [
	"res://tests/unit",
	"res://tests/integration",
	"res://tests/gameplay",
	"res://tests/smoke",
	"res://tests/performance",
]


func _init() -> void:
	var discovered := 0
	for dir_path in TEST_DIRS:
		discovered += _count_test_scripts(dir_path)

	if discovered == 0:
		print("[tests] No tests yet — foundation phase. Exiting cleanly.")
		quit(0)
		return

	# Intentionally not executing yet: the real runner is defined once D-004 is decided.
	# Fail loudly so we never silently "pass" with an unfinished runner.
	push_error("[tests] %d test script(s) found but the runner is not implemented (see D-004)." % discovered)
	quit(1)


func _count_test_scripts(dir_path: String) -> int:
	var count := 0
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.begins_with("test_") and name.ends_with(".gd"):
			count += 1
		name = dir.get_next()
	dir.list_dir_end()
	return count
