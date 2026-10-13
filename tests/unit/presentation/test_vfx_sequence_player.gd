extends TestCase
## The Blender-rendered VFX frame sequences (VFX workstream): the player loads
## every frame, plays one-shots in order and finishes, loops only when asked,
## pins the documented anchor pixel at its position, and costs nothing idle.

const PlayerScript := preload("res://src/presentation/vfx/vfx_sequence_player.gd")

const STEP := 1.0 / 12.0  # the authored playback speed of all three sequences


func _player(seq_dir: String, count: int, anchor: Vector2,
		loop: bool = false) -> VfxSequencePlayer:
	var player: VfxSequencePlayer = PlayerScript.new()
	player.sequence_dir = seq_dir
	player.frame_count = count
	player.anchor_px = anchor
	player.loop = loop
	add_to_tree(player)
	return player


func test_loads_every_frame_of_a_sequence() -> void:
	var player := _player("res://assets/vfx/qi_gather", 16, Vector2(32, 40))
	assert_eq(player.frame_total(), 16, "all 16 qi_gather frames load")
	for i in 16:
		var tex := player.frame_texture(i)
		assert_eq(tex.get_size(), Vector2(64, 64),
			"frame %d is the authored 64x64 canvas" % i)
	free_node(player)


func test_idle_costs_nothing_and_hides() -> void:
	var player := _player("res://assets/vfx/qi_gather", 16, Vector2(32, 40))
	assert_false(player.is_playing(), "never self-triggers")
	assert_false(player.is_processing(), "no _process while idle")
	assert_false(player.get_node("SequenceSprite").visible, "hidden while idle")
	assert_eq(player.z_index, 1, "transient VFX layer (style DNA depth)")
	free_node(player)


func test_play_starts_at_frame_zero() -> void:
	var player := _player("res://assets/vfx/qi_gather", 16, Vector2(32, 40))
	player.play()
	assert_true(player.is_playing(), "playing after play()")
	assert_true(player.is_processing(), "_process on while playing")
	var sprite := player.get_node("SequenceSprite") as Sprite2D
	assert_true(sprite.visible, "visible while playing")
	assert_eq(sprite.texture, player.frame_texture(0), "starts at the first frame")
	free_node(player)


func test_one_shot_advances_in_order_then_finishes() -> void:
	var player := _player("res://assets/vfx/attack_slash", 12, Vector2(24, 38))
	var fired := {"finished": 0}
	player.finished.connect(func() -> void: fired["finished"] += 1)
	player.play()
	var sprite := player.get_node("SequenceSprite") as Sprite2D
	for i in 11:
		player.advance(STEP)
		assert_eq(sprite.texture, player.frame_texture(i + 1),
			"frame %d shows after %d steps" % [i + 1, i + 1])
		assert_true(player.is_playing(), "still playing mid-sequence")
	player.advance(STEP)
	assert_eq(fired["finished"], 1, "finished emitted once at the last frame")
	assert_false(player.is_playing(), "one-shot stops by itself")
	assert_false(sprite.visible, "hidden after finishing")
	assert_false(player.is_processing(), "idle again after finishing")
	free_node(player)


func test_loop_wraps_instead_of_finishing() -> void:
	var player := _player("res://assets/vfx/qi_gather", 16, Vector2(32, 40), true)
	var fired := {"finished": 0}
	player.finished.connect(func() -> void: fired["finished"] += 1)
	player.play()
	var sprite := player.get_node("SequenceSprite") as Sprite2D
	for i in 16:
		player.advance(STEP)
	assert_true(player.is_playing(), "a loop never stops by itself")
	assert_eq(fired["finished"], 0, "a loop never emits finished")
	assert_eq(sprite.texture, player.frame_texture(0), "wraps back to the first frame")
	free_node(player)


func test_stop_idles_the_player() -> void:
	var player := _player("res://assets/vfx/qi_gather", 16, Vector2(32, 40))
	player.play()
	player.advance(STEP * 3)
	player.stop()
	assert_false(player.is_playing(), "stopped")
	assert_false(player.get_node("SequenceSprite").visible, "hidden after stop()")
	assert_false(player.is_processing(), "no _process after stop()")
	free_node(player)


func test_play_while_playing_restarts() -> void:
	var player := _player("res://assets/vfx/qi_gather", 16, Vector2(32, 40))
	var sprite := player.get_node("SequenceSprite") as Sprite2D
	player.play()
	player.advance(STEP * 5)
	assert_eq(sprite.texture, player.frame_texture(5), "mid-sequence")
	player.play()
	assert_eq(sprite.texture, player.frame_texture(0), "play() restarts at frame zero")
	free_node(player)


func test_anchor_pins_the_documented_pixel() -> void:
	var player := _player("res://assets/vfx/vein_erupt", 20, Vector2(64, 92))
	var sprite := player.get_node("SequenceSprite") as Sprite2D
	assert_eq(sprite.offset, Vector2(-64, -92),
		"the fissure pixel (64, 92) sits at the node's position")
	free_node(player)
