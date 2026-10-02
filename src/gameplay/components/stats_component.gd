extends Node
class_name StatsComponent
## StatsComponent — Aetheria gameplay (entity component).
##
## Holds an entity's base/max stats by reading a `StatBlock` resource (data). It is the
## entity's single source for "how strong am I" so HealthComponent/MovementComponent and
## the sandbox damage exchange don't duplicate numbers (`docs/ARCHITECTURE.md` §3). The
## numbers live in data (`StatBlock` `.tres`), never hard-coded here
## (`.kiro/steering/04-coding-standards.md`).
##
## Phase 02 exposes only validated read accessors for the subset the player/dummy need.
## It does NOT compute damage (that is the domain `DamageRules`) and owns no runtime HP
## (that is HealthComponent). This keeps the component reusable for any future entity
## (NPC/enemy/pet), which is why Player is not special-cased (`docs/CHARACTER_SYSTEM.md`).
##
## Note on authority (Phase 04 seam): the authoritative numbers conceptually belong to a
## future `CharacterState`/`StatBlock` in the domain/data layer; this component is the
## runtime *view* of them. It therefore reads a StatBlock and does not invent its own.

## The authored stat data this entity uses. Assigned via @export in the entity scene or
## set in code before the component is used.
@export var stat_block: StatBlock = null


## Validates the assigned StatBlock at the boundary. Call from the owner's _ready(). Fails
## loudly in dev (assert + push_error) rather than silently running with bad/missing data
## (`04-coding-standards.md` error handling). Returns true when usable.
func validate() -> bool:
	if stat_block == null:
		push_error("[stats] no StatBlock assigned")
		assert(false, "StatsComponent requires a StatBlock")
		return false
	var errors := stat_block.validation_errors()
	if not errors.is_empty():
		push_error("[stats] invalid StatBlock: %s" % str(errors))
		assert(false, "StatsComponent StatBlock invalid: %s" % str(errors))
		return false
	return true


# --- Validated read accessors (never return an out-of-range value) -----------
# A null/invalid StatBlock yields safe fallbacks AND a dev warning, so a missing
# resource is loud, not a silent zero that looks intentional.

func get_max_hp() -> int:
	if stat_block == null:
		push_warning("[stats] get_max_hp with no StatBlock; returning 1")
		return 1
	return max(1, stat_block.max_hp)


func get_attack() -> int:
	if stat_block == null:
		push_warning("[stats] get_attack with no StatBlock; returning 0")
		return 0
	return max(0, stat_block.attack)


func get_defense() -> int:
	if stat_block == null:
		push_warning("[stats] get_defense with no StatBlock; returning 0")
		return 0
	return max(0, stat_block.defense)


func get_move_speed() -> float:
	if stat_block == null:
		push_warning("[stats] get_move_speed with no StatBlock; returning 0")
		return 0.0
	return maxf(0.0, stat_block.move_speed)
