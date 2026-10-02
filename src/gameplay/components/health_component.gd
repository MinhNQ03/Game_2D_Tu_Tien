extends Node
class_name HealthComponent
## HealthComponent — Aetheria gameplay (entity component).
##
## Owns an entity's RUNTIME health (current/max) and the death transition. It emits
## direct signals to its owner (`docs/ARCHITECTURE.md` §4: local relationships use direct
## signals, not the EventBus). It owns no damage MATH — callers pass an already-computed
## amount (the domain `DamageRules` computes it). This keeps health reusable for any entity
## (player, dummy, future NPC/enemy) and keeps the "how much" rule in one domain place.
##
## INVARIANTS (always true after any public call):
##   0 <= current_health <= max_health
##   `died` is emitted exactly ONCE PER LIFE (per initialize() cycle), never twice for the
##     same life. `initialize()` begins a new life — a reused entity (e.g. the Training
##     Dummy's `reset_dummy()`) can therefore die again, emitting `died` once for THAT life.
##   DEAD is terminal within a life: no damage, no heal, no resurrection. Coming back is only
##     possible via an explicit `initialize()` (a new life), never as a side effect of heal.
##
## Health is a RUNTIME tier (`docs/CHARACTER_SYSTEM.md` §3): not serialized as-is; a future
## save stores authoritative persistent data and rebuilds current health on load.

signal health_changed(current: int, maximum: int)
signal damage_taken(amount: int, current: int)
signal healed(amount: int, current: int)
signal died()

var _max_health: int = 1
var _current_health: int = 1
var _is_dead: bool = false


## Set up max + current health. `maximum` is clamped to >= 1 (an entity can't have 0 max
## HP). Current starts full unless `start_current` is given (then clamped into range).
## Emits health_changed so a freshly-wired HUD reflects the initial value.
##
## This BEGINS A NEW LIFE: it clears the dead flag (unless started at 0), so the next time
## current health reaches 0 `died` fires again — once for the new life. This is how
## `TrainingDummy.reset_dummy()` reuses the entity. It is NOT a resurrection feature; it is
## an explicit re-initialization chosen by the owner.
func initialize(maximum: int, start_current: int = -1) -> void:
	_max_health = max(1, maximum)
	var start: int = _max_health if start_current < 0 else start_current
	_current_health = clampi(start, 0, _max_health)
	_is_dead = _current_health == 0
	health_changed.emit(_current_health, _max_health)


func get_current_health() -> int:
	return _current_health


func get_max_health() -> int:
	return _max_health


func is_dead() -> bool:
	return _is_dead


func is_full() -> bool:
	return _current_health == _max_health


func get_health_fraction() -> float:
	return float(_current_health) / float(_max_health)


## Apply damage. Returns the amount ACTUALLY subtracted (so a caller knows what landed).
## - amount <= 0 is rejected (returns 0) — damage is never a stealth-heal.
## - already dead → rejected (returns 0); no double processing, no second `died`.
## - clamps current to 0; crossing to 0 emits `died` exactly once.
func apply_damage(amount: int) -> int:
	if _is_dead:
		return 0
	if amount <= 0:
		if amount < 0:
			push_warning("[health] apply_damage ignored negative amount %d" % amount)
		return 0
	var before := _current_health
	_current_health = max(0, _current_health - amount)
	var applied := before - _current_health
	health_changed.emit(_current_health, _max_health)
	damage_taken.emit(applied, _current_health)
	if _current_health == 0:
		_is_dead = true
		died.emit()
	return applied


## Heal. Returns the amount ACTUALLY restored.
## - amount <= 0 is rejected (returns 0) — heal is never a stealth-damage.
## - DEAD is terminal: a dead entity cannot be healed back to life (returns 0). Revive is
##   a deliberate future feature, never a side effect of heal.
## - clamps current to max.
func heal(amount: int) -> int:
	if _is_dead:
		return 0
	if amount <= 0:
		if amount < 0:
			push_warning("[health] heal ignored negative amount %d" % amount)
		return 0
	var before := _current_health
	_current_health = min(_max_health, _current_health + amount)
	var restored := _current_health - before
	if restored > 0:
		health_changed.emit(_current_health, _max_health)
		healed.emit(restored, _current_health)
	return restored
