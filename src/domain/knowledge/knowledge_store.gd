extends RefCounted
class_name KnowledgeStore
## KnowledgeStore — Aetheria domain (THE authoritative collection of what the player knows,
## Phase 12 Knowledge Core, D-040 / C-012).
##
## Pure data + its persistence boundary. It records WHICH knowledge is held and WHERE it came
## from (the source id — a stele, a dialogue, a perception), never how it is presented.
##
## ONE MUTATOR. `record()` is the storage boundary and `KnowledgeService.grant()` is the only
## semantic mutation authority — the same split as `CharacterState.set_total_xp` and
## `ProgressionService.grant_xp` (D-055). Story, quest and dialogue never call `record()`;
## `tests/unit/knowledge/test_knowledge_authority.gd` walks `src/` and fails if anything but
## the service does. Knowledge is never a private story flag.
##
## PERMANENT: there is no `forget`. Knowledge may later be SUPERSEDED (§7: it may be wrong), and
## that is a new piece of knowledge, not a deletion.

## knowledge id (StringName) -> source id (StringName), in acquisition order.
var _known: Dictionary = {}


func knows(knowledge_id: StringName) -> bool:
	return _known.has(knowledge_id)


## Where `knowledge_id` was learned, or &"" when it is not held.
func source_of(knowledge_id: StringName) -> StringName:
	return _known.get(knowledge_id, &"")


## Every held id, in the order it was acquired.
func known_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in _known:
		out.append(key)
	return out


func count() -> int:
	return _known.size()


## STORAGE BOUNDARY — see the class note. Returns false (and changes nothing) when the id is
## empty or already held, so a double grant can never record twice.
func record(knowledge_id: StringName, source_id: StringName) -> bool:
	if knowledge_id == &"" or _known.has(knowledge_id):
		return false
	_known[knowledge_id] = source_id
	return true


## The persistence boundary: `{ "known": [ { "id": ..., "source": ... }, ... ] }`, in acquisition
## order, plain Strings only (SAVE_FORMAT: knowledge serializes through its own to_dict).
func to_dict() -> Dictionary:
	var rows: Array = []
	for key: StringName in _known:
		rows.append({"id": String(key), "source": String(_known[key])})
	return {"known": rows}


## Hydrate from `to_dict()` output, validating at the boundary against `catalog`: a row naming
## knowledge the catalog does not contain, a duplicate, or a row of the wrong shape REJECTS the
## whole payload (returns false, store unchanged) — a save must not smuggle in a phantom entry.
func from_dict(data: Dictionary, catalog: KnowledgeCatalogData) -> bool:
	var rows: Variant = data.get("known", [])
	if typeof(rows) != TYPE_ARRAY:
		push_error("[knowledge] from_dict: 'known' must be an Array")
		return false
	var staged: Dictionary = {}
	for row: Variant in rows:
		if typeof(row) != TYPE_DICTIONARY:
			push_error("[knowledge] from_dict: a row is not a Dictionary")
			return false
		var raw_id: Variant = (row as Dictionary).get("id")
		var raw_source: Variant = (row as Dictionary).get("source", "")
		if typeof(raw_id) != TYPE_STRING or typeof(raw_source) != TYPE_STRING:
			push_error("[knowledge] from_dict: id/source must be Strings")
			return false
		var knowledge_id := StringName(raw_id)
		if catalog == null or not catalog.has(knowledge_id):
			push_error("[knowledge] from_dict: '%s' is not in the catalog" % raw_id)
			return false
		if staged.has(knowledge_id):
			push_error("[knowledge] from_dict: '%s' appears twice" % raw_id)
			return false
		staged[knowledge_id] = StringName(raw_source)
	_known = staged
	return true
