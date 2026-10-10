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
## with an owner (`docs/handoff/phase-19-quest.md` §9); the list may only get shorter.
const KNOWN_EXCEPTIONS := {
	"res://src/data/worldsim/world_sim_catalog.gd": ["WorldClock"],  # Q19-05 (Phase 08)
}


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
