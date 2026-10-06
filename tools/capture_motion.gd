extends SceneTree
## capture_motion — Aetheria MOTION capture harness (D-057B).
##
## `capture_ui.gd` proves a layout; it cannot prove a motion. A walk that slides, a strike whose
## effect starts beside the hand, a post that does not react, grass that sways in lockstep —
## every one of those passes a single screenshot and every unit test. This harness boots the
## REAL application in a REAL window, drives it with the SAME semantic input a player uses
## (`Input.action_press` / key events through `Input.parse_input_event` — never a direct call
## into gameplay), and writes FRAME STRIPS: the same world-space box around the subject,
## captured frame after frame and laid side by side, so motion can be read the way an animator
## reads it.
##
## The one concession is SETUP: the player is placed beside a subject (as the E2E flows place
## it on an exit zone) so a strip does not spend its frames walking across the map. Everything
## after the placement is input and the real runtime.
##
## USAGE (needs a display; do NOT pass --headless)
##     godot --path . --resolution 1280x720 -s res://tools/capture_motion.gd -- out/dir
##
## OUTPUT: `<out>/motion_<scenario>.png` strips (each cell = one captured frame, magnified 2x
## on top of the camera's own zoom) and `<out>/scene_<name>.png` full frames. Exit code 1 if any
## scenario could not run — a missing strip must never look like a passing one.
##
## A BUILD-TIME TOOL: nothing in the game depends on it.

const MAIN_SCENE := "res://main.tscn"
const SETTLE_FRAMES := 12
const MENU_WAIT_FRAMES := 240
## Each strip cell is this many SCREEN pixels square around its subject, then magnified.
const CELL_PX := 160
const MAGNIFY := 2

var _out_dir := "user://motion_captures"
## Optional: run only the scenario with this name (second user argument).
var _only := ""
var _written: Array[String] = []
var _failed := false
var _main: Node = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_dir = String(args[0])
	if args.size() >= 2:
		_only = String(args[1])
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(_main)
	await _settle()
	var menu := await _await_menu()
	if menu == null or not menu.has_signal("new_game_pressed"):
		_fail("no main menu to start a game from")
		_finish()
		return
	menu.emit_signal("new_game_pressed")
	await _settle()
	await _settle()

	if _only == "" or _only == "walk_stop_turn":
		print("[capture_motion] scenario walk_stop_turn")
		await _scenario_walk_stop_turn()
	if _only == "" or _only == "strike_the_post":
		print("[capture_motion] scenario strike_the_post")
		await _scenario_strike_the_post()
	if _only == "" or _only == "ambient":
		print("[capture_motion] scenario ambient")
		await _scenario_ambient()
	if _only == "" or _only == "cultivation":
		print("[capture_motion] scenario cultivation")
		await _scenario_cultivation()
	if _only == "" or _only == "field_fight":
		print("[capture_motion] scenario field_fight")
		await _scenario_field_fight()
	_finish()


# === Scenarios ==============================================================

## Walk right across open ground, stop, then reverse: stride cadence, the settle, the turn.
func _scenario_walk_stop_turn() -> void:
	var player := _player()
	if player == null:
		_fail("walk: no player")
		return
	player.global_position = Vector2(300, 312)
	await _settle()
	await _shot("scene_hub")
	Input.action_press(&"move_right")
	var walk := await _strip(func() -> Vector2: return player.global_position + Vector2(0, -20),
		16, 2)
	Input.action_release(&"move_right")
	var stop := await _strip(func() -> Vector2: return player.global_position + Vector2(0, -20),
		8, 1)
	Input.action_press(&"move_left")
	var turn := await _strip(func() -> Vector2: return player.global_position + Vector2(0, -20),
		8, 1)
	Input.action_release(&"move_left")
	_save_strip("motion_walk", walk)
	_save_strip("motion_stop", stop)
	_save_strip("motion_turn", turn)
	await _settle()


## Strike the training post from its left: the coil, the release from the palm, the post's
## wobble about its footing and the straw that falls from it.
func _scenario_strike_the_post() -> void:
	var player := _player()
	var post := _map_node("CombatTargets/TrainingDummy") as Node2D
	if player == null or post == null:
		_fail("strike: no player or training post")
		return
	player.global_position = post.global_position + Vector2(-26, 2)
	# Face the post through the real input path, then let go.
	Input.action_press(&"move_right")
	await process_frame
	await process_frame
	Input.action_release(&"move_right")
	await _settle()
	var focus := func() -> Vector2: return post.global_position + Vector2(-14, -16)
	await _press(&"attack")
	var frames := await _strip(focus, 24, 1)
	_save_strip("motion_strike_post", frames)
	await _settle()


## Two moments a beat apart over the banners and a tree: the wind must have MOVED them, and not
## all by the same amount (no synchronized wallpaper).
func _scenario_ambient() -> void:
	var banner := _map_node("Visual/Decor/BannerW") as Node2D
	var tree := _map_node("Visual/Decor/TreeN") as Node2D
	if banner == null or tree == null:
		_fail("ambient: hub decor missing")
		return
	var player := _player()
	if player != null:
		player.global_position = banner.global_position + Vector2(20, 60)
	await _settle()
	var frames: Array[Image] = []
	for i in 6:
		frames.append(_cell(banner.global_position + Vector2(20, -24)))
		for _f in 20:
			await process_frame
	_save_strip("motion_banner_wind", frames)
	if player != null:
		player.global_position = tree.global_position + Vector2(40, 40)
	await _settle()
	frames = []
	for i in 6:
		frames.append(_cell(tree.global_position + Vector2(0, -22)))
		for _f in 20:
			await process_frame
	_save_strip("motion_tree_wind", frames)


## Read the stele, sit at the spring, break through: the seated pose, the qi a mortal barely
## senses, the macro release and the wind it pushes into the grass.
func _scenario_cultivation() -> void:
	var player := _player()
	var stele := _map_node("KnowledgeSources/LacHaStele") as Node2D
	var spring := _map_node("CultivationSites/LacHaSpring") as Node2D
	var cultivation := _main.get_node_or_null("Systems/CultivationRuntime") as CultivationRuntime
	if player == null or stele == null or spring == null or cultivation == null:
		_fail("cultivation: hub pieces missing")
		return
	player.global_position = stele.global_position + Vector2(0, 12)
	await _settle()
	await _press(&"interact")
	await _settle()
	await _shot("scene_stele_read")
	player.global_position = spring.global_position + Vector2(0, 8)
	await _settle()
	await _hold(&"cultivate")
	var focus := func() -> Vector2: return spring.global_position + Vector2(0, -10)
	var sit := await _strip(focus, 16, 3)
	_save_strip("motion_meditate_mortal", sit)
	cultivation.get_service().gather(player.call("get_character_state"), 999)
	await _hold(&"cultivate")
	var burst := await _strip(focus, 32, 4)
	_save_strip("motion_breakthrough", burst)
	await _shot("scene_after_breakthrough")
	var seated := await _strip(focus, 8, 6)
	_save_strip("motion_meditate_hau_thien", seated)
	Input.action_press(&"move_up")
	await _settle()
	Input.action_release(&"move_up")
	await _settle()


## Hold an action across a few frames (the way a hand presses a key), then release.
func _hold(action: StringName) -> void:
	Input.action_press(action)
	for _i in 4:
		await physics_frame
	Input.action_release(action)
	await process_frame


## Into the field through the real exit, then a mist wolf: its telegraphed bite on the player,
## and the player's strike landing on it.
func _scenario_field_fight() -> void:
	var player := _player()
	if player == null:
		_fail("field: no player")
		return
	if not await _travel_through_first_exit(player):
		_fail("field: the exit did not transition")
		return
	await _settle()
	await _shot("scene_field")
	var wolf := _first_enemy()
	if wolf == null:
		_fail("field: no enemy spawned")
		return
	# Stand within the wolf's reach and wait: it hunts, telegraphs, bites.
	player.global_position = wolf.global_position + Vector2(-30, 4)
	var bite := await _strip(func() -> Vector2:
		return (wolf.global_position + player.global_position) * 0.5 + Vector2(0, -14), 30, 2)
	_save_strip("motion_wolf_bite", bite)
	# Face the wolf through input, then strike it.
	var toward := (wolf.global_position - player.global_position).normalized()
	var key := &"move_right" if toward.x >= 0.0 else &"move_left"
	Input.action_press(key)
	await process_frame
	await process_frame
	Input.action_release(key)
	await _press(&"attack")
	var strike := await _strip(func() -> Vector2:
		return (wolf.global_position + player.global_position) * 0.5 + Vector2(0, -14), 22, 1)
	_save_strip("motion_strike_wolf", strike)
	await _settle()
	await _shot("scene_field_after")


# === Helpers ================================================================

func _player() -> Node2D:
	var host := _map_node("PlayerHost")
	if host == null:
		return null
	for child in host.get_children():
		if child is CharacterBody2D:
			return child as Node2D
	return null


func _current_map() -> Node:
	var router := root.get_node_or_null("SceneRouter")
	return router.call("get_current_scene") if router != null else null


func _map_node(path: String) -> Node:
	var map := _current_map()
	return map.get_node_or_null(path) if map != null else null


func _first_enemy() -> Node2D:
	var host := _map_node("CombatTargets")
	if host == null:
		return null
	for child in host.get_children():
		if child is CharacterBody2D:
			return child as Node2D
	return null


func _travel_through_first_exit(player: Node2D) -> bool:
	var router := root.get_node_or_null("SceneRouter")
	var before := String(router.call("get_current_key")) if router != null else ""
	var exits := _map_node("Exits")
	if exits == null or exits.get_child_count() == 0:
		return false
	var zone := exits.get_child(0) as Node2D
	player.global_position = zone.global_position
	for _i in 4:
		await physics_frame
	zone.emit_signal("body_entered", player)
	for _attempt in 8:
		await _press(&"interact")
		await process_frame
		if router != null and String(router.call("get_current_key")) != before:
			return true
	return false


## Press and release `action` through the real input pipeline (a key event when one is bound).
func _press(action: StringName) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var down := InputEventKey.new()
			down.physical_keycode = (e as InputEventKey).physical_keycode
			down.keycode = (e as InputEventKey).keycode
			down.pressed = true
			Input.parse_input_event(down)
			Input.flush_buffered_events()
			await process_frame
			var up := down.duplicate() as InputEventKey
			up.pressed = false
			Input.parse_input_event(up)
			Input.flush_buffered_events()
			return
	Input.action_press(action)
	await process_frame
	Input.action_release(action)


## Capture `count` cells, one every `every` rendered frames, around `focus.call()`.
func _strip(focus: Callable, count: int, every: int) -> Array[Image]:
	var frames: Array[Image] = []
	for _i in count:
		for _f in every:
			await process_frame
		frames.append(_cell(focus.call()))
	return frames


## One magnified cell of the CURRENT frame, centred on a world point.
func _cell(world: Vector2) -> Image:
	var image := root.get_texture().get_image()
	var screen := root.get_canvas_transform() * world
	var half := CELL_PX / 2
	var rect := Rect2i(int(screen.x) - half, int(screen.y) - half, CELL_PX, CELL_PX)
	rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var cell := Image.create(CELL_PX, CELL_PX, false, Image.FORMAT_RGBA8)
	if rect.size.x > 0 and rect.size.y > 0:
		cell.blit_rect(image.get_region(rect), Rect2i(Vector2i.ZERO, rect.size), Vector2i.ZERO)
	cell.resize(CELL_PX * MAGNIFY, CELL_PX * MAGNIFY, Image.INTERPOLATE_NEAREST)
	return cell


func _save_strip(strip_name: String, frames: Array[Image]) -> void:
	if frames.is_empty():
		_fail("%s: no frames" % strip_name)
		return
	var size := frames[0].get_size()
	var per_row := 8
	var rows := int(ceil(float(frames.size()) / float(per_row)))
	var sheet := Image.create(size.x * mini(per_row, frames.size()), size.y * rows, false,
		Image.FORMAT_RGBA8)
	for i in frames.size():
		var at := Vector2i((i % per_row) * size.x, int(float(i) / float(per_row)) * size.y)
		sheet.blit_rect(frames[i], Rect2i(Vector2i.ZERO, size), at)
	var file := "%s/%s.png" % [_out_dir, strip_name]
	if sheet.save_png(file) != OK:
		_fail("could not write %s" % file)
		return
	_written.append(file.get_file())


func _shot(shot_name: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	var file := "%s/%s.png" % [_out_dir, shot_name]
	if image == null or image.save_png(file) != OK:
		_fail("could not write %s" % file)
		return
	_written.append(file.get_file())


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await process_frame


func _await_menu() -> Node:
	for _i in MENU_WAIT_FRAMES:
		var ui := _main.get_node_or_null("UI")
		if ui != null:
			# The MENU specifically: other UI (a fade, a toast) may be the first child.
			for child in ui.get_children():
				if not child.is_queued_for_deletion() and child.has_signal("new_game_pressed"):
					return child
		await process_frame
	return null


func _fail(reason: String) -> void:
	push_error("[capture_motion] %s" % reason)
	_failed = true


func _finish() -> void:
	for action in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)
	print("[capture_motion] wrote %d file(s) to %s" % [_written.size(), _out_dir])
	for name in _written:
		print("[capture_motion]   %s" % name)
	if _main != null:
		_main.get_parent().remove_child(_main)
		_main.free()
	quit(1 if _failed else 0)
