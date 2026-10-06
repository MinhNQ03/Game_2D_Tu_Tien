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

## Optional authoritative character state this component is a VIEW of (Phase 04 binding,
## `docs/CHARACTER_SYSTEM.md` §6). When bound, the read accessors return the character's
## CURRENT numbers (the single source of truth, `src/domain/character/character_state.gd`)
## instead of the raw StatBlock. The StatBlock remains the authored DATA shape the state was
## seeded from; it is still used when NO state is bound (e.g. the Training Dummy, isolated
## tests). Set once by the owner via `bind_character_state()`; never mutated here.
var _character_state: CharacterState = null

## What worn equipment adds (Phase 14). A VIEW-side modifier: the authoritative base stays in
## `CharacterState`; the equipment state is persisted by its own runtime, so a save never bakes a
## sword's bonus into the body.
var _bonus_attack: int = 0
var _bonus_defense: int = 0


func set_equipment_bonus(attack_bonus: int, defense_bonus: int) -> void:
	_bonus_attack = maxi(0, attack_bonus)
	_bonus_defense = maxi(0, defense_bonus)


## Bind the authoritative CharacterState this component views. The owner (Player) calls this
## once after the state is created, so stat reads come from the one domain source of truth
## rather than a parallel copy. Null unbinds (falls back to the StatBlock), which is the
## normal path for entities that are not Characters yet (Training Dummy).
func bind_character_state(state: CharacterState) -> void:
	_character_state = state


## True when this component is a view of an authoritative CharacterState.
func has_character_state() -> bool:
	return _character_state != null


## Validates the stat source at the boundary. Call from the owner's _ready(). When a
## CharacterState is bound it is the authority (already validated at construction), so the
## StatBlock is optional in that case. Otherwise a valid StatBlock is required. Reports
## loudly via `push_error` and returns false on missing/invalid data; the OWNER is expected
## to fail closed on a false result (`Player`/`TrainingDummy` disable themselves). We do NOT
## `assert()`/abort here: aborting the process would prevent the owner from degrading
## gracefully and would differ between debug/release builds. Loud error + a checked return
## value is the robust fail-loud-and-closed contract (`04-coding-standards.md`).
func validate() -> bool:
	if _character_state != null:
		return true
	if stat_block == null:
		push_error("[stats] no StatBlock assigned")
		return false
	var errors := stat_block.validation_errors()
	if not errors.is_empty():
		push_error("[stats] invalid StatBlock: %s" % str(errors))
		return false
	return true


# --- Validated read accessors (never return an out-of-range value) -----------
# A null/invalid StatBlock yields safe fallbacks AND a dev warning, so a missing
# resource is loud, not a silent zero that looks intentional.

func get_max_hp() -> int:
	if _character_state != null:
		return max(1, _character_state.max_hp)
	if stat_block == null:
		push_warning("[stats] get_max_hp with no StatBlock; returning 1")
		return 1
	return max(1, stat_block.max_hp)


func get_attack() -> int:
	if _character_state != null:
		return max(0, _character_state.attack) + _bonus_attack
	if stat_block == null:
		push_warning("[stats] get_attack with no StatBlock; returning 0")
		return 0
	return max(0, stat_block.attack)


func get_defense() -> int:
	if _character_state != null:
		return max(0, _character_state.defense) + _bonus_defense
	if stat_block == null:
		push_warning("[stats] get_defense with no StatBlock; returning 0")
		return 0
	return max(0, stat_block.defense)


func get_move_speed() -> float:
	if _character_state != null:
		return maxf(0.0, _character_state.move_speed)
	if stat_block == null:
		push_warning("[stats] get_move_speed with no StatBlock; returning 0")
		return 0.0
	return maxf(0.0, stat_block.move_speed)
