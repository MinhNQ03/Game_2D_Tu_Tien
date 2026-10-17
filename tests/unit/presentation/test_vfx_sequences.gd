extends TestCase
## The rendered VFX layer (experience upgrade): the shipped sequences are whole, a player plays
## once and then costs nothing, it stands its anchor on the cue's point, and each sequence is
## played by the presentation node that owns its cue — never by anything a rule reads.

const SEQUENCES := {
	"res://data/fx/qi_gather.tres": "res://assets/fx/cultivation/qi_gather.png",
	"res://data/fx/loi_strike.tres": "res://assets/fx/skills/loi_strike.png",
	"res://data/fx/vein_rupture.tres": "res://assets/fx/world_events/vein_rupture.png",
}
const CultivationFeedbackScript := preload(
	"res://src/presentation/cultivation/cultivation_feedback.gd")
const CastFeedbackScript := preload("res://src/presentation/skills/cast_feedback.gd")
const MapAmbienceScript := preload("res://src/presentation/ambient/map_ambience.gd")
const AmbienceLightScript := preload("res://src/presentation/ambient/ambience_light.gd")


func test_every_shipped_sequence_is_whole_and_reads_its_frames_from_its_strip() -> void:
	for path: String in SEQUENCES:
		var data := load(path) as VfxSequenceData
		assert_not_null(data, "%s loads" % path)
		if data == null:
			continue
		assert_eq(data.validation_errors(), [] as Array[String], "%s validates" % path)
		assert_eq(data.texture.resource_path, SEQUENCES[path], "%s draws its own strip" % path)
		assert_eq(data.frame_count() * data.frame_size.x, data.texture.get_width(),
			"%s: the frame count is derived from the strip's width" % path)
		assert_true(data.frame_count() >= 8, "%s has enough frames to read as motion" % path)
		assert_true(data.duration() <= 1.6,
			"%s is a moment (%.2f s), not a loop" % [path, data.duration()])


## Every frame of every strip has transparent pixels AND lit ones: no accidental black
## background, no empty frame (the packer refuses both; this guards the shipped files).
func test_every_frame_has_light_and_air() -> void:
	for path: String in SEQUENCES:
		var data := load(path) as VfxSequenceData
		var image := data.texture.get_image()
		for f in data.frame_count():
			var lit := 0
			var air := 0
			for y in data.frame_size.y:
				for x in data.frame_size.x:
					if image.get_pixel(f * data.frame_size.x + x, y).a > 0.0:
						lit += 1
					else:
						air += 1
			assert_true(lit > 0 and air > 0, "%s frame %d: lit %d, transparent %d"
				% [path, f, lit, air])


func test_a_player_plays_once_on_its_anchor_and_then_costs_nothing() -> void:
	var player := VfxSequencePlayer.new()
	add_to_tree(player)
	var data := load("res://data/fx/loi_strike.tres") as VfxSequenceData
	player.setup(data)
	assert_false(player.visible or player.is_processing(), "idle: hidden, no _process")
	var ended := [0]
	player.finished.connect(func() -> void: ended[0] += 1)
	player.play_at(Vector2(40.4, 10.6))
	assert_eq(player.position, Vector2(40, 11), "stands on the cue's point, on whole pixels")
	assert_eq(player.offset, -Vector2(data.anchor), "the anchor pixel sits on that point")
	assert_true(player.visible and player.is_processing(), "playing")
	assert_eq(player.hframes, data.frame_count(), "every frame of the strip is a frame")
	player._process(data.duration() * 0.5)
	assert_true(player.frame > 0 and player.frame < data.frame_count(), "it moves")
	player._process(data.duration())
	assert_eq(ended[0], 1, "it ends once")
	assert_false(player.visible or player.is_processing(), "and is hidden, idle again")
	free_node(player)


func test_an_invalid_sequence_is_refused_and_plays_nothing() -> void:
	var player := VfxSequencePlayer.new()
	add_to_tree(player)
	var broken := VfxSequenceData.new()
	broken.id = &"broken"
	player.setup(broken)
	player.play_at(Vector2.ZERO)
	assert_false(player.is_playing() or player.visible, "a sequence with no strip never plays")
	free_node(player)


## The gather plays when a sitting BEGINS and stops when it ends — the runtime's own signals,
## nothing else. Bound to a stand-in runtime that only emits.
func test_the_gather_plays_when_a_sitting_begins_and_stops_when_it_ends() -> void:
	var feedback: CultivationFeedback = CultivationFeedbackScript.new()
	add_to_tree(feedback)
	var gather := feedback.gather_player()
	assert_not_null(gather, "the gather is loaded")
	feedback.call("_on_meditation_started", &"site_lac_ha_spring")
	assert_true(gather.is_playing(), "the first breath draws the vein in")
	assert_eq(gather.position, Vector2.ZERO, "at the feet: the vein is under the seat")
	feedback.call("_on_meditation_ended", &"moved")
	assert_false(gather.is_playing(), "and stops the moment the sitting does")
	free_node(feedback)


func test_a_bolt_strike_bursts_where_it_landed_and_a_volley_reuses_the_players() -> void:
	var feedback: CastFeedback = CastFeedbackScript.new()
	add_to_tree(feedback)
	var strikes := feedback.strike_players()
	assert_eq(strikes.size(), CastFeedback.STRIKE_PLAYERS, "a small fixed set")
	var landed := Vector2(312, 148)
	feedback.call("_on_struck", landed)
	assert_true(strikes[0].is_playing(), "the strike bursts")
	assert_eq(strikes[0].position, landed, "where the runtime says the bolt landed")
	var before := feedback.get_child_count()
	for i in 7:
		feedback.call("_on_struck", landed + Vector2(i, 0))
	assert_eq(feedback.get_child_count(), before, "a volley creates no node")
	free_node(feedback)


func test_the_vein_gives_way_where_its_light_stands() -> void:
	# Built as the map scene builds it: the lights are the ambience's children before it is
	# ready (it collects them in `_ready`).
	var map := Node2D.new()
	var ambience: Node2D = MapAmbienceScript.new()
	map.add_child(ambience)
	var vein: Node2D = AmbienceLightScript.new()
	vein.set("role", AmbienceLight.ROLE_VEIN)
	vein.position = Vector2(616, 470)
	ambience.add_child(vein)
	add_to_tree(map)
	await scene_tree.process_frame
	ambience.call("pulse")
	var rupture := ambience.call("rupture_player") as VfxSequencePlayer
	assert_not_null(rupture, "the rupture is made on the first pulse")
	if rupture != null:
		assert_true(rupture.is_playing(), "and plays")
		assert_eq(ambience.to_global(rupture.position), Vector2(616, 470),
			"where the vein's light stands")
		assert_eq(rupture.z_index, 1, "on the transient-VFX layer, above the world")
	free_node(map)
