extends TestCase
## Presentation tests for the character visual pipeline (Phase 05 / D-026). Validates the
## four archetype `CharacterVisualProfileData` resources, the `CharacterVisualComponent`
## rendering contract (baseline dims, nearest filter, anchor, facing, missing-asset fail), the
## preview builds all four, and — the layering invariant — a `CharacterState` carries NO
## presentation data. All Nodes created are freed (L-019).

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


# All four authored profiles load, validate, and declare the 16x24 baseline + a 4-frame sheet.
func test_four_profiles_load_and_are_valid() -> void:
	for path in PROFILE_PATHS:
		var profile: Resource = load(path)
		assert_not_null(profile, "profile loads: %s" % path)
		assert_true(profile.is_valid(),
			"profile valid %s: %s" % [path, str(profile.validation_errors())])
		assert_eq(profile.frame_size, Vector2i(16, 24), "baseline frame size 16x24: %s" % path)
		assert_not_null(profile.idle_sheet, "idle sheet present: %s" % path)
		var expected_w: int = profile.frame_size.x * ProfileScript.DIRECTION_COUNT
		assert_eq(profile.idle_sheet.get_width(), expected_w, "sheet is 4 frames wide: %s" % path)
		assert_eq(profile.idle_sheet.get_height(), profile.frame_size.y, "sheet one frame tall")


# The component builds a nearest-filtered Sprite2D anchored so the sprite is lifted a full
# frame height above the origin (feet-on-origin), with the 4-frame directional sheet.
func test_component_builds_sprite_with_contract() -> void:
	var profile: Resource = load(PROFILE_PATHS[0])
	var visual: Node = VisualScript.new()
	add_to_tree(visual)
	assert_true(visual.setup(profile), "component accepts a valid profile")
	var sprite: Sprite2D = visual.get_sprite()
	assert_not_null(sprite, "component owns a Sprite2D")
	assert_eq(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
		"pixel-art nearest filter (no blur)")
	assert_eq(sprite.hframes, ProfileScript.DIRECTION_COUNT, "sheet split into 4 direction frames")
	assert_false(sprite.centered, "sprite is top-left anchored for feet-on-origin math")
	# Anchor: a 24px-tall frame lifts the sprite -24 on Y so its bottom sits on the origin.
	assert_eq(sprite.position.y, -float(profile.frame_size.y), "sprite lifted a full frame height")
	free_node(visual)


# Facing follows the movement vector and collapses 8-way to the nearest cardinal frame.
func test_facing_selects_direction_frame() -> void:
	var profile: Resource = load(PROFILE_PATHS[0])
	var visual: Node = VisualScript.new()
	add_to_tree(visual)
	visual.setup(profile)
	visual.update_facing(Vector2.RIGHT, true)
	assert_eq(visual.get_direction(), ProfileScript.Direction.RIGHT, "faces RIGHT")
	assert_eq(visual.get_sprite().frame, ProfileScript.Direction.RIGHT, "RIGHT frame selected")
	visual.update_facing(Vector2.UP, true)
	assert_eq(visual.get_direction(), ProfileScript.Direction.UP, "faces UP")
	# A diagonal with dominant Y maps to a cardinal; a zero vector keeps the last facing.
	visual.update_facing(Vector2(0.3, -1.0), true)
	assert_eq(visual.get_direction(), ProfileScript.Direction.UP, "diagonal collapses to UP")
	visual.update_facing(Vector2.ZERO, false)
	assert_eq(visual.get_direction(), ProfileScript.Direction.UP, "zero vector keeps last facing")
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
