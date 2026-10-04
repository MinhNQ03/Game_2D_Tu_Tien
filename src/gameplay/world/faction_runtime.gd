extends Node
class_name FactionRuntime
## FactionRuntime — Aetheria gameplay (per-session owner of the faction domain, Phase 07).
##
## A node under `Main/Systems`, a SIBLING of `WorldRuntime` / `RelationshipRuntime` /
## `SectRuntime` — **NOT an autoload** (the D-017 budget stays at 5). It owns the domain
## `FactionStore` + `FactionService` for the running session and survives map transitions
## (SceneRouter only swaps the content scene under `Main/World`).
##
## It depends on BOTH subsystems that precede it, which is why it starts last:
##   - `SectStore` (read-only) — the single membership authority every faction defers to,
##   - the shared `RelationshipService` — where Faction↔Faction standing actually lives.
## On an unwind it is therefore ended FIRST, before the things it reads.
##
## It knows nothing about presentation; the HUD/panel pull a read-only `SectPoliticsView`.
##
## THE C-003 GUARD (deliberate, asserted below): this session does NOT enrol the player into
## any faction. The player's start SECT is an authored scaffold (C-003) and expanding it into
## an authored faction allegiance would hand the player a political identity they never chose
## — exactly the "chosen one" shape `01-product.md` forbids. Factions ship leaderless and
## memberless; taking a side is a gameplay act, authored from P-17 onward through
## `FactionService.join_member`. So `CharacterState.faction_id` is still `&""` when this
## session reports active, and step 6 proves it rather than trusting it.

const FACTION_CATALOG_PATH := "res://data/factions/faction_catalog.tres"

var _store: FactionStore = null
var _service: FactionService = null
var _catalog: FactionCatalog = null
var _session_active: bool = false

## The player's instance id, so the politics view can mark which side (if any) is theirs.
var _player_instance_id: StringName = &""


## Begin a faction session — FAIL-CLOSED.
##
## `sect_store` is REQUIRED: every faction names a parent sect and draws its members from that
## sect's roster, so without it nothing about this subsystem is verifiable.
## `relationship_service` is REQUIRED whenever the catalog declares any starting politics.
## `character_resolver` lets the service validate membership + maintain the derived
## `CharacterState.faction_id` cache without touching `/root` (§11).
## `player_instance_id` is used ONLY so the politics view can mark which side is the player's;
## it is never enrolled anywhere (the C-003 guard above), which step 6 then proves.
## Idempotent: a second call with an active session is a no-op returning true.
##
## The session is reported ACTIVE only after EVERY one of these succeeded:
##   1. the catalog exists, loads and validates,
##   2. the sect dependency is present, and the relationship dependency is satisfied
##      (a graph exists if any politics is declared),
##   3. every authored template is valid, built into a `FactionState`, and registered,
##   4. every faction's parent sect exists in the sect store and no faction id collides
##      with a sect id,
##   5. the declared starting politics mirrored into the graph for every pair,
##   6. no faction has any member yet (the C-003 guard above) and the derived character
##      cache agrees with the rosters.
##
## Everything is built into LOCALS and committed to the node's fields only at the very end, so
## a failure can never leave a half-session visible (L-025): `is_session_active()` stays false
## and every getter stays empty. Returns false (loud) on any failure; the caller (Main) treats
## that as FATAL for New Game and unwinds.
func start_session(
		sect_store: SectStore,
		relationship_service: RelationshipService,
		character_resolver: Callable,
		player_instance_id: StringName) -> bool:
	if _session_active and _service != null:
		return true

	# 1. Catalog (boundary-validated).
	var catalog := _load_catalog()
	if catalog == null:
		return _fail_start("catalog missing, unloadable or invalid")

	# 2. Dependencies.
	if sect_store == null:
		return _fail_start("no SectStore was provided, so no faction's parent sect or "
			+ "membership could be verified")
	if relationship_service == null and _declares_politics(catalog):
		return _fail_start("catalog declares starting politics but no RelationshipService "
			+ "was provided to mirror it into")

	var store := FactionStore.new()
	var service := FactionService.new(store)
	service.set_sect_store(sect_store)
	if relationship_service != null:
		service.set_relationship_service(relationship_service)
	if character_resolver.is_valid():
		service.set_character_resolver(character_resolver)

	# 3. Every authored faction must be valid, buildable AND registered. A single bad entry
	#    aborts the whole session rather than silently shipping a partial political world.
	for tmpl in catalog.factions:
		if tmpl == null:
			return _fail_start("catalog contains a null faction template")
		if not tmpl.is_valid():
			return _fail_start("invalid faction template '%s': %s"
				% [tmpl.id, str(tmpl.validation_errors())])
		var state := FactionState.create_from_template(tmpl)
		if state == null:
			return _fail_start("failed to build FactionState for '%s'" % tmpl.id)
		if not service.register_faction(state, tmpl):
			return _fail_start("failed to register faction '%s'" % tmpl.id)

	# 4. Cross-store referential integrity: the catalog cannot see sects, so this is the first
	#    point at which "does this faction's parent sect actually exist" is answerable.
	if not service.validate_against_sects():
		return _fail_start("a faction references a sect that does not exist (see errors above)")

	# 5. Mirror the declared starting politics now that every faction exists.
	if not service.apply_default_politics():
		return _fail_start("declared politics mirror failed (see errors above)")

	# 6. Post-conditions. The membership one is the C-003 guard: nothing in this start path
	#    enrols anybody, so any member here would mean a template or hydrate path invented an
	#    allegiance. Asserting it is what keeps a later "convenience" default from quietly
	#    turning the start-sect scaffold into an authored political identity.
	for faction in store.all():
		var f := faction as FactionState
		if f.member_count() > 0:
			return _fail_start(("faction '%s' already has %d member(s) at session start; "
				+ "Phase 07 enrols nobody (the player chooses a side in gameplay, C-003)")
				% [f.id, f.member_count()])
	service.sync_character_cache()
	if not service.verify_character_cache():
		return _fail_start("the derived CharacterState.faction_id cache does not match the "
			+ "authoritative faction rosters")

	# Commit: only now does the session exist.
	_catalog = catalog
	_store = store
	_service = service
	_player_instance_id = player_instance_id
	_session_active = true
	return true


## Report a start failure loudly and leave NO half-session behind: every session field is
## cleared, so `is_session_active()` is false and every getter reads empty. Always false.
func _fail_start(reason: String) -> bool:
	push_error("[faction] session start aborted: %s" % reason)
	_session_active = false
	_service = null
	_store = null
	_catalog = null
	_player_instance_id = &""
	return false


## True if ANY authored faction declares a starting ally or rival — i.e. whether the session
## needs a relationship graph to mirror into.
static func _declares_politics(catalog: FactionCatalog) -> bool:
	for tmpl in catalog.factions:
		if tmpl == null:
			continue
		if not tmpl.default_allied_faction_ids.is_empty() \
				or not tmpl.default_rival_faction_ids.is_empty():
			return true
	return false


## End the faction session: drop the store/service (RefCounted, freed with the last
## reference). Safe to call more than once.
func end_session() -> void:
	_session_active = false
	_service = null
	_store = null
	_catalog = null
	_player_instance_id = &""


func is_session_active() -> bool:
	return _session_active


func get_service() -> FactionService:
	return _service


func get_store() -> FactionStore:
	return _store


func get_catalog() -> FactionCatalog:
	return _catalog


## The player's instance id for this session. Used ONLY to mark which side is theirs in the
## politics view — never to enrol them (the C-003 guard in the class note).
func get_player_instance_id() -> StringName:
	return _player_instance_id


## Build the read-only presentation view of one sect's political landscape. Always returns a
## valid view: an "unavailable" view when there is no session, or an empty-but-available one
## when the sect simply has no factions, so the UI never crashes. Built ON DEMAND (panel open
## / membership change), never per frame (`05-performance-testing.md`).
func get_politics_view(sect_id: StringName) -> SectPoliticsView:
	if not _session_active or _store == null or _service == null:
		return SectPoliticsView.make_unavailable()
	return SectPoliticsView.make(_service, sect_id, _player_instance_id)


# --- Loading (boundary-validated) -------------------------------------------

func _load_catalog() -> FactionCatalog:
	if not ResourceLoader.exists(FACTION_CATALOG_PATH):
		push_error("[faction] catalog missing: %s" % FACTION_CATALOG_PATH)
		return null
	var cat := load(FACTION_CATALOG_PATH) as FactionCatalog
	if cat == null:
		push_error("[faction] catalog failed to load as FactionCatalog")
		return null
	if not cat.is_valid():
		push_error("[faction] invalid faction catalog: %s" % str(cat.validation_errors()))
		return null
	return cat
