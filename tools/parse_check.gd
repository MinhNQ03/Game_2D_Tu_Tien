extends SceneTree
## Project-wide GDScript parse check for Aetheria CI (foundation hardening).
##
## Run with:
##   godot --headless --path . -s res://tools/parse_check.gd
##
## Recursively scans the source + test directories, loads every `.gd` file, and fails
## (exit 1) if any script cannot be loaded/compiled. This catches parse errors in files
## that no test happens to import. Exit 0 only if every script loads.
##
## This is a tooling script, not a game system — it has no gameplay logic.

## Directories to scan for GDScript. Add new source roots here as the project grows.
const SCAN_DIRS := ["res://src", "res://tests", "res://tools"]


func _initialize() -> void:
	var scripts := _collect_gd_files()
	var failed: Array[String] = []
	var checked := 0

	for path in scripts:
		checked += 1
		var res := load(path)
		if res == null:
			failed.append("%s — failed to load (parse/compile error)" % path)
			continue
		if not (res is GDScript):
			failed.append("%s — loaded but is not a GDScript" % path)

	print("[parse_check] scanned %d script(s)." % checked)

	if not failed.is_empty():
		for f in failed:
			push_error("[parse_check] %s" % f)
			print("[parse_check] FAIL: %s" % f)
			# CI diagnostic (steering 10 §1.3): emit a GitHub Actions error annotation so the
			# failing file is readable via the check-run annotations API (logs need auth, D-009).
			print("::error::[parse_check] %s" % f)
		print("[parse_check] RESULT: FAIL")
		quit(1)
		return

	print("[parse_check] RESULT: PASS")
	quit(0)


## Returns all `.gd` paths under SCAN_DIRS, sorted. Safe if a dir is missing. Uses an
## explicit stack (no recursion) so it cannot loop infinitely.
func _collect_gd_files() -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = []
	for d in SCAN_DIRS:
		pending.append(d)
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry == "." or entry == "..":
				entry = dir.get_next()
				continue
			var full := "%s/%s" % [dir_path, entry]
			if dir.current_is_dir():
				if not entry.begins_with("."):
					pending.append(full)
			elif entry.ends_with(".gd"):
				out.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out
