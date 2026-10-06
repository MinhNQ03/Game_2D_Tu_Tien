extends TestCase
## LOCOMOTION as a gait, and the ANCHORS an effect starts from (D-057B).
##
## `CharacterVisualComponent` used to loop the walk on a clock whenever the owner said "moving",
## so a character pushing into a wall trod air at full cadence, a slowed one strode at full
## speed, the legs snapped together on every stop, and a 180° turn was a one-frame flip. The
## contract now under test (`MOTION_DESIGN_CONTRACT.md` M-3.3, M-3.5, M-8.1, M-10.1):
##
##   * the stride is clocked by the DISTANCE the node actually moved (`stride_px`);
##   * moving intent that moves nothing STALLS the stride; a teleport is not a step;
##   * the walk opens on a rest column and a stop SETTLES onto one;
##   * a reversal shows an intermediate facing, a diagonal does not flicker (hysteresis);
##   * idle breaths of creatures placed apart are out of phase, deterministically;
##   * a named body point (`palm`, `core`) is where the drawn frame puts it, for every facing.
##
## The tests MOVE the node and then `advance()`, which is exactly what a moving character does —
## no private cursor is poked. Every node is freed by the test that built it (L-019).

const VisualScript := preload("res://src/presentation/characters/character_visual_component.gd")
const ProfileScript := preload("res://src/data/characters/character_visual_profile_data.gd")
const AnchorScript := preload("res://src/data/characters/character_anchor_data.gd")

const PLAYER := "res://data/characters/visual/player_visual.tres"
const WOLF := "res://data/characters/visual/mist_wolf_visual.tres"
const ALL_PROFILES := [
	"res://data/characters/visual/player_visual.tres",
	"res://data/characters/visual/cultivator_f_visual.tres",
	"res://data/characters/visual/elder_visual.tres",
	"res://data/characters/visual/merchant_visual.tres",
	"res://data/characters/visual/mist_wolf_visual.tres",
]

const TICK := 1.0 / 60.0


func _profile(path: String) -> CharacterVisualProfileData:
	return load(path) as CharacterVisualProfileData


## A component in the tree at `at`, bound to a shipped profile, with its origin already observed
## (the first `advance` only records where the node stands).
func _component(path: String, at: Vector2 = Vector2.ZERO) -> CharacterVisualComponent:
	var component: CharacterVisualComponent = VisualScript.new()
	component.position = at
	add_to_tree(component)
	assert_true(component.setup(_profile(path)), "%s binds" % path.get_file())
	component.advance(0.0)
	return component


## Stride `component` one step of ground at a time until it shows `column` (bounded: a broken
## stride fails the assertion instead of hanging the suite).
func _stride_to(component: CharacterVisualComponent, column: int) -> void:
	var profile := _profile(PLAYER)
	var step := profile.stride_px / float(profile.frame_count_of(profile.walk_sheet))
	for _i in 32:
		if component.get_column() == column:
			return
		_walk(component, Vector2.RIGHT, step, 1)
	assert_eq(component.get_column(), column, "the stride reached column %d" % column)


## Walk `component` by `distance` px along `direction`, split over `ticks` frames.
func _walk(component: CharacterVisualComponent, direction: Vector2, distance: float,
		ticks: int) -> void:
	for _i in ticks:
		component.position += direction.normalized() * (distance / float(ticks))
		component.advance(TICK)


# === Data ====================================================================

## Every shipped profile authors the D-057B locomotion data and anchors that VALIDATE against
## its own sheets. An optional field nothing authors is a no-op with documentation (L-029).
func test_every_shipped_profile_authors_stride_and_anchors() -> void:
	for path in ALL_PROFILES:
		var profile := _profile(path)
		assert_true(profile.is_valid(),
			"%s validates: %s" % [path.get_file(), str(profile.validation_errors())])
		assert_true(profile.stride_px > 0.0,
			"%s walks by distance (stride_px %f)" % [path.get_file(), profile.stride_px])
		assert_not_null(profile.anchors, "%s carries anchors" % path.get_file())
		if profile.anchors == null:
			continue
		for anim in [ProfileScript.ANIM_IDLE, ProfileScript.ANIM_WALK, ProfileScript.ANIM_ATTACK]:
			for point in [ProfileScript.POINT_PALM, ProfileScript.POINT_CORE]:
				assert_true(profile.anchors.has_point(anim, point),
					"%s anchors %s/%s" % [path.get_file(), anim, point])


## A cultivator's stop needs rest columns; the four-beat wolf has none, by design.
func test_rest_columns_are_authored_where_a_biped_needs_them() -> void:
	var player := _profile(PLAYER)
	assert_false(player.walk_rest_columns.is_empty(), "the biped names its rest columns")
	assert_false(player.walk_rest_columns.has(0) or player.walk_rest_columns.has(4),
		"the two CONTACT frames (feet wide apart) are not rest columns")
	assert_true(_profile(WOLF).walk_rest_columns.is_empty(),
		"the quadruped's four-beat gait has no feet-together frame, so it stops at once")


## The validator refuses each way the new data can disagree with the art.
func test_profile_validation_refuses_mismatched_locomotion_data() -> void:
	var good := _profile(PLAYER)
	var bad: CharacterVisualProfileData = good.duplicate()
	bad.walk_rest_columns = PackedInt32Array([1, 99])
	assert_true("walk_rest_columns" in str(bad.validation_errors()),
		"a rest column outside the walk sheet is named")
	bad = good.duplicate()
	bad.stride_px = -4.0
	assert_true("stride_px" in str(bad.validation_errors()), "a negative stride is named")

	bad = good.duplicate()
	bad.anchors = _profile(WOLF).anchors  # a 32x32 anchor set on a 32x48 profile
	var reasons := str(bad.validation_errors())
	assert_true("cell" in reasons, "anchors measured in another cell size are refused: %s"
		% reasons)

	var short: CharacterAnchorData = AnchorScript.new()
	short.id = &"anchors_short"
	short.frame_size = good.frame_size
	short.points = {"idle/palm": PackedVector2Array([Vector2.ZERO, Vector2.ZERO,
		Vector2.ZERO, Vector2.ZERO])}  # 1 frame x 4 directions, idle has 6
	bad = good.duplicate()
	bad.anchors = short
	reasons = str(bad.validation_errors())
	assert_true("cover 1 frames" in reasons,
		"anchors covering the wrong number of frames are refused: %s" % reasons)


## Anchor data refuses a malformed key and a ragged track.
func test_anchor_data_validates_its_own_shape() -> void:
	var data: CharacterAnchorData = AnchorScript.new()
	data.id = &"anchors_x"
	data.frame_size = Vector2i(32, 48)
	data.points = {"nokey": PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
		Vector2.ZERO]), "idle/palm": PackedVector2Array([Vector2.ZERO])}
	# Joined, not `str()`: an Array's repr escapes the quotes the messages are written with.
	var reasons := " | ".join(PackedStringArray(data.validation_errors()))
	assert_true("'nokey' is not" in reasons, "a key without '<anim>/<point>' is named: %s"
		% reasons)
	assert_true("holds 1 points" in reasons, "a ragged track is named")
	assert_eq(data.point_at(&"idle", &"palm", 9, 0, Vector2(7, 7)), Vector2(7, 7),
		"an out-of-range lookup returns the fallback, never a point off the body")


# === The stride is clocked by distance =======================================

## One stride step of ground covered advances exactly one column; standing still advances none.
func test_the_stride_follows_distance_not_time() -> void:
	var component := _component(PLAYER)
	var profile := _profile(PLAYER)
	var frames := profile.frame_count_of(profile.walk_sheet)
	var step := profile.stride_px / float(frames)
	component.update_facing(Vector2.RIGHT, true)
	var start := component.get_column()
	assert_eq(start, profile.walk_rest_columns[0], "the walk opens on the first rest column")

	_walk(component, Vector2.RIGHT, step * 3.0 + 0.05, 6)
	assert_eq(component.get_column(), (start + 3) % frames,
		"three steps of ground = three columns, whatever the frame rate")

	# Time alone moves nothing: the same intent with no displacement holds the column until
	# the stall, and never strides.
	var held := component.get_column()
	component.advance(CharacterVisualComponent.STALL_SECONDS * 0.5)
	assert_eq(component.get_column(), held, "time without distance does not stride")
	free_node(component)


## Half the speed is half the cadence: the same distance takes twice the frames, and lands on
## the same column. This is the property the old time-clocked loop could not have.
func test_cadence_scales_with_real_speed() -> void:
	var fast := _component(PLAYER)
	var slow := _component(PLAYER, Vector2(0, 200))
	var profile := _profile(PLAYER)
	var distance := profile.stride_px * 0.75 + 5.0  # mid-step: no float tie on a boundary
	fast.update_facing(Vector2.RIGHT, true)
	slow.update_facing(Vector2.RIGHT, true)
	_walk(fast, Vector2.RIGHT, distance, 10)
	_walk(slow, Vector2.RIGHT, distance, 20)
	assert_eq(fast.get_column(), slow.get_column(),
		"the same ground covered gives the same stride, at any speed")
	free_node(fast)
	free_node(slow)


## Pushing into a wall: moving intent, no displacement. The stride stops and the body settles
## instead of treading air; when the body moves again, the stride resumes.
func test_a_blocked_body_stops_striding_and_resumes_when_it_moves() -> void:
	var component := _component(PLAYER)
	component.update_facing(Vector2.RIGHT, true)
	assert_eq(component.gait(), CharacterVisualComponent.Gait.WALK, "walking")
	for _i in 12:  # 0.2s of intent against a wall
		component.advance(TICK)
	assert_ne(component.gait(), CharacterVisualComponent.Gait.WALK,
		"intent that moves nothing for > STALL_SECONDS is not a walk")
	for _i in 6:
		component.advance(TICK)
	assert_eq(component.gait(), CharacterVisualComponent.Gait.IDLE, "it settled into the idle")
	_walk(component, Vector2.RIGHT, 6.0, 2)
	assert_eq(component.gait(), CharacterVisualComponent.Gait.WALK,
		"the stride picks back up the moment the body moves")
	free_node(component)


## A teleport (spawn, map transfer) is not a step: the stride does not spin.
func test_a_teleport_is_not_a_stride() -> void:
	var component := _component(PLAYER)
	component.update_facing(Vector2.RIGHT, true)
	var column := component.get_column()
	component.position += Vector2(600, 0)
	component.advance(TICK)
	assert_eq(component.get_column(), column, "a 600px jump advanced the stride by nothing")
	free_node(component)


# === Start and stop ==========================================================

## Stopping on a CONTACT frame (feet wide) settles: the stride finishes to the next rest column,
## quickly, and only then does the idle take over. Stopping on a rest column is immediate.
func test_a_stop_settles_onto_a_rest_column() -> void:
	var component := _component(PLAYER)
	var profile := _profile(PLAYER)
	component.update_facing(Vector2.RIGHT, true)
	_stride_to(component, 4)  # the second contact frame
	component.update_facing(Vector2.ZERO, false)
	assert_eq(component.gait(), CharacterVisualComponent.Gait.SETTLE,
		"stopping with the feet wide apart settles rather than snapping")
	assert_eq(component.get_sprite().texture, profile.walk_sheet,
		"the settle is drawn with the walk's own frames")
	component.advance(CharacterVisualComponent.SETTLE_FRAME_SECONDS * 1.01)
	assert_eq(component.gait(), CharacterVisualComponent.Gait.IDLE,
		"one settle frame lands on the next rest column, then the idle takes over")
	assert_eq(component.get_sprite().texture, profile.idle_sheet, "the idle is showing")
	free_node(component)


## Walking again in the middle of a settle CONTINUES the stride where the feet are.
func test_walking_again_mid_settle_continues_the_stride() -> void:
	var component := _component(PLAYER)
	component.update_facing(Vector2.RIGHT, true)
	_stride_to(component, 4)
	component.update_facing(Vector2.ZERO, false)
	assert_eq(component.gait(), CharacterVisualComponent.Gait.SETTLE, "settling")
	component.update_facing(Vector2.RIGHT, true)
	assert_eq(component.gait(), CharacterVisualComponent.Gait.WALK, "walking again")
	assert_eq(component.get_column(), 4, "from the column the feet were on, not a rest pose")
	free_node(component)


## The wolf names no rest columns, so its stop is immediate.
func test_a_quadruped_stops_at_once() -> void:
	var component := _component(WOLF)
	component.update_facing(Vector2.LEFT, true)
	_walk(component, Vector2.LEFT, 20.0, 4)
	component.update_facing(Vector2.ZERO, false)
	assert_eq(component.gait(), CharacterVisualComponent.Gait.IDLE, "straight to the idle")
	free_node(component)


# === Turning =================================================================

## A reversal shows the intermediate facing first; a quarter turn is instant.
func test_a_reversal_turns_through_an_intermediate_facing() -> void:
	var component := _component(PLAYER)
	component.update_facing(Vector2.RIGHT, false)
	component.advance(CharacterVisualComponent.TURN_SECONDS)
	component.update_facing(Vector2.LEFT, false)
	assert_eq(component.get_direction(), ProfileScript.Direction.LEFT,
		"the LOGICAL facing is LEFT at once")
	assert_eq(component.get_shown_direction(), ProfileScript.Direction.DOWN,
		"but LEFT<->RIGHT turns through the front, toward the viewer")
	component.advance(CharacterVisualComponent.TURN_SECONDS)
	assert_eq(component.get_shown_direction(), ProfileScript.Direction.LEFT,
		"and lands on LEFT after TURN_SECONDS")

	component.update_facing(Vector2.DOWN, false)
	assert_eq(component.get_shown_direction(), ProfileScript.Direction.DOWN,
		"a quarter turn is instant")
	component.update_facing(Vector2.UP, false)
	assert_eq(component.get_shown_direction(), ProfileScript.Direction.LEFT,
		"DOWN->UP turns through the side the body last showed (LEFT)")
	free_node(component)


## Mid-action a strike must face where it lands: no intermediate frame.
func test_turning_mid_action_is_instant() -> void:
	var component := _component(PLAYER)
	component.update_facing(Vector2.RIGHT, false)
	component.play_action(CharacterVisualComponent.ACTION_ATTACK)
	component.update_facing(Vector2.LEFT, false)
	assert_eq(component.get_shown_direction(), ProfileScript.Direction.LEFT,
		"a reversal during an action is shown at once")
	free_node(component)


## Hysteresis: a vector just past the 45° boundary keeps the current facing; a clear turn
## changes it. Without the band a creature chasing along a diagonal flips every frame.
func test_facing_has_hysteresis_on_diagonals() -> void:
	var component := _component(PLAYER)
	component.update_facing(Vector2.RIGHT, false)
	component.update_facing(Vector2.RIGHT.rotated(deg_to_rad(50.0)), false)
	assert_eq(component.get_direction(), ProfileScript.Direction.RIGHT,
		"50° off RIGHT is still RIGHT (inside the band)")
	component.update_facing(Vector2.RIGHT.rotated(deg_to_rad(40.0)), false)
	component.update_facing(Vector2.RIGHT.rotated(deg_to_rad(50.0)), false)
	assert_eq(component.get_direction(), ProfileScript.Direction.RIGHT,
		"wobbling across 45° does not flicker")
	component.update_facing(Vector2.RIGHT.rotated(deg_to_rad(62.0)), false)
	assert_eq(component.get_direction(), ProfileScript.Direction.DOWN,
		"a clear turn past the band does change the facing")
	free_node(component)


# === Idle variation ==========================================================

## Two creatures placed apart breathe out of phase; the same placement always gives the same
## phase (deterministic, M-8.2).
func test_idle_breaths_are_out_of_phase_and_deterministic() -> void:
	var phases := {}
	for x in [0.0, 37.0, 91.0, 143.0, 211.0]:
		var component := _component(WOLF, Vector2(x, 64.0))
		phases[component.get_column()] = true
		var again := _component(WOLF, Vector2(x, 64.0))
		assert_eq(again.get_column(), component.get_column(),
			"the same placement gives the same phase (x=%f)" % x)
		free_node(component)
		free_node(again)
	assert_true(phases.size() >= 3,
		"five wolves placed apart start on at least three different breaths (%d)"
			% phases.size())


# === Anchors =================================================================

## The striking palm is where the drawn frame puts it: on the facing side, further out at the
## strike than in the coil, mirrored between LEFT and RIGHT.
func test_the_palm_anchor_follows_the_drawn_strike() -> void:
	var component := _component(PLAYER)
	var profile := _profile(PLAYER)
	var frames := profile.frame_count_of(profile.attack_sheet)
	component.update_facing(Vector2.RIGHT, false)
	component.play_action(CharacterVisualComponent.ACTION_ATTACK)
	assert_eq(component.current_anim(), ProfileScript.ANIM_ATTACK, "the attack is showing")
	component.drive_action(1.0 / float(frames) + 0.01)  # frame 1: the coil
	var coil := component.anchor_point(ProfileScript.POINT_PALM)
	component.drive_action(3.0 / float(frames) + 0.01)  # frame 3: full extension
	var strike := component.anchor_point(ProfileScript.POINT_PALM)
	var core := component.anchor_point(ProfileScript.POINT_CORE)
	assert_true(strike.x > core.x + 6.0,
		"facing RIGHT, the extended palm is well right of the core (%s vs %s)"
			% [str(strike), str(core)])
	assert_true(strike.x > coil.x + 6.0,
		"the strike reaches further than the coil (%s vs %s)" % [str(strike), str(coil)])
	assert_true(strike.y < 0.0 and strike.y > -float(profile.frame_size.y),
		"the palm is on the body, between feet and crown (%s)" % str(strike))

	component.update_facing(Vector2.LEFT, false)
	var mirrored := component.anchor_point(ProfileScript.POINT_PALM)
	assert_eq(mirrored, Vector2(-strike.x, strike.y),
		"LEFT mirrors RIGHT exactly — anchors are pixel CENTRES (%s vs %s)"
			% [str(mirrored), str(strike)])
	free_node(component)


## The anchor follows the drawn body when a reaction displaces the sprite, and degrades to the
## fallback when the profile names no such point.
func test_anchors_follow_the_sprite_offset_and_degrade_cleanly() -> void:
	var component := _component(WOLF)
	var before := component.anchor_point(ProfileScript.POINT_CORE)
	component.set_sprite_offset(Vector2(3, -1))
	assert_eq(component.anchor_point(ProfileScript.POINT_CORE), before + Vector2(3, -1),
		"a recoil offset moves the anchor with the drawn body")
	assert_eq(component.sprite_offset(), Vector2(3, -1), "and is reported")
	component.set_sprite_offset(Vector2.ZERO)
	assert_false(component.has_anchor(&"tail_tip"), "an unnamed point is not claimed")
	assert_eq(component.anchor_point(&"tail_tip", Vector2(-9, -9)), Vector2(-9, -9),
		"and its lookup returns the caller's fallback")
	free_node(component)
