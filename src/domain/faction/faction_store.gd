extends RefCounted
class_name FactionStore
## FactionStore — Aetheria domain (the collection of authoritative faction states).
##
## Mirrors `SectStore`, plus ONE extra index. Every interesting faction question is "which
## factions belong to this sect?" (the politics of a sect are computed over its own factions,
## and the UI shows one sect's landscape), so a `sect_id -> [faction_id]` index is maintained
## alongside the id map. Without it, every influence-share and dominance query would scan the
## whole store — and those are read on every panel refresh (`05-performance-testing.md`:
## avoid full scans on a path the UI touches).
##
## Pure domain `RefCounted`: no Node, no signals, no rules. `FactionService` is the mutation
## path and the observable surface. The store never exposes its internal dictionaries.

var _by_id: Dictionary = {}     # String(faction_id) -> FactionState
var _by_sect: Dictionary = {}   # String(sect_id)    -> Array[String faction_id]


func count() -> int:
	return _by_id.size()


func has(faction_id: StringName) -> bool:
	return _by_id.has(String(faction_id))


func get_faction(faction_id: StringName) -> FactionState:
	return _by_id.get(String(faction_id))


## Insert a faction. Rejects (false, loud) a null state, an empty id, an empty parent sect id,
## or a duplicate id. Keeps the per-sect index in step.
func add(state: FactionState) -> bool:
	if state == null:
		push_error("[faction] store.add got null state")
		return false
	if state.id == &"":
		push_error("[faction] store.add: faction has an empty id")
		return false
	if state.parent_sect_id == &"":
		push_error("[faction] store.add '%s': faction has an empty parent_sect_id" % state.id)
		return false
	var key := String(state.id)
	if _by_id.has(key):
		push_error("[faction] store.add: duplicate faction id '%s'" % key)
		return false
	_by_id[key] = state
	var sect_key := String(state.parent_sect_id)
	if not _by_sect.has(sect_key):
		_by_sect[sect_key] = []
	(_by_sect[sect_key] as Array).append(key)
	return true


## Remove a faction by id, keeping the per-sect index consistent. True if one was removed.
func remove(faction_id: StringName) -> bool:
	var key := String(faction_id)
	var state: FactionState = _by_id.get(key)
	if state == null:
		return false
	_by_id.erase(key)
	var sect_key := String(state.parent_sect_id)
	if _by_sect.has(sect_key):
		var ids: Array = _by_sect[sect_key]
		ids.erase(key)
		if ids.is_empty():
			_by_sect.erase(sect_key)
	return true


## All faction ids, sorted (deterministic).
func ids_sorted() -> Array:
	var keys := _by_id.keys()
	keys.sort()
	return keys


## Every faction, in `ids_sorted()` order, as a fresh Array.
func all() -> Array:
	var out: Array = []
	for key in ids_sorted():
		out.append(_by_id[key])
	return out


## Every faction belonging to `sect_id`, in deterministic id order. Indexed — no full scan.
func factions_of_sect(sect_id: StringName) -> Array:
	var ids: Array = _by_sect.get(String(sect_id), [])
	var sorted := ids.duplicate()
	sorted.sort()
	var out: Array = []
	for key in sorted:
		out.append(_by_id[key])
	return out


## The faction (within `sect_id`) that `character_id` belongs to, or null.
##
## A character may hold at most ONE faction seat per sect — the invariant `FactionService`
## enforces on join — which is what makes `CharacterState.faction_id` a single-value cache
## rather than a list. This lookup is how the service checks that invariant and how the view
## resolves "which side is the player on".
func faction_of_member(sect_id: StringName, character_id: StringName) -> FactionState:
	for faction in factions_of_sect(sect_id):
		var f := faction as FactionState
		if f.is_member(character_id):
			return f
	return null


## Every distinct parent sect id present in the store, sorted (deterministic).
func sect_ids_sorted() -> Array:
	var keys := _by_sect.keys()
	keys.sort()
	return keys


# --- Serialization (deterministic) + hydrate (fail-closed) -------------------

## Serialize the whole collection. Factions emitted in sorted id order so the snapshot is
## byte-stable.
func to_dict() -> Dictionary:
	var listed := []
	for key in ids_sorted():
		listed.append((_by_id[key] as FactionState).to_dict())
	return {"factions": listed}


## Replace the whole collection from plain data, FAILING CLOSED: on any malformed entry the
## store is left byte-identical (staged, then committed). Rejects a non-dict payload, a
## non-array `factions`, an entry that fails `FactionState.from_dict`, or a duplicate id.
##
## It deliberately does NOT check that a hydrated faction's `parent_sect_id` names a real
## sect: this store cannot see the sect store. `FactionService.validate_against_sects()` is
## the owner of that cross-store check, and the session start calls it — so a save that
## references a vanished sect is caught, just not here.
func hydrate(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[faction] hydrate: payload is not a Dictionary")
		return false
	var listed: Variant = (data as Dictionary).get("factions", [])
	if typeof(listed) != TYPE_ARRAY:
		push_error("[faction] hydrate: 'factions' is not an Array")
		return false

	var staged_by_id := {}
	var staged_by_sect := {}
	for entry in (listed as Array):
		var state := FactionState.new()
		if not state.from_dict(entry):
			push_error("[faction] hydrate: malformed faction entry")
			return false
		var key := String(state.id)
		if staged_by_id.has(key):
			push_error("[faction] hydrate: duplicate faction id '%s'" % key)
			return false
		staged_by_id[key] = state
		var sect_key := String(state.parent_sect_id)
		if not staged_by_sect.has(sect_key):
			staged_by_sect[sect_key] = []
		(staged_by_sect[sect_key] as Array).append(key)

	# Commit atomically.
	_by_id = staged_by_id
	_by_sect = staged_by_sect
	return true
