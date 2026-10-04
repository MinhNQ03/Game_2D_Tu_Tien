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
## resolves; the player start rank (if set) exists in that sect's ladder; and every DECLARED
## default ally/enemy reference is referentially sound across the catalog (see
## `_validate_declared_diplomacy`).
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
	_validate_declared_diplomacy(errors, seen)
	return errors


## Referential integrity for each sect's `default_ally_sect_ids` / `default_enemy_sect_ids`.
##
## A sect template can only check the SHAPE of its own two lists (non-self, unique, disjoint).
## Whether a referenced id actually EXISTS is a question only the catalog can answer, and it
## is the one that used to be answered by silently skipping: a dangling reference like
## `default_enemy_sect_ids = [&"sect_ghost"]` was dropped at mirror time, so the session
## started with a sect whose state declared an enemy that no relationship edge recorded and no
## sect in the world matched. A declared relationship with a sect that does not exist is a
## CONTENT BUG, so it invalidates the catalog and `SectRuntime` refuses to load it (rather
## than booting a world that quietly disagrees with its own data).
##
## `present_ids` is the set of valid, non-duplicate sect ids collected above (String keys);
## templates that already failed their own validation are not re-reported here.
func _validate_declared_diplomacy(errors: Array[String], present_ids: Dictionary) -> void:
	for tmpl in sects:
		if tmpl == null or not tmpl.is_valid():
			continue  # its own errors are already reported
		var sid := String(tmpl.id)
		var allies := {}
		for a in tmpl.default_ally_sect_ids:
			var aid := String(a)
			if aid == sid:
				errors.append("sect '%s' declares ITSELF as a default ally" % sid)
				continue
			if allies.has(aid):
				errors.append("sect '%s' declares duplicate default ally '%s'" % [sid, aid])
				continue
			allies[aid] = true
			if not present_ids.has(aid):
				errors.append("sect '%s' declares default ally '%s' which is not in the catalog"
					% [sid, aid])
		var enemies := {}
		for e in tmpl.default_enemy_sect_ids:
			var eid := String(e)
			if eid == sid:
				errors.append("sect '%s' declares ITSELF as a default enemy" % sid)
				continue
			if enemies.has(eid):
				errors.append("sect '%s' declares duplicate default enemy '%s'" % [sid, eid])
				continue
			enemies[eid] = true
			if allies.has(eid):
				errors.append("sect '%s' declares '%s' as BOTH a default ally and enemy"
					% [sid, eid])
				continue
			if not present_ids.has(eid):
				errors.append("sect '%s' declares default enemy '%s' which is not in the catalog"
					% [sid, eid])


## The SectTemplateData for `sect_id`, or null.
func find_sect(sect_id: StringName) -> SectTemplateData:
	for tmpl in sects:
		if tmpl != null and tmpl.id == sect_id:
			return tmpl
	return null
