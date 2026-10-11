extends SceneTree
## measure_ambience_frame_time — what a map's light costs a frame, MEASURED (H21-19).
##
## PERF-NOTE-21 counted the Night's lights and argued they were cheap. This times them: the
## REAL application in a REAL window, the same place on the same map under each ambience —
## as authored (day), `dusk`, `night` — interleaved over several rounds so that drift (thermal,
## the compositor, a background task) lands on all three alike.
##
## METHOD: simple frame-time sampling, NOT the engine profiler. Each sample is the wall time
## between two consecutive `process_frame`s (`Time.get_ticks_usec`). With `--disable-vsync
## --max-fps 0` that is the whole cost of producing a frame (script + physics + render +
## present); with vsync it is the display's interval and only hitches show.
##
## USAGE (needs a display; do NOT pass --headless)
##     godot --path . --resolution 1280x720 --disable-vsync --max-fps 0 \
##         -s res://tools/measure_ambience_frame_time.gd -- out/report.md [seconds] [rounds]
##
## SETUP, stated: the run is begun through the one sanctioned setup (`RunKit.begin_run`), the
## player is stood where the map's lights are on screen, and the ambience is set on the map's
## own `MapAmbience` (presentation; it holds no truth). Nothing is learned here about the
## story reaching the Night — that is the Story E2E's.
##
## A BUILD-TIME TOOL: nothing in the game depends on it. Exit code 1 if a map or its ambience
## could not be measured.

const MAIN_SCENE := "res://main.tscn"
const AMBIENCES: Array[StringName] = [&"", &"dusk", &"night"]
## An ambience eases in over its own seconds; nothing is sampled until it has.
const SETTLE_SECONDS := 1.6
## Where the player stands (setup): [map, what is in frame there, position]. A light off
## screen is culled, so each map is measured where the MOST of its lights are in frame — the
## worst case — and the woods also where only the vein is.
const STANDS := [
	[&"map_hub", "both lanterns", Vector2(900, 300)],
	[&"map_field", "the vein", Vector2(590, 380)],
	[&"map_field", "lanterns + vein", Vector2(360, 300)],
]

var _seconds := 6.0
var _rounds := 3
var _out := "user://ambience_frame_time.md"
var _failed := false
var _lines: PackedStringArray = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out = String(args[0])
	if args.size() >= 2:
		_seconds = maxf(1.0, float(args[1]))
	if args.size() >= 3:
		_rounds = maxi(1, int(args[2]))
	_run.call_deferred()


func _run() -> void:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	for _i in 12:
		await process_frame
	if not await RunKit.begin_run(main, self):
		_fail("the identity screen did not open")
		_finish(main)
		return
	RunKit.skip_scenes(main)
	_lines.append("# Ambience frame time — %s" % Time.get_datetime_string_from_system())
	_lines.append("")
	_lines.append("- engine: Godot %s, renderer `%s`" % [Engine.get_version_info()["string"],
		ProjectSettings.get_setting("rendering/renderer/rendering_method")])
	_lines.append("- GPU: %s (%s), driver %s" % [RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(),
		" ".join(OS.get_video_adapter_driver_info())])
	_lines.append("- CPU: %s (%d threads); OS: %s %s" % [OS.get_processor_name(),
		OS.get_processor_count(), OS.get_name(), OS.get_version()])
	_lines.append("- window %dx%d, vsync mode %d, max_fps %d, physics %d Hz" % [root.size.x,
		root.size.y, DisplayServer.window_get_vsync_mode(), Engine.max_fps,
		Engine.physics_ticks_per_second])
	_lines.append("- %d round(s) x %.1f s per ambience, interleaved; %.1f s settle before each"
		% [_rounds, _seconds, SETTLE_SECONDS])
	_lines.append("")
	_lines.append("| map (in frame) | ambience | frames | median ms | p95 ms | p99 ms | max ms | "
		+ "lights lit / in frame | draw calls |")
	_lines.append("|---|---|---|---|---|---|---|---|---|")
	var world := main.get_node_or_null("Systems/WorldRuntime")
	var here: StringName = &"map_hub"
	for stand: Array in STANDS:
		if stand[0] != here:
			here = stand[0]
			world.call("request_map_transition", here, &"from_hub")
			for _i in 40:
				await process_frame
			RunKit.skip_scenes(main)
		await _measure(here, stand[1], stand[2], world)
	_finish(main)


func _measure(map_id: StringName, label: String, stand: Vector2, world: Node) -> void:
	var ambience := get_first_node_in_group(MapAmbience.GROUP) as MapAmbience
	var player := world.call("get_player") as Node2D
	if ambience == null or player == null:
		_fail("%s: no MapAmbience or no player" % map_id)
		return
	player.global_position = stand
	for _i in 30:
		await process_frame  # the camera eases onto the new place
	var samples := {}
	var lights := {}
	var calls := {}
	for id in AMBIENCES:
		samples[id] = PackedFloat64Array()
	for _round in _rounds:
		for id in AMBIENCES:
			if not MapAmbience.profile_exists(id):
				_fail("%s: no ambience '%s'" % [map_id, id])
				return
			ambience.apply(id)
			var settle_until := Time.get_ticks_usec() + int(SETTLE_SECONDS * 1e6)
			while Time.get_ticks_usec() < settle_until:
				await process_frame
			lights[id] = _lit_in_frame(ambience)
			var series: PackedFloat64Array = samples[id]
			var until := Time.get_ticks_usec() + int(_seconds * 1e6)
			var last := Time.get_ticks_usec()
			while last < until:
				await process_frame
				var now := Time.get_ticks_usec()
				series.append(float(now - last) / 1000.0)
				last = now
			samples[id] = series
			calls[id] = int(Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	ambience.apply(&"")
	for id in AMBIENCES:
		var series: PackedFloat64Array = samples[id]
		series.sort()
		_lines.append("| %s | %s | %d | %.3f | %.3f | %.3f | %.3f | %s | %d |" % [
			"%s (%s)" % [map_id, label],
			"day (as authored)" if id == &"" else String(id), series.size(),
			_at(series, 0.5), _at(series, 0.95), _at(series, 0.99), series[series.size() - 1],
			lights[id], calls[id]])


## "lit / in frame": how many of the map's lights are on, and how many of those reach into
## the visible playfield (a light off screen is culled and costs nothing to draw).
func _lit_in_frame(ambience: MapAmbience) -> String:
	var view := root.get_canvas_transform().affine_inverse() \
		* Rect2(Vector2.ZERO, Vector2(root.size))
	var lit := 0
	var seen := 0
	for light in ambience.lights():
		if not light.enabled:
			continue
		lit += 1
		var reach := Vector2.ZERO
		if light.texture != null:
			reach = light.texture.get_size() * light.texture_scale * 0.5
		if view.intersects(Rect2(light.global_position - reach, reach * 2.0)):
			seen += 1
	return "%d / %d" % [lit, seen]


func _at(sorted: PackedFloat64Array, quantile: float) -> float:
	return sorted[mini(sorted.size() - 1, int(floor(quantile * float(sorted.size()))))]


func _fail(reason: String) -> void:
	push_error("[measure] %s" % reason)
	_failed = true


func _finish(main: Node) -> void:
	var text := "\n".join(_lines) + "\n"
	print(text)
	var file := FileAccess.open(_out, FileAccess.WRITE)
	if file == null:
		_fail("could not write %s" % _out)
	else:
		file.store_string(text)
		file.close()
	main.get_parent().remove_child(main)
	main.free()
	quit(1 if _failed else 0)
