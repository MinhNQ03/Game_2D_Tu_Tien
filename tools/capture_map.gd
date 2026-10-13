extends SceneTree
## capture_map — deterministic before/after capture of a map's painted floor + props.
##
## Boots the REAL application in a REAL window, begins a run through the one sanctioned
## setup, parks a fixed camera over the hub map, and writes the actual viewport. The camera
## is the tool's own (the map's follow camera is disabled), so a "before" and an "after" run
## are the same shot: same positions, same zoom, same settle frames.
##
## USAGE (needs a display; do NOT pass --headless)
##     godot --path . --resolution 1280x720 --disable-vsync -s res://tools/capture_map.gd \
##         -- <out_dir> <prefix> [vi|en]
##
## Writes <out_dir>/<prefix>_full.png (whole map, zoom 1),
##        <out_dir>/<prefix>_spring.png (the spring court, zoom 2),
##        <out_dir>/<prefix>_square.png (the paved square + outpost, zoom 2),
##        <out_dir>/<prefix>_westbank.png (stream + bridge + west bank, zoom 2).
## A BUILD-TIME TOOL: nothing in the game depends on it.

const MAIN_SCENE := "res://main.tscn"
const SETTLE_FRAMES := 24

## [name, position, zoom] — world px, fixed for every run.
const VIEWS := [
	["full", Vector2(488, 304), 1.0],
	["spring", Vector2(408, 336), 2.0],
	["square", Vector2(520, 290), 2.0],
	["westbank", Vector2(170, 300), 2.0],
]

var _out_dir := "user://map_captures"
var _prefix := "map"
var _language := ""
var _written: Array[String] = []
var _failed := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_dir = String(args[0])
	if args.size() >= 2:
		_prefix = String(args[1])
	if args.size() >= 3:
		_language = String(args[2])
	_run.call_deferred()


func _settle(frames := SETTLE_FRAMES) -> void:
	for i in frames:
		await process_frame


func _fail(msg: String) -> void:
	_failed = true
	push_error("[capture_map] FAIL: " + msg)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	for i in 240:
		if RunKit.menu_of(main) != null:
			break
		await process_frame
	if _language != "":
		var loc := root.get_node_or_null("Localization")
		if loc == null or not bool(loc.call("set_language", _language)) \
				or String(loc.call("get_language")) != _language:
			_fail("could not switch to language '%s'" % _language)
			_finish()
			return
	if not await RunKit.begin_run(main, self):
		_fail("begin_run failed: no identity screen")
		_finish()
		return
	await _settle()
	var router := root.get_node_or_null("SceneRouter")
	var map: Node = null
	if router != null and router.has_method("get_current_scene"):
		map = router.call("get_current_scene") as Node
	if map == null:
		_fail("no current map scene from SceneRouter")
		_finish()
		return
	print("[capture_map] current map: ", map.name, " key=", router.call("get_current_key"))
	# Park the map's own follow camera; the tool's camera is the fixed shot.
	var map_cam := map.get_node_or_null("Camera2D") as Camera2D
	if map_cam != null:
		map_cam.enabled = false
	var cam := Camera2D.new()
	cam.name = "CaptureCamera"
	map.add_child(cam)
	cam.make_current()
	for view in VIEWS:
		cam.position = view[1]
		var z: float = view[2]
		cam.zoom = Vector2(z, z)
		await _settle()
		var img := root.get_texture().get_image()
		var path := "%s/%s_%s.png" % [_out_dir, _prefix, String(view[0])]
		if img.save_png(path) == OK:
			_written.append(path)
			print("[capture_map] wrote ", path)
		else:
			_fail("could not write " + path)
	_finish()


func _finish() -> void:
	print("[capture_map] done: %d written, failed=%s" % [_written.size(), str(_failed)])
	for w in _written:
		print("[capture_map]   ", w)
	quit(1 if _failed else 0)
