extends TestCase
## Structural guards for the motion design contract (D-057, `docs/MOTION_DESIGN_CONTRACT.md`).
##
## PRESENTATION NEVER WRITES SIMULATION TIME. Hit-stop — a held frame on impact — is the motion
## technique most likely to be implemented wrongly here, because the one-line Godot recipe is
## `Engine.time_scale = 0.05` for a few frames. That does not hold an IMAGE; it slows the whole
## simulation: the attack lifecycle, enemy AI, movement and every timer run slower because a
## presentation effect decided they should. Gameplay timing owns the truth
## (`PRESENTATION_ARCHITECTURE_CONTRACT.md` §3), and an authoritative server could never honour a
## client's hit-stop anyway. So a held frame is presentation holding ITS OWN pose and effects —
## the action layer already takes its frame from outside — and the simulation clock is not
## presentation's to touch.

const PRESENTATION_ROOT := "res://src/presentation"

## Writes to the engine's simulation clock: an assignment (plain or compound, never `==`) to
## one of the three properties, or a call to their setters. Compiled ONCE, not per line
## (`PRESENTATION_ARCHITECTURE_CONTRACT.md` §13: a guard that walks the tree is a hot loop).
const CLOCK_WRITE_PATTERN := ("\\bEngine\\s*\\.\\s*(?:"
	+ "(?:time_scale|physics_ticks_per_second|max_physics_steps_per_frame)\\s*[-+*/]?=(?!=)"
	+ "|set_(?:time_scale|physics_ticks_per_second|max_physics_steps_per_frame)\\s*\\()")

var _clock_write: RegEx = null


func test_presentation_never_writes_the_simulation_clock() -> void:
	var offenders: Array[String] = []
	var scanned := _scan(PRESENTATION_ROOT, offenders)
	assert_true(scanned >= 15,
		"the walk read the presentation sources (%d files) — a broken walk passes vacuously"
			% scanned)
	assert_eq(offenders, [],
		("presentation may hold its own pose or effect, never the simulation: these lines write "
			+ "the engine clock — %s") % str(offenders))


## The matcher catches the recipe that shipped in countless games, and nothing innocent.
func test_a_simulation_clock_write_is_detected() -> void:
	for line in [
		"\tEngine.time_scale = 0.05",
		"Engine.time_scale *= 0.5",
		"Engine.physics_ticks_per_second = 30",
		"\tEngine.set_time_scale(0.1)",
	]:
		assert_true(_writes_clock(line), "flagged: `%s`" % line)
	for line in [
		"var slowed := Engine.time_scale < 1.0",
		"if Engine.time_scale == 1.0:",
		"# Engine.time_scale = 0.05 is forbidden here",
		"\tvar ticks := Engine.physics_ticks_per_second",
	]:
		assert_false(_writes_clock(line), "not flagged (a read or a comment): `%s`" % line)


func _writes_clock(line: String) -> bool:
	if _clock_write == null:
		_clock_write = RegEx.create_from_string(CLOCK_WRITE_PATTERN)
	var code := line
	var comment := code.find("#")
	if comment >= 0:
		code = code.substr(0, comment)
	return _clock_write.search(code) != null


## Read every `.gd` under `dir_path`, recording `file:line` for each clock write. Returns the
## number of files read, so the caller can prove the walk happened.
func _scan(dir_path: String, offenders: Array[String]) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	var scanned := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			scanned += _scan(full, offenders)
		elif entry.ends_with(".gd"):
			scanned += 1
			var lines := FileAccess.get_file_as_string(full).split("\n")
			for index in lines.size():
				if _writes_clock(lines[index]):
					offenders.append("%s:%d" % [full, index + 1])
		entry = dir.get_next()
	dir.list_dir_end()
	return scanned
