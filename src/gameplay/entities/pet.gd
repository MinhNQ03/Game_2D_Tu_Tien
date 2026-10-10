extends CharacterBody2D
class_name Pet
## Pet — Aetheria gameplay (a linh thú walking beside its owner, Phase 16).
##
## A composed entity, exactly like `Enemy`: the SAME `StatsComponent`, `HealthComponent`,
## `MovementComponent`, `AttackComponent`, `HurtboxComponent` and `AIComponent`, configured by a
## `PetData` instead of an `EnemyData`. Nothing about how it moves, swings, is hit or dies is
## new code — which is the point: a companion fights through the seams every fighter uses.
##
## It owns NO persistent truth. Which pet this is, and how much it has grown, belong to
## `PetStore`; this node is the RUNTIME body `PetRuntime` spawns for the active pet and frees
## on dismissal. Its health is runtime: a pet that falls withdraws and comes back whole.
##
## It is NOT solid to the player or to creatures (it collides with the WORLD only): a companion
## that can block a doorway or be body-blocked into a corner is a nuisance, not an ally.

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

var _data: PetData = null
var _instance_id: StringName = &""
## The pet's DERIVED stats for this summoning (base + growth at its current level).
var _stat_block: StatBlock = null
var _visual: CharacterVisualComponent = null
var _dead := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = CollisionLayers.WORLD
	_movement.setup(self)
	_health.health_changed.connect(_on_health_changed)
	_health.died.connect(_on_health_died)
	if _data != null:
		_apply()


## Configure this body. `stats` is the pet's derived block at its current level. Call BEFORE
## `add_child`, so `_ready` sees final data (the ordering `Enemy.setup` uses, D-026).
func setup(data: PetData, instance_id: StringName, stats: StatBlock) -> bool:
	if data == null or not data.is_valid():
		push_error("[pet] setup refused: invalid PetData")
		return false
	if instance_id == &"":
		push_error("[pet] setup refused: an instance id is required for combat targeting")
		return false
	if stats == null or not stats.is_valid():
		push_error("[pet] setup refused: '%s' has no valid derived stats" % data.id)
		return false
	_data = data
	_instance_id = instance_id
	_stat_block = stats
	if is_node_ready():
		return _apply()
	return true


func _apply() -> bool:
	_stats.stat_block = _stat_block
	if not _stats.validate():
		push_error("[pet] '%s' has an invalid StatBlock; the entity stays inert" % _data.id)
		return false
	_health.initialize(_stats.get_max_hp())
	_hurtbox.entity_id = _instance_id
	_hurtbox.radius = _data.hurt_radius
	_apply_visual()
	return true


func _apply_visual() -> void:
	if _data.visual_profile == null or _visual != null:
		return
	_visual = VisualComponentScript.new() as CharacterVisualComponent
	_visual.name = "CharacterVisualComponent"
	add_child(_visual)
	if not _visual.setup(_data.visual_profile):
		push_error("[pet] '%s' has an unusable visual profile" % _data.id)
		_visual.queue_free()
		_visual = null


## The pet grew while it was out: adopt its new derived stats. The new maximum applies and the
## health it had is kept (a level is a reward, never a surprise heal or a surprise wound).
func apply_stats(stats: StatBlock) -> bool:
	if stats == null or not stats.is_valid() or is_dead():
		return false
	_stat_block = stats
	_stats.stat_block = stats
	_health.initialize(_stats.get_max_hp(), mini(_health.get_current_health(),
		_stats.get_max_hp()))
	return true


func data() -> PetData:
	return _data


func instance_id() -> StringName:
	return _instance_id


func ai() -> AIComponent:
	return _ai


func ai_state_name() -> String:
	return _ai.brain_state_name() if _ai != null else "IDLE"


func visual() -> CharacterVisualComponent:
	return _visual


# --- The combat contract (identical to the player's and an enemy's, by design) ---------------

func get_attack_power() -> int:
	return _stats.get_attack()


func get_defense() -> int:
	return _stats.get_defense()


func get_move_speed() -> float:
	return _stat_block.move_speed if _stat_block != null else 0.0


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


func _on_health_died() -> void:
	if _dead:
		return
	_dead = true
	if _ai != null and is_instance_valid(_ai):
		_ai.stop()
	if _attack != null and is_instance_valid(_attack):
		_attack.cancel()
	velocity = Vector2.ZERO
	died.emit()
