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
