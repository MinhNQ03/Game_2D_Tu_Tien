extends Resource
class_name SectCatalog
## SectCatalog — Aetheria data (the authored list of sects a session loads).
##
## A DATA-ONLY index of `SectTemplateData` resources (`docs/SECT_SYSTEM.md` §3). `SectRuntime`
## loads this ONE resource, validates it, and registers every listed sect — so adding a sect
## to the world is "author a `.tres` + add it to the catalog", no code edit (the extensibility
## invariant). It also names the PLAYER's starting sect + rank so membership is authored data,
## not a hard-coded id in gameplay code.
##
## Pure data: no behavior beyond boundary validation.

## The sect templates available this session.
@export var sects: Array[SectTemplateData] = []

## The sect the player begins as a member of (&"" = player starts with no sect). Must match a
## listed sect id when non-empty.
@export var player_start_sect_id: StringName = &""

## The rank the player joins at (&"" = the sect ladder's lowest rank). Must exist in that
## sect's ladder when non-empty.
@export var player_start_rank_id: StringName = &""


func is_valid() -> bool:
	return validation_errors().is_empty()


## Boundary validation: every listed sect valid + unique id; the player start sect (if set)
## resolves; the player start rank (if set) exists in that sect's ladder.
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if sects.is_empty():
		errors.append("catalog must list at least one sect")
	var seen := {}
	for i in sects.size():
		var tmpl := sects[i]
		if tmpl == null:
			errors.append("sects[%d] is null" % i)
			continue
		if not tmpl.is_valid():
			errors.append("sects[%d] invalid: %s" % [i, str(tmpl.validation_errors())])
			continue
		var sid := String(tmpl.id)
		if seen.has(sid):
			errors.append("duplicate sect id '%s' in catalog" % sid)
		seen[sid] = true
	if player_start_sect_id != &"":
		var start := find_sect(player_start_sect_id)
		if start == null:
			errors.append("player_start_sect_id '%s' not in catalog" % player_start_sect_id)
		elif player_start_rank_id != &"" and not start.has_rank(player_start_rank_id):
			errors.append("player_start_rank_id '%s' not in sect '%s' ladder" % [
				player_start_rank_id, player_start_sect_id])
	return errors


## The SectTemplateData for `sect_id`, or null.
func find_sect(sect_id: StringName) -> SectTemplateData:
	for tmpl in sects:
		if tmpl != null and tmpl.id == sect_id:
			return tmpl
	return null
