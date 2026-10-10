extends Resource
class_name PetData
## PetData — Aetheria data (one linh thú's authored definition, Phase 16).
##
## CONTENT, not behaviour: who the creature is, what it starts with, how it grows, how it
## fights, how it behaves beside its owner and how it looks. A new pet is a new `.tres` listed in
## the `PetCatalogData` — never a branch in a runtime (`02-game-design.md` extensibility rule).
##
## A PET IS NOT A HUMAN CHARACTER. It has no sect, faction, rank, realm or relationship edges, so
## it is not a `CharacterState` and never enters the `CharacterRegistry`; the persistent facts
## about an OWNED pet live in `PetStore` (which pet, how much XP), and everything else here is
## authored.
##
## GROWTH IS DERIVED, NEVER STORED. `stats_at(level)` is the authored base plus `growth` per
## level above the first, and the level itself is derived from the pet's XP through
## `progression_curve` — the same `ProgressionCurveData` math the player's level uses (D-064).
## Nothing stores a level or a current stat.

@export var id: StringName = &""
@export var name_key: StringName = &""
@export var desc_key: StringName = &""

## Stats at the curve's first level.
@export var stats: StatBlock = null
## Added per level above the first: whole points of max_hp / attack / defense (`move_speed`
## is ignored — a companion that outgrows its owner's pace stops being a companion).
@export var growth: StatBlock = null
## The curve this pet levels on (XP -> level). Its own resource, so a pet can grow at its own
## pace without touching the player's curve.
@export var progression_curve: ProgressionCurveData = null
## The share of a defeated enemy's XP the pet earns while it is out, in whole percent.
@export_range(0, 100) var xp_share_percent: int = 50

## Technique ids the pet knows (the P15 technique model; `SYSTEM_DEPENDENCY_MATRIX` P15 -> P16).
## May be empty: the first frontier companion only bites.
@export var skills: Array[StringName] = []

## How it behaves beside its owner (an ally `AiProfileData`: `follow_radius` > 0).
@export var ai_profile: AiProfileData = null
## Its attack, resolved by the session's `CombatService` like every other attack.
@export var attack: AttackData = null
## How close it closes before swinging. Must not exceed the attack's reach.
@export var engage_distance: float = 20.0
## Damageable radius (`HurtboxComponent.radius`).
@export var hurt_radius: float = 9.0
@export var visual_profile: CharacterVisualProfileData = null
## Seconds before a pet that fell in a fight can be called again.
@export var recall_seconds: float = 12.0


func is_valid() -> bool:
	return validation_errors().is_empty()


## Every reason this definition is unusable ([] when it is fine). `technique_ids` is the set of
## known technique ids to validate `skills` against (empty = the caller has no catalog to check
## with, and only the shape is validated).
func validation_errors(technique_ids: Array[StringName] = []) -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id is empty")
	elif not String(id).begins_with("pet_"):
		errors.append("id '%s' must use the pet_ prefix" % id)
	if name_key == &"":
		errors.append("name_key is empty")
	if desc_key == &"":
		errors.append("desc_key is empty")
	if stats == null:
		errors.append("stats is null")
	else:
		for problem in stats.validation_errors():
			errors.append("stats: %s" % problem)
		if stats.move_speed <= 0.0:
			errors.append("stats.move_speed must be > 0 or the pet cannot follow")
	if growth == null:
		errors.append("growth is null (author a zero block for a pet that does not grow)")
	elif growth.max_hp < 0 or growth.attack < 0 or growth.defense < 0:
		errors.append("growth must not be negative: a pet never weakens by levelling")
	if progression_curve == null:
		errors.append("progression_curve is null")
	else:
		for problem in progression_curve.validation_errors():
			errors.append("progression_curve: %s" % problem)
	if xp_share_percent < 0 or xp_share_percent > 100:
		errors.append("xp_share_percent must be in [0, 100] (got %d)" % xp_share_percent)
	var seen: Dictionary = {}
	for skill in skills:
		if skill == &"":
			errors.append("skills holds an empty id")
		elif seen.has(skill):
			errors.append("skills lists '%s' twice" % skill)
		elif not technique_ids.is_empty() and not technique_ids.has(skill):
			errors.append("skill '%s' is not in the technique catalog" % skill)
		seen[skill] = true
	if ai_profile == null:
		errors.append("ai_profile is null")
	elif not ai_profile.is_valid():
		errors.append("ai_profile '%s' is invalid" % ai_profile.id)
	elif ai_profile.follow_radius <= 0.0:
		errors.append("ai_profile '%s' has no follow_radius, so the pet would not follow"
			% ai_profile.id)
	if attack == null:
		errors.append("attack is null")
	elif not attack.validation_errors().is_empty():
		errors.append("attack '%s' is invalid" % attack.id)
	if engage_distance <= 0.0:
		errors.append("engage_distance must be > 0 (got %.1f)" % engage_distance)
	elif attack != null and engage_distance > attack.reach_pixels:
		errors.append("engage_distance (%.1f) exceeds the attack's reach (%.1f)"
			% [engage_distance, attack.reach_pixels])
	if hurt_radius <= 0.0:
		errors.append("hurt_radius must be > 0 (got %.1f)" % hurt_radius)
	if visual_profile == null:
		errors.append("visual_profile is null (it would render as nothing)")
	elif not visual_profile.is_valid():
		errors.append("visual_profile '%s' is invalid" % visual_profile.id)
	if recall_seconds < 0.0:
		errors.append("recall_seconds must be >= 0 (got %.1f)" % recall_seconds)
	return errors


## The level a total XP is worth on this pet's curve (the curve's first level when unusable).
func level_for_xp(total_xp: int) -> int:
	if progression_curve == null:
		return 1
	return progression_curve.level_for_xp(total_xp)


## The pet's stats at `level`: base + growth per level above the curve's first. A NEW block —
## the authored resources are never mutated.
func stats_at(level: int) -> StatBlock:
	var out := StatBlock.new()
	if stats == null:
		return out
	var first := progression_curve.min_level if progression_curve != null else 1
	var steps: int = maxi(0, level - first)
	out.max_hp = stats.max_hp + (growth.max_hp * steps if growth != null else 0)
	out.attack = stats.attack + (growth.attack * steps if growth != null else 0)
	out.defense = stats.defense + (growth.defense * steps if growth != null else 0)
	out.move_speed = stats.move_speed
	return out
