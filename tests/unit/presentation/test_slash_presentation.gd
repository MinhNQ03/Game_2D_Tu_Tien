extends TestCase
## The SWORD CUT presentation (D-063 A3).
##
## What is under test is the SECOND body of the attack lifecycle: the same
## `READY → WINDUP → ACTIVE → RECOVERY` authority drives either the palm strike or the sword
## cut, chosen by `AttackData.body_action` and resolved with fallback by the visual component.
## The contract:
##
##   1. **DATA NAMES THE BODY** — `body_action` defaults to `attack`; the Kiếm attack names
##      `slash`; an empty name is refused at the boundary.
##   2. **GRACEFUL DEGRADATION** — a profile without the slash sheet falls back to the attack
##      sheet; nothing is ever left without a body for its swing.
##   3. **THE BLADE IS THE RIG'S** — while slashing, the drawn blade runs from the gripping
##      palm to the tip anchor of the frame being drawn, layered by the rig's own per-frame
##      depth; the VFX crescent is the tip's trajectory, so the two can never diverge.
##   4. **TIMING IS UNTOUCHED** — the cut keeps the shipped 120/80/240 ms; presentation
##      moves no mechanic.
##
## These drive the PUBLIC API only, never private cursors. Every `Node` built here is freed
## by the test that built it (L-019).

const ProfileScript := preload("res://src/data/characters/character_visual_profile_data.gd")
const VisualScript := preload("res://src/presentation/characters/character_visual_component.gd")
const AnchorScript := preload("res://src/data/characters/character_anchor_data.gd")
const AttackDataScript := preload("res://src/data/combat/attack_data.gd")
const FeedbackScript := preload("res://src/presentation/equipment/equipment_feedback.gd")

const PLAYER_PROFILE := "res://data/characters/visual/player_visual.tres"
const WOLF_PROFILE := "res://data/characters/visual/mist_wolf_visual.tres"
const PLAYER_ANCHORS := "res://data/characters/visual/anchors/player_proto_anchors.tres"
const KIEM_ATTACK := "res://data/combat/attack_player_kiem.tres"

const DOWN := CharacterVisualProfileData.Direction.DOWN
const POINT_BLADE := CharacterVisualProfileData.POINT_BLADE
const POINT_PALM := CharacterVisualProfileData.POINT_PALM


func _profile(path: String) -> CharacterVisualProfileData:
	return load(path) as CharacterVisualProfileData


func _component_for(profile: CharacterVisualProfileData) -> CharacterVisualComponent:
	var component: CharacterVisualComponent = VisualScript.new()
	add_to_tree(component)
	assert_true(component.setup(profile), "the profile binds")
	return component


## An entity with a visual and a weapon feedback, the way `Player` wires them: the feedback
## finds the visual by its sibling name.
func _entity_with_feedback(profile: CharacterVisualProfileData) -> Node2D:
	var entity := Node2D.new()
	add_to_tree(entity)
	var visual: CharacterVisualComponent = VisualScript.new()
	visual.name = "CharacterVisualComponent"
	entity.add_child(visual)
	assert_true(visual.setup(profile), "the profile binds")
	var feedback: EquipmentFeedback = FeedbackScript.new()
	feedback.name = "EquipmentFeedback"
	entity.add_child(feedback)
	feedback.show_weapon(&"weapon_kiem")
	return entity


# === Data names the body =====================================================

## `body_action` defaults to the palm strike every profile authors.
func test_body_action_defaults_to_attack() -> void:
	var data: AttackData = AttackDataScript.new()
	assert_eq(data.body_action, &"attack", "the default body is the palm strike")


## An empty body name is refused at the boundary, naming the field.
func test_empty_body_action_is_refused_at_the_boundary() -> void:
	var data: AttackData = AttackDataScript.new()
	data.id = &"attack_test_body"
	assert_true(data.is_valid(), "the fixture is valid with defaults")
	data.body_action = &""
	assert_false(data.is_valid(), "an empty body_action is refused")
	assert_true("body_action" in str(data.validation_errors()),
		"and the error names the field")


## The Kiếm attack names the slash body, and its timing is LOCKED: presentation may change
## the body, never the 120/80/240 ms the combat balance was tuned on (PLAN A0 §7).
func test_kiem_attack_names_slash_and_locks_its_timing() -> void:
	var attack := load(KIEM_ATTACK) as AttackData
	assert_not_null(attack, "the shipped attack loads")
	assert_true(attack.is_valid(), "it is valid: %s" % str(attack.validation_errors()))
	assert_eq(attack.body_action, &"slash", "the Kiếm swings the sword cut")
	assert_true(absf(attack.windup_seconds - 0.12) < 0.0001, "windup stays 120 ms")
	assert_true(absf(attack.active_seconds - 0.08) < 0.0001, "active stays 80 ms")
	assert_true(absf(attack.recovery_seconds - 0.24) < 0.0001, "recovery stays 240 ms")


# === Graceful degradation ====================================================

## The player profile plays the slash sheet by name.
func test_slash_plays_the_slash_sheet() -> void:
	var profile := _profile(PLAYER_PROFILE)
	var component := _component_for(profile)
	assert_true(component.play_action(CharacterVisualComponent.ACTION_SLASH),
		"the slash starts")
	assert_eq(component.current_action(), CharacterVisualComponent.ACTION_SLASH, "by name")
	assert_eq(component.current_anim(), CharacterVisualProfileData.ANIM_SLASH,
		"and anchors resolve under the slash key")
	assert_eq(component.get_sprite().texture, profile.slash_sheet,
		"the slash sheet shows")
	free_node(component)


## A look without the slash sheet (the wolf; the daobao look until its sheet is rendered)
## falls back to the palm strike — never left without a body for its swing.
func test_slash_falls_back_to_attack_without_the_sheet() -> void:
	var component := _component_for(_profile(WOLF_PROFILE))
	assert_false(component.play_action(CharacterVisualComponent.ACTION_SLASH),
		"no slash sheet: the action is refused, not faked")
	assert_eq(component.resolve_body_action(&"slash"),
		CharacterVisualComponent.ACTION_ATTACK,
		"so the slash resolves to the palm strike")
	assert_eq(component.resolve_body_action(&"attack"),
		CharacterVisualComponent.ACTION_ATTACK,
		"attack still resolves to itself")
	assert_eq(component.resolve_body_action(&""),
		CharacterVisualComponent.ACTION_ATTACK,
		"and an empty name degrades instead of breaking")
	free_node(component)


## The wiring is fail-closed: anchors naming `slash/*` with no slash sheet on the profile is
## an invalid profile, so a missing sheet can never ship silently.
func test_profile_naming_slash_anchors_but_no_sheet_is_invalid() -> void:
	var profile := _profile(PLAYER_PROFILE).duplicate() as CharacterVisualProfileData
	profile.slash_sheet = null
	assert_false(profile.is_valid(),
		"slash anchors with no slash sheet is refused")
	assert_true("slash" in str(profile.validation_errors()),
		"and the error names the missing sheet")


## Both bodies share the strike lifecycle paths.
func test_is_strike_action_covers_both_bodies() -> void:
	assert_true(CharacterVisualComponent.is_strike_action(
		CharacterVisualComponent.ACTION_ATTACK), "the palm strike is a strike")
	assert_true(CharacterVisualComponent.is_strike_action(
		CharacterVisualComponent.ACTION_SLASH), "the sword cut is a strike")
	assert_false(CharacterVisualComponent.is_strike_action(
		CharacterVisualComponent.ACTION_MEDITATE), "meditate is not")
	assert_false(CharacterVisualComponent.is_strike_action(
		CharacterVisualComponent.ACTION_CAST), "cast is not")
	assert_false(CharacterVisualComponent.is_strike_action(
		CharacterVisualComponent.ACTION_NONE), "none is not")


# === The rig's depth =========================================================

## The pipeline's depth track is readable per frame and direction; unknown points fall back.
func test_blade_depth_track_is_readable() -> void:
	var anchors := load(PLAYER_ANCHORS) as CharacterAnchorData
	assert_not_null(anchors, "the shipped anchors load")
	assert_true(anchors.has_depth(&"slash", &"blade"),
		"the pipeline wrote a depth for the sword tip")
	assert_eq(anchors.depth_at(&"slash", &"blade", DOWN, 0, 999.0),
		anchors.depth_at(&"slash", &"blade", DOWN, 0),
		"where the track exists, the value comes from the track, not the fallback")
	assert_false(anchors.has_depth(&"attack", &"blade"),
		"no depth where the pipeline wrote none")
	assert_eq(anchors.depth_at(&"attack", &"blade", DOWN, 0, -1.0), -1.0,
		"and the lookup falls back instead of guessing")


## A depth track that does not match its point track is refused at the boundary.
func test_depth_validation_rejects_mismatched_tracks() -> void:
	var anchors: CharacterAnchorData = AnchorScript.new()
	anchors.id = &"test_depths"
	anchors.frame_size = Vector2i(32, 48)
	var pts := PackedVector2Array()
	for i in 8:  # 2 frames x 4 directions: valid on its own.
		pts.append(Vector2(i, -i))
	anchors.points = {"slash/blade": pts}
	assert_true(anchors.is_valid(), "the points-only fixture is accepted")
	anchors.depths = {"slash/blade": PackedFloat32Array([1.0, 2.0, 3.0, 4.0])}
	assert_false(anchors.is_valid(), "a depth track of the wrong length is refused")
	assert_true("slash/blade" in str(anchors.validation_errors()),
		"and the error names the track")
	anchors.depths = {"slash/ghost": PackedFloat32Array(
		[1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0])}
	assert_false(anchors.is_valid(), "a depth with no point track is refused")


# === The drawn blade =========================================================

## While slashing, the blade runs from the gripping palm to the tip anchor of the frame
## being drawn — never the old facing-guess thrust.
func test_blade_segment_runs_palm_to_tip_while_slashing() -> void:
	var entity := _entity_with_feedback(_profile(PLAYER_PROFILE))
	var visual := entity.get_node("CharacterVisualComponent") as CharacterVisualComponent
	var feedback := entity.get_node("EquipmentFeedback") as EquipmentFeedback
	assert_true(visual.play_action(CharacterVisualComponent.ACTION_SLASH),
		"the slash starts")
	var segment := feedback.blade_segment()
	assert_eq(segment.size(), 2, "a grip and a tip")
	var expected_tip := (visual.position
		+ visual.anchor_point(POINT_BLADE)).round()
	assert_eq(segment[1], expected_tip,
		"the tip is the rig's tip anchor of the drawn frame")
	var expected_grip := (visual.position
		+ visual.anchor_point(POINT_PALM)).round()
	assert_eq(segment[0], expected_grip, "the grip is the drawn palm")
	var stale_tip := (expected_grip + Vector2(0.0, 13.0)).round()
	assert_ne(segment[1], stale_tip,
		"and it is not the old facing-guess thrust")
	free_node(entity)


## The blade layers from the rig's per-frame depth: in front where the rig holds it in
## front, behind where it lays it back — varying across the swing.
func test_blade_layer_follows_the_rig_depth() -> void:
	var entity := _entity_with_feedback(_profile(PLAYER_PROFILE))
	var visual := entity.get_node("CharacterVisualComponent") as CharacterVisualComponent
	var feedback := entity.get_node("EquipmentFeedback") as EquipmentFeedback
	visual.play_action(CharacterVisualComponent.ACTION_SLASH)
	var depth0 := visual.anchor_depth(POINT_BLADE)
	assert_eq(feedback.blade_layer(), 1 if depth0 >= 0.0 else 0,
		"the showing frame layers by its own depth")
	visual.drive_action(0.15)
	var depth1 := visual.anchor_depth(POINT_BLADE)
	assert_eq(feedback.blade_layer(), 1 if depth1 >= 0.0 else 0,
		"and a later frame layers by its own depth")
	free_node(entity)


## A tip sampled at a driven progress reads the same column the body draws.
func test_tip_at_progress_matches_the_drawn_column() -> void:
	var component := _component_for(_profile(PLAYER_PROFILE))
	component.play_action(CharacterVisualComponent.ACTION_SLASH)
	assert_eq(component.anchor_point_at_progress(POINT_BLADE, 0.0),
		component.anchor_point(POINT_BLADE),
		"progress 0 reads the showing column")
	component.drive_action(0.99)
	assert_eq(component.anchor_point_at_progress(POINT_BLADE, 0.99),
		component.anchor_point(POINT_BLADE),
		"progress .99 reads the driven column")
	free_node(component)
	var idle := _component_for(_profile(PLAYER_PROFILE))
	assert_eq(idle.anchor_point_at_progress(POINT_BLADE, 0.5, Vector2(-1, -1)),
		Vector2(-1, -1), "with no action playing, the lookup falls back")
	free_node(idle)
