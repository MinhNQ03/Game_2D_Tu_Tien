extends TestCase
## Unit tests for `AiBrain` — the Phase-10 decision machine (states, transitions, determinism).
##
## Pure domain: plain scalars, no node, no tree, no physics frame. That is the whole reason the
## brain takes a perception of numbers and returns an intent KIND — "at 300px it gives up" is
## an assertion here rather than a scene somebody has to watch.

const AiProfileScript := preload("res://src/data/enemies/ai_profile_data.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")

const WORLD_SEED := 20261005


## A known-GOOD profile. Every negative case differs from THIS in exactly one field and would
## otherwise be accepted (L-024), so a rejection can only be about that field.
func _profile() -> AiProfileData:
	var profile: AiProfileData = AiProfileScript.new()
	profile.id = &"ai_test"
	profile.detect_radius = 100.0
	profile.lose_interest_radius = 200.0
	profile.leash_radius = 300.0
	profile.decision_interval = 0.2
	profile.chase_speed_scale = 1.0
	profile.patrol_speed_scale = 0.5
	profile.alert_seconds = 0.3
	profile.recover_seconds = 0.6
	profile.idle_seconds = 1.0
	profile.patrol_seconds = 1.5
	profile.recover_distance = 70.0
	return profile


func _brain(profile: AiProfileData = null) -> AiBrain:
	var rng: RngService = RngServiceScript.new(WORLD_SEED)
	var brain := AiBrain.new(
		profile if profile != null else _profile(), rng.stream(&"enemy_ai"))
	brain.set_engage_distance(24.0)
	return brain


## Perception in the shape the brain consumes.
func _see(distance: float, home: float = 0.0, can_attack: bool = true) -> Dictionary:
	return {
		"has_target": distance < INF,
		"target_distance": distance,
		"home_distance": home,
		"can_attack": can_attack,
	}


func _blind(home: float = 0.0) -> Dictionary:
	return {
		"has_target": false, "target_distance": INF,
		"home_distance": home, "can_attack": true,
	}


# === AiProfileData ==========================================================

func test_the_baseline_profile_fixture_is_valid() -> void:
	assert_true(_profile().is_valid(), "the known-good profile is accepted")


## The notice/forget radii must form a HYSTERESIS BAND. Equal radii make the creature flicker
## between noticing and forgetting while the player stands at exactly that distance — a
## visible twitch that looks like a bug and is invisible to any other test.
func test_lose_interest_must_exceed_detect_radius() -> void:
	var equal := _profile()
	equal.lose_interest_radius = equal.detect_radius
	assert_false(equal.is_valid(), "equal radii are rejected (no hysteresis band)")
	var inverted := _profile()
	inverted.lose_interest_radius = 10.0
	assert_false(inverted.is_valid(), "an inverted band is rejected")


func test_a_zero_decision_interval_is_rejected() -> void:
	var profile := _profile()
	profile.decision_interval = 0.0
	assert_false(profile.is_valid(),
		"a zero interval would mean the AI thinks every frame, which Phase 10 forbids")


func test_every_state_timing_must_be_positive() -> void:
	for field in ["alert_seconds", "recover_seconds", "idle_seconds", "patrol_seconds"]:
		var profile := _profile()
		profile.set(field, 0.0)
		assert_false(profile.is_valid(), "%s = 0 is rejected" % field)


# === Arming =================================================================

func test_a_brain_without_a_stream_is_unarmed() -> void:
	var brain := AiBrain.new(_profile(), null)
	assert_false(brain.is_armed(), "no seeded stream means unarmed (no global rand*)")
	assert_eq(brain.decide(_see(10.0), 1.0), AiBrain.Intent.HOLD,
		"and it holds rather than acting on an unseeded guess")


func test_a_brain_with_an_invalid_profile_is_unarmed() -> void:
	var broken := _profile()
	broken.detect_radius = 0.0
	var rng: RngService = RngServiceScript.new(WORLD_SEED)
	var brain := AiBrain.new(broken, rng.stream(&"enemy_ai"))
	assert_false(brain.is_armed(), "an invalid profile does not arm the brain")
	assert_eq(brain.state(), AiBrain.State.IDLE, "it stays IDLE forever")


func test_a_malformed_perception_holds_loudly_rather_than_guessing() -> void:
	var brain := _brain()
	assert_eq(brain.decide({"has_target": true}, 0.2), AiBrain.Intent.HOLD,
		"a perception missing keys produces HOLD, not an invented decision")


# === States and transitions =================================================

func test_it_starts_idle_and_wanders_when_nothing_happens() -> void:
	var brain := _brain()
	assert_eq(brain.state(), AiBrain.State.IDLE, "a fresh brain is IDLE")
	assert_eq(brain.decide(_blind(), 0.2), AiBrain.Intent.HOLD, "and holds while idling")
	# Past `idle_seconds` it should start a patrol leg.
	var intent := AiBrain.Intent.HOLD
	for _i in 10:
		intent = brain.decide(_blind(), 0.2)
		if brain.state() == AiBrain.State.PATROL:
			break
	assert_eq(brain.state(), AiBrain.State.PATROL, "it eventually patrols")
	assert_eq(intent, AiBrain.Intent.WANDER, "and the patrol intent is WANDER")


## The documented chain, walked one transition at a time:
## IDLE → ALERT → CHASE → ATTACK → RECOVER → CHASE.
func test_the_encounter_chain_runs_alert_chase_attack_recover() -> void:
	var brain := _brain()
	# Seeing a target inside detect range interrupts idling and ALERTS.
	assert_eq(brain.decide(_see(80.0), 0.2), AiBrain.Intent.HOLD,
		"noticing a target holds position — the ALERT pause IS the telegraph")
	assert_eq(brain.state(), AiBrain.State.ALERT, "it is ALERT")

	# The pause lasts `alert_seconds`, then it closes.
	brain.decide(_see(80.0), 0.2)
	assert_eq(brain.state(), AiBrain.State.ALERT, "still alert mid-pause")
	assert_eq(brain.decide(_see(80.0), 0.2), AiBrain.Intent.APPROACH,
		"after the pause it closes")
	assert_eq(brain.state(), AiBrain.State.CHASE, "it is CHASING")

	# Still out of reach: keep approaching.
	assert_eq(brain.decide(_see(60.0), 0.2), AiBrain.Intent.APPROACH, "still closing")

	# In reach and able to swing: ATTACK.
	assert_eq(brain.decide(_see(20.0), 0.2), AiBrain.Intent.SWING, "in reach, it swings")
	assert_eq(brain.state(), AiBrain.State.ATTACK, "it is ATTACKING")

	# ATTACK is a one-tick commitment: the next decision moves to RECOVER. It does NOT wait
	# for the swing to finish, because `AttackStateMachine` owns that timing — a second copy
	# of the lifecycle here could disagree with the real one.
	var after := brain.decide(_see(20.0), 0.2)
	assert_eq(brain.state(), AiBrain.State.RECOVER, "it recovers immediately after swinging")
	assert_eq(brain.swings(), 1, "one swing was counted")
	# The tick that LEAVES attack holds position: that one decision interval is the bite's
	# follow-through, and it happens while `AttackStateMachine` is still in ACTIVE/RECOVERY
	# anyway. Backing off begins on the next decision.
	assert_eq(after, AiBrain.Intent.HOLD, "the transition tick holds — the follow-through")
	assert_eq(brain.decide(_see(20.0), 0.2), AiBrain.Intent.BACK_OFF,
		"then it backs off while closer than recover_distance — the archetype's signature")
	# Beyond that distance it waits instead of retreating forever, so it disengages and
	# re-closes rather than fleeing.
	assert_eq(brain.decide(_see(90.0), 0.2), AiBrain.Intent.HOLD,
		"past recover_distance it waits rather than retreating further")

	# Past `recover_seconds` it re-engages, which is what punishes standing still.
	for _i in 5:
		brain.decide(_see(20.0), 0.2)
		if brain.state() == AiBrain.State.CHASE:
			break
	assert_eq(brain.state(), AiBrain.State.CHASE, "it comes back for another pass")


## It must NOT swing while already mid-swing. The brain asks `can_attack`, which the component
## answers from `AttackStateMachine` — this is how the commitment rule is respected once
## instead of duplicated.
func test_it_does_not_request_a_swing_while_already_swinging() -> void:
	var brain := _brain()
	_reach_chase(brain)
	assert_eq(brain.decide(_see(20.0, 0.0, false), 0.2), AiBrain.Intent.APPROACH,
		"in reach but mid-swing, it keeps closing rather than queuing a second swing")
	assert_eq(brain.state(), AiBrain.State.CHASE, "and stays in CHASE")


func test_losing_a_target_sends_it_home() -> void:
	var brain := _brain()
	_reach_chase(brain)
	assert_eq(brain.decide(_blind(50.0), 0.2), AiBrain.Intent.RETURN_HOME,
		"a vanished target sends it home")
	assert_eq(brain.state(), AiBrain.State.RETURN, "it is RETURNING")


## Beyond `lose_interest_radius` it gives up — the far edge of the hysteresis band.
func test_it_gives_up_beyond_the_lose_interest_radius() -> void:
	var brain := _brain()
	_reach_chase(brain)
	assert_eq(brain.decide(_see(150.0), 0.2), AiBrain.Intent.APPROACH,
		"inside the band it keeps chasing even though it is past detect range")
	assert_eq(brain.decide(_see(250.0), 0.2), AiBrain.Intent.RETURN_HOME,
		"past lose_interest it gives up")


## The LEASH outranks everything, including a visible target. Without that precedence a player
## who keeps backing away can walk one creature across the whole map and the encounter stops
## being local.
func test_the_leash_outranks_a_visible_target() -> void:
	var brain := _brain()
	_reach_chase(brain)
	assert_eq(brain.decide(_see(20.0, 400.0), 0.2), AiBrain.Intent.RETURN_HOME,
		"strayed past the leash, it goes home even with the target in reach")
	assert_eq(brain.state(), AiBrain.State.RETURN, "it is RETURNING")


## While returning it may re-acquire — but only once back INSIDE the leash, or a player
## standing just outside it holds the creature in a permanent turn-around at the boundary.
func test_it_only_reacquires_once_back_inside_the_leash() -> void:
	var brain := _brain()
	_reach_chase(brain)
	brain.decide(_see(20.0, 400.0), 0.2)
	assert_eq(brain.state(), AiBrain.State.RETURN, "returning")
	brain.decide(_see(20.0, 400.0), 0.2)
	assert_eq(brain.state(), AiBrain.State.RETURN,
		"a target in reach does NOT interrupt the return while still outside the leash")
	brain.decide(_see(20.0, 100.0), 0.2)
	assert_eq(brain.state(), AiBrain.State.ALERT, "back inside the leash, it re-acquires")


func test_arriving_home_returns_it_to_idle() -> void:
	var brain := _brain()
	_reach_chase(brain)
	brain.decide(_blind(50.0), 0.2)
	assert_eq(brain.state(), AiBrain.State.RETURN, "returning")
	assert_eq(brain.decide(_blind(1.0), 0.2), AiBrain.Intent.HOLD, "arrived")
	assert_eq(brain.state(), AiBrain.State.IDLE, "and it is IDLE again")


func test_reset_returns_to_idle_from_any_state() -> void:
	var brain := _brain()
	_reach_chase(brain)
	brain.reset()
	assert_eq(brain.state(), AiBrain.State.IDLE, "reset lands in IDLE")
	assert_eq(brain.time_in_state(), 0.0, "and clears the state timer")


# === Determinism ============================================================

## THE determinism contract: same seed → same patrol headings. This is what makes an encounter
## reproducible, and it is why there is no `randf()` in the brain.
func test_the_same_seed_produces_the_same_patrol_headings() -> void:
	var first := _patrol_headings(WORLD_SEED, 6)
	var second := _patrol_headings(WORLD_SEED, 6)
	assert_eq(str(first), str(second), "two brains on one seed wander identically")
	var other := _patrol_headings(WORLD_SEED + 1, 6)
	assert_ne(str(other), str(first),
		"a different seed wanders differently (the seed actually matters)")
	# And the headings must VARY, or "deterministic" would be satisfied by a constant and
	# every assertion above would pass for the wrong reason.
	var distinct := {}
	for angle in first:
		distinct[angle] = true
	assert_true(distinct.size() >= 2,
		"the headings differ from each other, got %s" % str(first))


## Collect `count` patrol headings by cycling IDLE → PATROL repeatedly.
func _patrol_headings(world_seed: int, count: int) -> Array:
	var rng: RngService = RngServiceScript.new(world_seed)
	var brain := AiBrain.new(_profile(), rng.stream(&"enemy_ai"))
	brain.set_engage_distance(24.0)
	var out: Array = []
	var guard := count * 40
	while out.size() < count and guard > 0:
		guard -= 1
		brain.decide(_blind(), 0.2)
		if brain.state() == AiBrain.State.PATROL and brain.time_in_state() == 0.0:
			out.append(snappedf(brain.patrol_angle(), 0.0001))
	return out


## Drive a brain from IDLE into CHASE, so a test can start from the interesting state.
func _reach_chase(brain: AiBrain) -> void:
	brain.decide(_see(80.0), 0.2)   # -> ALERT
	brain.decide(_see(80.0), 0.2)
	brain.decide(_see(80.0), 0.2)   # -> CHASE
