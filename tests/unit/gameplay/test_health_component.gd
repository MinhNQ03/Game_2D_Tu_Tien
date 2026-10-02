extends TestCase
## Unit tests for HealthComponent (src/gameplay/components/health_component.gd).
## High-risk area (health/death). Fresh instance per test; no autoloads, no tree needed
## (a bare Node's signals work via connect). free() each instance (no orphan).

const HealthScript := preload("res://src/gameplay/components/health_component.gd")


func _make(maximum: int = 100) -> Node:
	var h: Node = HealthScript.new()
	h.initialize(maximum)
	return h


func test_starts_full() -> void:
	var h := _make(100)
	assert_eq(h.get_current_health(), 100, "starts at max")
	assert_eq(h.get_max_health(), 100)
	assert_false(h.is_dead(), "not dead at start")
	assert_true(h.is_full(), "full at start")
	h.free()


func test_damage_reduces_health_and_returns_applied() -> void:
	var h := _make(100)
	var applied: int = h.apply_damage(30)
	assert_eq(applied, 30, "returns amount applied")
	assert_eq(h.get_current_health(), 70, "health reduced")
	h.free()


func test_damage_clamps_to_zero_and_kills() -> void:
	var h := _make(100)
	var applied: int = h.apply_damage(999999)
	assert_eq(applied, 100, "only the remaining health is applied")
	assert_eq(h.get_current_health(), 0, "clamped to zero, not negative")
	assert_true(h.is_dead(), "zero health == dead")
	h.free()


func test_died_emitted_exactly_once() -> void:
	var h := _make(50)
	var count := {"n": 0}
	h.died.connect(func() -> void: count["n"] += 1)
	h.apply_damage(50)            # dies
	h.apply_damage(10)            # already dead, must not re-emit
	h.apply_damage(10)            # ditto
	assert_eq(count["n"], 1, "died emitted exactly once")
	h.free()


func test_heal_restores_and_returns_applied() -> void:
	var h := _make(100)
	h.apply_damage(40)            # -> 60
	var restored: int = h.heal(25)
	assert_eq(restored, 25, "returns amount restored")
	assert_eq(h.get_current_health(), 85)
	h.free()


func test_heal_clamps_to_max() -> void:
	var h := _make(100)
	h.apply_damage(10)            # -> 90
	var restored: int = h.heal(999999)
	assert_eq(restored, 10, "only up to max is restored")
	assert_eq(h.get_current_health(), 100, "never exceeds max")
	h.free()


func test_negative_damage_rejected() -> void:
	var h := _make(100)
	var applied: int = h.apply_damage(-50)
	assert_eq(applied, 0, "negative damage applies nothing")
	assert_eq(h.get_current_health(), 100, "health unchanged (no stealth heal)")
	h.free()


func test_zero_damage_rejected() -> void:
	var h := _make(100)
	assert_eq(h.apply_damage(0), 0, "zero damage applies nothing")
	assert_eq(h.get_current_health(), 100)
	h.free()


func test_negative_and_zero_heal_rejected() -> void:
	var h := _make(100)
	h.apply_damage(50)            # -> 50
	assert_eq(h.heal(-30), 0, "negative heal applies nothing (no stealth damage)")
	assert_eq(h.heal(0), 0, "zero heal applies nothing")
	assert_eq(h.get_current_health(), 50, "health unchanged")
	h.free()


func test_dead_is_terminal_no_heal_resurrect() -> void:
	var h := _make(40)
	h.apply_damage(40)            # dead
	var restored: int = h.heal(100)
	assert_eq(restored, 0, "heal on a dead entity restores nothing")
	assert_eq(h.get_current_health(), 0, "stays dead")
	assert_true(h.is_dead(), "no resurrection via heal")
	h.free()


func test_dead_rejects_further_damage() -> void:
	var h := _make(40)
	h.apply_damage(40)            # dead
	var applied: int = h.apply_damage(10)
	assert_eq(applied, 0, "dead entity takes no further damage")
	assert_eq(h.get_current_health(), 0)
	h.free()


func test_invariant_hp_in_range_across_ops() -> void:
	var h := _make(30)
	for amount in [5, -3, 10, 999, 7, -100]:
		if amount >= 0:
			h.apply_damage(amount)
		var cur: int = h.get_current_health()
		assert_true(cur >= 0 and cur <= h.get_max_health(),
			"invariant 0<=hp<=max held (hp=%d)" % cur)
	h.free()


func test_initialize_with_partial_current() -> void:
	var h: Node = HealthScript.new()
	h.initialize(100, 25)
	assert_eq(h.get_current_health(), 25, "starts at given current")
	assert_false(h.is_full(), "not full")
	assert_false(h.is_dead(), "alive at 25")
	h.free()


# --- Death/reset lifecycle (per-life "died once", not lifetime-global) --------

## After death, further damage AND heal are rejected and do NOT emit a second `died`
## within the same life (the "once per life" invariant).
func test_no_duplicate_died_within_a_life() -> void:
	var h := _make(40)
	var count := {"n": 0}
	h.died.connect(func() -> void: count["n"] += 1)
	h.apply_damage(40)   # dies (died #1)
	h.apply_damage(10)   # dead → rejected, no died
	h.heal(50)           # dead → rejected, no revive, no died
	h.apply_damage(10)   # dead → rejected, no died
	assert_eq(count["n"], 1, "died fires exactly once for this life")
	assert_true(h.is_dead(), "still dead; heal did not resurrect")
	h.free()


## A NEW LIFE via initialize() (how TrainingDummy.reset_dummy works): the entity is alive
## again and can die once more — `died` fires exactly once PER LIFE, not once ever.
func test_reinitialize_begins_new_life_and_can_die_again() -> void:
	var h := _make(30)
	var count := {"n": 0}
	h.died.connect(func() -> void: count["n"] += 1)

	h.apply_damage(30)   # life 1 death (died #1)
	assert_true(h.is_dead())
	assert_eq(count["n"], 1, "one died in life 1")

	h.initialize(30)     # NEW LIFE: full health, alive again
	assert_false(h.is_dead(), "alive after re-initialize (new life)")
	assert_eq(h.get_current_health(), 30, "full health in life 2")

	h.apply_damage(30)   # life 2 death (died #2 total, but one per life)
	assert_true(h.is_dead(), "dead again in life 2")
	assert_eq(count["n"], 2, "exactly one died per life (2 lives → 2 deaths)")
	h.free()
