extends Node
class_name HurtboxComponent
## HurtboxComponent — Aetheria gameplay (an entity's damageable presence, Phase 09).
##
## Makes its parent entity TARGETABLE. It is the one place an attacker learns that an entity
## exists, where it is, how big it is, how tough it is and whether it is still alive — and the
## one place damage is handed back in. Composition, not inheritance: the player and the
## training dummy are both targetable because both carry one of these, and neither shares a
## base class (`03-architecture.md`).
##
## IT IS A PLAIN `Node`, NOT AN `Area2D`, AND THAT IS THE DESIGN (D-007).
## Combat resolves hits analytically — `CombatService` compares reach and arc against the
## session's registry of hurtboxes — so no physics sensor is involved. The reason is L-016 and
## L-017: in the headless `-s` runner an Area2D overlap does not fire reliably, so a combat
## system that detected hits with one could not be tested end to end. It is also cheaper (no
## physics query per swing) and its hit window opens and closes with the attack's state
## machine rather than with the physics tick. The trade: a target is a point plus a radius
## rather than an arbitrary polygon, which on a 16px grid is not a distinction a player sees.
##
## REGISTRATION IS AUTOMATIC AND SYMMETRIC. It registers on entering the tree and unregisters
## on leaving, so an entity that is freed mid-swing cannot be hit afterwards. An unregistered
## hurtbox is simply not a target — it never half-exists.
##
## WHAT IT DOES NOT DO: it owns no health (the `HealthComponent` beside it does), computes no
## damage (`DamageRules`), decides no hit (`CombatService`), and knows nothing about who
## attacked it. It is the target side of the seam and nothing else.

## Damage landed on this entity. `is_critical` is carried so presentation can distinguish a
## crit without recomputing anything, and `amount` is what was ACTUALLY applied (so a hit
## absorbed by an already-dead entity reports 0).
##
## `push_direction` (D-057B) is the unit direction the blow travelled — attacker toward this
## entity — or ZERO when the source has no direction. A SEMANTIC fact of the hit, exactly what an
## authoritative "attack hit" event will carry (`MOTION_DESIGN_CONTRACT.md` M-12.1), so the
## body's reaction can push the right way without presentation knowing who struck it. Nothing in
## gameplay reads it: a basic attack has no knockback, and the reaction moves only the drawing.
signal damaged(amount: int, is_critical: bool, push_direction: Vector2)

## Stable identity of the entity this hurtbox belongs to. Echoed back in a hit result so an
## attacker can map a result to an entity without relying on array order.
@export var entity_id: StringName = &""

## Which SIDE this entity is on (Phase 16). An attack never lands on a hurtbox of the
## attacker's own team, so a companion's bite cannot hurt its owner and the owner's blade cannot
## hurt the companion. Empty = no side: anything may hit it (a training post) and it shields
## nobody. Set by whoever arms the entity (`CombatRuntime`), never by the entity's art.
@export var team: StringName = &""

## Damageable radius in pixels, ADDED to an attack's reach. Authored per entity because it
## describes the entity's size, not the attack's: the 32x48 character baseline
## (`06-art-assets.md`) is about 10px from centre to flank.
@export var radius: float = 10.0

## The node whose health this hurtbox fronts. Resolved from the parent when left unset, which
## is the normal case — a hurtbox is a child of the entity it belongs to.
var _entity: Node = null
var _registry: CombatHurtboxRegistry = null


## Bind the entity and the session registry, then register. Called by whoever realizes the
## entity (`WorldRuntime` for the player, a map for a dummy) BEFORE or AFTER the node enters
## the tree — registration happens on whichever comes last, so ordering cannot lose it.
##
## A null registry is legal and means "not in a combat session": the hurtbox stays inert and
## simply is not a target. That is the isolated-harness case, and it must not be an error,
## because a unit test that builds an entity on its own is not a mis-wired game.
func setup(entity: Node, registry: CombatHurtboxRegistry) -> void:
	_entity = entity
	_registry = registry
	if is_inside_tree():
		_register()


func _ready() -> void:
	if _entity == null:
		_entity = get_parent()
	_register()


func _exit_tree() -> void:
	if _registry != null:
		_registry.unregister(self)


func _register() -> void:
	if _registry == null:
		return
	if entity_id == &"":
		push_error("[hurtbox] refusing to register a hurtbox with no entity_id: a hit result "
			+ "could not be mapped back to an entity")
		return
	_registry.register(self)


## Where this entity is, in world space. Read from the entity node, so a moving target is
## always measured where it currently is rather than where it was when it registered.
func world_position() -> Vector2:
	var node_2d := _entity as Node2D
	if node_2d == null or not is_instance_valid(node_2d):
		return Vector2.ZERO
	return node_2d.global_position


## The entity's defense stat, fed to `DamageRules`. 0 when the entity exposes none, which
## makes an un-statted target maximally fragile rather than invulnerable — a missing stat
## should be obvious in play, not silently protective.
func defense() -> int:
	if _entity != null and is_instance_valid(_entity) and _entity.has_method("get_defense"):
		return int(_entity.call("get_defense"))
	return 0


## Is this entity already dead? A corpse is not a target.
func is_dead() -> bool:
	if _entity != null and is_instance_valid(_entity) and _entity.has_method("is_dead"):
		return bool(_entity.call("is_dead"))
	return false


## Is this hurtbox usable as a target right now? False once its entity is gone, so a stale
## registry entry can never produce a hit on something that no longer exists.
func is_targetable() -> bool:
	return _entity != null and is_instance_valid(_entity) and not is_dead()


## The target record `CombatService` consumes. Built HERE so the dictionary's shape is known
## in exactly two places — this method and `CombatService.make_target` — rather than being
## assembled by every attacker.
func to_target() -> Dictionary:
	return CombatService.make_target(
		entity_id, world_position(), defense(), is_dead(), radius)


## Apply a resolved hit. Returns what was ACTUALLY applied, so a caller can tell a landed hit
## from one absorbed by an already-dead entity.
##
## It routes through the entity's own `take_damage()` rather than reaching into its
## `HealthComponent`: the entity owns its health and may have more to do than subtract a
## number (the player syncs its authoritative `CharacterState`). Going around it would make
## combat the second writer of a value the entity is responsible for.
func apply_hit(amount: int, is_critical: bool, push_direction: Vector2 = Vector2.ZERO) -> int:
	if _entity == null or not is_instance_valid(_entity):
		return 0
	if not _entity.has_method("take_damage"):
		push_error("[hurtbox] '%s' fronts a node with no take_damage(); the hit is lost"
			% entity_id)
		return 0
	var applied := int(_entity.call("take_damage", amount))
	if applied > 0:
		damaged.emit(applied, is_critical, push_direction.normalized())
	return applied
