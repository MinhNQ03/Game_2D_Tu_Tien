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

## Files architecture permits to write `CharacterState.xp`.
##
##   * `character_state.gd` — the storage + invariant boundary. The clamp (`xp >= 0`) belongs
##     next to the field it constrains, and the class must be able to initialise and hydrate
##     its own field.
##   * `progression_service.gd` — the semantic authority. It decides the new value from the
##     authored curve and commits it through the boundary above.
const XP_WRITERS_ALLOWED := ["character_state.gd", "progression_service.gd"]

## Files architecture permits to call `ProgressionService.grant_xp()`.
##
## Exactly one: the per-session runtime that owns the idempotency ledger. A second caller would
## be a second way to pay for the same thing, which is the defect the ledger exists to prevent.
const GRANT_CALLERS_ALLOWED := ["progression_runtime.gd"]


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
func test_the_allow_lists_name_real_files() -> void:
	var found: Array[String] = []
	_collect_filenames(&"res://src", found)
	for name_ in XP_WRITERS_ALLOWED + GRANT_CALLERS_ALLOWED:
		assert_true(name_ in found,
			("the allow-list names '%s', which is not in src/ — a rename must update this "
				+ "guard, not quietly disable it") % name_)


## Proof the matcher is not vacuous: it must flag a realistic bypass.
##
## §27 requires every new guard to be shown catching the behaviour it forbids. There was no
## pre-existing violation to catch here, so the honest equivalent is to feed the matcher the
## exact line a future phase would write and assert it is rejected — and to feed it the lines
## that legitimately mention XP and assert they are not.
func test_the_xp_write_guard_actually_fires() -> void:
	# Lines a bypass would look like, from the layers most likely to try it.
	var bypasses := [
		"\tcharacter.set_total_xp(500)",
		"\t_character.set_total_xp(_character.xp + amount)",
		"\tstate.xp = 0",
		"\tstate.xp += reward",
		"\txp = 42",
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
	]
	for line in innocent:
		assert_false(_writes_xp(line), "must NOT be flagged: '%s'" % line)


## The same proof for the `grant_xp` call matcher, including the false positive it shipped with.
func test_the_grant_xp_call_guard_distinguishes_a_call_from_a_declaration() -> void:
	var calls := [
		"\t_service.grant_xp(_character, xp_reward)",
		"\tvar r := service.grant_xp(state, 25)",
		"\tprogression.get_service().grant_xp(c, 5)",
	]
	for line in calls:
		assert_true(_calls_grant_xp(line), "a call must be flagged: '%s'" % line)

	var not_calls := [
		# The declaration. The guard's FIRST run flagged this and failed on the service,
		# which is the defect this case exists to pin.
		"func grant_xp(state: CharacterState, amount: int) -> ProgressionResult:",
		"\tfunc grant_xp(a, b):",
		"\tvar name := \"grant\"",
	]
	for line in not_calls:
		assert_false(_calls_grant_xp(line), "must NOT be flagged: '%s'" % line)


# === Helpers =================================================================

## Does this line WRITE the authoritative XP?
##
## Two shapes: a call to the storage boundary, or a direct assignment to a member named exactly
## `xp`. `\bxp\s*=` cannot match `xp_reward`/`xp_into_level`/`xp_gained`, because after `xp`
## those have `_` rather than whitespace-or-`=`; `=[^=]` excludes `==`.
func _writes_xp(line: String) -> bool:
	if "set_total_xp(" in line:
		return true
	var re := RegEx.new()
	re.compile("\\bxp\\s*(=[^=]|\\+=|-=|\\*=|/=)")
	return re.search(line) != null


## Does this line CALL `grant_xp`, as opposed to DECLARING it?
##
## The first version of this guard asked only `"grant_xp(" in line`, and failed immediately on
## `progression_service.gd` — which does not call `grant_xp`, it IS `grant_xp`. The fix is the
## matcher, not the allow-list: widening the allow-list to silence a false positive is how a
## guard stops guarding, and the service genuinely must not be permitted to call it.
##
## Worth keeping as a note: the guard caught something on its very first run, which is the
## cheapest possible proof that the directory walk works.
func _calls_grant_xp(line: String) -> bool:
	if not ("grant_xp(" in line):
		return false
	return not line.strip_edges().begins_with("func ")


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
		elif entry.ends_with(".gd") and not (entry in allowed):
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
						offenders.append(entry)
						break
		entry = dir.get_next()
	dir.list_dir_end()


func _collect_filenames(dir_path: StringName, out: Array[String]) -> void:
	var dir := DirAccess.open(String(dir_path))
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			_collect_filenames(StringName("%s/%s" % [String(dir_path), entry]), out)
		elif entry.ends_with(".gd"):
			out.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
