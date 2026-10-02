extends CharacterBody2D
class_name Player
## Player — Aetheria gameplay entity (composition coordinator).
##
## A `CharacterBody2D` assembled from components (`docs/ARCHITECTURE.md` §3,
## `docs/CHARACTER_SYSTEM.md` §6) — NOT an inheritance chain and NOT a God object. It only
## COORDINATES; it owns no rules:
##   - reads SEMANTIC intent from `InputService` (never physical keys) and forwards it to
##     MovementComponent (`docs/MULTIPLAYER_PLAN.md` §3 intent boundary),
##   - initializes HealthComponent from StatsComponent,
##   - exposes a minimal attack INTENT (`attack_requested`) + stat reads for a gameplay
##     coordinator to resolve a hit via the domain rule,
##   - re-exposes health signals for a HUD/coordinator.
##
## It contains NO damage math, NO max-HP calc, NO inventory/quest/cultivation/save/story,
## and reads NO raw input. The player is "a Character conceptually" (Phase 04): authoritative
## numbers live in the StatBlock (data); this node is a runtime view, so Phase 04 can bind
## the same composition to a CharacterState without a rewrite.

## Emitted when the player expresses an attack intent this frame. The sandbox/gameplay
## coordinator decides what it hits and resolves damage via the domain `DamageRules` — the
## player never computes or applies combat damage itself.
signal attack_requested()

## Re-exposed health signals (direct, local). A HUD/coordinator connects to these instead
## of reaching into the HealthComponent across the tree.
signal health_changed(current: int, maximum: int)
signal died()

const ATTACK_ACTION := &"attack"

@onready var _stats: StatsComponent = $StatsComponent
@onready var _health: HealthComponent = $HealthComponent
@onready var _movement: MovementComponent = $MovementComponent

var _input: Node = null


func _ready() -> void:
	# Fail CLOSED on invalid/missing authored stats: a broken scene must not quietly run as
	# if valid (`04-coding-standards.md`: fail loud; no silent-fallback as the normal path).
	# `validate()` already reports loudly; here we stop wiring and disable processing so the
	# entity is inert rather than half-initialized. Valid `.tres` files take the normal path.
	if not _stats.validate():
		set_physics_process(false)
		push_error("[player] invalid StatBlock; player disabled (fail-closed)")
		return

	# Collision wiring from the single source of truth (`CollisionLayers`), not scene magic
	# numbers: the player occupies the PLAYER layer and collides with WORLD (walls) and the
	# DUMMY body. Setting it here means the named constants are authoritative at runtime.
	collision_layer = CollisionLayers.PLAYER
	collision_mask = CollisionLayers.WORLD | CollisionLayers.DUMMY

	_health.initialize(_stats.get_max_hp())
	_movement.setup(self)

	# Forward component signals outward as player-level signals (local, direct).
	_health.health_changed.connect(_on_health_changed)
	_health.died.connect(_on_health_died)

	# InputService is the ONLY input source (semantic gateway). Resolved once here, not
	# every physics frame, to avoid a per-tick tree lookup (`docs/PERFORMANCE.md`).
	_input = get_node_or_null("/root/InputService")


func _physics_process(delta: float) -> void:
	# No input service (e.g. an isolated unit harness) → no movement; deterministic.
	if _input == null:
		return
	var intent: Vector2 = _input.call("get_move_vector")
	_movement.apply_intent(intent, _stats.get_move_speed(), delta)

	# Edge-triggered attack INTENT. The service gates this on GAMEPLAY context, so an open
	# menu/modal can never leak an attack to the world.
	if _input.call("is_gameplay_action_just_pressed", ATTACK_ACTION):
		attack_requested.emit()


# --- Stat reads (for a gameplay coordinator resolving a hit via DamageRules) ---

func get_attack_power() -> int:
	return _stats.get_attack()


func get_defense() -> int:
	return _stats.get_defense()


# --- Health access (intent-revealing; UI/coordinator never mutate fields directly) ---

func take_damage(amount: int) -> int:
	return _health.apply_damage(amount)


func heal(amount: int) -> int:
	return _health.heal(amount)


func get_current_health() -> int:
	return _health.get_current_health()


func get_max_health() -> int:
	return _health.get_max_health()


func is_dead() -> bool:
	return _health.is_dead()


func _on_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)


func _on_health_died() -> void:
	died.emit()
