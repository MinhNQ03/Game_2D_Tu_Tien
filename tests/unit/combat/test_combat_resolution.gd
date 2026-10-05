extends TestCase
## Unit tests for Phase-09 hit RESOLUTION: `DamageRules` (the formula) and `CombatService`
## (facing, reach, crit roll, per-target filtering).
##
## Pure domain: plain vectors and dictionaries, no node, no physics frame. That is deliberate —
## in the headless `-s` runner an Area2D overlap does not fire reliably (L-016), so if the
## geometry rules lived in the component that owns the Area2D they could not be tested at all.

const AttackDataScript := preload("res://src/data/combat/attack_data.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")

const WORLD_SEED := 20261005


func _attack(crit_percent: int = 0, arc: float = 120.0, reach: float = 24.0) -> AttackData:
	var attack: AttackData = AttackDataScript.new()
	attack.id = &"attack_test"
	attack.windup_seconds = 0.1
	attack.active_seconds = 0.05
	attack.recovery_seconds = 0.2
	attack.reach_pixels = reach
	attack.arc_degrees = arc
	attack.power_multiplier = 1.0
	attack.critical_chance_percent = crit_percent
	attack.critical_multiplier = 2.0
	return attack


## A service bound to the real seeded COMBAT stream, built the way the runtime builds it.
func _service(world_seed: int = WORLD_SEED) -> CombatService:
	var rng: RngService = RngServiceScript.new(world_seed)
	return CombatService.new(rng.stream(RngService.STREAM_COMBAT))


# === DamageRules: the formula ===============================================

## The Phase-02 two-argument behaviour must be UNCHANGED. Phase 09 added two defaulted
## parameters, and a default that shifted the existing numbers would silently rebalance every
## existing hit and every existing test.
func test_the_two_argument_formula_is_unchanged_by_the_phase_09_parameters() -> void:
	assert_eq(DamageRules.compute_hit(20, 5), DamageRules.compute_hit(20, 5, 1.0, 1.0),
		"an unscaled, non-crit hit equals the original two-argument result")
	# 20 * (100 / 105) = 19.05 -> 19
	assert_eq(DamageRules.compute_hit(20, 5), 19, "the documented defense curve still holds")
	assert_eq(DamageRules.compute_hit(0, 0), DamageRules.MIN_DAMAGE,
		"a landed hit always subtracts at least MIN_DAMAGE")


func test_power_and_crit_multiply_into_the_formula() -> void:
	var plain := DamageRules.compute_hit(100, 0)
	assert_eq(plain, 100, "no defense means no mitigation")
	assert_eq(DamageRules.compute_hit(100, 0, 1.5), 150, "power scales the hit")
	assert_eq(DamageRules.compute_hit(100, 0, 1.0, 2.0), 200, "a crit scales the hit")
	assert_eq(DamageRules.compute_hit(100, 0, 1.5, 2.0), 300, "both scale together")


## Defensive at the boundary: a mis-authored multiplier must not be able to ZERO a hit that
## landed. Degrading to 1.0 keeps the "a hit always hurts" invariant that `MIN_DAMAGE` states.
func test_a_non_positive_multiplier_degrades_to_unscaled_rather_than_zeroing_a_hit() -> void:
	assert_eq(DamageRules.compute_hit(100, 0, 0.0), 100,
		"a zero power multiplier is treated as unscaled, not as no damage")
	assert_eq(DamageRules.compute_hit(100, 0, -2.0), 100, "and so is a negative one")
	assert_eq(DamageRules.compute_hit(100, 0, 1.0, 0.0), 100,
		"a zero crit multiplier is treated as no crit")
	assert_eq(DamageRules.compute_hit(-5, -5), DamageRules.MIN_DAMAGE,
		"negative stats are clamped to 0, not propagated")


# === CombatService: construction ============================================

## A service with no seeded stream must be UNUSABLE, not silently unseeded. An unreproducible
## combat is worse than no combat: the failure only shows up later, as a desynced save or a
## test that passes once.
func test_a_service_without_a_seeded_stream_is_unusable() -> void:
	var service := CombatService.new()
	assert_false(service.is_ready(), "no stream means the service is not ready")
	var results := service.resolve_hit(
		Vector2.ZERO, Vector2.RIGHT, 20, _attack(),
		[CombatService.make_target(&"t", Vector2(10, 0), 0, false)])
	assert_eq(results.size(), 0, "and it resolves nothing at all")


func test_a_service_built_from_the_rng_service_is_ready() -> void:
	assert_true(_service().is_ready(), "the seeded combat stream makes the service usable")
	assert_eq(String(RngService.STREAM_COMBAT), "combat",
		"the combat stream is named, with a real consumer (no speculative constant)")


# === CombatService: reach and facing ========================================

func test_a_target_inside_reach_and_arc_is_hit() -> void:
	var results := _service().resolve_hit(
		Vector2.ZERO, Vector2.RIGHT, 20, _attack(),
		[CombatService.make_target(&"dummy", Vector2(10, 0), 5, false)])
	assert_eq(results.size(), 1, "the target in front and in range is hit")
	if results.is_empty():
		return
	assert_eq(results[0]["target_id"], &"dummy", "the result names the target it hit")
	assert_eq(results[0]["damage"], 19, "and carries the formula's damage")


func test_a_target_beyond_reach_is_not_hit() -> void:
	var results := _service().resolve_hit(
		Vector2.ZERO, Vector2.RIGHT, 20, _attack(0, 120.0, 24.0),
		[CombatService.make_target(&"far", Vector2(25, 0), 0, false)])
	assert_eq(results.size(), 0, "one pixel beyond reach is a miss, not a hit")


## FACING must matter — that is the point of an action model. A target directly behind the
## attacker is outside a 120-degree arc and must not be hit.
func test_a_target_behind_the_attacker_is_not_hit() -> void:
	var service := _service()
	var behind := [CombatService.make_target(&"behind", Vector2(-10, 0), 0, false)]
	assert_eq(service.resolve_hit(Vector2.ZERO, Vector2.RIGHT, 20, _attack(), behind).size(), 0,
		"a target behind the attacker is outside the arc")
	# Turning around hits the same target: the only thing that changed is facing.
	assert_eq(service.resolve_hit(Vector2.ZERO, Vector2.LEFT, 20, _attack(), behind).size(), 1,
		"and facing it makes the same target hittable")


## A full 360-degree arc hits regardless of direction. This is what proves the arc test is
## actually driven by the authored data rather than hard-coded to a half-plane.
func test_a_full_circle_arc_hits_in_every_direction() -> void:
	var service := _service()
	var attack := _attack(0, 360.0)
	for offset in [Vector2(10, 0), Vector2(-10, 0), Vector2(0, 10), Vector2(0, -10)]:
		var results := service.resolve_hit(Vector2.ZERO, Vector2.RIGHT, 20, attack,
			[CombatService.make_target(&"ring", offset, 0, false)])
		assert_eq(results.size(), 1, "a 360-degree arc hits at offset %s" % str(offset))


## A target exactly ON the attacker has no direction, so the arc cannot judge it. It counts as
## hit: it is unambiguously within reach, and whiffing point-blank reads as a broken attack.
func test_a_target_exactly_on_the_attacker_is_hit() -> void:
	var results := _service().resolve_hit(
		Vector2.ZERO, Vector2.RIGHT, 20, _attack(),
		[CombatService.make_target(&"overlap", Vector2.ZERO, 0, false)])
	assert_eq(results.size(), 1, "a point-blank target is hit rather than whiffed")


## A zero facing has no arc, so every arc test would be meaningless. Refusing is better than
## picking a direction: a swing in an arbitrary direction is a hit the player did not aim.
func test_a_zero_facing_resolves_nothing() -> void:
	var results := _service().resolve_hit(
		Vector2.ZERO, Vector2.ZERO, 20, _attack(),
		[CombatService.make_target(&"t", Vector2(5, 0), 0, false)])
	assert_eq(results.size(), 0, "a swing with no facing resolves nothing")


func test_an_invalid_attack_resolves_nothing() -> void:
	var broken := _attack()
	broken.reach_pixels = 0.0
	var results := _service().resolve_hit(
		Vector2.ZERO, Vector2.RIGHT, 20, broken,
		[CombatService.make_target(&"t", Vector2(1, 0), 0, false)])
	assert_eq(results.size(), 0, "an invalid AttackData resolves nothing")


func test_a_dead_target_is_skipped() -> void:
	var results := _service().resolve_hit(
		Vector2.ZERO, Vector2.RIGHT, 20, _attack(),
		[CombatService.make_target(&"corpse", Vector2(10, 0), 0, true)])
	assert_eq(results.size(), 0, "a corpse is not a target")


func test_each_hit_target_appears_exactly_once() -> void:
	var results := _service().resolve_hit(
		Vector2.ZERO, Vector2.RIGHT, 20, _attack(0, 360.0),
		[
			CombatService.make_target(&"a", Vector2(5, 0), 0, false),
			CombatService.make_target(&"b", Vector2(0, 5), 0, false),
			CombatService.make_target(&"far", Vector2(500, 0), 0, false),
		])
	assert_eq(results.size(), 2, "two of the three targets were in range")
	var ids: Array[String] = []
	for result in results:
		ids.append(String(result["target_id"]))
	ids.sort()
	assert_eq(str(ids), str(["a", "b"]), "each hit target appears once, by id")


# === CombatService: malformed input =========================================

## A malformed entry is SKIPPED, not fatal: one bad entry must not cancel the hits on the
## valid targets beside it. Types are checked before being read, because a coercion that
## succeeds on bad input is indistinguishable from valid input (L-024) — `int("x")` is 0,
## which would read as "this target has no defense".
func test_a_malformed_target_is_skipped_without_losing_the_valid_ones() -> void:
	var results := _service().resolve_hit(
		Vector2.ZERO, Vector2.RIGHT, 20, _attack(0, 360.0),
		[
			"not a dictionary",
			{"id": &"missing_fields"},
			_bad(&"bad_id", "id", 42),
			_bad(&"bad_pos", "position", "here"),
			_bad(&"bad_radius", "radius", "wide"),
			_bad(&"bad_def", "defense", "none"),
			_bad(&"bad_dead", "is_dead", 1),
			CombatService.make_target(&"good", Vector2(5, 0), 0, false),
		])
	assert_eq(results.size(), 1, "only the well-formed target resolved")
	if not results.is_empty():
		assert_eq(results[0]["target_id"], &"good", "and it is the valid one")


## A target that differs from a KNOWN-GOOD one in exactly ONE field, which is set to a wrong
## TYPE. Each negative case must be rejected for the field it is testing and would otherwise
## be accepted — a payload that is also broken in a second way proves nothing (L-024).
func _bad(id: StringName, field: String, wrong_value: Variant) -> Dictionary:
	var target := CombatService.make_target(id, Vector2(5, 0), 0, false, 0.0)
	target[field] = wrong_value
	return target


## Reach is measured to the target's SURFACE. Without the radius term a wide target would have
## to be half-overlapped before it could be hit, and every attack would need a compensating
## reach value per target size.
func test_a_targets_radius_extends_the_effective_reach() -> void:
	var service := _service()
	var attack := _attack(0, 120.0, 24.0)
	var just_out := [CombatService.make_target(&"t", Vector2(30, 0), 0, false, 0.0)]
	assert_eq(service.resolve_hit(Vector2.ZERO, Vector2.RIGHT, 20, attack, just_out).size(), 0,
		"a point target 30px away is beyond a 24px reach")
	var with_radius := [CombatService.make_target(&"t", Vector2(30, 0), 0, false, 8.0)]
	assert_eq(service.resolve_hit(Vector2.ZERO, Vector2.RIGHT, 20, attack,
			with_radius).size(), 1,
		"the same centre with an 8px radius is within reach of its surface")
	# A negative radius must not SHRINK reach — a mis-authored value cannot make a target
	# harder to hit than a point.
	var negative := [CombatService.make_target(&"t", Vector2(20, 0), 0, false, -100.0)]
	assert_eq(service.resolve_hit(Vector2.ZERO, Vector2.RIGHT, 20, attack, negative).size(), 1,
		"a negative radius is clamped to 0 rather than shrinking the attack's reach")


# === CombatService: determinism =============================================

## THE determinism contract: the same world seed produces the same crit sequence. This is what
## makes a fight reproducible from a save, and it is why the service never creates its own
## generator.
func test_the_same_world_seed_produces_the_same_crit_sequence() -> void:
	var first := _crit_sequence(WORLD_SEED, 40)
	var second := _crit_sequence(WORLD_SEED, 40)
	assert_eq(str(first), str(second),
		"two services on the same seed roll an identical crit sequence")
	var other := _crit_sequence(WORLD_SEED + 1, 40)
	assert_ne(str(other), str(first),
		"a different world seed produces a different sequence (the seed actually matters)")
	# A 50% chance over 40 rolls must produce both outcomes — otherwise the "sequence" could
	# be a constant and every assertion above would pass for the wrong reason.
	assert_true(first.has(true) and first.has(false),
		"the sequence contains both crits and non-crits, got %s" % str(first))


## Roll `count` hits at 50% crit and record the outcomes.
func _crit_sequence(world_seed: int, count: int) -> Array:
	var service := _service(world_seed)
	var attack := _attack(50)
	var out: Array = []
	for _i in count:
		var results := service.resolve_hit(
			Vector2.ZERO, Vector2.RIGHT, 100, attack,
			[CombatService.make_target(&"t", Vector2(5, 0), 0, false)])
		out.append(bool(results[0]["is_critical"]) if not results.is_empty() else false)
	return out


## A crit must actually multiply the damage. Asserting only the flag would pass for a service
## that reports `is_critical` and then deals normal damage.
func test_a_critical_hit_deals_the_multiplied_damage() -> void:
	var service := _service()
	var attack := _attack(100)  # always crits
	var results := service.resolve_hit(
		Vector2.ZERO, Vector2.RIGHT, 100, attack,
		[CombatService.make_target(&"t", Vector2(5, 0), 0, false)])
	assert_eq(results.size(), 1, "the always-crit attack hit")
	if results.is_empty():
		return
	assert_true(bool(results[0]["is_critical"]), "and reports itself as critical")
	assert_eq(results[0]["damage"], 200,
		"a 2.0x crit on 100 attack against 0 defense deals 200, not 100")

	var never := _service().resolve_hit(
		Vector2.ZERO, Vector2.RIGHT, 100, _attack(0),
		[CombatService.make_target(&"t", Vector2(5, 0), 0, false)])
	assert_false(bool(never[0]["is_critical"]), "a 0% attack never crits")
	assert_eq(never[0]["damage"], 100, "and deals the unmultiplied damage")


## A FILTERED-OUT target must not consume a draw. If it did, the crit sequence would depend on
## how many out-of-range entries the hitbox happened to report — so standing somewhere else
## would change the dice, and a replay would diverge.
func test_filtered_targets_do_not_consume_the_random_sequence() -> void:
	var rng_a: RngService = RngServiceScript.new(WORLD_SEED)
	var stream_a := rng_a.stream(RngService.STREAM_COMBAT)
	var service_a := CombatService.new(stream_a)
	service_a.resolve_hit(Vector2.ZERO, Vector2.RIGHT, 100, _attack(50), [
		CombatService.make_target(&"far", Vector2(900, 0), 0, false),
		CombatService.make_target(&"behind", Vector2(-9, 0), 0, false),
		CombatService.make_target(&"corpse", Vector2(5, 0), 0, true),
		CombatService.make_target(&"hit", Vector2(5, 0), 0, false),
	])
	assert_eq(stream_a.draw_count(), 1,
		"exactly one draw for the one target that was actually hit (got %d)"
			% stream_a.draw_count())

	var rng_b: RngService = RngServiceScript.new(WORLD_SEED)
	var stream_b := rng_b.stream(RngService.STREAM_COMBAT)
	var service_b := CombatService.new(stream_b)
	service_b.resolve_hit(Vector2.ZERO, Vector2.RIGHT, 100, _attack(50), [
		CombatService.make_target(&"hit", Vector2(5, 0), 0, false),
	])
	assert_eq(stream_a.state(), stream_b.state(),
		"so the stream lands in the same place whether or not misses were reported")
