extends Resource
class_name StatBlock
## StatBlock — Aetheria data (content Resource).
##
## The shared base-stat shape (`docs/DATA_SCHEMA.md` §1). This is DATA, not behavior:
## authored numbers live in `.tres` files under `data/stats/`, never as magic numbers in
## scripts (`.kiro/steering/04-coding-standards.md`). A `StatsComponent` reads one of these
## for an entity's base/max values.
##
## PHASE 02 SUBSET: only the fields a movement + minimal-damage entity needs now
## (`max_hp`, `attack`, `defense`, `move_speed`). The full DATA_SCHEMA StatBlock
## (max_mana, resistances, crit, speed-as-float, …) is added by the phases that need it —
## no speculative fields (`03-architecture.md` anti-over-engineering). The field names here
## match the schema so Phase 04 (Character) and later combat/equipment reuse the same shape
## instead of a Player-specific invention.

## Max health points. Must be > 0 (an entity with 0 max HP is invalid content).
@export var max_hp: int = 1

## Attack power fed into the domain damage rule. Must be >= 0.
@export var attack: int = 0

## Flat damage mitigation fed into the domain damage rule. Must be >= 0.
@export var defense: int = 0

## Movement speed in pixels/second for top-down movement. Must be >= 0.
@export var move_speed: float = 0.0


## True when every field satisfies its invariant. Content loaded from disk is external
## input and must be validated at the boundary (`04-coding-standards.md` error handling).
func is_valid() -> bool:
	return max_hp > 0 and attack >= 0 and defense >= 0 and move_speed >= 0.0


## Returns the list of invariant violations (empty == valid). Used by StatsComponent to
## fail loudly in dev and by tests to assert authored content is well-formed.
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if max_hp <= 0:
		errors.append("max_hp must be > 0 (got %d)" % max_hp)
	if attack < 0:
		errors.append("attack must be >= 0 (got %d)" % attack)
	if defense < 0:
		errors.append("defense must be >= 0 (got %d)" % defense)
	if move_speed < 0.0:
		errors.append("move_speed must be >= 0 (got %f)" % move_speed)
	return errors
