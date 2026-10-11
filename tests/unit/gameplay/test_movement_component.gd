extends TestCase
## Unit tests for MovementComponent's PURE velocity math
## (src/gameplay/components/movement_component.gd `resolve_velocity`). No physics step
## needed here — the collision-aware `apply_intent` is exercised by the integration test.
## High-risk area (movement). Deterministic.

const MovementScript := preload("res://src/gameplay/components/movement_component.gd")

const SPEED := 200.0
const EPS := 0.001


func test_zero_intent_is_zero_velocity() -> void:
	assert_eq(MovementScript.resolve_velocity(Vector2.ZERO, SPEED), Vector2.ZERO,
		"no intent => no movement")


func test_cardinal_intent_full_speed() -> void:
	var v := MovementScript.resolve_velocity(Vector2.RIGHT, SPEED)
	assert_true(v.is_equal_approx(Vector2(SPEED, 0.0)), "cardinal moves at full speed")
	assert_true(absf(v.length() - SPEED) < EPS, "cardinal magnitude == speed")


func test_diagonal_not_faster_than_cardinal() -> void:
	# Raw diagonal intent (1,1) would be length ~1.414; it must be normalized so the
	# resulting speed equals SPEED, not SPEED*1.414.
	var diag := MovementScript.resolve_velocity(Vector2(1, 1), SPEED)
	assert_true(absf(diag.length() - SPEED) < EPS,
		"diagonal magnitude == speed (not faster); got %f" % diag.length())


func test_all_eight_directions_same_speed() -> void:
	var dirs := [
		Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
		Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1),
	]
	for d in dirs:
		var v := MovementScript.resolve_velocity(d, SPEED)
		assert_true(absf(v.length() - SPEED) < EPS,
			"dir %s moves at speed; got %f" % [str(d), v.length()])


func test_speed_scales_velocity() -> void:
	var slow := MovementScript.resolve_velocity(Vector2.UP, 50.0)
	assert_true(absf(slow.length() - 50.0) < EPS, "velocity magnitude follows speed")


func test_zero_speed_is_zero_velocity() -> void:
	assert_eq(MovementScript.resolve_velocity(Vector2.RIGHT, 0.0), Vector2.ZERO,
		"zero speed => no movement (deterministic)")


func test_negative_speed_is_zero_velocity() -> void:
	assert_eq(MovementScript.resolve_velocity(Vector2.RIGHT, -100.0), Vector2.ZERO,
		"negative speed => no movement, never reversed garbage")


# --- Pursuit: which way round (Q19-04) ---------------------------------------
#
# The two pure rules behind `apply_pursuit`. Pinned with LITERAL directions (screen space: +x
# right, +y down), because "the default hand" asserted against its own constant pins nothing.

func test_following_a_surface_is_a_quarter_turn_of_its_normal() -> void:
	# A body west of a trunk meets its west face: the normal points back at the body.
	assert_eq(MovementScript.detour_heading(Vector2.LEFT, 1), Vector2.UP,
		"west face, hand +1: walk up it")
	assert_eq(MovementScript.detour_heading(Vector2.LEFT, -1), Vector2.DOWN,
		"west face, hand -1: walk down it")
	# ONE hand keeps the obstacle on one side all the way round: up the west face, east along
	# the top, down the east face, west along the bottom.
	assert_eq(MovementScript.detour_heading(Vector2.UP, 1), Vector2.RIGHT, "then along the top")
	assert_eq(MovementScript.detour_heading(Vector2.RIGHT, 1), Vector2.DOWN, "down the far face")
	assert_eq(MovementScript.detour_heading(Vector2.DOWN, 1), Vector2.LEFT, "and back underneath")


func test_the_hand_is_the_side_the_target_lies_toward() -> void:
	var face := Vector2.LEFT  # the west face of something, met while heading east
	assert_eq(MovementScript.choose_hand(face, Vector2(1.0, -0.2).normalized()), 1,
		"target a little above: go up (hand +1)")
	assert_eq(MovementScript.choose_hand(face, Vector2(1.0, 0.2).normalized()), -1,
		"target a little below: go down (hand -1)")


func test_a_head_on_tie_takes_the_same_hand_every_time() -> void:
	for face: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		assert_eq(MovementScript.choose_hand(face, -face), 1,
			"dead ahead into a face with normal %s: hand +1, no draw" % face)
	assert_eq(MovementScript.DETOUR_DEFAULT_HAND, 1, "which is the documented default")
	assert_eq(MovementScript.choose_hand(Vector2.LEFT, Vector2(1.0, 0.005).normalized()), 1,
		"and a lean too small to be a preference is still a tie")
