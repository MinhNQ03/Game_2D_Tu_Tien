extends RefCounted
class_name SectState
## SectState — Aetheria domain (authoritative sect instance).
##
## The single AUTHORITATIVE, serializable, presentation-free source of truth for one sect in
## a running game (`docs/SECT_SYSTEM.md` §3–§5, D-011/D-015). The ROSTER here
## (leader/elders/disciples + `rank_by_character`) is the source of truth for membership; a
## `CharacterState.sect_id`/`sect_rank` is only a DERIVED cache kept in sync by the
## `SectService` (D-015). On any disagreement, THIS roster wins.
##
## Pure domain `RefCounted` — NO Node/scene/presentation dependency (`03-architecture.md`:
## domain must not import presentation). It carries NO Sprite2D/Texture2D/emblem path (the
## emblem is a template-level PRESENTATION ref, resolved by the UI from the template, never
## stored here). Built from a `SectTemplateData` via `create_from_template()`.
##
## MUTATION DISCIPLINE: callers do NOT edit the arrays/dicts here directly; every change goes
## through `SectService` (the single mutation path, §9). The members exposed here are read via
## *copy* accessors so a caller cannot mutate internal collections behind the service's back.
## Writes go through the documented SERVICE-ONLY raw writers at the bottom of this file
## (`write_*` / `insert_*` / `erase_*`) - they do no validation, so calling one from outside
## the sect domain bypasses every invariant. They are public because GDScript has no
## package visibility (D-033); the invariant is enforced by review + tests, not a prefix.
##
## Phase 06 scope: identity, leadership, membership+rank, resources, territory, reputation,
## influence, declared allies/enemies. Factions/techniques/secrets/story-flags are NOT here
## (Phase 07+; no speculative fields — `03-architecture.md`).

# --- Identity (persistent) ---------------------------------------------------

## Unique sect id within a save (matches the `SectTemplateData.id` it was built from).
var id: StringName = &""

## The `SectTemplateData.id` this instance was built from (content reference).
var template_id: StringName = &""


# --- Leadership (persistent; subset of the roster) ---------------------------

## The leader's character `instance_id` (&"" = no leader). MUST be in the roster when set.
var leader_ref: StringName = &""

## Elder character `instance_id`s (a subset of the roster, disjoint from leader).
var _elder_refs: Array[StringName] = []


# --- Membership roster (persistent; AUTHORITATIVE, D-015) --------------------

## rank_by_character: character `instance_id`(String) -> rank_id(String). The KEYS are the
## canonical roster (every member appears exactly once); the VALUE is their rank.
var _rank_by_character: Dictionary = {}


# --- Economy / holdings (persistent) -----------------------------------------

## resources: resource_id(String) -> quantity(int >= 0).
var _resources: Dictionary = {}

## territory: controlled region ids (unique, non-empty).
var _territory: Array[StringName] = []

## reputation: scope(String) -> value(int in [REP_MIN, REP_MAX]).
var _reputation: Dictionary = {}

## Political influence in the wider world (int >= 0).
var influence: int = 0


# --- Declared diplomacy (persistent; mirrored to Relationship edges by service) ---

var _ally_sect_ids: Array[StringName] = []
var _enemy_sect_ids: Array[StringName] = []


# --- Range contract (mirrors SectTemplateData, §12) --------------------------
const REP_MIN := -100
const REP_MAX := 100


# --- Construction ------------------------------------------------------------

## Build an authoritative SectState from a validated template. Fails LOUD + returns null on a
## missing/invalid template (the caller fails closed). Leadership/membership start EMPTY — the
## service populates the roster (so membership always flows through the single mutation path);
## economy/territory/reputation/influence/diplomacy are seeded from the template.
static func create_from_template(template: SectTemplateData) -> SectState:
	if template == null:
		push_error("[sect] create_from_template with null template")
		return null
	if not template.is_valid():
		push_error("[sect] invalid template: %s" % str(template.validation_errors()))
		return null
	var state := SectState.new()
	state.id = template.id
	state.template_id = template.id
	# Seed economy through the raw writers (value copies - the state OWNS its numbers and
	# never writes back into the shared template Resource). Going through the writers rather
	# than touching the dicts/arrays directly keeps ALL storage mutation on one seam.
	for key in template.starting_resources:
		state.write_resource(StringName(String(key)), int(template.starting_resources[key]))
	for region in template.starting_territory:
		state.insert_territory(region)
	for scope in template.reputation_seed:
		state.write_reputation(
			StringName(String(scope)), int(template.reputation_seed[scope]))
	state.influence = template.influence_seed
	for ally in template.default_ally_sect_ids:
		state.insert_ally(ally)
	for enemy in template.default_enemy_sect_ids:
		state.insert_enemy(enemy)
	return state


# --- Read-only accessors (COPIES; callers never get the internal collection) -

func elder_refs() -> Array[StringName]:
	return _elder_refs.duplicate()


func disciple_refs() -> Array[StringName]:
	# Disciples = roster members who are neither the leader nor an elder.
	var out: Array[StringName] = []
	for key in _rank_by_character:
		var cid := StringName(String(key))
		if cid == leader_ref:
			continue
		if _elder_refs.has(cid):
			continue
		out.append(cid)
	return out


## Every member's instance_id (the canonical roster), sorted (deterministic).
func member_refs() -> Array[StringName]:
	var out: Array[StringName] = []
	var keys := _rank_by_character.keys()
	keys.sort()
	for key in keys:
		out.append(StringName(String(key)))
	return out


func member_count() -> int:
	return _rank_by_character.size()


func is_member(character_id: StringName) -> bool:
	return _rank_by_character.has(String(character_id))


## The rank_id of `character_id`, or &"" if not a member.
func rank_of(character_id: StringName) -> StringName:
	return StringName(String(_rank_by_character.get(String(character_id), "")))


func resources() -> Dictionary:
	return _resources.duplicate()


func get_resource(resource_id: StringName) -> int:
	return int(_resources.get(String(resource_id), 0))


func territory() -> Array[StringName]:
	return _territory.duplicate()


func controls_territory(region_id: StringName) -> bool:
	return _territory.has(region_id)


func reputation() -> Dictionary:
	return _reputation.duplicate()


func get_reputation(scope: StringName) -> int:
	return int(_reputation.get(String(scope), 0))


func ally_sect_ids() -> Array[StringName]:
	return _ally_sect_ids.duplicate()


func enemy_sect_ids() -> Array[StringName]:
	return _enemy_sect_ids.duplicate()


func is_ally(sect_id: StringName) -> bool:
	return _ally_sect_ids.has(sect_id)


func is_enemy(sect_id: StringName) -> bool:
	return _enemy_sect_ids.has(sect_id)


# --- Raw writers (SERVICE-ONLY) ----------------------------------------------
#
# These perform the RAW write with NO validation: every membership invariant, clamp and
# rollback lives in `SectService`, which is the single mutation path (§9). They are named
# `write_*` / `insert_*` / `erase_*` so they read as low-level storage operations and never
# shadow the validated service verbs (`join_member`, `add_alliance`, ...): if you are
# calling one of these from outside the sect domain, you are bypassing the rules.
#
# They are PUBLIC on purpose. GDScript has no package/friend visibility, so the previous
# `_`-prefixed form made `SectService` reach into another class's private API on every
# mutation (28 violations flagged by `tools/gdscript_lint.py` GD002, D-033). An underscore
# that the owning package must itself violate is not encapsulation, it is noise - so the
# seam is now explicit and documented instead of pretend-private. The real guard is the
# single-mutation-path invariant, enforced by review + the domain tests, not by a prefix.

func write_member_rank(character_id: StringName, rank_id: StringName) -> void:
	_rank_by_character[String(character_id)] = String(rank_id)


func erase_member(character_id: StringName) -> void:
	_rank_by_character.erase(String(character_id))
	_elder_refs.erase(character_id)
	if leader_ref == character_id:
		leader_ref = &""


func write_leader(character_id: StringName) -> void:
	leader_ref = character_id


func insert_elder(character_id: StringName) -> void:
	if not _elder_refs.has(character_id):
		_elder_refs.append(character_id)


func erase_elder(character_id: StringName) -> void:
	_elder_refs.erase(character_id)


func write_resource(resource_id: StringName, quantity: int) -> void:
	_resources[String(resource_id)] = maxi(0, quantity)


func write_reputation(scope: StringName, value: int) -> void:
	_reputation[String(scope)] = clampi(value, REP_MIN, REP_MAX)


func insert_territory(region_id: StringName) -> void:
	if not _territory.has(region_id):
		_territory.append(region_id)


func erase_territory(region_id: StringName) -> void:
	_territory.erase(region_id)


func insert_ally(sect_id: StringName) -> void:
	if not _ally_sect_ids.has(sect_id):
		_ally_sect_ids.append(sect_id)


func erase_ally(sect_id: StringName) -> void:
	_ally_sect_ids.erase(sect_id)


func insert_enemy(sect_id: StringName) -> void:
	if not _enemy_sect_ids.has(sect_id):
		_enemy_sect_ids.append(sect_id)


func erase_enemy(sect_id: StringName) -> void:
	_enemy_sect_ids.erase(sect_id)


# --- Serialization (PERSISTENT tier; deterministic) --------------------------

## Serialize to plain data (`docs/SECT_SYSTEM.md` §8). Deterministic: roster keys, elder
## list, territory, allies/enemies are emitted sorted so the snapshot is byte-stable. No
## Node/Texture/presentation (`03-architecture.md`).
func to_dict() -> Dictionary:
	var elders := _sorted_string_names(_elder_refs)
	var allies := _sorted_string_names(_ally_sect_ids)
	var enemies := _sorted_string_names(_enemy_sect_ids)
	var terr := _sorted_string_names(_territory)
	# rank_by_character emitted with sorted keys for a stable textual snapshot.
	var ranks := {}
	var member_keys := _rank_by_character.keys()
	member_keys.sort()
	for key in member_keys:
		ranks[String(key)] = String(_rank_by_character[key])
	return {
		"id": String(id),
		"template_id": String(template_id),
		"leader_ref": String(leader_ref),
		"elder_refs": elders,
		"rank_by_character": ranks,
		"resources": _resources.duplicate(),
		"territory": terr,
		"reputation": _reputation.duplicate(),
		"influence": influence,
		"ally_sect_ids": allies,
		"enemy_sect_ids": enemies,
	}


## Hydrate from plain data, validating at the boundary and FAILING CLOSED (returns false,
## leaves the state UNCHANGED) on any malformed entry (`04-coding-standards.md`: never
## reconstruct an impossible state). Checks: id present; roster is a dict of string->string;
## every member rank non-empty; leader (if set) and every elder are in the roster; no member
## is both leader and elder; resources int >= 0; reputation int in range; territory unique
## non-empty; ally/enemy unique and disjoint and not self.
func from_dict(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[sect] from_dict: payload is not a Dictionary")
		return false
	var dict: Dictionary = data
	var in_id := StringName(String(dict.get("id", "")))
	if in_id == &"":
		push_error("[sect] from_dict: missing id")
		return false

	# Roster.
	var ranks_in: Variant = dict.get("rank_by_character", {})
	if typeof(ranks_in) != TYPE_DICTIONARY:
		push_error("[sect] from_dict '%s': rank_by_character is not a Dictionary" % in_id)
		return false
	var staged_ranks := {}
	for key in (ranks_in as Dictionary):
		var cid := String(key)
		var rid := String((ranks_in as Dictionary)[key])
		if cid == "":
			push_error("[sect] from_dict '%s': empty member id in roster" % in_id)
			return false
		if rid == "":
			push_error("[sect] from_dict '%s': member '%s' has empty rank" % [in_id, cid])
			return false
		if staged_ranks.has(cid):
			push_error("[sect] from_dict '%s': duplicate member '%s'" % [in_id, cid])
			return false
		staged_ranks[cid] = rid

	# Leadership.
	var in_leader := StringName(String(dict.get("leader_ref", "")))
	if in_leader != &"" and not staged_ranks.has(String(in_leader)):
		push_error("[sect] from_dict '%s': leader '%s' not in roster" % [in_id, in_leader])
		return false
	var elders_in: Variant = dict.get("elder_refs", [])
	if typeof(elders_in) != TYPE_ARRAY:
		push_error("[sect] from_dict '%s': elder_refs is not an Array" % in_id)
		return false
	var staged_elders: Array[StringName] = []
	var elder_seen := {}
	for e in (elders_in as Array):
		var ecid := String(e)
		if ecid == "" or not staged_ranks.has(ecid):
			push_error("[sect] from_dict '%s': elder '%s' not in roster" % [in_id, ecid])
			return false
		if elder_seen.has(ecid):
			push_error("[sect] from_dict '%s': duplicate elder '%s'" % [in_id, ecid])
			return false
		if StringName(ecid) == in_leader:
			push_error("[sect] from_dict '%s': '%s' is both leader and elder" % [in_id, ecid])
			return false
		elder_seen[ecid] = true
		staged_elders.append(StringName(ecid))

	# Economy.
	var staged_resources := {}
	var resources_in: Variant = dict.get("resources", {})
	if typeof(resources_in) != TYPE_DICTIONARY:
		push_error("[sect] from_dict '%s': resources is not a Dictionary" % in_id)
		return false
	for key in (resources_in as Dictionary):
		var qty := int((resources_in as Dictionary)[key])
		if qty < 0:
			push_error("[sect] from_dict '%s': resource '%s' negative (%d)" % [in_id, key, qty])
			return false
		staged_resources[String(key)] = qty

	var staged_reputation := {}
	var reputation_in: Variant = dict.get("reputation", {})
	if typeof(reputation_in) != TYPE_DICTIONARY:
		push_error("[sect] from_dict '%s': reputation is not a Dictionary" % in_id)
		return false
	for scope in (reputation_in as Dictionary):
		var val := int((reputation_in as Dictionary)[scope])
		if val < REP_MIN or val > REP_MAX:
			push_error("[sect] from_dict '%s': reputation '%s' %d out of [%d,%d]" % [
				in_id, scope, val, REP_MIN, REP_MAX])
			return false
		staged_reputation[String(scope)] = val

	var in_influence := int(dict.get("influence", 0))
	if in_influence < 0:
		push_error("[sect] from_dict '%s': influence must be >= 0 (%d)" % [in_id, in_influence])
		return false

	var staged_territory: Variant = _parse_unique_id_array(dict.get("territory", []))
	if staged_territory == null:
		push_error("[sect] from_dict '%s': malformed/duplicate territory" % in_id)
		return false
	var staged_allies: Variant = _parse_unique_id_array(dict.get("ally_sect_ids", []))
	var staged_enemies: Variant = _parse_unique_id_array(dict.get("enemy_sect_ids", []))
	if staged_allies == null or staged_enemies == null:
		push_error("[sect] from_dict '%s': malformed/duplicate ally or enemy list" % in_id)
		return false
	for a in (staged_allies as Array):
		if a == in_id:
			push_error("[sect] from_dict '%s': self in ally list" % in_id)
			return false
		if (staged_enemies as Array).has(a):
			push_error("[sect] from_dict '%s': '%s' both ally and enemy" % [in_id, a])
			return false
	for en in (staged_enemies as Array):
		if en == in_id:
			push_error("[sect] from_dict '%s': self in enemy list" % in_id)
			return false

	# Commit atomically.
	id = in_id
	template_id = StringName(String(dict.get("template_id", String(in_id))))
	leader_ref = in_leader
	_elder_refs = staged_elders
	_rank_by_character = staged_ranks
	_resources = staged_resources
	_territory = staged_territory as Array[StringName]
	_reputation = staged_reputation
	influence = in_influence
	_ally_sect_ids = staged_allies as Array[StringName]
	_enemy_sect_ids = staged_enemies as Array[StringName]
	return true


# --- Helpers -----------------------------------------------------------------

static func _sorted_string_names(arr: Array[StringName]) -> Array:
	var out: Array = []
	for item in arr:
		out.append(String(item))
	out.sort()
	return out


## Parse an Array of ids into a typed Array[StringName], rejecting empty/duplicate entries.
## Returns null on malformed input (not an Array, empty id, or a duplicate).
static func _parse_unique_id_array(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		return null
	var out: Array[StringName] = []
	var seen := {}
	for item in (value as Array):
		var s := String(item)
		if s == "":
			return null
		if seen.has(s):
			return null
		seen[s] = true
		out.append(StringName(s))
	return out
