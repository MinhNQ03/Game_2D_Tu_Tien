extends TestCase
## Unit tests for the Phase-16 ALLY additions to the shared AI: the three `AiProfileData`
## fields (`follow_radius`, `home_arrival_radius`, `return_speed_scale`) and the one `AiBrain`
## transition they enable. The companion has no brain of its own — it is the enemy's brain with
## a home that moves — so what is tested here is exactly the difference, on plain scalars.

const AiProfileScript := preload("res://src/data/enemies/ai_profile_data.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")

const COMPANION_PATH := "res://data/pets/ai_pet_companion.tres"
const SKIRMISHER_PATH := "res://data/enemies/ai_frontier_skirmisher.tres"


func _profile(follow: float = 40.0) -> AiProfileData:
	var profile: AiProfileData = AiProfileScript.new()
	profile.id = &"ai_test_ally"
	profile.detect_radius = 100.0
	profile.lose_interest_radius = 200.0
	profile.leash_radius = 300.0
	profile.decision_interval = 0.2
	profile.alert_seconds = 0.3
	profile.recover_seconds = 0.6
	profile.idle_seconds = 5.0
	profile.patrol_seconds = 1.5
	profile.recover_distance = 70.0
	profile.follow_radius = follow
	profile.home_arrival_radius = 20.0
	profile.return_speed_scale = 1.0
	return profile


func _brain(profile: AiProfileData) -> AiBrain:
	var rng: RngService = RngServiceScript.new(7)
	var brain := AiBrain.new(profile, rng.stream(&"ally_ai"))
	brain.set_engage_distance(20.0)
	return brain


func _alone(home: float) -> Dictionary:
	return {"has_target": false, "target_distance": INF, "home_distance": home,
		"can_attack": true}


func test_the_shipped_profiles_are_valid_and_only_the_companion_follows() -> void:
	var companion := load(COMPANION_PATH) as AiProfileData
	var skirmisher := load(SKIRMISHER_PATH) as AiProfileData
	assert_true(companion.is_valid(), "the companion profile is valid")
	assert_true(companion.follow_radius > 0.0, "and follows")
	assert_true(skirmisher.is_valid(), "the wolf's profile is still valid")
	assert_eq(skirmisher.follow_radius, 0.0, "and does NOT follow: its behaviour is unchanged")
	assert_eq(skirmisher.effective_return_speed_scale(), skirmisher.patrol_speed_scale,
		"an unset return speed keeps the old walk-home pace")
	assert_eq(companion.effective_return_speed_scale(), companion.return_speed_scale,
		"a set one is used")


func test_follow_geometry_is_validated() -> void:
	assert_true(_profile().is_valid(), "the fixture is valid")
	var inside_arrival := _profile(15.0)
	assert_false(inside_arrival.is_valid(),
		"a follow radius inside the arrival radius would never settle: rejected")
	var beyond_leash := _profile(400.0)
	assert_false(beyond_leash.is_valid(), "a follow radius beyond the leash is rejected")
	var negative := _profile()
	negative.return_speed_scale = -1.0
	assert_false(negative.is_valid(), "a negative return speed is rejected")
	var no_arrival := _profile()
	no_arrival.home_arrival_radius = 0.0
	assert_false(no_arrival.is_valid(), "a zero arrival radius is rejected")


func test_an_idle_ally_returns_when_its_home_moves_away_and_settles_on_arrival() -> void:
	var brain := _brain(_profile())
	assert_eq(brain.decide(_alone(10.0), 0.2), AiBrain.Intent.HOLD, "beside its home it holds")
	assert_eq(brain.state(), AiBrain.State.IDLE, "idle")
	brain.decide(_alone(39.0), 0.2)
	assert_eq(brain.state(), AiBrain.State.IDLE, "inside the follow radius it stays idle")
	brain.decide(_alone(41.0), 0.2)
	assert_eq(brain.state(), AiBrain.State.RETURN, "beyond it, it goes to its home")
	brain.decide(_alone(25.0), 0.2)
	assert_eq(brain.state(), AiBrain.State.RETURN, "still walking outside the arrival radius")
	brain.decide(_alone(19.0), 0.2)
	assert_eq(brain.state(), AiBrain.State.IDLE, "inside the arrival radius it settles")


func test_a_non_following_brain_never_leaves_idle_for_distance_alone() -> void:
	var brain := _brain(_profile(0.0))
	brain.decide(_alone(250.0), 0.2)
	assert_eq(brain.state(), AiBrain.State.IDLE,
		"follow_radius 0 keeps the Phase-10 behaviour: distance from home alone moves nothing")
