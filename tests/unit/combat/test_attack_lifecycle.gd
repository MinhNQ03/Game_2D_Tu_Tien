extends TestCase
## Unit tests for the Phase-09 attack lifecycle (D-007, real-time action combat).
##
## Covers `AttackData` validation and the `AttackStateMachine` state/timing contract. All pure
## domain — no node, no tree, no physics frame — so every frame-timing question about combat is
## answered by an assertion instead of by watching the game.
##
## The timing cases are written as EXACT deltas, because the defects they guard against are all
## frame-timing defects: a hit landing during windup, a swing restartable mid-attack, and a hit
## window a long frame steps clean over.

const AttackDataScript := preload("res://src/data/combat/attack_data.gd")
const PLAYER_ATTACK_PATH := "res://data/combat/attack_player_basic.tres"


## A known-GOOD attack. Every negative case below differs from THIS in exactly one field and
## would otherwise be accepted (L-024/L-026), so a rejection can only be about that field.
func _attack() -> AttackData:
	var attack: AttackData = AttackDataScript.new()
	attack.id = &"attack_test"
	attack.windup_seconds = 0.10
	attack.active_seconds = 0.05
	attack.recovery_seconds = 0.20
	attack.reach_pixels = 24.0
	attack.arc_degrees = 120.0
	attack.power_multiplier = 1.0
	attack.critical_chance_percent = 0
	attack.critical_multiplier = 1.5
	return attack


# === AttackData =============================================================

## The baseline fixture must be ACCEPTED. Without this, every negative case below could be
## passing for the wrong reason — a fixture that is invalid for an unrelated field.
func test_the_baseline_attack_fixture_is_valid() -> void:
	assert_true(_attack().is_valid(), "the known-good attack fixture is accepted")


func test_an_attack_needs_an_id() -> void:
	var attack := _attack()
	attack.id = &""
	assert_false(attack.is_valid(), "an attack with no id is rejected")


## Every phase duration must be strictly positive, and each for its own reason: a zero windup
## is unreactable, a zero active window can be stepped over by one long frame, and a zero
## recovery makes attacking free (so there is nothing to time).
func test_every_lifecycle_duration_must_be_positive() -> void:
	for field in ["windup_seconds", "active_seconds", "recovery_seconds"]:
		var zero := _attack()
		zero.set(field, 0.0)
		assert_false(zero.is_valid(), "%s = 0 is rejected" % field)
		var negative := _attack()
		negative.set(field, -0.1)
		assert_false(negative.is_valid(), "%s < 0 is rejected" % field)


func test_geometry_and_scalars_are_range_checked() -> void:
	var no_reach := _attack()
	no_reach.reach_pixels = 0.0
	assert_false(no_reach.is_valid(), "an attack with no reach is rejected")

	var no_arc := _attack()
	no_arc.arc_degrees = 0.0
	assert_false(no_arc.is_valid(), "an attack with no arc is rejected")

	var over_arc := _attack()
	over_arc.arc_degrees = 361.0
	assert_false(over_arc.is_valid(), "an arc beyond a full circle is rejected")

	var no_power := _attack()
	no_power.power_multiplier = 0.0
	assert_false(no_power.is_valid(), "a zero power multiplier is rejected")

	var bad_chance := _attack()
	bad_chance.critical_chance_percent = 101
	assert_false(bad_chance.is_valid(), "a crit chance above 100% is rejected")

	# A "crit" that REDUCES damage is a content bug. Allowing it silently would make a
	# balance mistake invisible, which is the whole reason this bound exists.
	var weak_crit := _attack()
	weak_crit.critical_multiplier = 0.9
	assert_false(weak_crit.is_valid(), "a critical multiplier below 1.0 is rejected")


func test_total_seconds_is_the_sum_of_the_three_phases() -> void:
	var attack := _attack()
	assert_true(absf(attack.total_seconds() - 0.35) < 0.0001,
		"a full cycle costs windup + active + recovery (got %.4f)" % attack.total_seconds())


## The SHIPPED attack resource must be valid and must be loadable. An authored `.tres` that
## fails validation would leave the player unable to attack, and nothing else would notice:
## the state machine simply refuses to arm (L-029 — an optional-looking path that is the only
## path that ever runs).
func test_the_shipped_player_attack_resource_is_valid() -> void:
	assert_true(ResourceLoader.exists(PLAYER_ATTACK_PATH),
		"the authored player attack exists at %s" % PLAYER_ATTACK_PATH)
	var attack := load(PLAYER_ATTACK_PATH) as AttackData
	assert_not_null(attack, "it loads as an AttackData")
	if attack == null:
		return
	assert_true(attack.is_valid(), "and the shipped values pass validation")
	assert_eq(attack.id, &"attack_player_basic", "with its documented id")


# === AttackStateMachine: states and transitions =============================

func test_a_fresh_machine_is_ready_and_armed() -> void:
	var fsm := AttackStateMachine.new(_attack())
	assert_true(fsm.is_armed(), "a valid attack arms the machine")
	assert_eq(fsm.state(), AttackStateMachine.State.READY, "it starts READY")
	assert_true(fsm.can_begin(), "and will accept an attack")
	assert_eq(fsm.state_name(), "READY", "the state has a readable name for assertions")


## An INVALID attack must leave the machine unarmed rather than armed with nonsense timings.
## An armed machine with a zero-length hit window would accept swings that can never land —
## a bug that looks like "my attacks do nothing" and has no error attached to it.
func test_an_invalid_attack_leaves_the_machine_unarmed() -> void:
	var broken := _attack()
	broken.active_seconds = 0.0
	var fsm := AttackStateMachine.new(broken)
	assert_false(fsm.is_armed(), "an invalid AttackData does not arm the machine")
	assert_false(fsm.can_begin(), "so it refuses to begin an attack")
	assert_false(fsm.try_begin(), "try_begin() reports the refusal")
	assert_eq(fsm.state(), AttackStateMachine.State.READY, "and it stays READY forever")


func test_a_machine_with_no_attack_is_unarmed() -> void:
	var fsm := AttackStateMachine.new()
	assert_false(fsm.is_armed(), "a machine built with no attack is unarmed")
	assert_eq(fsm.advance(1.0), AttackStateMachine.State.READY,
		"advancing an unarmed machine does nothing")


## The documented lifecycle, walked one phase at a time: READY → WINDUP → ACTIVE → RECOVERY
## → READY. Deltas are chosen to land just inside each phase, then to cross its boundary.
func test_the_lifecycle_runs_ready_windup_active_recovery_ready() -> void:
	var fsm := AttackStateMachine.new(_attack())
	assert_true(fsm.try_begin(), "an attack starts from READY")
	assert_eq(fsm.state(), AttackStateMachine.State.WINDUP, "beginning enters WINDUP")

	# Mid-windup: still WINDUP, and NOTHING may be hittable yet.
	fsm.advance(0.05)
	assert_eq(fsm.state(), AttackStateMachine.State.WINDUP, "half-way through windup")
	assert_false(fsm.has_pending_hit_window(),
		"no hit window exists during WINDUP — a hit landing here is the commitment bug")

	# Crossing into the hit window.
	fsm.advance(0.05)
	assert_eq(fsm.state(), AttackStateMachine.State.ACTIVE, "windup ends in ACTIVE")
	assert_true(fsm.has_pending_hit_window(), "entering ACTIVE opens the hit window")

	fsm.advance(0.05)
	assert_eq(fsm.state(), AttackStateMachine.State.RECOVERY, "the window closes into RECOVERY")

	fsm.advance(0.20)
	assert_eq(fsm.state(), AttackStateMachine.State.READY, "recovery ends back at READY")
	assert_eq(fsm.completed_count(), 1, "and the attack counts as completed")
	assert_true(fsm.can_begin(), "so another attack may start")


## COMMITMENT: an attack in flight cannot be restarted. Without this, recovery has no cost and
## an action model has nothing to time — a player mashing the key would attack continuously.
func test_an_attack_in_flight_cannot_be_restarted() -> void:
	var fsm := AttackStateMachine.new(_attack())
	assert_true(fsm.try_begin(), "the first attack starts")
	for phase in ["WINDUP", "ACTIVE", "RECOVERY"]:
		assert_false(fsm.try_begin(),
			"a second attack is refused during %s (got %s)" % [phase, fsm.state_name()])
		assert_false(fsm.can_begin(), "and can_begin() agrees during %s" % phase)
		fsm.advance(fsm.time_remaining() + 0.0001)
	assert_eq(fsm.state(), AttackStateMachine.State.READY, "after a full cycle it is READY")
	assert_true(fsm.try_begin(), "and only then does a new attack start")


# === AttackStateMachine: frame-timing contract ==============================

## A single long frame must NOT skip the hit window.
##
## This is the regression for the most expensive class of bug in an action model: a frame
## spike swallowing a hit the player already paid windup for. A naive implementation that
## compares total elapsed time against thresholds drops the window entirely here, and the
## symptom — "sometimes my attack does nothing" — is nearly impossible to reproduce.
func test_one_huge_delta_still_opens_the_hit_window() -> void:
	var fsm := AttackStateMachine.new(_attack())
	fsm.try_begin()
	var ended := fsm.advance(10.0)
	assert_eq(ended, AttackStateMachine.State.READY,
		"a 10-second frame finishes the whole cycle")
	assert_true(fsm.has_pending_hit_window(),
		"and the hit window it passed THROUGH is still pending, not lost")
	assert_true(fsm.consume_hit_window(), "so the caller can still resolve that swing")
	assert_eq(fsm.completed_count(), 1, "the attack completed exactly once")


## The hit window is an EDGE: one swing resolves one hit pass, however the frames fell.
## Polling `state() == ACTIVE` instead would resolve the swing once per frame the window is
## open, which makes damage a function of frame rate.
func test_the_hit_window_is_consumed_exactly_once_per_attack() -> void:
	var fsm := AttackStateMachine.new(_attack())
	fsm.try_begin()
	fsm.advance(0.10)  # into ACTIVE
	assert_eq(fsm.state(), AttackStateMachine.State.ACTIVE, "the window is open")
	assert_true(fsm.consume_hit_window(), "the first consume takes the window")
	assert_false(fsm.consume_hit_window(), "a second consume in the same swing gets nothing")
	# Stay in ACTIVE across more frames: still nothing, because the swing already resolved.
	fsm.advance(0.01)
	assert_eq(fsm.state(), AttackStateMachine.State.ACTIVE, "still inside the window")
	assert_false(fsm.consume_hit_window(),
		"a longer hit window does not mean more hits — that would make frame rate damage")


## Many tiny deltas must produce the same result as a few large ones: same number of hit
## windows, same completion count. If they differ, damage depends on frame rate.
func test_frame_rate_does_not_change_how_many_hits_a_swing_produces() -> void:
	var windows_at_240 := _count_windows_over(_attack(), 1.0 / 240.0, 3)
	var windows_at_30 := _count_windows_over(_attack(), 1.0 / 30.0, 3)
	var windows_in_one_frame := _count_windows_over(_attack(), 10.0, 3)
	assert_eq(windows_at_240, 3, "three swings at 240fps produce three hit windows")
	assert_eq(windows_at_30, windows_at_240,
		"30fps produces the same count as 240fps (got %d vs %d)"
			% [windows_at_30, windows_at_240])
	assert_eq(windows_in_one_frame, windows_at_240,
		"and so does one absurdly long frame per swing (got %d)" % windows_in_one_frame)


## Drive `swings` complete attacks at a fixed `delta`, counting consumed hit windows.
##
## It runs until every swing has been started AND the machine is back at READY — not merely
## until the last swing was started. Stopping at "started == swings" cuts the final swing off
## mid-flight and under-counts by one, which looks exactly like the frame-rate bug this helper
## exists to detect.
func _count_windows_over(attack: AttackData, delta: float, swings: int) -> int:
	var fsm := AttackStateMachine.new(attack)
	var windows := 0
	var started := 0
	# Bounded: enough iterations for `swings` full cycles even at the smallest delta tested,
	# so a logic error here fails the assertion instead of hanging the runner (L-033).
	var guard := int(ceil(attack.total_seconds() / delta)) * (swings + 1) + swings + 16
	while guard > 0:
		guard -= 1
		if started >= swings and fsm.state() == AttackStateMachine.State.READY:
			break
		if started < swings and fsm.can_begin():
			fsm.try_begin()
			started += 1
		fsm.advance(delta)
		if fsm.consume_hit_window():
			windows += 1
	return windows


## `cancel()` drops an unconsumed hit window on purpose. A window that outlived its swing
## would land after the attacker died or after a scene change — a phantom hit nobody can
## reproduce.
func test_cancel_returns_to_ready_and_drops_a_pending_hit_window() -> void:
	var fsm := AttackStateMachine.new(_attack())
	fsm.try_begin()
	fsm.advance(0.10)
	assert_true(fsm.has_pending_hit_window(), "the window is pending before cancel")
	fsm.cancel()
	assert_eq(fsm.state(), AttackStateMachine.State.READY, "cancel returns to READY")
	assert_false(fsm.has_pending_hit_window(), "and the pending window is dropped")
	assert_false(fsm.consume_hit_window(), "so a cancelled swing resolves nothing")
	assert_true(fsm.can_begin(), "the attacker may attack again immediately")
