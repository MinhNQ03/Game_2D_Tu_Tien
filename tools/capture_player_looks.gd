extends SceneTree
## capture_player_looks — the protagonist's looks standing in the REAL hub, at real size
## (art-01, CHARACTER_ART_BIBLE §4c).
##
## `capture_ui.gd` confirms one look and shows it in passing; a readability pass on the player
## sprite has to be judged where the player sees it: in the hub, at the game's own camera zoom,
## facing the camera and in profile, in the wanderer's clothes and in the Thanh Vân robe. This
## boots the REAL application in a REAL window, starts a run as the chosen look through the
## identity screen's own `confirmed` (RunKit, the one sanctioned setup), and writes the frame.
##
## USAGE (needs a display; do NOT pass --headless)
##     godot --path . --resolution 1280x720 -s res://tools/capture_player_looks.gd -- \
##         vi /tmp/out appearance_wanderer_f [before_dir]
##
## OUTPUT, per garment (`proto`, then `daobao`) and facing (`down`, `left`):
##   <lang>_<w>x<h>_<tag>_<look>_<garment>_<facing>_hub.png    the whole frame, 1x
##   <lang>_<w>x<h>_<tag>_<look>_<garment>_<facing>_crop4x.png the player's box, x4 nearest
## `tag` is `after`, or `before` when `before_dir` is given: a folder of sheets from an earlier
## revision (`<sheet prefix>_idle.png`, `_walk.png`). The four player profiles' idle and walk
## sheets are swapped IN MEMORY for those before the run starts, so the same build shows the
## old sprite in the same hub, same spot, same light. Nothing on disk changes.
##
## Exit code 1 if any frame could not be taken. A BUILD-TIME TOOL: nothing in the game uses it.

const MAIN_SCENE := "res://main.tscn"
const SETTLE_FRAMES := 12
const MENU_WAIT_FRAMES := 240
const PACED_FPS := 60
## The player's box on screen, in viewport px around the feet origin (32x48 sprite and air).
const BOX := Rect2i(-40, -88, 80, 104)
const MAGNIFY := 4
## The four player profiles and their sheet prefixes (designs/actors/player_*.yaml outputs).
const PROFILES := {
	"res://data/characters/visual/player_visual.tres": "player_proto",
	"res://data/characters/visual/player_f_visual.tres": "player_f_proto",
	"res://data/characters/visual/player_daobao_visual.tres": "player_daobao",
	"res://data/characters/visual/player_f_daobao_visual.tres": "player_f_daobao",
}
const ROBE := &"item_dao_bao_thanh_van"

var _language := "vi"
var _out_dir := "user://player_looks"
var _appearance: StringName = &"appearance_wanderer_m"
var _before_dir := ""
var _failed := false
var _written: Array[String] = []
## Held so the swapped profiles stay cached (and swapped) for the whole run.
var _profiles: Array[Resource] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_language = String(args[0])
	if args.size() >= 2:
		_out_dir = String(args[1])
	if args.size() >= 3:
		_appearance = StringName(String(args[2]))
	if args.size() >= 4:
		_before_dir = String(args[3])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = PACED_FPS
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if _before_dir != "" and not _swap_in_before_sheets():
		_finish(null)
		return
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await _settle()
	# after boot, and read back (Main._boot applies the saved language; capture_ui.gd)
	var loc := root.get_node_or_null("Localization")
	if loc != null:
		loc.call("set_language", _language)
	if loc == null or String(loc.call("get_language")) != _language:
		_fail("could not switch to language '%s'" % _language)
		_finish(main)
		return
	await _settle()
	var menu := await _await_menu(main)
	if menu == null:
		_fail("no main menu")
		_finish(main)
		return
	if not await RunKit.begin_run(main, self, RunKit.DEFAULT_ORIGIN, _appearance):
		_fail("the identity screen did not open")
		_finish(main)
		return
	RunKit.take_outpost_issue(main)  # setup: the robe is the outpost's issue
	await _settle()
	await _settle()
	var player := _player()
	if player == null:
		_fail("no player in the hub")
		_finish(main)
		return
	var spawn := player.global_position
	await _shoot_facings(player, "proto")
	if not await _wear_robe(main, player):
		_finish(main)
		return
	player.global_position = spawn
	await _settle()
	await _shoot_facings(player, "daobao")
	_finish(main)


## Face the camera, then turn to profile (real movement input, released before the frame).
func _shoot_facings(player: Node2D, garment: String) -> void:
	for facing: String in ["down", "left"]:
		var action := StringName("move_" + facing)
		Input.action_press(action)
		for _i in 3:
			await physics_frame
		Input.action_release(action)
		await _settle()
		await _shot(player, "%s_%s" % [garment, facing])


## The hub robe, worn as DETERMINISTIC SETUP (as `capture_motion.gd` wears it): this tool shows
## the daobao body, the inventory UI is proved by tests/e2e/world_flow_case.gd.
func _wear_robe(main: Node, player: Node2D) -> bool:
	var map := _map()
	var pickup: Node2D = null
	if map != null:
		pickup = map.get_node_or_null("Pickups/HubRobe") as Node2D
	var equipment := main.get_node_or_null("Systems/EquipmentRuntime")
	if pickup == null or equipment == null:
		_fail("no HubRobe pickup or EquipmentRuntime")
		return false
	player.global_position = pickup.global_position
	for _i in 6:
		await physics_frame
	var err: StringName = equipment.call("equip", ROBE)
	if err != &"" or not bool(equipment.call("is_worn", ROBE)):
		_fail("the robe was not worn (%s)" % err)
		return false
	return true


## Replace the idle and walk sheets of the player profiles with `before_dir`'s, in memory.
func _swap_in_before_sheets() -> bool:
	for path: String in PROFILES:
		var profile := load(path) as CharacterVisualProfileData
		if profile == null:
			_fail("no profile %s" % path)
			return false
		for anim in ["idle", "walk"]:
			var file := "%s/%s_%s.png" % [_before_dir, PROFILES[path], anim]
			var image := Image.load_from_file(file)
			if image == null or image.is_empty():
				_fail("no before sheet %s" % file)
				return false
			profile.set("%s_sheet" % anim, ImageTexture.create_from_image(image))
		_profiles.append(profile)
	return true


func _map() -> Node:
	var router := root.get_node_or_null("SceneRouter")
	return router.call("get_current_scene") if router != null else null


func _player() -> Node2D:
	var map := _map()
	var host := map.get_node_or_null("PlayerHost") if map != null else null
	if host == null:
		return null
	for child in host.get_children():
		if child is CharacterBody2D:
			return child as Node2D
	return null


## The whole frame, and the player's box magnified (nearest: every pixel stays a pixel).
func _shot(player: Node2D, shot_name: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	if image == null:
		_fail("viewport produced no image for '%s'" % shot_name)
		return
	var view := root.get_visible_rect().size
	var tag := "before" if _before_dir != "" else "after"
	var stem := "%s/%s_%dx%d_%s_%s_%s" % [_out_dir, _language, int(view.x), int(view.y), tag,
		String(_appearance).trim_prefix("appearance_"), shot_name]
	_save(image, stem + "_hub.png")
	var px := Vector2(image.get_size()) / view
	var feet := player.get_global_transform_with_canvas().origin * px
	var box := Rect2i(Vector2i(feet) + Vector2i(Vector2(BOX.position) * px),
		Vector2i(Vector2(BOX.size) * px)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if box.size.x <= 0 or box.size.y <= 0:
		_fail("the player is off screen for '%s'" % shot_name)
		return
	var crop := image.get_region(box)
	crop.resize(crop.get_width() * MAGNIFY, crop.get_height() * MAGNIFY, Image.INTERPOLATE_NEAREST)
	_save(crop, stem + "_crop4x.png")


func _save(image: Image, file: String) -> void:
	if image.save_png(file) != OK:
		_fail("could not write %s" % file)
		return
	_written.append(file.get_file())


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await process_frame


func _await_menu(main: Node) -> Node:
	for _i in MENU_WAIT_FRAMES:
		var menu := RunKit.menu_of(main)
		if menu != null:
			return menu
		await process_frame
	return null


func _fail(reason: String) -> void:
	push_error("[capture_player_looks] " + reason)
	_failed = true


func _finish(main: Node) -> void:
	print("[capture_player_looks] wrote %d file(s) to %s" % [_written.size(), _out_dir])
	if main != null:
		main.get_parent().remove_child(main)
		main.free()
	quit(1 if _failed or _written.is_empty() else 0)
