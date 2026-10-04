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

## Markers for WHICH list a declaration came from, used only by the pair-symmetry check.
## Deliberately NOT a reference to the RelationshipService edge-type vocabulary: `SectCatalog`
## is DATA and must not depend on the domain layer (`03-architecture.md` — dependencies point
## downward/inward). The domain owns the mapping from "declared ally" to an ALLY edge; these
## two names exist so the validation errors read in the author's language.
const REL_ALLY := &"ALLY"
const REL_ENEMY := &"ENEMY"


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
	# pair_key("a","b") -> { "a": &"ALLY"/&"ENEMY", "b": ... } — what each SIDE declared.
	var pairs := {}
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
				continue
			_record_declaration(pairs, sid, aid, REL_ALLY)
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
				continue
			_record_declaration(pairs, sid, eid, REL_ENEMY)
	_validate_pair_symmetry(errors, pairs)


## Record "`from` declares `relation` toward `to`" under the pair's CANONICAL key.
static func _record_declaration(
		pairs: Dictionary, from_id: String, to_id: String, relation: StringName) -> void:
	var key := _pair_key(from_id, to_id)
	if not pairs.has(key):
		pairs[key] = {}
	(pairs[key] as Dictionary)[from_id] = relation


## Canonical key for an UNORDERED pair: the two ids sorted, so A→B and B→A land on the SAME
## entry. This is what makes the symmetry check order-independent — the authored order of
## `sects` (and of each sect's lists) can never decide the outcome.
static func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a <= b else "%s|%s" % [b, a]


## A default diplomacy declaration is a SYMMETRIC authored relation: it describes a mutual
## standing between two sects, and `SectService` mirrors it as ONE symmetric Sect↔Sect edge
## per pair. So a one-sided or contradictory declaration is not a half-truth to be resolved,
## it is a content bug:
##   * `A ALLY B` with B saying nothing about A would mirror an edge that only one sect's
##     state records — the sect store and the relationship graph disagree from the first frame;
##   * `A ALLY B` + `B ENEMY A` has no correct answer at all, and because the mirror writes
##     one edge per pair, the WINNER would be decided by iteration order (whichever sect the
##     catalog happens to list last). Validation must reject it rather than let authoring
##     order pick a relationship type.
## Both sides declaring the same relation, or neither side declaring anything, are accepted.
func _validate_pair_symmetry(errors: Array[String], pairs: Dictionary) -> void:
	var keys := pairs.keys()
	keys.sort()  # deterministic error order, independent of Dictionary iteration
	for key in keys:
		var sides: Dictionary = pairs[key]
		var ids: Array = sides.keys()
		ids.sort()
		if ids.size() == 1:
			var only := String(ids[0])
			var other := _other_in_pair(String(key), only)
			errors.append(
				"sect '%s' declares '%s' as a default %s but '%s' declares nothing about "
				% [only, other, String(sides[only]).to_lower(), other]
				+ "'%s' - default diplomacy must be declared on BOTH sects" % only)
			continue
		var first := String(ids[0])
		var second := String(ids[1])
		if sides[first] != sides[second]:
			errors.append(
				"sects '%s' and '%s' declare CONFLICTING default diplomacy ('%s' vs '%s') - "
				% [first, second, String(sides[first]), String(sides[second])]
				+ "one symmetric edge per pair cannot be both")


## Given a canonical pair key and one of its ids, return the other id.
static func _other_in_pair(key: String, known: String) -> String:
	var parts := key.split("|", true, 1)
	if parts.size() != 2:
		return ""
	return String(parts[1]) if String(parts[0]) == known else String(parts[0])


## The SectTemplateData for `sect_id`, or null.
func find_sect(sect_id: StringName) -> SectTemplateData:
	for tmpl in sects:
		if tmpl != null and tmpl.id == sect_id:
			return tmpl
	return null
