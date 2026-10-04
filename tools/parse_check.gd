extends SceneTree
## Project-wide GDScript parse check for Aetheria CI (foundation hardening).
##
## Run with:
##   godot --headless --path . -s res://tools/parse_check.gd
##
## Recursively scans the source + test directories and fails (exit 1) if any script does
## not fully COMPILE. This catches errors in files that no test happens to import.
##
## Three checks per script, in order of strictness (D-033):
##   1. `load()` returns a non-null GDScript.
##   2. `can_instantiate()` is true. THIS IS THE IMPORTANT ONE: `load()` returns a
##      non-null but UNUSABLE GDScript when a script parses yet fails to compile - which
##      is exactly how L-020 walked past this gate. A warning-promoted-to-error (e.g. a
##      local whose type is inferred from a `Variant` expression) leaves `load()` happy
##      while the class is broken; an invalid script cannot be instantiated. This check is
##      deliberately SIDE-EFFECT FREE: `reload()` would also detect it but recompiles the
##      script, including this running tool and the live autoloads (D-019), which is not
##      worth the risk in a gate that cannot be rehearsed locally (D-009). The project has
##      no `@abstract` classes, so "cannot instantiate" means "does not compile" here.
##   3. A script declaring `class_name X` must actually be registered as a global class.
##      When a script fails to compile its `class_name` silently never registers, so every
##      `X.some_static()` call site then dies at runtime with the deeply misleading
##      "Nonexistent function 'some_static' in base 'GDScript'" (the L-020 symptom).
##      Skipped (with a printed note) if the engine reports an empty global class list, so
##      this check can never fail the build for an environment reason.
##
## This is a tooling script, not a game system - it has no gameplay logic.

## Directories to scan for GDScript. Add new source roots here as the project grows.
const SCAN_DIRS := ["res://src", "res://tests", "res://tools"]

## Source prefix that declares a global class (check 3 reads it from the raw text).
const CLASS_NAME_PREFIX := "class_name "


func _initialize() -> void:
	var scripts := _collect_gd_files()
	var failed: Array[String] = []
	var checked := 0
	var global_classes := _global_class_names()
	var can_check_classes := not global_classes.is_empty()
	if not can_check_classes:
		print("[parse_check] NOTE: global class list empty; skipping class_name checks.")

	for path in scripts:
		checked += 1
		var res := load(path)
		if res == null:
			failed.append("%s - failed to load (parse/compile error)" % path)
			continue
		if not (res is GDScript):
			failed.append("%s - loaded but is not a GDScript" % path)
			continue

		var script := res as GDScript
		if not script.can_instantiate():
			failed.append("%s - loaded but does NOT compile (script is invalid)" % path)
			continue

		if can_check_classes:
			var declared := _declared_class_name(path)
			if declared != "" and not global_classes.has(declared):
				failed.append(("%s - declares class_name '%s' but it is NOT registered "
					+ "globally (the class failed to compile)") % [path, declared])

	print("[parse_check] scanned %d script(s)." % checked)

	if not failed.is_empty():
		for f in failed:
			push_error("[parse_check] %s" % f)
			print("[parse_check] FAIL: %s" % f)
		print("[parse_check] RESULT: FAIL")
		quit(1)
		return

	print("[parse_check] RESULT: PASS")
	quit(0)


## Every `class_name` the engine has registered as a global class, as a set
## (`{name: path}`). Empty if the engine exposes no global class list, in which case the
## caller SKIPS the class_name check rather than failing the build.
func _global_class_names() -> Dictionary:
	var out: Dictionary = {}
	for entry in ProjectSettings.get_global_class_list():
		var cls := String((entry as Dictionary).get("class", ""))
		if cls != "":
			out[cls] = String((entry as Dictionary).get("path", ""))
	return out


## The `class_name` a script declares, or "" if it declares none. Reads the source text
## (not the compiled script) so a BROKEN script still reports the name it *meant* to
## register - that is the whole point of check 3.
func _declared_class_name(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var found := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with(CLASS_NAME_PREFIX):
			found = line.substr(CLASS_NAME_PREFIX.length()).strip_edges()
			break
	f.close()
	return found


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
