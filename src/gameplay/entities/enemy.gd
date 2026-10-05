extends CharacterBody2D
class_name Enemy
## Enemy — Aetheria gameplay entity (a data-driven creature, Phase 10).
##
## Built from the SAME components as the player — Stats, Health, Movement, Attack, Hurtbox —
## plus an `AIComponent` where the player has `InputService`. That symmetry is the point: an
## enemy is not a special class with its own combat path, it is a body that happens to be
## driven by a brain instead of by a keyboard, so `DamageRules`, `AttackStateMachine` and
## `CombatService` need no creature-specific branch (`03-architecture.md`: composition).
##
## EVERYTHING ABOUT IT COMES FROM `EnemyData`. Stats, hurt radius, attack, AI tuning and visual
## profile are all applied in `setup()`, so a second creature is a `.tres` and a spawn-table
## row. There is no `if enemy_id == ...` here and there must never be.
##
## IT HAS NO `CharacterState`. A `CharacterState` is the authoritative record of a PERSON —
## realm, sect, relationships, a place in the world simulation's cast. A frontier beast has
## none of those and nothing to remember between encounters, so it is a purely RUNTIME entity
## and nothing about it is persistent. The day a creature must be remembered (a named boss, a
## tamed pet) it gets a `CharacterState`; this class is not in the way of that.
##
## IT RUNS NO `_physics_process`. The session ticks its AI (`CombatRuntime`), which is what
## makes the cost of N enemies one measurable number instead of N callbacks.

## Re-exposed health signals, so a coordinator or HUD connects here instead of reaching across
## the tree into the HealthComponent.
signal health_changed(current: int, maximum: int)
signal died()

const VisualComponentScript := preload(
	"res://src/presentation/characters/character_visual_component.gd")

@onready var _stats: StatsComponent = $StatsComponent
@onready var _health: HealthComponent = $HealthComponent
@onready var _movement: MovementComponent = $MovementComponent
@onready var _attack: AttackComponent = $AttackComponent
@onready var _hurtbox: HurtboxComponent = $HurtboxComponent
@onready var _ai: AIComponent = $AIComponent

var _data: EnemyData = null
var _instance_id: StringName = &""
var _visual: CharacterVisualComponent = null
var _dead := false


func _ready() -> void:
	# Collision from the single source of truth, never a scene magic number. An enemy occupies
	# the DUMMY layer — the project's "solid non-player body" layer — and collides with WORLD
	# and PLAYER so it cannot walk through walls or stand inside the player.
	collision_layer = CollisionLayers.DUMMY
	collision_mask = CollisionLayers.WORLD | CollisionLayers.PLAYER
	_movement.setup(self)
	_health.health_changed.connect(_on_health_changed)
	_health.died.connect(_on_health_died)
	# Apply the authored data HERE, after the signals are connected and the `@onready` members
	# exist. `_ready` is the only correct hook: in `_enter_tree` the `@onready` fields are
	# still null, which is how the first version silently skipped `_apply()` entirely and
	# spawned creatures with 1 HP and an empty hurtbox id.
	if _data != null:
		_apply()


## Apply authored content to this body. Call BEFORE adding it to the tree where possible; it
## tolerates either, because `@onready` members only resolve once in-tree.
##
## Returns false (loud) on invalid data, leaving the entity inert rather than half-built: a
## creature with no stats that still walks around is worse than one that never spawned, because
## it looks like content and behaves like a bug (fail closed, `04-coding-standards.md`).
func setup(data: EnemyData, instance_id: StringName) -> bool:
	if data == null or not data.is_valid():
		push_error("[enemy] setup refused: invalid EnemyData")
		return false
	if instance_id == &"":
		push_error("[enemy] setup refused: an instance id is required for combat targeting")
		return false
	_data = data
	_instance_id = instance_id
	# Already in the tree (a rebuild/retune): apply now. Otherwise `_ready()` applies it, which
	# is the normal path — the spawner configures before `add_child` so `_ready` sees final
	# data, exactly as the player's `bind_character_state` does (D-026).
	if is_node_ready():
		return _apply()
	return true


## Push the data into the components. Separate from `setup()` so it can run once the
## `@onready` members exist, whichever order the caller chose.
func _apply() -> bool:
	_stats.stat_block = _data.stats
	if not _stats.validate():
		push_error("[enemy] '%s' has an invalid StatBlock; the entity stays inert" % _data.id)
		return false
	_health.initialize(_stats.get_max_hp())
	_hurtbox.entity_id = _instance_id
	_hurtbox.radius = _data.hurt_radius
	_apply_visual()
	return true


## Attach the data-driven visual. A missing profile is reported and leaves the entity
## invisible-but-functional rather than crashing — presentation degrades, gameplay does not.
func _apply_visual() -> void:
	if _data.visual_profile == null or _visual != null:
		return
	_visual = VisualComponentScript.new() as CharacterVisualComponent
	_visual.name = "CharacterVisualComponent"
	add_child(_visual)
	if not _visual.setup(_data.visual_profile):
		push_error("[enemy] '%s' has an unusable visual profile" % _data.id)
		_visual.queue_free()
		_visual = null


func data() -> EnemyData:
	return _data


func instance_id() -> StringName:
	return _instance_id


## The AI component, so the session can arm and tick it.
func ai() -> AIComponent:
	return _ai


func ai_state_name() -> String:
	return _ai.brain_state_name() if _ai != null else "IDLE"


# --- The combat contract (identical to the player's, by design) ---------------
#
# `HurtboxComponent` and `CombatService` reach an entity only through these five methods, so
# anything implementing them can fight. That is why there is no shared base class.

func get_attack_power() -> int:
	return _stats.get_attack()


func get_defense() -> int:
	return _stats.get_defense()


func take_damage(amount: int) -> int:
	return _health.apply_damage(amount)


func get_current_health() -> int:
	return _health.get_current_health()


func get_max_health() -> int:
	return _health.get_max_health()


func is_dead() -> bool:
	return _dead or _health.is_dead()


func _on_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)


## Death: stop being an actor, immediately and completely.
##
## All four of these matter and each one alone leaves a visible wrong (C11): a corpse that
## keeps sliding, keeps hunting, lands a hit from beyond the grave, or stays targetable so the
## player keeps swinging at nothing. The node is NOT freed here — the session owns the
## lifetime, and freeing mid-signal would tear down the emitter (L-013).
func _on_health_died() -> void:
	if _dead:
		return
	_dead = true
	if _ai != null and is_instance_valid(_ai):
		_ai.stop()
	if _attack != null and is_instance_valid(_attack):
		_attack.cancel()
	velocity = Vector2.ZERO
	# Visually dead: dimmed and flattened, which is readable at a glance and costs nothing.
	# A death ANIMATION belongs to the phase that owns combat VFX; this is the minimum that
	# distinguishes a corpse from a live creature (C13).
	modulate = Color(0.55, 0.55, 0.62, 0.75)
	died.emit()
