extends RefCounted
class_name SectStore
## SectStore — Aetheria domain (the canonical collection of SectState).
##
## The SINGLE source of truth for all `SectState` instances in a session
## (`docs/SECT_SYSTEM.md` §8). Indexed by sect id so lookups are O(1), not full scans
## (`05-performance-testing.md`). Pure domain `RefCounted` — no Node/presentation/SceneTree.
##
## It owns STRUCTURE (which sects exist); it does NOT run membership/diplomacy rules — the
## `SectService` is the mutation path (§9). It never returns its raw internal dictionary; a
## caller gets the live `SectState` objects (to read via their copy-accessors) or a fresh
## array, never the index itself.

var _by_id: Dictionary = {}  # String(sect_id) -> SectState


func count() -> int:
	return _by_id.size()


func has(sect_id: StringName) -> bool:
	return _by_id.has(String(sect_id))


func get_sect(sect_id: StringName) -> SectState:
	return _by_id.get(String(sect_id))


## Insert a SectState. Rejects (returns false) a null state, an empty id, or a duplicate id.
func add(state: SectState) -> bool:
	if state == null or state.id == &"":
		push_error("[sect] store.add rejected: null state or empty id")
		return false
	var key := String(state.id)
	if _by_id.has(key):
		push_error("[sect] store.add rejected: duplicate sect id '%s'" % key)
		return false
	_by_id[key] = state
	return true


## Remove a sect by id. Returns true if one was removed.
func remove(sect_id: StringName) -> bool:
	return _by_id.erase(String(sect_id))


## All sect ids, sorted (deterministic) — for serialization + tests.
func ids_sorted() -> Array:
	var keys := _by_id.keys()
	keys.sort()
	return keys


## All SectState instances (fresh Array; order matches ids_sorted).
func all() -> Array:
	var out: Array = []
	for key in ids_sorted():
		out.append(_by_id[key])
	return out


# --- Serialization (deterministic snapshot) + hydrate (fail-closed) ----------

## Serialize the whole collection: `{ "sects": [ <SectState.to_dict> … ] }`, emitted sorted
## by id so the snapshot is byte-stable (`docs/SECT_SYSTEM.md` §8). No presentation.
func to_dict() -> Dictionary:
	var sects := []
	for key in ids_sorted():
		sects.append((_by_id[key] as SectState).to_dict())
	return {"sects": sects}


## Replace the whole collection from plain data, validating at the boundary and FAILING
## CLOSED (returns false, leaves the store UNCHANGED) on any malformed entry: non-dict
## payload, non-array `sects`, a sect that fails `SectState.from_dict`, or a duplicate id.
## Builds into a staging dict and commits only if the WHOLE payload is valid.
func hydrate(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[sect] store.hydrate: payload is not a Dictionary")
		return false
	var sects_in: Variant = (data as Dictionary).get("sects", [])
	if typeof(sects_in) != TYPE_ARRAY:
		push_error("[sect] store.hydrate: 'sects' is not an Array")
		return false
	var staged := {}
	for entry in (sects_in as Array):
		var state := SectState.new()
		if not state.from_dict(entry):
			return false  # from_dict already pushed a specific error
		var key := String(state.id)
		if staged.has(key):
			push_error("[sect] store.hydrate: duplicate sect id '%s'" % key)
			return false
		staged[key] = state
	_by_id = staged
	return true
