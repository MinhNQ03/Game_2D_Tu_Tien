extends TestCase
## Unit tests for the SESSION LIFECYCLE CONTRACT the bootstrap owns (D-047).
##
## The contract, frozen:
##   start    World → Relationship → Sect → Faction
##   teardown Faction → Sect → Relationship → World → GameState
##
## Teardown is the exact REVERSE of start because each subsystem's state is defined in terms
## of the ones ended after it (the faction session reads the sect store + the relationship
## graph; the sect session holds the graph and the player's `CharacterState`). The Phase-07
## defect this file exists to prevent was a `_on_return_to_menu()` that ended World and
## Relationship FIRST — under a comment claiming it did the opposite, with every gate green.
##
## WHAT IS ASSERTED WHERE, deliberately split:
##   * HERE (cheap, in-runner): the ORDER CONSTANT, that each named subsystem really is an
##     endable session, and the STRUCTURAL property that made the defect possible — a second,
##     hand-written teardown sequence living outside the one ordered function.
##   * `tests/e2e/world_flow_case.gd` (real process): the RUNTIME order, read back from the
##     real `Main` after a real `open_menu` return-to-menu.
## Neither alone is enough: a constant can be right while the code ignores it, and an E2E
## assertion on a literal order can drift away from the documented constant. The E2E therefore
## compares the observed trace against THIS constant as well as against the literal.
##
## `Main` is NOT instantiated here. It drives the live `/root/GameState` autoload, which the
## shared runner forbids a test to mutate (L-010 / the isolation guard), so anything that boots
## it belongs in the dedicated E2E process (D-019). Reading constants and source structure off
## the loaded script needs no instance.

const MainScript := preload("res://src/bootstrap/main.gd")
const MAIN_SOURCE_PATH := "res://src/bootstrap/main.gd"

## The frozen teardown order, written out as a literal rather than derived, so this file says
## what the contract IS instead of only saying "the reverse of whatever start happens to be".
const EXPECTED_TEARDOWN := [
	&"FactionRuntime", &"SectRuntime", &"RelationshipRuntime", &"WorldRuntime", &"GameState",
]

## subsystem name -> the script that implements its session. Pairing them here is what makes
## "every name in the order is a real endable subsystem" assertable.
const SUBSYSTEM_SCRIPTS := {
	"WorldRuntime": "res://src/gameplay/world/world_runtime.gd",
	"RelationshipRuntime": "res://src/gameplay/world/relationship_runtime.gd",
	"SectRuntime": "res://src/gameplay/world/sect_runtime.gd",
	"FactionRuntime": "res://src/gameplay/world/faction_runtime.gd",
}

## How the bootstrap actually ends a session: the runtimes are duck-typed (`Node`-typed
## fields, no hard dependency from `src/bootstrap` on `src/gameplay`), so every teardown is a
## `call("end_session")`. Matching this exact form rather than the bare word is what keeps the
## structural guard from firing on the function's own NAME or on the comments describing it.
const END_SESSION_CALL := 'call("end_session")'


## The start order IS the dependency order, and it is pinned by value: adding a subsystem in
## the wrong place, or quietly reordering two of them, fails here.
func test_01_start_order_is_the_frozen_dependency_order() -> void:
	var order: Array = MainScript.SESSION_START_ORDER
	assert_eq(order.size(), 4, "four per-session subsystems (got %s)" % str(order))
	assert_eq(order[0], &"WorldRuntime",
		"the world session is first: it owns the player CharacterState everything else reads")
	assert_eq(order[1], &"RelationshipRuntime",
		"the relationship graph is second: sect + faction diplomacy mirror into it")
	assert_eq(order[2], &"SectRuntime",
		"the sect session is third: it needs the player state AND the graph")
	assert_eq(order[3], &"FactionRuntime",
		"the faction session is last: it reads the sect store AND the graph (D-042)")
	assert_eq(MainScript.SESSION_OWNER_STEP, &"GameState",
		"the lifecycle owner is ended after every subsystem, never before")


## Teardown is the exact reverse, plus the session owner. This is the one place the two
## directions are compared, so they cannot drift apart silently.
func test_02_teardown_is_the_exact_reverse_plus_the_session_owner() -> void:
	var start: Array = MainScript.SESSION_START_ORDER
	var derived: Array[StringName] = []
	for i in range(start.size() - 1, -1, -1):
		derived.append(StringName(start[i]))
	derived.append(StringName(MainScript.SESSION_OWNER_STEP))

	assert_eq(derived.size(), EXPECTED_TEARDOWN.size(),
		"the derived teardown has one step per subsystem plus the session owner")
	for i in EXPECTED_TEARDOWN.size():
		assert_eq(derived[i], EXPECTED_TEARDOWN[i],
			"teardown step %d is '%s'" % [i, EXPECTED_TEARDOWN[i]])
	# And it is genuinely a reversal, not a coincidence of four hard-coded names.
	for i in start.size():
		assert_eq(StringName(start[i]), derived[start.size() - 1 - i],
			"start[%d] is teardown[%d] mirrored" % [i, start.size() - 1 - i])


## Every name in the order must correspond to a real subsystem that can START and END a
## session. A name with no such script would make its teardown step a silent no-op — which is
## exactly how a reordered teardown hides: the step "runs" and does nothing.
func test_03_every_ordered_subsystem_is_a_real_endable_session() -> void:
	var order: Array = MainScript.SESSION_START_ORDER
	assert_eq(order.size(), SUBSYSTEM_SCRIPTS.size(),
		"the order and the name→script table cover the same set")
	for entry in order:
		var subsystem := String(entry)
		assert_true(SUBSYSTEM_SCRIPTS.has(subsystem),
			"'%s' has a known implementing script" % subsystem)
		if not SUBSYSTEM_SCRIPTS.has(subsystem):
			continue
		var path := String(SUBSYSTEM_SCRIPTS[subsystem])
		var script: GDScript = load(path) as GDScript
		assert_not_null(script, "'%s' script loads (%s)" % [subsystem, path])
		if script == null:
			continue
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			methods.append(String(m.get("name", "")))
		assert_true(methods.has("start_session"),
			"%s exposes start_session()" % subsystem)
		assert_true(methods.has("end_session"),
			"%s exposes end_session()" % subsystem)
		assert_true(methods.has("is_session_active"),
			"%s exposes is_session_active() so a teardown is observable" % subsystem)


## THE STRUCTURAL GUARD, and the one that would actually have caught the D-047 defect.
##
## The bug was not a wrong constant — it was a SECOND, hand-written teardown sequence
## (`_on_return_to_menu`) living beside the correct one (`_unwind_failed_session`) and having
## drifted out of step with it. So the invariant worth enforcing is not "the order is right"
## but "there is only ONE place that ends sessions". Every `end_session` call in the bootstrap
## must live inside `_end_session_stack()`, and the two public teardown entry points must
## delegate to it rather than sequencing anything themselves.
func test_04_only_one_function_in_the_bootstrap_ends_sessions() -> void:
	var source := _main_source()
	assert_true(source != "", "main.gd source is readable")
	if source == "":
		return

	var bodies := _function_bodies(source)
	assert_true(bodies.has("_end_session_stack"),
		"the bootstrap has the single ordered teardown function")
	assert_true(bodies.has("_on_return_to_menu"), "and the normal return-to-menu entry point")
	assert_true(bodies.has("_unwind_failed_session"), "and the failed-start unwind")

	# The bootstrap ends a session by duck-typed invocation (`node.call("end_session")`), so
	# THAT is the shape to look for. Searching for the bare word would also hit the name
	# `_end_session_stack` itself and every doc comment that explains the contract.
	var callers: Array[String] = []
	var names: Array = bodies.keys()
	names.sort()
	for key in names:
		var fname := String(key)
		if String(bodies[fname]).contains(END_SESSION_CALL):
			callers.append(fname)
	assert_eq(str(callers), str(["_end_session_stack"]),
		("exactly ONE function may end sessions, so the order cannot be re-implemented "
			+ "elsewhere and drift (functions issuing %s: %s)")
			% [END_SESSION_CALL, str(callers)])

	for entry_point in ["_on_return_to_menu", "_unwind_failed_session"]:
		assert_true(String(bodies[entry_point]).contains("_end_session_stack()"),
			"%s delegates to the single ordered teardown" % entry_point)

	# The ordered walk must consume the CONSTANT, not a second hard-coded list of names.
	var stack := String(bodies["_end_session_stack"])
	assert_true(stack.contains("SESSION_START_ORDER"),
		"the teardown iterates SESSION_START_ORDER rather than re-listing the subsystems")
	assert_true(stack.contains("SESSION_OWNER_STEP"),
		"and names the session-owner step from the same source of truth")
	# Exactly two end-session calls: one inside the ordered subsystem walk, one for the
	# lifecycle owner. A third would mean something is ended outside the walk.
	assert_eq(stack.count(END_SESSION_CALL), 2,
		"the ordered teardown issues exactly two end-session calls (the subsystem walk and "
		+ "the session owner), so nothing is ended off to the side")


# --- helpers -----------------------------------------------------------------

func _main_source() -> String:
	var file := FileAccess.open(MAIN_SOURCE_PATH, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


## `func_name -> body CODE text`, by splitting on top-level `func ` lines. Crude on purpose:
## it only has to attribute a line of code to the function it sits in, and a parser would be a
## framework (which A2 forbids) for a four-assertion guard.
##
## COMMENTS ARE STRIPPED FIRST, for a reason worth stating: a `##` docstring sits BEFORE its
## `func` line, so it would otherwise be attributed to the body of the PRECEDING function —
## which is exactly how the first version of this guard reported four extra "callers" that were
## really just the comments explaining the contract. A guard that fires on prose would train
## the next person to weaken it.
func _function_bodies(source: String) -> Dictionary:
	var bodies := {}
	var current := ""
	var buffer: Array[String] = []
	for raw_line in source.split("\n"):
		var line := _strip_comment(String(raw_line))
		if line.begins_with("func "):
			if current != "":
				bodies[current] = "\n".join(buffer)
			var head := line.substr(5)
			var paren := head.find("(")
			current = head.substr(0, paren).strip_edges() if paren >= 0 else head.strip_edges()
			buffer = []
			continue
		if current != "":
			buffer.append(line)
	if current != "":
		bodies[current] = "\n".join(buffer)
	return bodies


## `line` with any trailing comment removed. Quote-aware, so a `#` inside a string literal is
## not mistaken for a comment marker (and `'call("end_session")'` in THIS file's own constant
## is why that matters).
func _strip_comment(line: String) -> String:
	var in_double := false
	var in_single := false
	for i in line.length():
		var ch := line[i]
		if ch == '"' and not in_single:
			in_double = not in_double
		elif ch == "'" and not in_double:
			in_single = not in_single
		elif ch == "#" and not in_double and not in_single:
			return line.substr(0, i)
	return line
