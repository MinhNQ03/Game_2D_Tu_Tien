extends RefCounted
class_name CombatService
## CombatService — Aetheria domain (resolves one hit pass, Phase 09, D-007).
##
## The authority on "what did this swing do". Pure and node-free: it takes DESCRIPTIONS of an
## attacker and the targets its hit window found, and returns a list of results. It never
## touches a node, a HealthComponent, a scene or `/root` — the gameplay layer applies the
## results it returns (`03-architecture.md`: UI/gameplay send intents and apply outcomes;
## rules decide them).
##
## WHY THIS SITS BETWEEN THE HITBOX AND `DamageRules`. `DamageRules` answers "how much does
## one hit subtract" and must stay a formula. Something still has to decide, per swing: does
## facing allow this target to be hit, did it crit, is the target already dead, and is each
## target hit exactly once. Those are RULES, and putting them in the component that owns the
## Area2D would make them untestable without a physics frame — which is precisely the headless
## trap L-016 describes. Here they are unit-testable with plain vectors.
##
## DETERMINISM. The only nondeterministic input is the crit roll, and it comes from an injected
## `RngStream` (the seeded `combat` stream, `RngService.STREAM_COMBAT`). Same stream state +
## same inputs = same results, every time, which is what makes a combat sequence reproducible
## from a world seed. The service never creates a generator of its own; a service that did
## could not be reproduced and would quietly make every combat test order-dependent.
##
## ONE DRAW PER RESOLVED TARGET, ALWAYS. `next_chance()` consumes a draw even at 0% or 100%
## (see `RngStream`), so editing an attack's crit chance cannot shift every later draw in the
## world. The same discipline is kept here: a target that is filtered out by facing or by being
## dead is rejected BEFORE the roll, so the number of draws depends only on how many targets
## were actually hit — never on their order in the array.

## What one target looked like when the hit window found it.
##
## A plain Dictionary rather than a Resource/class: it is a transient argument built once per
## swing and thrown away, so a class would be an allocation per target per swing in a combat
## hot path (`05-performance-testing.md`) with no behaviour to justify it.
##
## Keys (all required):
##   `id`        StringName — stable identity of the target, echoed into the result so the
##                            caller can map a result back to its entity without array order.
##   `position`  Vector2    — world position, for the reach/arc test.
##   `radius`    float      — the target's damageable radius, ADDED to the attack's reach.
##                            Without it, reach would be measured to a target's centre, so a
##                            large target would have to be half-overlapped to be hit — and
##                            every target would need its own compensating reach value.
##   `defense`   int        — the target's defense stat, fed to `DamageRules`.
##   `is_dead`   bool       — already-dead targets are skipped (a corpse is not a target).
const TARGET_KEYS := ["id", "position", "radius", "defense", "is_dead"]

var _rng: RngStream = null


## Bind the seeded combat stream. A null stream is REFUSED loudly and leaves the service
## unusable, rather than silently falling back to an unseeded generator: an unreproducible
## combat is worse than no combat, because the failure only shows up as a desynced save or a
## test that passes once.
func _init(combat_stream: RngStream = null) -> void:
	if combat_stream == null:
		push_error("[combat] CombatService requires a seeded RngStream; it is UNUSABLE "
			+ "without one and will resolve nothing")
		return
	_rng = combat_stream


## True once a seeded stream is bound.
func is_ready() -> bool:
	return _rng != null


## Resolve one hit pass and return a result per target that was actually hit.
##
## `attacker_position` / `attacker_facing` define the arc, `attack` supplies reach, arc, power
## and crit, `attacker_attack` is the attacker's attack stat, and `targets` is what the hit
## window found (each entry shaped by `TARGET_KEYS`).
##
## Returns an Array of result Dictionaries:
##   `target_id` StringName · `damage` int · `is_critical` bool
## An empty array means the swing hit nothing — a normal outcome, not an error.
##
## Order is the order of `targets`, so a caller feeding a deterministically ordered list gets
## deterministically ordered results (and therefore a deterministic draw sequence).
func resolve_hit(
		attacker_position: Vector2,
		attacker_facing: Vector2,
		attacker_attack: int,
		attack: AttackData,
		targets: Array) -> Array:
	var results: Array = []
	if not is_ready():
		return results
	if attack == null or not attack.is_valid():
		push_error("[combat] resolve_hit called with an invalid AttackData; nothing resolved")
		return results
	var facing := attacker_facing
	if facing.length_squared() <= 0.0:
		# A zero facing has no arc, so every arc test would be meaningless. Refuse rather than
		# pick a default direction: a swing in an arbitrary direction is worse than no swing,
		# because the player sees a hit they did not aim.
		push_error("[combat] resolve_hit needs a non-zero attacker facing; nothing resolved")
		return results
	facing = facing.normalized()
	# Half the arc, as a cosine, so the per-target test is one dot product instead of an
	# `atan2` + angle wrap. Computed ONCE per swing rather than per target.
	var half_arc_cos := cos(deg_to_rad(attack.arc_degrees * 0.5))

	# GEOMETRY FIRST, FULL VALIDATION SECOND. Every registered entity is a CANDIDATE and only
	# a few are hits, so the per-candidate work has to be the cheap part. Validating all five
	# fields of every candidate before rejecting it by distance made a swing cost 9x more
	# against a 10x-larger registry — measured, in `tests/performance/test_combat_budget.gd`,
	# which is how it was noticed. The geometric reject needs two fields, so only those two
	# are checked up front and the rest are checked for survivors (`PERFORMANCE.md` PERF-002).
	for entry in targets:
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("[combat] target entry is not a Dictionary (got %s)"
				% type_string(typeof(entry)))
			continue
		var candidate: Dictionary = entry
		var position_value: Variant = candidate.get("position")
		if typeof(position_value) != TYPE_VECTOR2:
			push_error("[combat] target 'position' must be a Vector2 (got %s)"
				% type_string(typeof(position_value)))
			continue
		var radius_value: Variant = candidate.get("radius")
		var radius_type := typeof(radius_value)
		if radius_type != TYPE_FLOAT and radius_type != TYPE_INT:
			push_error("[combat] target 'radius' must be a number (got %s)"
				% type_string(radius_type))
			continue
		var offset: Vector2 = (position_value as Vector2) - attacker_position
		var distance_squared := offset.length_squared()
		# Reach is measured to the target's SURFACE, not its centre: a wide target does not
		# have to be half-overlapped before it can be hit. Squared comparison, so no sqrt per
		# candidate in a combat hot path (`05-performance-testing.md`).
		var effective_reach: float = attack.reach_pixels + maxf(0.0, float(radius_value))
		if distance_squared > effective_reach * effective_reach:
			continue
		# A target exactly ON the attacker has no direction, so the arc cannot reject it.
		# Treat it as hit: it is unambiguously within reach, and skipping it would make a
		# point-blank attack whiff, which reads as the attack being broken.
		if distance_squared > 0.0:
			if offset.normalized().dot(facing) < half_arc_cos:
				continue
		# In range and in arc: now the remaining fields matter, so now they are validated.
		var target: Dictionary = _validated_target(candidate)
		if target.is_empty():
			continue
		if bool(target["is_dead"]):
			continue
		# Past every filter: this target IS hit, so now — and only now — the die is rolled.
		var is_critical := _rng.next_chance(attack.critical_chance_percent)
		var crit_multiplier := attack.critical_multiplier if is_critical \
			else DamageRules.NO_CRIT_MULTIPLIER
		var damage := DamageRules.compute_hit(
			attacker_attack, int(target["defense"]), attack.power_multiplier, crit_multiplier)
		results.append({
			"target_id": target["id"] as StringName,
			"damage": damage,
			"is_critical": is_critical,
		})
	return results


## Validate one target entry, returning it on success and an EMPTY dictionary on failure.
##
## Type-checks before reading (L-024: a coercion that succeeds on bad input is
## indistinguishable from valid input — `int("x")` is 0, which would read as "no defense").
## A malformed entry is reported and SKIPPED rather than aborting the whole swing: one bad
## entry must not cancel the hits on the valid targets beside it.
func _validated_target(entry: Variant) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		push_error("[combat] target entry is not a Dictionary (got %s)"
			% type_string(typeof(entry)))
		return {}
	var target: Dictionary = entry
	for key in TARGET_KEYS:
		if not target.has(key):
			push_error("[combat] target entry is missing '%s'" % key)
			return {}
	var id_type := typeof(target["id"])
	if id_type != TYPE_STRING and id_type != TYPE_STRING_NAME:
		push_error("[combat] target 'id' must be a String/StringName (got %s)"
			% type_string(id_type))
		return {}
	if typeof(target["position"]) != TYPE_VECTOR2:
		push_error("[combat] target 'position' must be a Vector2 (got %s)"
			% type_string(typeof(target["position"])))
		return {}
	var radius_type := typeof(target["radius"])
	if radius_type != TYPE_FLOAT and radius_type != TYPE_INT:
		push_error("[combat] target 'radius' must be a number (got %s)"
			% type_string(radius_type))
		return {}
	if typeof(target["defense"]) != TYPE_INT:
		push_error("[combat] target 'defense' must be an int (got %s)"
			% type_string(typeof(target["defense"])))
		return {}
	if typeof(target["is_dead"]) != TYPE_BOOL:
		push_error("[combat] target 'is_dead' must be a bool (got %s)"
			% type_string(typeof(target["is_dead"])))
		return {}
	return target


## Build a target entry in the shape `resolve_hit` expects.
##
## Exists so the gameplay layer has ONE place that knows the dictionary's shape — a caller
## assembling the keys by hand is a typo away from a silently skipped target, and the typo
## would look like a missed hit rather than a bug.
static func make_target(
		id: StringName,
		position: Vector2,
		defense: int,
		is_dead: bool,
		radius: float = 0.0) -> Dictionary:
	return {
		"id": id,
		"position": position,
		"radius": radius,
		"defense": defense,
		"is_dead": is_dead,
	}
