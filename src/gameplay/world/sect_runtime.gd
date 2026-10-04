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


## Begin a sect session — FAIL-CLOSED. `relationship_service` powers the Sect↔Sect mirror
## (REQUIRED whenever the catalog declares any default diplomacy); `character_resolver` lets
## the service validate membership + sync the player's `CharacterState` cache;
## `player_instance_id` is the player to enroll into the authored start sect.
## Idempotent: a second call with an active session is a no-op returning true.
##
## The session is reported ACTIVE only after EVERY one of these succeeded:
##   1. the catalog exists, loads, and validates,
##   2. the relationship dependency is satisfied (a graph exists if diplomacy is declared),
##   3. every authored template is valid,
##   4. a `SectState` was built for every template,
##   5. every `register_sect` succeeded,
##   6. the default diplomacy mirror succeeded for every declared pair,
##   7. the authored player start sect resolves in the store, with a non-empty player id AND
##      a valid character resolver that actually resolves that id,
##   8. the player's enrollment through the service succeeded,
##   9. the player's derived `CharacterState` cache agrees with the authoritative roster.
##
## Everything is built into LOCALS and only committed to the node's fields at the very end,
## so a failure can never leave a half-session visible: `is_session_active()` stays false and
## `get_service()`/`get_store()`/`get_player_sect_id()` stay empty. Returns false (loud) on
## any failure; the caller (Main) treats that as FATAL for New Game and unwinds.
func start_session(
		relationship_service: RelationshipService,
		character_resolver: Callable,
		player_instance_id: StringName) -> bool:
	if _session_active and _service != null:
		return true

	# 1. Catalog (boundary-validated).
	var catalog := _load_catalog()
	if catalog == null:
		return _fail_start("catalog missing, unloadable or invalid")

	# 2. Relationship dependency. Declared diplomacy has nowhere to be mirrored without a
	#    graph, so starting anyway would guarantee sect-state/relationship-graph divergence.
	if relationship_service == null and _declares_diplomacy(catalog):
		return _fail_start("catalog declares default diplomacy but no RelationshipService "
			+ "was provided to mirror it into")

	var store := SectStore.new()
	var service := SectService.new(store)
	if relationship_service != null:
		service.set_relationship_service(relationship_service)
	if character_resolver.is_valid():
		service.set_character_resolver(character_resolver)

	# 3-5. Every authored sect must be valid, buildable AND registered. A single bad entry
	#      aborts the whole session rather than silently shipping a partial sect world.
	for tmpl in catalog.sects:
		if tmpl == null:
			return _fail_start("catalog contains a null sect template")
		if not tmpl.is_valid():
			return _fail_start("invalid sect template '%s': %s"
				% [tmpl.id, str(tmpl.validation_errors())])
		var state := SectState.create_from_template(tmpl)
		if state == null:
			return _fail_start("failed to build SectState for '%s'" % tmpl.id)
		if not service.register_sect(state, tmpl):
			return _fail_start("failed to register sect '%s'" % tmpl.id)

	# 6. Mirror declared alliances/enemies into the relationship graph now that all sects
	#    exist (§14). A dangling or rejected pair fails the session.
	if not service.apply_default_diplomacy():
		return _fail_start("default diplomacy mirror failed (see errors above)")

	# 7-8. Enroll the player into the authored starting sect. Membership flows through the
	#      service, so the ROSTER is authoritative and the derived cache is written — never
	#      `CharacterState.sect_id` set directly (§17/D-015).
	var resolved_sect_id: StringName = &""
	if catalog.player_start_sect_id != &"":
		if store.get_sect(catalog.player_start_sect_id) == null:
			return _fail_start("authored player start sect '%s' is not in the store"
				% catalog.player_start_sect_id)
		if player_instance_id == &"":
			return _fail_start("catalog names a player start sect but no player instance id "
				+ "was provided to enroll")
		# A WORKING resolver is required here. `SectService` deliberately treats an absent
		# resolver as "character checks disabled" so pure roster unit tests can exercise
		# membership logic without characters — that service-level contract is unchanged. But
		# at THIS boundary a real session is enrolling a real player, so an absent or
		# non-resolving resolver would silently skip both the existence check (§10: never
		# invent a character) and the derived-cache write, producing a sect whose roster
		# names a player that no CharacterState is bound to.
		if not character_resolver.is_valid():
			return _fail_start("catalog names a player start sect but no valid character "
				+ "resolver was provided, so membership could not be verified or cached")
		var player_state: CharacterState = character_resolver.call(player_instance_id)
		if player_state == null:
			return _fail_start("the character resolver does not resolve the player id '%s'"
				% player_instance_id)
		if not service.join_member(
				catalog.player_start_sect_id, player_instance_id,
				catalog.player_start_rank_id):
			return _fail_start("player '%s' could not join start sect '%s'"
				% [player_instance_id, catalog.player_start_sect_id])
		resolved_sect_id = catalog.player_start_sect_id

	# 9. Derived-cache sync + verification (D-015: the roster is authority, the
	#    CharacterState fields are a cache that MUST agree with it).
	service.sync_character_cache()
	if resolved_sect_id != &"":
		# The resolver was proven valid + resolving in step 7, so this is a real comparison.
		var cs: CharacterState = character_resolver.call(player_instance_id)
		var sect := store.get_sect(resolved_sect_id)
		if cs == null or cs.sect_id != resolved_sect_id \
				or cs.sect_rank != sect.rank_of(player_instance_id):
			# Unwind the enrollment so the character is not left pointing at a sect that
			# this (aborted) session owns.
			service.leave_member(resolved_sect_id, player_instance_id)
			return _fail_start("player's derived CharacterState cache does not match the "
				+ "authoritative roster after enrollment")

	# Commit: only now does the session exist.
	_catalog = catalog
	_store = store
	_service = service
	_player_instance_id = player_instance_id
	_player_sect_id = resolved_sect_id
	_session_active = true
	return true


## Report a start failure loudly and leave NO half-session behind: every session field is
## cleared, so `is_session_active()` is false and every getter reads empty. Always false.
func _fail_start(reason: String) -> bool:
	push_error("[sect] session start aborted: %s" % reason)
	_session_active = false
	_service = null
	_store = null
	_catalog = null
	_player_sect_id = &""
	_player_instance_id = &""
	return false


## True if ANY authored sect in `catalog` declares a default ally or enemy — i.e. whether the
## session needs a relationship graph to mirror into.
static func _declares_diplomacy(catalog: SectCatalog) -> bool:
	for tmpl in catalog.sects:
		if tmpl == null:
			continue
		if not tmpl.default_ally_sect_ids.is_empty() \
				or not tmpl.default_enemy_sect_ids.is_empty():
			return true
	return false


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
