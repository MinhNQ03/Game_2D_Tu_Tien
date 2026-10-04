extends RefCounted
class_name FactionState
## FactionState — Aetheria domain (authoritative instance of one internal sect faction).
##
## The authoritative, serializable, presentation-free state of one faction inside a sect
## (`docs/SECT_SYSTEM.md` §7, D-011/D-042). Built from a `FactionTemplateData` via
## `create_from_template()`; mutated ONLY through `FactionService` (the single mutation path).
##
## Pure domain `RefCounted` — no Node/scene/presentation dependency, and no emblem path (that
## is a template-level presentation ref the UI resolves, never domain state).
##
## MEMBERSHIP IS A SUBSET, NOT A SOURCE OF TRUTH.
## The PARENT SECT's roster is the single membership authority (D-015). `_member_refs` here
## records which of those sect members have additionally taken a side, so it is always a
## subset of the sect roster, and `FactionService` is what enforces that — this class holds no
## reference to the sect store and cannot check it. A character's `CharacterState.faction_id`
## is a DERIVED cache the service writes, exactly as `sect_id` is. On any disagreement the
## sect roster wins, then this roster, then the cache.
##
## WHAT IS DELIBERATELY ABSENT
##   * No attitude dictionaries. §7 sketched `attitude_toward_player` and
##     `attitudes_toward_factions` as inline scalars and left the choice open; D-042 pins them
##     to RELATIONSHIP EDGES, since `affinity`/`rivalry` are two of the six frozen dimensions
##     (CL-12) and a copy here would be a second source of truth for the same question.
##   * No goal MUTATORS. The pursued goal ids are seeded from the template and serialized
##     (§7 requires them in the persistent tier), with a read-only accessor — but nothing
##     changes them yet, so no writer exists. The phase that first needs a faction to adopt
##     or abandon a goal adds the writer and its service verb together (L-005: no API without
##     a real producer AND consumer).
##   * No stance mutator, for the same reason: seeded, serialized, read-only until a producer
##     exists.
##   * No RNG. Every ordering this class produces comes from an explicit sort. The
##     deterministic RNG seam belongs to Phase 08 (D-040) and Phase 07 must not anticipate it.

# --- Identity (persistent) ---------------------------------------------------

## Unique faction id within a save (matches the `FactionTemplateData.id` it was built from).
var id: StringName = &""

## The `FactionTemplateData.id` this instance was built from (content reference).
var template_id: StringName = &""

## The sect this faction is internal to. Never empty on a validly built state.
var parent_sect_id: StringName = &""


# --- Leadership + roster (persistent; a SUBSET of the parent sect's roster) --

## The faction leader's character `instance_id` (&"" = no leader — the shipped state, since
## Phase 07 authors no NPCs). MUST be in `_member_refs` when set.
var leader_ref: StringName = &""

## Character `instance_id`s who have taken this faction's side.
var _member_refs: Array[StringName] = []


# --- Politics (persistent) ---------------------------------------------------

## Weight within the parent sect, in [INFLUENCE_MIN, INFLUENCE_MAX]. This is the one
## political value Phase 07 actually moves, and it is what the derived rules read
## (`FactionService.influence_share` / `dominant_faction_of` / `is_contested`).
var influence: int = 0

## `FactionTemplateData.Stance` as an int (the domain stores the value, not the data enum, so
## it never imports the data class's symbols at runtime).
var stance: int = 0

## Authored goal ids this faction pursues (see the class note: read-only for now).
var _goal_ids: Array[StringName] = []

## Faction-controlled holdings `{ resource_id(String) -> quantity(int >= 0) }`.
var _resources: Dictionary = {}


# --- Declared internal politics (mirrored to relationship edges by the service) ---

var _allied_faction_ids: Array[StringName] = []
var _rival_faction_ids: Array[StringName] = []


# --- Range contract (mirrors FactionTemplateData) ----------------------------
const INFLUENCE_MIN := 0
const INFLUENCE_MAX := 100


# --- Construction ------------------------------------------------------------

## Build an authoritative FactionState from a validated template. Fails LOUD + returns null on
## a missing/invalid template so the caller fails closed. Leadership and roster start EMPTY —
## taking a side always flows through the service, which is the only thing that can check the
## parent sect's roster.
static func create_from_template(template: FactionTemplateData) -> FactionState:
	if template == null:
		push_error("[faction] create_from_template with null template")
		return null
	if not template.is_valid():
		push_error("[faction] invalid template: %s" % str(template.validation_errors()))
		return null
	var state := FactionState.new()
	state.id = template.id
	state.template_id = template.id
	state.parent_sect_id = template.parent_sect_id
	state.stance = int(template.stance)
	state.write_influence(template.influence_seed)
	for goal_id in template.goal_ids():
		state.insert_goal(goal_id)
	for key in template.starting_resources:
		state.write_resource(StringName(String(key)), int(template.starting_resources[key]))
	for other in template.default_allied_faction_ids:
		state.insert_allied(other)
	for other in template.default_rival_faction_ids:
		state.insert_rival(other)
	return state


# --- Read-only accessors (COPIES; callers never get the internal collection) -

## Every member's instance_id, sorted (deterministic).
func member_refs() -> Array[StringName]:
	var out: Array[StringName] = []
	for member in _member_refs:
		out.append(member)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b))
	return out


func member_count() -> int:
	return _member_refs.size()


func is_member(character_id: StringName) -> bool:
	return _member_refs.has(character_id)


func goal_ids() -> Array[StringName]:
	return _goal_ids.duplicate()


func pursues_goal(goal_id: StringName) -> bool:
	return _goal_ids.has(goal_id)


func resources() -> Dictionary:
	return _resources.duplicate()


func get_resource(resource_id: StringName) -> int:
	return int(_resources.get(String(resource_id), 0))


func allied_faction_ids() -> Array[StringName]:
	return _allied_faction_ids.duplicate()


func rival_faction_ids() -> Array[StringName]:
	return _rival_faction_ids.duplicate()


func is_allied_with(faction_id: StringName) -> bool:
	return _allied_faction_ids.has(faction_id)


func is_rival_of(faction_id: StringName) -> bool:
	return _rival_faction_ids.has(faction_id)


# --- Raw writers (SERVICE-ONLY) ----------------------------------------------
#
# RAW writes with NO validation: every invariant, clamp and rollback lives in
# `FactionService`, the single mutation path. Named `write_*`/`insert_*`/`erase_*` so they
# read as low-level storage operations and never shadow the validated service verbs — if you
# are calling one of these from outside the faction domain, you are bypassing the rules.
#
# PUBLIC on purpose, for the reason recorded in D-033: GDScript has no package visibility, so
# `_`-prefixing them would force the owning service to violate its own privacy on every
# mutation (which `tools/gdscript_lint.py` GD002 then flags). The real guard is the
# single-mutation-path invariant, enforced by review + tests, not by a prefix.

func insert_member(character_id: StringName) -> void:
	if not _member_refs.has(character_id):
		_member_refs.append(character_id)


func erase_member(character_id: StringName) -> void:
	_member_refs.erase(character_id)
	if leader_ref == character_id:
		leader_ref = &""


func write_leader(character_id: StringName) -> void:
	leader_ref = character_id


func write_influence(value: int) -> void:
	influence = clampi(value, INFLUENCE_MIN, INFLUENCE_MAX)


func insert_goal(goal_id: StringName) -> void:
	if not _goal_ids.has(goal_id):
		_goal_ids.append(goal_id)


func write_resource(resource_id: StringName, quantity: int) -> void:
	_resources[String(resource_id)] = maxi(0, quantity)


func insert_allied(faction_id: StringName) -> void:
	if not _allied_faction_ids.has(faction_id):
		_allied_faction_ids.append(faction_id)


func erase_allied(faction_id: StringName) -> void:
	_allied_faction_ids.erase(faction_id)


func insert_rival(faction_id: StringName) -> void:
	if not _rival_faction_ids.has(faction_id):
		_rival_faction_ids.append(faction_id)


func erase_rival(faction_id: StringName) -> void:
	_rival_faction_ids.erase(faction_id)


# --- Serialization (PERSISTENT tier; deterministic) --------------------------

## Serialize to plain data. Deterministic: every list is emitted sorted so the snapshot is
## byte-stable. No Node/Texture/presentation.
func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"template_id": String(template_id),
		"parent_sect_id": String(parent_sect_id),
		"leader_ref": String(leader_ref),
		"member_refs": _sorted_string_names(_member_refs),
		"influence": influence,
		"stance": stance,
		"goal_ids": _sorted_string_names(_goal_ids),
		"resources": _resources.duplicate(),
		"allied_faction_ids": _sorted_string_names(_allied_faction_ids),
		"rival_faction_ids": _sorted_string_names(_rival_faction_ids),
	}


## Hydrate from plain data, validating at the boundary and FAILING CLOSED (returns false,
## leaves this instance BYTE-IDENTICAL) on any malformed entry.
##
## STRICT TYPES — every field is checked with `typeof()` BEFORE any conversion, and a wrong
## type is a rejection, never a coercion (L-024). GDScript's `String()`/`int()` do not fail,
## they INVENT: `String(100)` turns a number into the id `"100"`, `String(null)` turns a
## missing value into `""` which then reads as the legitimate "this faction has no leader"
## rather than "this payload is corrupt", and `int("60")`/`int(60.0)` turn text and a float
## into an influence weight. Each silently converts a corrupt save into an accepted state.
## So every ID-like field must be a String/StringName, and every COUNT-like field must be
## TYPE_INT (a float is rejected even when integral).
##
## Invariants enforced: non-empty id and parent_sect_id; id != parent_sect_id; unique
## non-empty members; the leader (when set) is a member; influence in range; stance a known
## enum ordinal; resources int >= 0; allied/rival unique, not self, and disjoint.
func from_dict(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[faction] from_dict: payload is not a Dictionary")
		return false
	var dict: Dictionary = data

	if dict.has("id") and not _is_id_token(dict["id"]):
		push_error("[faction] from_dict: 'id' must be a String/StringName (got %s)"
			% type_string(typeof(dict["id"])))
		return false
	var in_id := StringName(String(dict.get("id", "")))
	if in_id == &"":
		push_error("[faction] from_dict: missing id")
		return false

	if dict.has("template_id") and not _is_id_token(dict["template_id"]):
		push_error("[faction] from_dict '%s': 'template_id' must be a String/StringName (got %s)"
			% [in_id, type_string(typeof(dict["template_id"]))])
		return false

	if dict.has("parent_sect_id") and not _is_id_token(dict["parent_sect_id"]):
		push_error("[faction] from_dict '%s': 'parent_sect_id' must be a String/StringName "
			% in_id + "(got %s)" % type_string(typeof(dict["parent_sect_id"])))
		return false
	var in_parent := StringName(String(dict.get("parent_sect_id", "")))
	if in_parent == &"":
		push_error("[faction] from_dict '%s': missing parent_sect_id" % in_id)
		return false
	if in_parent == in_id:
		push_error("[faction] from_dict '%s': parent_sect_id equals the faction id" % in_id)
		return false

	var staged_members: Variant = _parse_unique_id_array(dict.get("member_refs", []))
	if staged_members == null:
		push_error("[faction] from_dict '%s': malformed/duplicate member_refs" % in_id)
		return false

	if dict.has("leader_ref") and not _is_id_token(dict["leader_ref"]):
		push_error("[faction] from_dict '%s': 'leader_ref' must be a String/StringName (got %s)"
			% [in_id, type_string(typeof(dict["leader_ref"]))])
		return false
	var in_leader := StringName(String(dict.get("leader_ref", "")))
	if in_leader != &"" and not (staged_members as Array).has(in_leader):
		push_error("[faction] from_dict '%s': leader '%s' is not in member_refs"
			% [in_id, in_leader])
		return false

	var influence_value: Variant = dict.get("influence", 0)
	if typeof(influence_value) != TYPE_INT:
		push_error("[faction] from_dict '%s': influence must be an int (got %s)"
			% [in_id, type_string(typeof(influence_value))])
		return false
	var in_influence: int = influence_value
	if in_influence < INFLUENCE_MIN or in_influence > INFLUENCE_MAX:
		push_error("[faction] from_dict '%s': influence %d out of [%d,%d]"
			% [in_id, in_influence, INFLUENCE_MIN, INFLUENCE_MAX])
		return false

	var stance_value: Variant = dict.get("stance", 0)
	if typeof(stance_value) != TYPE_INT:
		push_error("[faction] from_dict '%s': stance must be an int (got %s)"
			% [in_id, type_string(typeof(stance_value))])
		return false
	var in_stance: int = stance_value
	if in_stance < 0 or in_stance >= FactionTemplateData.Stance.size():
		push_error("[faction] from_dict '%s': stance %d is not a known Stance ordinal"
			% [in_id, in_stance])
		return false

	var staged_goals: Variant = _parse_unique_id_array(dict.get("goal_ids", []))
	if staged_goals == null:
		push_error("[faction] from_dict '%s': malformed/duplicate goal_ids" % in_id)
		return false

	var resources_in: Variant = dict.get("resources", {})
	if typeof(resources_in) != TYPE_DICTIONARY:
		push_error("[faction] from_dict '%s': resources is not a Dictionary" % in_id)
		return false
	var staged_resources := {}
	for key in (resources_in as Dictionary):
		if not _is_id_token(key):
			push_error("[faction] from_dict '%s': resource id must be a String/StringName "
				% in_id + "(got %s)" % type_string(typeof(key)))
			return false
		if String(key) == "":
			push_error("[faction] from_dict '%s': empty resource id" % in_id)
			return false
		var qty: Variant = (resources_in as Dictionary)[key]
		if typeof(qty) != TYPE_INT:
			push_error("[faction] from_dict '%s': resource '%s' quantity must be an int (got %s)"
				% [in_id, String(key), type_string(typeof(qty))])
			return false
		var quantity: int = qty
		if quantity < 0:
			push_error("[faction] from_dict '%s': resource '%s' must be >= 0 (%d)"
				% [in_id, String(key), quantity])
			return false
		staged_resources[String(key)] = quantity

	var staged_allied: Variant = _parse_unique_id_array(dict.get("allied_faction_ids", []))
	var staged_rivals: Variant = _parse_unique_id_array(dict.get("rival_faction_ids", []))
	if staged_allied == null or staged_rivals == null:
		push_error("[faction] from_dict '%s': malformed/duplicate allied or rival list" % in_id)
		return false
	for other in (staged_allied as Array):
		if other == in_id:
			push_error("[faction] from_dict '%s': self in allied list" % in_id)
			return false
		if (staged_rivals as Array).has(other):
			push_error("[faction] from_dict '%s': '%s' is both allied and rival"
				% [in_id, other])
			return false
	for other in (staged_rivals as Array):
		if other == in_id:
			push_error("[faction] from_dict '%s': self in rival list" % in_id)
			return false

	# Commit atomically — no validation below this line.
	id = in_id
	template_id = StringName(String(dict.get("template_id", String(in_id))))
	parent_sect_id = in_parent
	leader_ref = in_leader
	_member_refs = staged_members as Array[StringName]
	influence = in_influence
	stance = in_stance
	_goal_ids = staged_goals as Array[StringName]
	_resources = staged_resources
	_allied_faction_ids = staged_allied as Array[StringName]
	_rival_faction_ids = staged_rivals as Array[StringName]
	return true


# --- Helpers -----------------------------------------------------------------

static func _sorted_string_names(arr: Array[StringName]) -> Array:
	var out: Array = []
	for item in arr:
		out.append(String(item))
	out.sort()
	return out


## Parse an Array of ids into a typed Array[StringName], rejecting empty/duplicate entries and
## any entry that is not already a String/StringName. Returns null on malformed input.
##
## The receiver at every call site MUST be declared `var x: Variant = ...`, never `:=`: this
## returns `Variant`, and `:=` would infer a Variant local, which this project's
## warnings-as-errors configuration rejects — breaking the whole file's compile and, because
## a non-compiling script never registers its `class_name`, producing the misleading
## "nonexistent function in base 'GDScript'" cascade at every call site (L-020).
static func _parse_unique_id_array(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		return null
	var out: Array[StringName] = []
	var seen := {}
	for item in (value as Array):
		if not _is_id_token(item):
			return null
		var s := String(item)
		if s == "":
			return null
		if seen.has(s):
			return null
		seen[s] = true
		out.append(StringName(s))
	return out


## True only for a String or StringName — the two types an authored/serialized ID may have.
## Everything else (int, float, bool, null, Object, Array, Dictionary) is REJECTED rather than
## converted, because `String(100)`, `String(null)` and `String(true)` all produce a
## syntactically valid id out of data that was never an id (L-024).
static func _is_id_token(value: Variant) -> bool:
	var t := typeof(value)
	return t == TYPE_STRING or t == TYPE_STRING_NAME
