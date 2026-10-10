extends RefCounted
class_name PetService
## PetService — Aetheria domain (the rules of owning a pet, Phase 16).
##
## The ONLY writer of `PetStore`. Node-free and scene-free: acquisition, choosing the active
## pet and granting XP are decided here from the store and the authored `PetCatalogData`, and
## every refusal names its reason (a localization key the HUD can say) and changes nothing.
##
## LEVEL IS DERIVED FROM XP (D-064). There is no stored level: `level_of` asks the pet's own
## `ProgressionCurveData` — the same curve arithmetic the player's level uses, not a second
## formula — and `stats_of` derives the stats from that level.

const REFUSE_UNKNOWN_PET := &"UI_PET_UNKNOWN"
const REFUSE_ALREADY_OWNED := &"UI_PET_ALREADY_OWNED"
const REFUSE_NOT_OWNED := &"UI_PET_NOT_OWNED"

var _catalog: PetCatalogData = null
var _store: PetStore = null


func _init(catalog: PetCatalogData = null, store: PetStore = null) -> void:
	if catalog == null or store == null:
		return
	if not catalog.is_valid():
		push_error("[pet] refusing an invalid pet catalog: %s" % str(catalog.validation_errors()))
		return
	_catalog = catalog
	_store = store


func is_ready() -> bool:
	return _catalog != null and _store != null


func catalog() -> PetCatalogData:
	return _catalog


func store() -> PetStore:
	return _store


## Take ownership of `pet_id`. Returns &"" on success, else the refusal key (nothing changed).
func acquire(pet_id: StringName) -> StringName:
	if not is_ready() or not _catalog.has(pet_id):
		return REFUSE_UNKNOWN_PET
	if _store.owns(pet_id):
		return REFUSE_ALREADY_OWNED
	_store.add_owned(pet_id)
	return &""


## Make an owned pet the active one. &"" on success (also when it already was), else the key.
func activate(pet_id: StringName) -> StringName:
	if not is_ready() or not _catalog.has(pet_id):
		return REFUSE_UNKNOWN_PET
	if not _store.owns(pet_id):
		return REFUSE_NOT_OWNED
	_store.set_active(pet_id)
	return &""


## No pet is active. Always succeeds; safe when none was.
func deactivate() -> void:
	if is_ready():
		_store.set_active(&"")


## The active pet's definition, or null.
func active_pet() -> PetData:
	if not is_ready() or _store.active_id() == &"":
		return null
	return _catalog.entry(_store.active_id())


func level_of(pet_id: StringName) -> int:
	var pet := _catalog.entry(pet_id) if is_ready() else null
	if pet == null or not _store.owns(pet_id):
		return 0
	return pet.level_for_xp(_store.xp_of(pet_id))


## The derived stats of an owned pet at its current level (null when it is not owned).
func stats_of(pet_id: StringName) -> StatBlock:
	var pet := _catalog.entry(pet_id) if is_ready() else null
	if pet == null or not _store.owns(pet_id):
		return null
	return pet.stats_at(level_of(pet_id))


## Grant `amount` XP to an owned pet. Returns `{ accepted, reason, xp_before, xp_after,
## level_before, level_after }`. Refused (nothing changed) for an unknown or unowned pet, a
## negative amount, or a pet already at its curve's ceiling. The whole outcome is computed
## before the one write, and the total is capped at the ceiling's cumulative XP so a maxed pet
## never accumulates an unbounded number nothing reads.
func earn_xp(pet_id: StringName, amount: int) -> Dictionary:
	var pet := _catalog.entry(pet_id) if is_ready() else null
	if pet == null:
		return _refused(REFUSE_UNKNOWN_PET, 0, 0)
	if not _store.owns(pet_id):
		return _refused(REFUSE_NOT_OWNED, 0, 0)
	var curve := pet.progression_curve
	var xp_before := _store.xp_of(pet_id)
	var level_before := curve.level_for_xp(xp_before)
	if amount < 0:
		push_error("[pet] refusing a negative XP grant (%d) to '%s'" % [amount, pet_id])
		return _refused(&"UI_PET_XP_INVALID", xp_before, level_before)
	if curve.is_ceiling(level_before):
		return _refused(&"UI_PET_AT_CEILING", xp_before, level_before)
	var ceiling := curve.cumulative_for_level(curve.max_level())
	var xp_after: int = mini(xp_before + amount, ceiling)
	_store.set_xp(pet_id, xp_after)
	return {"accepted": true, "reason": &"", "xp_before": xp_before, "xp_after": xp_after,
		"level_before": level_before, "level_after": curve.level_for_xp(xp_after)}


func _refused(reason: StringName, xp: int, level: int) -> Dictionary:
	return {"accepted": false, "reason": reason, "xp_before": xp, "xp_after": xp,
		"level_before": level, "level_after": level}
