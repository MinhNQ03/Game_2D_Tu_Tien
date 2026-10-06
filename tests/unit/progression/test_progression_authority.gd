extends TestCase
## STRUCTURAL authority guards for Phase-11 progression (D-055).
##
## Phase 11 shipped with its ownership model written down in three docstrings and asserted
## nowhere:
##
##   * `CharacterState.set_total_xp` says "the ONLY writer is ProgressionService.grant_xp()"
##   * `ProgressionService.grant_xp` is documented as the only semantic mutation authority
##   * `ProgressionRuntime.grant_for_defeat` says it "is the ONLY place in the project that
##     calls grant_xp, which is what makes 'one mutation path' CHECKABLE rather than
##     aspirational" — while nothing checked it
##
## A claim that nothing checks is a comment, and a comment does not survive the next phase.
## Phase 12 (Cultivation) is the immediate risk: it arrives wanting to react to progression,
## and the cheapest wrong thing it could do is write `character.set_total_xp(...)` from its own
## runtime, which would create a second mutation path that every existing test would tolerate.
##
## WHY A WALK AND NOT A FILE LIST: a hand-written inventory only protects the files somebody
## remembered (L-034). These scan `res://src` recursively, so a file added in a later phase is
## covered on the day it lands.
##
## WHY `src` ONLY: tests legitimately drive `set_total_xp` to arrange a state (seven call sites
## across two files today). The rule being defended is about PRODUCTION consumers, so scanning
## the test tree would forbid the arrangement that makes the behavioural tests possible.
##
## NOT AN ACCESS-CONTROL ABSTRACTION. The setter stays public and keeps its name. GDScript has
## no package-private, and inventing a capability object to simulate one would be more
## machinery than the rule is worth (D-055 supplement C: the guard matters, not the spelling).

## Files architecture permits to write `CharacterState.xp`, as EXACT repository-relative paths.
##
##   * `src/domain/character/character_state.gd` — the storage + invariant boundary. The clamp
##     (`xp >= 0`) belongs next to the field it constrains, and the class must be able to
##     initialise and hydrate its own field.
##   * `src/domain/progression/progression_service.gd` — the semantic authority. It decides the
##     new value from the authored curve and commits it through the boundary above.
##
## FULL PATHS, not basenames. The first version of this guard allow-listed
## `"progression_service.gd"`, which permits a file with that NAME anywhere in `src` — so a
## future `src/gameplay/progression/progression_service.gd` (a plausible thing for Phase 12 to
## add while reaching for the nearest familiar name) would have been silently exempt. An
## allow-list keyed on a basename is an allow-list for a name, not for a file.
## `test_the_allow_list_is_keyed_on_the_path_not_the_filename` pins that.
const XP_WRITERS_ALLOWED := [
	"src/domain/character/character_state.gd",
	"src/domain/progression/progression_service.gd",
]

## Files architecture permits to call `ProgressionService.grant_xp()`, as exact paths.
##
## Exactly one: the per-session runtime that owns the idempotency ledger. A second caller would
## be a second way to pay for the same thing, which is the defect the ledger exists to prevent.
const GRANT_CALLERS_ALLOWED := [
	"src/gameplay/world/progression_runtime.gd",
]


# === XP write authority =====================================================

## No production file outside the storage boundary and the service may mutate XP.
##
## This is the structural half of D-055-F. The semantic half already held when the guard was
## written — the only production writer was the service — so this does not fix a live defect;
## it stops the next phase from introducing one silently. Its non-vacuity is proven by
## `test_the_xp_write_guard_actually_fires` below.
func test_only_the_storage_boundary_and_the_service_write_xp() -> void:
	var offenders: Array[String] = []
	_scan(&"res://src", offenders, XP_WRITERS_ALLOWED, func(line: String) -> bool:
		return _writes_xp(line))
	assert_true(offenders.is_empty(),
		("XP is mutated only by ProgressionService (through CharacterState's invariant "
			+ "boundary). These production files bypass that authority: %s") % str(offenders))


## Exactly one production file may call `grant_xp` — the runtime that holds the ledger.
func test_only_the_progression_runtime_calls_grant_xp() -> void:
	var offenders: Array[String] = []
	_scan(&"res://src", offenders, GRANT_CALLERS_ALLOWED, func(line: String) -> bool:
		return _calls_grant_xp(line))
	assert_true(offenders.is_empty(),
		("`grant_xp` has one production caller so that 'paid once' is enforced by the "
			+ "ledger rather than by every caller remembering. Extra callers: %s")
			% str(offenders))


## The allow-lists must name files that EXIST, or a rename would silently widen the rule into
## permitting nothing and the guards above would pass by vacuously scanning a renamed file.
##
## Checked by PATH now, which also means a file MOVED to another directory breaks this loudly
## instead of staying exempt under its old basename.
func test_the_allow_lists_name_real_files() -> void:
	for path in XP_WRITERS_ALLOWED + GRANT_CALLERS_ALLOWED:
		assert_true(FileAccess.file_exists("res://%s" % path),
			("the allow-list names '%s', which does not exist — a rename or a move must "
				+ "update this guard, not quietly disable it") % path)


## The allow-list is keyed on the PATH, so a same-named file elsewhere is NOT exempt.
##
## This is the regression for the basename hole described on `XP_WRITERS_ALLOWED`. It asserts
## the membership predicate directly rather than by planting a decoy file in `src/`: the guards
## scan the real tree, so a decoy would have to be created and deleted inside a test, and a
## test that writes into the source tree is a worse trade than testing the predicate the
## scanner actually uses.
func test_the_allow_list_is_keyed_on_the_path_not_the_filename() -> void:
	assert_true(_is_allowed("src/domain/progression/progression_service.gd",
			XP_WRITERS_ALLOWED),
		"the real service is exempt")
	assert_false(_is_allowed("src/gameplay/progression/progression_service.gd",
			XP_WRITERS_ALLOWED),
		("a DIFFERENT file with the same basename must NOT inherit the exemption — the "
			+ "basename allow-list this replaced would have let it write XP silently"))
	assert_false(_is_allowed("progression_service.gd", XP_WRITERS_ALLOWED),
		"and a bare basename is not a path, so it matches nothing")
	assert_true(_is_allowed("src/gameplay/world/progression_runtime.gd",
			GRANT_CALLERS_ALLOWED),
		"the real runtime may call grant_xp")
	assert_false(_is_allowed("src/domain/world/progression_runtime.gd",
			GRANT_CALLERS_ALLOWED),
		"a same-named file in another layer may not")


## Proof the matcher is not vacuous: it must flag a realistic bypass.
##
## §27 requires every new guard to be shown catching the behaviour it forbids. There was no
## pre-existing violation to catch here, so the honest equivalent is to feed the matcher the
## exact line a future phase would write and assert it is rejected — and to feed it the lines
## that legitimately mention XP and assert they are not.
func test_the_xp_write_guard_actually_fires() -> void:
	# Lines a bypass would look like, from the layers most likely to try it. The DYNAMIC forms
	# are the ones the previous version of this guard let through: every one of them mutates
	# `CharacterState.xp` in Godot, and none of them contains the static spelling the old
	# matcher looked for.
	var bypasses := [
		# static: the setter, and direct member assignment
		"\tcharacter.set_total_xp(500)",
		"\t_character.set_total_xp(_character.xp + amount)",
		"\tstate.xp = 0",
		"\tstate.xp += reward",
		"\tstate.xp -= penalty",
		"\tstate.xp *= 2",
		"\tstate.xp /= 2",
		"\txp = 42",
		# dynamic: the setter named as a string
		"\tcharacter.call(\"set_total_xp\", 500)",
		"\tcharacter.callv(\"set_total_xp\", [500])",
		"\tcharacter.call_deferred(\"set_total_xp\", 500)",
		# dynamic: the PROPERTY named as a string
		"\tstate.set(\"xp\", 999)",
		"\tstate.set(&\"xp\", 999)",
		"\tstate.set_indexed(\"xp\", 999)",
		"\tstate.set_deferred(\"xp\", 999)",
		# indexed property assignment
		"\tstate[\"xp\"] = 999",
	]
	for line in bypasses:
		assert_true(_writes_xp(line), "a bypass must be flagged: '%s'" % line)

	# Lines that mention XP without mutating the authority. A guard with false positives gets
	# relaxed by the next person who hits one, so these matter as much as the cases above.
	var innocent := [
		"\t@export var xp_reward: int = 0",
		"\txp_gained.emit(result.xp_applied, reward_id)",
		"\tview.xp_into_level = service.xp_into_level(state)",
		"\tview.xp_for_next = 45",
		"\t_xp_meter = UITheme.xp_meter()",
		"\tif state.xp == 0:",
		"\tvar xp_before := state.xp",
		"\treturn state.xp",
		"\tassert_eq(state.xp, 25, \"paid\")",
		# A neighbouring property whose name STARTS with xp. The quoted patterns require the
		# closing quote immediately after `xp`, so these must not be caught.
		"\tdata.set(\"xp_reward\", 10)",
		"\tdata.set_deferred(\"xp_into_level\", 3)",
		"\tvar v = state[\"xp_reward\"]",
		# Reading the property dynamically is not writing it.
		"\tvar current = state.get(\"xp\")",
		# A diagnostic that merely names the setter.
		"\tpush_error(\"only set_total_xp may write it\")",
	]
	for line in innocent:
		assert_false(_writes_xp(line), "must NOT be flagged: '%s'" % line)


## The same proof for the `grant_xp` call matcher, including the false positive it shipped with.
func test_the_grant_xp_call_guard_distinguishes_a_call_from_a_declaration() -> void:
	var calls := [
		# static
		"\t_service.grant_xp(_character, xp_reward)",
		"\tvar r := service.grant_xp(state, 25)",
		"\tprogression.get_service().grant_xp(c, 5)",
		# DYNAMIC — the hole the previous matcher left wide open. None of these contains
		# `grant_xp(`, so the `in line` check missed them all while the guard claimed the
		# mutation path was single.
		"\t_service.call(\"grant_xp\", _character, 25)",
		"\t_service.call(&\"grant_xp\", _character, 25)",
		"\t_service.callv(\"grant_xp\", [_character, 25])",
		"\t_service.call_deferred(\"grant_xp\", _character, 25)",
		"\tvar c := Callable(_service, \"grant_xp\")",
	]
	for line in calls:
		assert_true(_calls_grant_xp(line), "a call must be flagged: '%s'" % line)

	var not_calls := [
		# The declaration. The guard's FIRST run flagged this and failed on the service,
		# which is the defect this case exists to pin.
		"func grant_xp(state: CharacterState, amount: int) -> ProgressionResult:",
		"\tfunc grant_xp(a, b):",
		"\tvar name := \"grant\"",
		# A real line in `progression_service.gd`: a diagnostic that NAMES the function it is
		# inside. The dynamic patterns only match a method-name position, so this stays clean —
		# without that precision the service itself would be reported as its own caller.
		"\tpush_error(\"[progression] grant_xp with a null CharacterState\")",
		"\tpush_error(\"[progression] grant_xp with no bound curve\")",
	]
	for line in not_calls:
		assert_false(_calls_grant_xp(line), "must NOT be flagged: '%s'" % line)


# === Helpers =================================================================

## Does this line WRITE the authoritative XP?
##
## The first version covered two shapes — `set_total_xp(` and a direct `xp` assignment — which
## is every form a reviewer would THINK to write and not every form that works. `xp` is an
## ordinary script property on an `Object`, so Godot offers several dynamic routes to it, and a
## guard that only knows the static spelling is bypassed by typing the property name as a
## string. Each pattern below is a form that genuinely mutates `CharacterState.xp`:
##
##   1. `set_total_xp(...)`           — the narrow setter (the sanctioned boundary)
##   2. `call("set_total_xp", ...)`   — the same setter, named dynamically
##   3. `xp = / += / -= / *= / /=`    — direct assignment to the member
##   4. `set("xp", v)`                — `Object.set`, works on any property
##   5. `set_indexed("xp", v)`        — `Object.set_indexed`, a NodePath-addressed write
##   6. `set_deferred("xp", v)`       — the same write, one frame later
##   7. `obj["xp"] = v`               — indexed property assignment
##
## Deliberately NOT matched: `rpc`/`rpc_id` forms (no networking exists in Stage 1, and
## inventing detection for a form the project cannot produce is dead weight), and anything
## routed through `from_dict` (that IS the storage boundary, and it lives in an allowed file).
##
## PRECISION MATTERS AS MUCH AS COVERAGE. The quoted patterns require the closing quote
## immediately after `xp`, so `set("xp_reward", v)` is not flagged; `\bxp\s*=` cannot match
## `xp_reward`/`xp_into_level`/`xp_gained`, because those have `_` after `xp` rather than
## whitespace-or-`=`; and `=[^=]` excludes `==`. A guard with false positives gets relaxed by
## the next person who trips over one.
func _writes_xp(line: String) -> bool:
	if "set_total_xp(" in line:
		return true
	for re in _compiled(XP_WRITE_PATTERNS, _xp_res):
		if re.search(line) != null:
			return true
	return false


## The dynamic/indexed write forms, as regexes. `&?` accepts the `StringName` spelling
## (`set(&"xp", v)`), which Godot treats identically.
const XP_WRITE_PATTERNS := [
	# 3. direct member assignment (compound operators included)
	"\\bxp\\s*(=[^=]|\\+=|-=|\\*=|/=)",
	# 2. the setter named as a string and invoked dynamically
	"\\b(call|callv|call_deferred)\\(\\s*&?[\"']set_total_xp[\"']",
	# 4/5/6. property-name writes: set / set_indexed / set_deferred
	"\\b(set|set_indexed|set_deferred)\\(\\s*&?[\"']xp[\"']\\s*,",
	# 7. indexed property assignment
	"\\[\\s*&?[\"']xp[\"']\\s*\\]\\s*=[^=]",
]


## Does this line CALL `grant_xp`, as opposed to DECLARING it?
##
## Two histories worth keeping. The first version asked only `"grant_xp(" in line` and failed
## immediately on `progression_service.gd` — which does not call `grant_xp`, it IS `grant_xp`;
## the fix was the matcher, not the allow-list, because widening an allow-list to silence a
## false positive is how a guard stops guarding. The second version kept that `grant_xp(`
## requirement and therefore **missed every dynamic invocation**: `call("grant_xp", state, 25)`
## contains `grant_xp"`, not `grant_xp(`, so it sailed through a guard whose entire job was to
## keep the mutation path single.
##
## Now both: the static call, and the method name supplied as a string to a dynamic invoker
## (`call` / `callv` / `call_deferred` / `Callable`). The string is only matched in a METHOD-NAME
## POSITION, which is what keeps `push_error("[progression] grant_xp with a null ...")` — a real
## line in the service — from being read as a call.
func _calls_grant_xp(line: String) -> bool:
	if line.strip_edges().begins_with("func "):
		# The DECLARATION. It is the authority, not a consumer of it.
		return false
	if "grant_xp(" in line:
		return true
	for re in _compiled(GRANT_DYNAMIC_PATTERNS, _grant_res):
		if re.search(line) != null:
			return true
	return false


## Dynamic invocation forms for `grant_xp`. Each requires the name in a method-name position,
## so a diagnostic string that merely mentions the function is not mistaken for a call.
const GRANT_DYNAMIC_PATTERNS := [
	"\\b(call|callv|call_deferred)\\(\\s*&?[\"']grant_xp[\"']",
	"\\bCallable\\(\\s*[^,()]+,\\s*&?[\"']grant_xp[\"']",
]


## Walk `dir_path` recursively; append the name of every `.gd` NOT in `allowed` for which
## `matches` returns true on a comment-stripped line.
##
## Comments are stripped so a file may still DOCUMENT the rule (and the mistake it forbids)
## without tripping it — the same concession `test_damage_feedback`'s colour walk makes, and
## for the same reason: pushing the explanation out of the file where it is most useful is a
## bad trade.
func _scan(dir_path: StringName, offenders: Array[String], allowed: Array,
		matches: Callable) -> void:
	var dir := DirAccess.open(String(dir_path))
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [String(dir_path), entry]
		if dir.current_is_dir():
			_scan(StringName(full), offenders, allowed, matches)
		elif entry.ends_with(".gd") and not _is_allowed(_relative(full), allowed):
			var file := FileAccess.open(full, FileAccess.READ)
			if file != null:
				var source := file.get_as_text()
				file.close()
				for raw_line in source.split("\n"):
					var line: String = raw_line
					var hash_at := line.find("#")
					if hash_at >= 0:
						line = line.substr(0, hash_at)
					if bool(matches.call(line)):
						# Report the PATH: "progression_service.gd" does not say which one,
						# and telling them apart is the point of the path-keyed allow-list.
						offenders.append(_relative(full))
						break
		entry = dir.get_next()
	dir.list_dir_end()


## A `res://`-rooted path as the repository-relative path the allow-lists are written in.
func _relative(full: String) -> String:
	return full.trim_prefix("res://")


## The membership predicate the scanner uses, exposed so the path-vs-basename regression can
## assert it directly instead of planting a decoy file in the source tree.
func _is_allowed(relative: String, allowed: Array) -> bool:
	return relative in allowed


## Compiled-once regex caches.
##
## `_writes_xp` and `_calls_grant_xp` run ONCE PER LINE of every `.gd` under `src` — 97 files
## and ~21,000 lines today. Compiling the patterns inside those functions meant roughly 126,000
## `RegEx.new()` + `compile()` calls per suite run, which is exactly the per-iteration
## allocation in a hot loop that `05-performance-testing.md` forbids — introduced by the change
## that grew the loop from one pattern to six. Built lazily because a compiled `RegEx` cannot
## be a `const`, and reused for the rest of the run.
var _xp_res: Array[RegEx] = []
var _grant_res: Array[RegEx] = []


## The compiled form of `patterns`, built into `cache` on first use and reused afterwards.
func _compiled(patterns: Array, cache: Array[RegEx]) -> Array[RegEx]:
	if cache.is_empty():
		for pattern in patterns:
			var re := RegEx.new()
			re.compile(String(pattern))
			cache.append(re)
	return cache
