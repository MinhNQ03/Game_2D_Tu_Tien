extends TestCase
## Presentation tests for the character visual pipeline (Phase 05 / D-026, animated in D-046).
## Validates the four archetype `CharacterVisualProfileData` resources, the GRID sheet
## contract (direction rows x animation columns), the `CharacterVisualComponent` rendering
## contract (baseline dims, nearest filter, anchor, facing, missing-asset fail), the ANIMATION
## clock (advance, wrap, idle<->walk switch, static sheets cost nothing), the preview builds
## all four, and — the layering invariant — a `CharacterState` carries NO presentation data.
## All Nodes created are freed (L-019).

const ProfileScript := preload("res://src/data/characters/character_visual_profile_data.gd")
const VisualScript := preload("res://src/presentation/characters/character_visual_component.gd")
const PreviewScript := preload("res://src/presentation/characters/character_preview.gd")
const StateScript := preload("res://src/domain/character/character_state.gd")
const TemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")

const PROFILE_PATHS := [
	"res://data/characters/visual/player_visual.tres",
	"res://data/characters/visual/cultivator_f_visual.tres",
	"res://data/characters/visual/elder_visual.tres",
	"res://data/characters/visual/merchant_visual.tres",
]


# All four authored profiles load, validate, and declare the 32x48 baseline with a GRID sheet
# (D-046): a whole number of animation columns x exactly DIRECTION_COUNT rows. Every profile
# must now author a walk sheet too — the whole point of D-046 was that leaving it null made
# the character slide without animating.
func test_four_profiles_load_and_are_valid() -> void:
	for path in PROFILE_PATHS:
		var profile: Resource = load(path)
		assert_not_null(profile, "profile loads: %s" % path)
		assert_true(profile.is_valid(),
			"profile valid %s: %s" % [path, str(profile.validation_errors())])
		assert_eq(profile.frame_size, Vector2i(32, 48), "baseline frame size 32x48: %s" % path)
		assert_true(profile.frame_duration > 0.0, "frame_duration authored: %s" % path)
		assert_not_null(profile.idle_sheet, "idle sheet present: %s" % path)
		assert_not_null(profile.walk_sheet,
			"walk sheet present (a null walk sheet is what made the old character slide): %s"
				% path)
		var rows: int = ProfileScript.DIRECTION_COUNT
		for label in ["idle", "walk"]:
			var sheet: Texture2D = profile.idle_sheet if label == "idle" else profile.walk_sheet
			assert_eq(sheet.get_height(), profile.frame_size.y * rows,
				"%s sheet is %d direction rows tall: %s" % [label, rows, path])
			var frames: int = profile.frame_count_of(sheet)
			assert_true(frames >= 1, "%s sheet has >=1 frame: %s" % [label, path])
			assert_eq(sheet.get_width(), profile.frame_size.x * frames,
				"%s sheet width is exactly %d whole frames: %s" % [label, frames, path])


# The generator and the data must agree on the frame COUNTS. If someone regenerates the art
# with a different number of columns and forgets the profile, this is the drift guard (L-014).
# D-057B redrew the cultivator: a 6-beat breath, an 8-frame two-step stride, an 8-frame palm
# strike (two anticipation, two strike, four recovery).
func test_player_sheets_have_the_authored_frame_counts() -> void:
	var profile: Resource = load(PROFILE_PATHS[0])
	assert_eq(profile.frame_count_of(profile.idle_sheet), 6, "idle is a 6-frame breath")
	assert_eq(profile.frame_count_of(profile.walk_sheet), 8, "walk is an 8-frame stride")
	assert_eq(profile.frame_count_of(profile.attack_sheet), 8, "the palm strike is 8 frames")


# A sheet whose width is not a whole number of frames is REJECTED, not silently floored —
# otherwise a mis-sliced sheet renders half a character and nothing reports it.
func test_ragged_sheet_width_is_rejected() -> void:
	var profile: Resource = ProfileScript.new()
	profile.id = &"vis_ragged"
	profile.frame_size = Vector2i(32, 48)
	var ragged := ImageTexture.create_from_image(
		Image.create(32 * 2 + 7, 48 * ProfileScript.DIRECTION_COUNT, false, Image.FORMAT_RGBA8))
	profile.idle_sheet = ragged
	assert_false(profile.is_valid(), "a ragged sheet width is invalid")
	assert_eq(profile.frame_count_of(ragged), 0, "frame count of a ragged sheet is 0, not 2")
	var reason := str(profile.validation_errors())
	assert_true(reason.contains("whole multiple"),
		"the error names the real reason (got: %s)" % reason)


# The component builds a nearest-filtered Sprite2D anchored so the sprite is lifted a full
# frame height above the origin (feet-on-origin), split as a direction-row x frame-column grid.
func test_component_builds_sprite_with_contract() -> void:
	var profile: Resource = load(PROFILE_PATHS[0])
	var visual: Node = VisualScript.new()
	add_to_tree(visual)
	assert_true(visual.setup(profile), "component accepts a valid profile")
	var sprite: Sprite2D = visual.get_sprite()
	assert_not_null(sprite, "component owns a Sprite2D")
	assert_eq(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
		"pixel-art nearest filter (no blur)")
	assert_eq(sprite.vframes, ProfileScript.DIRECTION_COUNT,
		"one sheet ROW per direction")
	assert_eq(sprite.hframes, profile.frame_count_of(profile.idle_sheet),
		"columns == the idle sheet's frame count")
	assert_false(sprite.centered, "sprite is top-left anchored for feet-on-origin math")
	# Anchor: the sheet's GROUND LINE sits on the origin. A 48px frame is lifted -48 on Y, then
	# lowered by anchor_offset.y — the rows the sheet keeps below its feet (D-062: a forward
	# foot seen from 30° projects below the origin, so the pipeline stands feet on row 43).
	assert_eq(sprite.position.y, -float(profile.frame_size.y) + profile.anchor_offset.y,
		"sprite lifted a frame height less the rows below the feet")
	assert_true(profile.anchor_offset.y >= 0.0
			and profile.anchor_offset.y <= profile.frame_size.y / 8.0,
		"the feet stand at most an eighth of the frame above its bottom (%s)"
			% str(profile.anchor_offset))
	free_node(visual)


# Facing follows the movement vector and collapses 8-way to the nearest cardinal ROW.
func test_facing_selects_direction_row() -> void:
	var profile: Resource = load(PROFILE_PATHS[0])
	var visual: Node = VisualScript.new()
	add_to_tree(visual)
	visual.setup(profile)
	# Moving uses the walk sheet, so the row stride is the WALK frame count, and the walk opens
	# on the profile's first rest column (a weight shift, not a leap into full stride).
	var walk_frames: int = profile.frame_count_of(profile.walk_sheet)
	var entry: int = profile.walk_rest_columns[0]
	visual.update_facing(Vector2.RIGHT, true)
	assert_eq(visual.get_direction(), ProfileScript.Direction.RIGHT, "faces RIGHT")
	assert_eq(visual.get_sprite().frame, ProfileScript.Direction.RIGHT * walk_frames + entry,
		"RIGHT row, the walk's entry column selected")
	visual.update_facing(Vector2.UP, true)
	assert_eq(visual.get_direction(), ProfileScript.Direction.UP, "faces UP")
	# A diagonal with dominant Y maps to a cardinal; a zero vector keeps the last facing.
	visual.update_facing(Vector2(0.3, -1.0), true)
	assert_eq(visual.get_direction(), ProfileScript.Direction.UP, "diagonal collapses to UP")
	visual.update_facing(Vector2.ZERO, false)
	assert_eq(visual.get_direction(), ProfileScript.Direction.UP, "zero vector keeps last facing")
	free_node(visual)


# The animation actually ADVANCES and WRAPS, and stays inside its own direction row. This is
# the test the old pipeline could not have: with one frame per direction there was nothing
# to advance.
func test_animation_advances_within_the_row_and_wraps() -> void:
	var profile: Resource = load(PROFILE_PATHS[0])
	var visual: Node = VisualScript.new()
	add_to_tree(visual)
	visual.setup(profile)
	visual.update_facing(Vector2.DOWN, false)        # idle, DOWN row
	var frames: int = profile.frame_count_of(profile.idle_sheet)
	var step: float = profile.frame_duration
	assert_eq(visual.get_column(), 0, "starts on column 0")
	visual.advance(step * 1.5)
	assert_eq(visual.get_column(), 1, "one whole step advances exactly one column")
	assert_eq(visual.get_sprite().frame, ProfileScript.Direction.DOWN * frames + 1,
		"frame index is row*frames + column")
	# Walk a full cycle from here: it must land back on the starting column, never past it.
	for _i in range(frames):
		visual.advance(step)
	assert_eq(visual.get_column(), 1, "a full cycle of %d frames wraps back round" % frames)
	assert_true(visual.get_sprite().frame < frames * ProfileScript.DIRECTION_COUNT,
		"the frame index never leaves the sheet")
	free_node(visual)


# Switching walk->idle must land on the idle sheet's FIRST column. The sheets have different
# frame counts (8 vs 6), so a column carried over from the longer sheet would index past the
# shorter one. The walk is distance-clocked (D-057B), so the node is MOVED to advance it, and
# the stop is taken on a rest column so it hands straight to the idle.
func test_switching_animation_resets_the_column() -> void:
	var profile: Resource = load(PROFILE_PATHS[0])
	var visual: Node2D = VisualScript.new()
	add_to_tree(visual)
	visual.setup(profile)
	var walk_frames: int = profile.frame_count_of(profile.walk_sheet)
	var idle_frames: int = profile.frame_count_of(profile.idle_sheet)
	assert_true(walk_frames > idle_frames,
		"this test only means something while walk (%d) is longer than idle (%d)"
			% [walk_frames, idle_frames])
	var step: float = profile.stride_px / float(walk_frames)
	visual.advance(0.0)                              # first observation of the origin
	visual.update_facing(Vector2.DOWN, true)         # walk, on the entry column
	var last := walk_frames - 1
	while visual.get_column() != last:
		visual.position.y += step
		visual.advance(0.016)
	assert_eq(visual.get_column(), last, "advanced to the last walk column")
	assert_true(profile.walk_rest_columns.has(last),
		"the last column is a rest column, so the stop is immediate (fixture premise)")
	visual.update_facing(Vector2.DOWN, false)        # back to idle (shorter sheet)
	assert_eq(visual.get_column(), 0, "column reset on the animation switch")
	assert_eq(visual.get_sprite().texture, profile.idle_sheet, "the idle sheet is showing")
	assert_true(visual.get_sprite().frame < idle_frames * ProfileScript.DIRECTION_COUNT,
		"the idle frame index stays inside the shorter idle sheet")
	free_node(visual)


# A single-frame sheet must switch _process OFF — a static character should cost nothing
# per frame (`05-performance-testing.md`).
func test_single_frame_sheet_stops_processing() -> void:
	var still := ImageTexture.create_from_image(
		Image.create(32, 48 * ProfileScript.DIRECTION_COUNT, false, Image.FORMAT_RGBA8))
	var profile: Resource = ProfileScript.new()
	profile.id = &"vis_still"
	profile.frame_size = Vector2i(32, 48)
	profile.frame_duration = 0.1
	profile.idle_sheet = still
	assert_true(profile.is_valid(), "a 1-frame sheet is legal: %s"
		% str(profile.validation_errors()))
	var visual: Node = VisualScript.new()
	add_to_tree(visual)
	assert_true(visual.setup(profile), "component accepts the single-frame profile")
	assert_eq(profile.frame_count_of(still), 1, "one frame")
	assert_false(visual.is_processing(), "_process is off for a static sheet")
	free_node(visual)


# A missing/invalid profile fails CLEARLY (setup returns false), does not crash or render.
func test_missing_profile_fails_clearly() -> void:
	var visual: Node = VisualScript.new()
	add_to_tree(visual)
	assert_false(visual.setup(null), "null profile rejected")
	var bad: Resource = ProfileScript.new()
	bad.id = &""  # invalid: empty id, no idle sheet
	assert_false(visual.setup(bad), "invalid profile rejected (no silent blank)")
	free_node(visual)


# The preview scene builds a visual for all four archetypes (dev showcase, not first scene).
func test_preview_builds_all_four() -> void:
	var preview: Node = PreviewScript.new()
	add_to_tree(preview)  # _ready() builds the four components
	var visuals := 0
	for child in preview.get_children():
		if child is CharacterVisualComponent:
			visuals += 1
	assert_eq(visuals, PROFILE_PATHS.size(), "preview shows all four archetypes")
	free_node(preview)


# The two visual paths must put the character's FEET in the same place. `player.tscn` carries
# a static fallback Sprite2D for the isolated-harness case, and the component replaces it in a
# real run; if only one of them is feet-anchored the character jumps half a body height the
# moment a profile binds. The scene is instantiated but NOT added to the tree, so `_ready()`
# never runs and this reads the AUTHORED values (and touches no autoload — L-010).
func test_scene_fallback_sprite_is_feet_anchored_like_the_component() -> void:
	var profile: Resource = load(PROFILE_PATHS[0])
	var packed: PackedScene = load("res://src/gameplay/entities/player.tscn")
	assert_not_null(packed, "player.tscn loads")
	var player: Node = packed.instantiate()
	assert_not_null(player, "player instantiates")
	if player == null:
		return
	var fallback := player.get_node_or_null("Visual") as Sprite2D
	assert_not_null(fallback, "the scene still has its fallback Visual sprite")
	if fallback == null:
		player.free()
		return
	assert_false(fallback.centered,
		"fallback is top-left anchored, like the component, so feet math matches")
	# Component anchor: x = -w/2, y = -h. The fallback must land on the same point.
	assert_eq(fallback.offset,
		Vector2(-profile.frame_size.x / 2.0, -float(profile.frame_size.y)),
		"fallback offset puts the feet on the origin for a %s frame" % str(profile.frame_size))

	# The collision footprint belongs AT the feet, not straddling the origin: with the origin
	# at the feet, a box centred on it would put half the player's collision underground.
	var body := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	assert_not_null(body, "player has a collision shape")
	if body == null:
		player.free()
		return
	var rect := body.shape as RectangleShape2D
	assert_not_null(rect, "the footprint is a rectangle")
	if rect != null:
		var top := body.position.y - rect.size.y * 0.5
		var bottom := body.position.y + rect.size.y * 0.5
		assert_true(bottom <= 0.01,
			"the footprint does not extend below the feet/origin (bottom=%f)" % bottom)
		assert_true(top < 0.0, "the footprint has height above the origin (top=%f)" % top)
		assert_true(rect.size.x <= float(profile.frame_size.x),
			"the footprint is no wider than the art frame (%f vs %d)"
				% [rect.size.x, profile.frame_size.x])
	player.free()


# LAYERING INVARIANT: a CharacterState (domain) carries NO presentation field — the sprite
# ref lives only on the template/profile, never serialized into the authoritative state.
func test_character_state_has_no_presentation_data() -> void:
	var stats: Resource = StatBlockScript.new()
	stats.max_hp = 10
	stats.attack = 1
	stats.defense = 0
	stats.move_speed = 10.0
	var template: Resource = TemplateScript.new()
	template.id = &"char_x"
	template.name_key = &"NAME_X"
	template.base_stats = stats
	template.sprite_set_ref = "res://data/characters/visual/player_visual.tres"
	var state = StateScript.create_from_template(template, &"inst_x")
	assert_not_null(state, "state built")
	var dict: Dictionary = state.to_dict()
	assert_false(dict.has("sprite_set_ref"), "state does not serialize sprite_set_ref")
	assert_false(dict.has("portrait_ref"), "state does not serialize portrait_ref")
	# No key in the persistent dict should reference a visual resource path.
	for key in dict:
		var v: Variant = dict[key]
		if typeof(v) == TYPE_STRING:
			assert_false((v as String).contains("visual"), "no visual path leaked into '%s'" % key)
