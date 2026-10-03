extends Node
class_name SectRuntime
## SectRuntime — Aetheria gameplay (per-session owner of the sect domain, Phase 06).
##
## A node under `Main/Systems` (a SIBLING of `WorldRuntime` + `RelationshipRuntime`, NOT an
## autoload — the D-017 autoload budget stays at 5). It owns the domain `SectStore` +
## `SectService` for the running session and SURVIVES map transitions (SceneRouter only swaps
## the content scene under `Main/World`; everything under `Main/Systems` persists). This is
## the runtime home of sect state (`docs/SECT_SYSTEM.md` §2, D-011/D-015).
##
## Scope discipline: it knows NOTHING about presentation (the HUD/panel pull a read-only
## `SectMembershipView`). It wires the domain seams for the session:
##   - the shared `RelationshipService` (from RelationshipRuntime) for the Sect↔Sect
##     alliance/enemy mirror (§14),
##   - a character resolver so the service can validate membership + sync the player's derived
##     cache WITHOUT reaching into `/root` or the tree (§11).
##
## WorldRuntime stays the map/player coordinator; this is a separate subsystem so no node
## becomes a God object (`03-architecture.md`).

const SECT_CATALOG_PATH := "res://data/sects/sect_catalog.tres"

var _store: SectStore = null
var _service: SectService = null
var _catalog: SectCatalog = null
var _session_active: bool = false

## The player's sect id this session (derived at join time; &"" if the player has no sect).
var _player_sect_id: StringName = &""
## The player's instance id (so the membership view resolves the player's rank). Set at start.
var _player_instance_id: StringName = &""


## Begin a sect session. `relationship_service` (may be null) powers the Sect↔Sect mirror;
## `character_resolver` (may be invalid) lets the service validate membership + sync the
## player's `CharacterState` cache; `player_instance_id` is the player to enroll into the
## authored start sect. Returns false (loud) on a missing/invalid catalog. NON-FATAL at the
## caller (Main) — like RelationshipRuntime, a sect-load failure must not abort New Game.
## Idempotent: a second call with an active session is a no-op returning true.
func start_session(
		relationship_service: RelationshipService,
		character_resolver: Callable,
		player_instance_id: StringName) -> bool:
	if _session_active and _service != null:
		return true
	_catalog = _load_catalog()
	if _catalog == null:
		return false
	_store = SectStore.new()
	_service = SectService.new(_store)
	if relationship_service != null:
		_service.set_relationship_service(relationship_service)
	if character_resolver.is_valid():
		_service.set_character_resolver(character_resolver)
	_player_instance_id = player_instance_id

	# Register every authored sect (state + template) with the service.
	for tmpl in _catalog.sects:
		var state := SectState.create_from_template(tmpl)
		if state == null:
			push_error("[sect] failed to build SectState for '%s'" % tmpl.id)
			continue
		_service.register_sect(state, tmpl)
	# Mirror declared alliances/enemies into the relationship graph once all sects exist (§14).
	_service.apply_default_diplomacy()

	# Enroll the player into the authored starting sect (membership flows through the service,
	# so the ROSTER is authoritative and the player's derived cache is written — not just
	# CharacterState.sect_id set directly, §17/D-015).
	_player_sect_id = &""
	if _catalog.player_start_sect_id != &"" and player_instance_id != &"":
		var ok := _service.join_member(
			_catalog.player_start_sect_id, player_instance_id, _catalog.player_start_rank_id)
		if ok:
			_player_sect_id = _catalog.player_start_sect_id
		else:
			push_warning("[sect] player could not join start sect '%s'"
				% _catalog.player_start_sect_id)

	_session_active = true
	return true


## End the sect session: drop the store/service (RefCounted, freed with the last reference).
## Safe to call more than once.
func end_session() -> void:
	_session_active = false
	_service = null
	_store = null
	_catalog = null
	_player_sect_id = &""
	_player_instance_id = &""


func is_session_active() -> bool:
	return _session_active


func get_service() -> SectService:
	return _service


func get_store() -> SectStore:
	return _store


## The player's current sect id (&"" if none).
func get_player_sect_id() -> StringName:
	return _player_sect_id


## The player's authoritative SectState (or null if the player has no sect / no session).
func get_player_sect() -> SectState:
	if _store == null or _player_sect_id == &"":
		return null
	return _store.get_sect(_player_sect_id)


## Build the read-only presentation view of the player's membership (§21). Always returns a
## valid view: a "not a member" view (is_member == false) when the player has no sect, so the
## UI never crashes on no-sect. Built on demand (on a membership change / HUD refresh), NOT
## per frame.
func get_player_membership_view() -> SectMembershipView:
	var sect := get_player_sect()
	if sect == null or _catalog == null:
		return SectMembershipView.make_empty()
	var template := _catalog.find_sect(_player_sect_id)
	if template == null:
		return SectMembershipView.make_empty()
	return SectMembershipView.make(sect, template, sect.rank_of(_player_instance_id))


# --- Loading (boundary-validated) -------------------------------------------

func _load_catalog() -> SectCatalog:
	if not ResourceLoader.exists(SECT_CATALOG_PATH):
		push_error("[sect] catalog missing: %s" % SECT_CATALOG_PATH)
		return null
	var cat := load(SECT_CATALOG_PATH) as SectCatalog
	if cat == null:
		push_error("[sect] catalog failed to load as SectCatalog")
		return null
	if not cat.is_valid():
		push_error("[sect] invalid sect catalog: %s" % str(cat.validation_errors()))
		return null
	return cat
