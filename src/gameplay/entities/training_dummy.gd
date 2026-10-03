extends StaticBody2D
class_name TrainingDummy
## TrainingDummy — Aetheria gameplay entity (sandbox target).
##
## A STATIONARY, non-AI target that proves bidirectional health interaction in the Phase-02
## sandbox. It is built from the SAME components as the player (StatsComponent +
## HealthComponent) — composition, not a new "Enemy" class (`docs/ARCHITECTURE.md` §3). It
## is deliberately NOT called Enemy and defines no enemy/AI abstraction; the enemy phase
## chooses that later. No `_process`/`_physics_process`, no movement, no targeting, no
## networking.
##
## It takes damage via its HealthComponent and exposes a DETERMINISTIC retaliation value
## (derived from its stats) that the sandbox coordinator applies to the player — the dummy
## never reaches across the tree to damage anything itself.

## Re-exposed health signals (direct, local) for a coordinator/HUD.
signal health_changed(current: int, maximum: int)
signal died()

@onready var _stats: StatsComponent = $StatsComponent
@onready var _health: HealthComponent = $HealthComponent


func _ready() -> void:
	# Collision wiring from the single source of truth (`CollisionLayers`): the dummy is a
	# solid body on the DUMMY layer; it detects nothing itself (mask 0 — it is a target, not
	# a sensor). Done FIRST (before the stats check) so the body is always correctly layered
	# even if the entity later fails closed. Authoritative at runtime, not a scene magic number.
	collision_layer = CollisionLayers.DUMMY
	collision_mask = 0

	# Fail CLOSED on invalid/missing authored stats (same contract as Player): do not wire
	# health or signals on a broken scene; report loudly and stay inert. Valid `.tres` files
	# take the normal path.
	if not _stats.validate():
		push_error("[dummy] invalid StatBlock; training dummy disabled (fail-closed)")
		return

	_health.initialize(_stats.get_max_hp())
	_health.health_changed.connect(_on_health_changed)
	_health.died.connect(_on_health_died)


## Apply already-computed damage (the coordinator computes it via domain DamageRules).
## Returns the amount actually applied.
func take_damage(amount: int) -> int:
	return _health.apply_damage(amount)


## The dummy's attack stat, so a coordinator can compute its retaliation hit via the same
## domain rule used for the player's hit. Keeps the "how much" in one place.
func get_attack_power() -> int:
	return _stats.get_attack()


func get_defense() -> int:
	return _stats.get_defense()


func get_current_health() -> int:
	return _health.get_current_health()


func get_max_health() -> int:
	return _health.get_max_health()


func is_dead() -> bool:
	return _health.is_dead()


## Reset to full health for a fresh sandbox run (deterministic re-initialize). This begins
## a NEW LIFE on the HealthComponent (`died` can fire once more for the new life — see
## HealthComponent). It is an explicit sandbox reuse, NOT a general revive/resurrection.
func reset_dummy() -> void:
	_health.initialize(_stats.get_max_hp())


func _on_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)


func _on_health_died() -> void:
	died.emit()
