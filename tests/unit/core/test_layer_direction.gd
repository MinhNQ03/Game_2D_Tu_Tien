extends TestCase
## The dependency arrow points ONE way: `presentation → gameplay → domain → data`
## (`.kiro/steering/03-architecture.md`). Data describes; it must not know that a service, a
## runtime or a screen exists.
##
## GDScript resolves `class_name` globally, so there is no import to look wrong: a data
## resource typed on a domain class compiles, runs and passes every behavioural test (L-036).
## Phase 19 did exactly that — `DialogueConditionData` was typed on `QuestService.Phase` — and
## nothing noticed until the diff was read. This test reads the SOURCE instead: no code line
## under `src/data` or `src/domain` may name a class that a layer above it declares.
##
## SCOPE, stated plainly. It guards the two layers that must run with no scene tree. It does
## NOT police gameplay → presentation: this codebase's runtimes build the presentation DTOs
## they push (`DialogueRuntime.build_view`) and its entities host visual components, by
## design — that boundary is `PRESENTATION_ARCHITECTURE_CONTRACT.md`'s, not this test's.

const LAYERS: Array[String] = ["data", "domain", "gameplay", "presentation"]
## The layers whose code is checked (every layer ABOVE each is forbidden to it).
const GUARDED: Array[String] = ["data", "domain"]

## Known, RECORDED exceptions — `file -> class` pairs that predate this guard. Each is debt
## with an owner; the list may only get shorter, and it is EMPTY: its one entry
## (`world_sim_catalog.gd` naming `WorldClock`, Q19-05) was fixed, not excused. An entry added
## here must come with a register row, an owner and a closure criterion.
const KNOWN_EXCEPTIONS := {}


func test_no_lower_layer_names_a_class_an_upper_layer_declares() -> void:
	var declared: Dictionary = {}  # layer -> Array[String] of class names
	for layer in LAYERS:
		declared[layer] = _class_names("res://src/%s" % layer)
		assert_true((declared[layer] as Array).size() > 0, "%s declares classes" % layer)
	var violations: Array[String] = []
	var excused := 0
	for i in GUARDED.size():
		assert_eq(LAYERS[i], GUARDED[i], "the guarded layers are the lowest ones, in order")
		var forbidden: Array[String] = []
		for upper in LAYERS.slice(i + 1):
			forbidden.append_array(declared[upper])
		for path in _scripts("res://src/%s" % LAYERS[i]):
			for hit in _names_used(path, forbidden):
				if (KNOWN_EXCEPTIONS.get(path, []) as Array).has(hit):
					excused += 1
				else:
					violations.append("%s names %s" % [path.trim_prefix("res://"), hit])
	assert_eq(violations, [] as Array[String],
		"a lower layer names a class of an upper one — the arrow points the wrong way")
	assert_eq(excused, _exception_count(),
		"every recorded exception still exists; one that was fixed must leave the list")


## Q19-05, by name. The world simulation's data must not know its own domain exists: the
## catalog validated its calendar against `WorldClock.MIN_UNIT`, so authored content depended
## on the code that consumes it. The general scan above reports this too; this test names the
## pair of folders, so the failure says exactly which boundary was crossed and where.
func test_world_simulation_data_does_not_depend_on_its_domain() -> void:
	var domain := _class_names("res://src/domain/worldsim")
	var data_scripts := _scripts("res://src/data/worldsim")
	assert_true(domain.has("WorldClock"), "the worldsim domain declares its classes")
	assert_true(data_scripts.has("res://src/data/worldsim/world_sim_catalog.gd"),
		"and the worldsim data is where this looks")
	var violations: Array[String] = []
	for path in data_scripts:
		for hit in _names_used(path, domain):
			violations.append("%s names %s" % [path.trim_prefix("res://"), hit])
		for hit in _layer_paths_used(path, ["domain"]):
			violations.append("%s loads %s" % [path.trim_prefix("res://"), hit])
	assert_eq(violations, [] as Array[String],
		"src/data/worldsim depends on src/domain/worldsim — the arrow points the wrong way")


## A `class_name` is not the only way up: `preload("res://src/domain/...")` reaches an upper
## layer through a STRING, which the name scan deliberately ignores. No lower layer may load a
## script from an upper one by path either.
func test_no_lower_layer_loads_a_script_from_an_upper_layer_by_path() -> void:
	var violations: Array[String] = []
	for i in GUARDED.size():
		for path in _scripts("res://src/%s" % LAYERS[i]):
			for hit in _layer_paths_used(path, LAYERS.slice(i + 1)):
				violations.append("%s loads %s" % [path.trim_prefix("res://"), hit])
	assert_eq(violations, [] as Array[String],
		"a lower layer loads an upper layer's script by path")


## The path scan must be able to fail, and must not fire on a comment.
func test_the_path_scan_reports_a_load_and_ignores_comments() -> void:
	var upper: Array[String] = ["domain", "gameplay"]
	assert_eq(_layer_paths_in(
		"const C := preload(\"res://src/domain/worldsim/world_clock.gd\")", upper),
		["res://src/domain/"] as Array[String], "a preload of a domain script is a reference")
	assert_eq(_layer_paths_in("\tvar s = load(\"res://src/gameplay/x.gd\")  # why", upper),
		["res://src/gameplay/"] as Array[String], "so is a load")
	assert_eq(_layer_paths_in("## see res://src/domain/worldsim/world_clock.gd", upper),
		[] as Array[String], "a doc comment is not")
	assert_eq(_layer_paths_in("const C := preload(\"res://src/data/x.gd\")", upper),
		[] as Array[String], "nor is a path into a layer that is allowed")


## The guard must be able to fail: a data line naming a domain service IS reported.
func test_the_scan_reports_an_upward_reference_and_ignores_comments_and_strings() -> void:
	var names: Array[String] = ["QuestService", "DialogueRuntime"]
	assert_eq(_names_in("@export var phase: QuestService.Phase = 0", names),
		["QuestService"] as Array[String], "a type annotation is a reference")
	assert_eq(_names_in("\tif x >= QuestService.Phase.size():", names),
		["QuestService"] as Array[String], "so is a value")
	assert_eq(_names_in("## decided by `QuestService`, at session start", names),
		[] as Array[String], "a doc comment is not")
	assert_eq(_names_in("\tpush_error(\"asked of QuestService\")  # DialogueRuntime", names),
		[] as Array[String], "nor a string, nor a trailing comment")
	assert_eq(_names_in("var x: MyQuestServiceLike = null", names), [] as Array[String],
		"and a longer identifier that merely contains the name is a different name")


func _exception_count() -> int:
	var count := 0
	for path: String in KNOWN_EXCEPTIONS:
		count += (KNOWN_EXCEPTIONS[path] as Array).size()
	return count


func _scripts(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_scripts("%s/%s" % [dir_path, sub]))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, file])
	out.sort()
	return out


func _class_names(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	for path in _scripts(dir_path):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if line.begins_with("class_name "):
				out.append(line.trim_prefix("class_name ").strip_edges())
				break
	return out


## Which of `names` the CODE of `path` uses, each once.
func _names_used(path: String, names: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		for hit in _names_in(line, names):
			if not found.has(hit):
				found.append(hit)
	return found


## Which of `names` appear in the code of one line — not in a string, not in a comment.
func _names_in(line: String, names: Array[String]) -> Array[String]:
	var code := ""
	var in_string := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			in_string = not in_string
			continue
		if in_string:
			continue
		if ch == "#":
			break
		code += ch
	var found: Array[String] = []
	var word := RegEx.new()
	for class_id in names:
		word.compile("(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % class_id)
		if word.search(code) != null:
			found.append(class_id)
	return found


## Which `res://src/<layer>/` prefixes, for `layers`, the CODE of `path` mentions, each once.
func _layer_paths_used(path: String, layers: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		for hit in _layer_paths_in(line, layers):
			if not found.has(hit):
				found.append(hit)
	return found


## The same, for one line. Unlike `_names_in` this reads INSIDE strings — a path only ever
## appears in one — and stops at a comment that starts outside a string.
func _layer_paths_in(line: String, layers: Array[String]) -> Array[String]:
	var code := ""
	var in_string := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			in_string = not in_string
		elif ch == "#" and not in_string:
			break
		code += ch
	var found: Array[String] = []
	for layer in layers:
		var prefix := "res://src/%s/" % layer
		if code.contains(prefix):
			found.append(prefix)
	return found
