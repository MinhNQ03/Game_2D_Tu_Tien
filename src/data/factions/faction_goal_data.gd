extends Resource
class_name FactionGoalData
## FactionGoalData — Aetheria data (one structured goal a faction pursues).
##
## `docs/SECT_SYSTEM.md` §7 specifies faction `goals` as "structured goals (power, doctrine,
## secession, …)" — explicitly NOT free text and NOT a pile of per-faction booleans. This is
## that structure: a stable id, a localization key, a closed-set KIND, and a priority.
##
## Why a Resource rather than a Dictionary entry: a goal is content that must be
## boundary-validated and authored in the editor, exactly like `SectRankData`. A Dictionary
## would push validation into every consumer and let a typo invent a goal kind at runtime.
##
## It carries NO behaviour and NO rules. What a goal *causes* is decided by the systems that
## read it (politics outcomes here, world simulation at P-08, quests later) — a goal is a
## stated intention, not an effect. Pure data (`03-architecture.md`).

## The closed set of things a faction can want. A closed enum, not a free `StringName`, so
## content cannot author a goal kind that no rule handles (same reasoning as
## `SectTemplateData.SectType`).
##
## The five are deliberately the ones the shipped canon needs and no more
## (`03-architecture.md` anti-over-engineering — a sixth is added by the phase that needs it):
##   AUTHORITY  — win control of the parent sect's leadership/decisions.
##   DOCTRINE   — make the sect's teaching/practice match this faction's reading of it.
##   RESOURCES  — enlarge this faction's share of the sect's allocation.
##   EXPANSION  — grow the sect's reach outward (territory, frontier, outside ties).
##   SECESSION  — leave, and take members/holdings along.
enum GoalKind { AUTHORITY, DOCTRINE, RESOURCES, EXPANSION, SECESSION }

## Stable content id, unique within one faction's goal list (`goal_*`).
@export var goal_id: StringName = &""

## Localization key for the goal's display text. Required — no hard-coded user-facing string
## ever reaches the screen (`07-localization.md`).
@export var name_key: StringName = &""

@export var kind: GoalKind = GoalKind.AUTHORITY

## How much this faction cares, relative to its OTHER goals. 1-based; higher = more
## important. Not comparable across factions (it is an internal ordering, not a world scalar).
@export var priority: int = 1


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if goal_id == &"":
		errors.append("goal_id must be non-empty")
	if name_key == &"":
		errors.append("name_key must be non-empty")
	if kind < 0 or kind >= GoalKind.size():
		errors.append("kind enum out of range (got %d)" % kind)
	if priority < 1:
		errors.append("priority must be >= 1 (got %d)" % priority)
	return errors
