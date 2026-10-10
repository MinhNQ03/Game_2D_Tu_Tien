extends RefCounted
class_name PetStore
## PetStore — Aetheria domain (which pets the player owns, Phase 16).
##
## THE one persistent owner of pet state. Exactly three facts are persistent:
##   * which pets are OWNED (ids from the `PetCatalogData`, in the order they were acquired);
##   * each owned pet's cumulative XP — the ONLY progression truth; its level and stats are
##     DERIVED from it (`PetData.level_for_xp` / `stats_at`), never stored (D-064);
##   * which owned pet is ACTIVE (the one that walks with the player), or none.
##
## NOT here, by design: world position, current target, path or steering state, cooldowns and
## recall timers, health in a fight, node references, animation frames. Those are runtime
## (`PetRuntime`, the `Pet` entity) and are rebuilt, not saved.
##
## Mutated only through `PetService`. Pure data plus its plain-data boundary
## (`to_dict` / `from_dict`), which is what Phase 23's file-level save will call — no file is
## written here.

const SCHEMA := 1

## pet_id -> total XP, in acquisition order (a Dictionary preserves insertion order).
var _xp_by_pet: Dictionary = {}
var _active: StringName = &""


func owned_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in _xp_by_pet:
		out.append(key)
	return out


func owns(pet_id: StringName) -> bool:
	return _xp_by_pet.has(pet_id)


func owned_count() -> int:
	return _xp_by_pet.size()


## Total XP of an owned pet (0 for one that is not owned).
func xp_of(pet_id: StringName) -> int:
	return int(_xp_by_pet.get(pet_id, 0))


func active_id() -> StringName:
	return _active


# --- Narrow setters: the service validates, these keep the invariants -----------------------

## Add `pet_id` with no XP. False (no change) when already owned or the id is empty.
func add_owned(pet_id: StringName) -> bool:
	if pet_id == &"" or _xp_by_pet.has(pet_id):
		return false
	_xp_by_pet[pet_id] = 0
	return true


## Set an owned pet's total XP. False (no change) for an unowned pet or a negative total.
func set_xp(pet_id: StringName, total_xp: int) -> bool:
	if not _xp_by_pet.has(pet_id) or total_xp < 0:
		return false
	_xp_by_pet[pet_id] = total_xp
	return true


## Make an OWNED pet active, or clear with `&""`. False (no change) for a pet that is not owned.
func set_active(pet_id: StringName) -> bool:
	if pet_id != &"" and not _xp_by_pet.has(pet_id):
		return false
	_active = pet_id
	return true


# --- The plain-data boundary -------------------------------------------------------------------

## `{ schema, owned: [{ pet_id, xp }], active_pet }` — SAVE_FORMAT `pets`.
func to_dict() -> Dictionary:
	var owned: Array = []
	for key: StringName in _xp_by_pet:
		owned.append({"pet_id": String(key), "xp": int(_xp_by_pet[key])})
	return {"schema": SCHEMA, "owned": owned, "active_pet": String(_active)}


## Hydrate from `to_dict()` output, validated against `catalog`. The WHOLE payload is staged
## and checked before anything is committed: a wrong schema, a malformed shape or type, an
## unknown pet, a duplicate row, a negative XP or an active pet that is not owned rejects it
## all and leaves this store exactly as it was (L-024 type checks).
func from_dict(data: Dictionary, catalog: PetCatalogData) -> bool:
	if catalog == null:
		return _reject("no pet catalog to validate against")
	if typeof(data.get("schema")) != TYPE_INT or int(data["schema"]) != SCHEMA:
		return _reject("schema must be the int %d (got %s)" % [SCHEMA, str(data.get("schema"))])
	var rows: Variant = data.get("owned")
	if typeof(rows) != TYPE_ARRAY:
		return _reject("'owned' must be an Array")
	var raw_active: Variant = data.get("active_pet")
	if typeof(raw_active) != TYPE_STRING:
		return _reject("'active_pet' must be a String")
	var staged: Dictionary = {}
	for row: Variant in rows:
		if typeof(row) != TYPE_DICTIONARY:
			return _reject("an 'owned' row is not a Dictionary")
		var fields := row as Dictionary
		if fields.size() != 2 or typeof(fields.get("pet_id")) != TYPE_STRING \
				or typeof(fields.get("xp")) != TYPE_INT:
			return _reject("an 'owned' row must be exactly { pet_id: String, xp: int }")
		var pet_id := StringName(String(fields["pet_id"]))
		if not catalog.has(pet_id):
			return _reject("'%s' is not in the pet catalog" % pet_id)
		if staged.has(pet_id):
			return _reject("'%s' is owned twice" % pet_id)
		if int(fields["xp"]) < 0:
			return _reject("'%s' has a negative xp (%d)" % [pet_id, int(fields["xp"])])
		staged[pet_id] = int(fields["xp"])
	var active := StringName(String(raw_active))
	if active != &"" and not staged.has(active):
		return _reject("active_pet '%s' is not an owned pet" % active)
	# COMMIT: every row passed.
	_xp_by_pet = staged
	_active = active
	return true


func _reject(reason: String) -> bool:
	push_error("[pet-store] from_dict rejected: %s" % reason)
	return false
