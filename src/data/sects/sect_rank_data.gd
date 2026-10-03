extends Resource
class_name SectRankData
## SectRankData — Aetheria data (one rung of a sect's rank ladder, `sect_rank_*`).
##
## A DATA-ONLY definition of a single rank within a `SectTemplateData.rank_ladder`
## (`docs/SECT_SYSTEM.md` §4–§5). The rank vocabulary (Outer Disciple → Inner Disciple →
## … → Sect Master) is CONTENT, authored as ordered `SectRankData` entries — it is NEVER
## hard-coded in `SectService`/gameplay code (`04-coding-standards.md` no magic strings,
## `02-game-design.md` extensibility). A sect with a different ladder is a data edit only.
##
## `authority` is a comparable integer (higher = more authority) so promotion/leadership
## rules can order ranks without string matching. The ladder's ARRAY ORDER is the official
## progression; `authority` lets rules compare two ranks directly.
##
## Pure data: no behavior beyond boundary validation; no Node/presentation dependency.

## Stable rank id within THIS sect's ladder (e.g. `rank_outer`, `rank_elder`). Unique per
## ladder; never changes once shipped (changing it is a breaking content change).
@export var rank_id: StringName = &""

## Localization key for the rank's display name (never a literal string, `07-localization.md`).
@export var name_key: StringName = &""

## Authority weight — higher means more power inside the sect. Used by rules to order ranks
## (e.g. a leader must hold the highest authority). Must be >= 0.
@export var authority: int = 0


func is_valid() -> bool:
	return validation_errors().is_empty()


## Loud, specific boundary validation (content from disk is external input).
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if rank_id == &"":
		errors.append("rank_id must be non-empty")
	if name_key == &"":
		errors.append("name_key must be non-empty (every rank has a display name)")
	if authority < 0:
		errors.append("authority must be >= 0 (got %d)" % authority)
	return errors
