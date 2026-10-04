extends Resource
class_name FactionCatalog
## FactionCatalog — Aetheria data (every authored faction + the cross-template integrity
## checks a single template cannot perform).
##
## Mirrors `SectCatalog`: one template validates itself, and the catalog validates the things
## that only exist BETWEEN templates — unique ids, declared politics resolving to real
## factions, those factions sharing a parent sect, and pair symmetry. A dangling or one-sided
## declaration invalidates the whole catalog rather than being skipped at runtime, because
## skipping is what produces a session whose faction state claims a rivalry the relationship
## graph has no record of (the divergence D-038 had to fix for sect diplomacy).
##
## It does NOT validate that `parent_sect_id` names a real sect: the sect catalog is not
## visible from here. `FactionRuntime` is the first place the sect store and the faction
## catalog exist together, so that check lives there and fails the session.

## Author-language markers for the declared-politics relation, so this DATA class can express
## "allied"/"rival" in validation messages without importing the domain (the domain owns the
## real `REL_TYPE_*` edge vocabulary — `03-architecture.md` layer direction).
const REL_ALLIED := &"ALLIED"
const REL_RIVAL := &"RIVAL"

@export var factions: Array[FactionTemplateData] = []


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if factions.is_empty():
		errors.append("factions must have at least one entry")
		return errors

	var by_id := {}
	for i in factions.size():
		var tmpl := factions[i]
		if tmpl == null:
			errors.append("factions[%d] is null" % i)
			continue
		if not tmpl.is_valid():
			errors.append("factions[%d] ('%s') invalid: %s"
				% [i, String(tmpl.id), str(tmpl.validation_errors())])
			continue
		var fid := String(tmpl.id)
		if by_id.has(fid):
			errors.append("duplicate faction id '%s'" % fid)
			continue
		by_id[fid] = tmpl

	_validate_declared_politics(by_id, errors)
	return errors


## Every declared ally/rival must (a) exist in this catalog, (b) share the declaring
## faction's `parent_sect_id`, and (c) be declared the SAME way from the other side.
##
## (b) is the rule that makes this system "internal politics" rather than a second diplomacy
## system: a faction arguing with a faction in a DIFFERENT sect is not internal politics, it
## is the two sects' relationship, which `SectState`'s declared ally/enemy already owns. Left
## unchecked, content could quietly route cross-sect diplomacy through the faction graph and
## produce two independent answers to "are these two groups hostile".
func _validate_declared_politics(by_id: Dictionary, errors: Array[String]) -> void:
	# declaration[pair_key] = { declarer_id -> relation }
	var declarations := {}
	for fid in by_id:
		var tmpl: FactionTemplateData = by_id[fid]
		for other in tmpl.default_allied_faction_ids:
			_record(tmpl, other, REL_ALLIED, by_id, declarations, errors)
		for other in tmpl.default_rival_faction_ids:
			_record(tmpl, other, REL_RIVAL, by_id, declarations, errors)
	_validate_pair_symmetry(declarations, errors)


func _record(
		declarer: FactionTemplateData,
		other: StringName,
		relation: StringName,
		by_id: Dictionary,
		declarations: Dictionary,
		errors: Array[String]) -> void:
	var other_key := String(other)
	if not by_id.has(other_key):
		errors.append("faction '%s' declares %s with unknown faction '%s'"
			% [String(declarer.id), String(relation), other_key])
		return
	var other_tmpl: FactionTemplateData = by_id[other_key]
	if other_tmpl.parent_sect_id != declarer.parent_sect_id:
		errors.append(("faction '%s' (sect '%s') declares %s with '%s' (sect '%s'): internal "
			+ "politics must stay inside ONE sect — cross-sect standing is the sects' own "
			+ "declared diplomacy")
			% [String(declarer.id), String(declarer.parent_sect_id), String(relation),
				other_key, String(other_tmpl.parent_sect_id)])
		return
	var pair := pair_key(declarer.id, other)
	if not declarations.has(pair):
		declarations[pair] = {}
	var sides: Dictionary = declarations[pair]
	sides[String(declarer.id)] = relation


## A stable key for the UNORDERED faction pair, so the author's declaration order can never
## decide what the pair means.
static func pair_key(a: StringName, b: StringName) -> String:
	var sa := String(a)
	var sb := String(b)
	return "%s|%s" % [sa, sb] if sa <= sb else "%s|%s" % [sb, sa]


## A declared pair must agree from both sides. A one-sided declaration, or `A ALLIED B` with
## `B RIVAL A`, is a content bug: the runtime mirror creates ONE symmetric edge per pair, so
## the two declarations would fight over its type and whichever iterated last would win —
## i.e. the authored politics would depend on dictionary order.
func _validate_pair_symmetry(declarations: Dictionary, errors: Array[String]) -> void:
	var pairs := declarations.keys()
	pairs.sort()  # deterministic error order
	for pair in pairs:
		var sides: Dictionary = declarations[pair]
		var declarers: Array = sides.keys()
		declarers.sort()
		if declarers.size() < 2:
			errors.append(("faction '%s' declares %s with '%s' but it is not declared back; "
				+ "internal politics must be mutual")
				% [String(declarers[0]), String(sides[declarers[0]]),
					_other_in_pair(String(pair), String(declarers[0]))])
			continue
		var first: StringName = sides[declarers[0]]
		var second: StringName = sides[declarers[1]]
		if first != second:
			errors.append(("factions '%s' and '%s' disagree about their relation (%s vs %s)")
				% [String(declarers[0]), String(declarers[1]),
					String(first), String(second)])


static func _other_in_pair(pair: String, known: String) -> String:
	var parts := pair.split("|")
	if parts.size() != 2:
		return ""
	return parts[1] if parts[0] == known else parts[0]


# --- Lookups -----------------------------------------------------------------

func find_faction(faction_id: StringName) -> FactionTemplateData:
	for tmpl in factions:
		if tmpl != null and tmpl.id == faction_id:
			return tmpl
	return null


## Every authored faction belonging to `sect_id`, in deterministic id order.
func factions_of_sect(sect_id: StringName) -> Array[FactionTemplateData]:
	var matching: Array[FactionTemplateData] = []
	for tmpl in factions:
		if tmpl != null and tmpl.parent_sect_id == sect_id:
			matching.append(tmpl)
	matching.sort_custom(func(a: FactionTemplateData, b: FactionTemplateData) -> bool:
		return String(a.id) < String(b.id))
	return matching


## Every distinct parent sect id named by the catalog, sorted (deterministic).
func parent_sect_ids() -> Array[StringName]:
	var seen := {}
	for tmpl in factions:
		if tmpl != null and tmpl.parent_sect_id != &"":
			seen[String(tmpl.parent_sect_id)] = true
	var keys := seen.keys()
	keys.sort()
	var out: Array[StringName] = []
	for key in keys:
		out.append(StringName(key))
	return out
