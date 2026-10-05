extends Node
class_name WorldSimulationRuntime
## WorldSimulationRuntime — Aetheria gameplay (per-session owner of the world simulation).
##
## A node under `Main/Systems`, the FIFTH sibling of `WorldRuntime` / `RelationshipRuntime` /
## `SectRuntime` / `FactionRuntime` — **NOT an autoload** (the D-017 budget stays at 5). It
## owns the `WorldSimulationState` + `WorldSimulationService` for the running session and
## survives map transitions, like its siblings.
##
## It is started LAST and ended FIRST, because it reads ALL FOUR of them:
## the character registry (its cast are real `CharacterState`s), the sect store and service
## (its actors enrol, its events move influence), the faction service, and the relationship
## graph. That makes it the new tail of the dependency chain, so `Main.SESSION_START_ORDER`
## gains it at the end and every teardown drops it first (D-047).
##
## NO PER-FRAME WORK AT ALL. There is no `_process`, no `_physics_process`, no `Timer` and no
## wall-clock read in this file — a regression test asserts that by reading the source, because
## the cheapest way for this class to betray its entire design is for somebody to add a
## `_process` that "just" accumulates delta. Time passes on EXPLICIT GAMEPLAY BEATS:
##   * session start (`ticks_on_session_start`),
##   * the player arriving in a map (`ticks_per_map_transition`).
## Both tick costs are authored on the catalog. Only one beat exists because hub ↔ field is
## currently the only gameplay beat there is; a later phase adds its own beats as data beside
## these, not by editing the simulation (`02-game-design.md` extensibility rule).
##
## IT SPAWNS NOTHING, in any band. `docs/WORLD_SIMULATION.md` §2 reserves entity
## instantiation for the NEAR band, and the phase that renders background characters will do
## it; Phase 08 marks the band and keeps every actor as pure serializable state. So the
## "Far band has no entity nodes" guarantee is currently true of EVERY band, and the tests
## assert the node count rather than trusting this paragraph.

const WORLD_SIM_CATALOG_PATH := "res://data/worldsim/world_sim_catalog.tres"

## Fallback world seed, used only when the caller supplies none. A FIXED value, not a
## time-based one: `MULTIPLAYER_PLAN.md` §7 lists wall-clock-seeded simulation as a
## corner-painting risk, and a world that differs between two runs of the same save would make
## every determinism test meaningless. A real run derives its seed from the run id.
const DEFAULT_WORLD_SEED := 20261005

var _catalog: WorldSimCatalog = null
var _state: WorldSimulationState = null
var _service: WorldSimulationService = null
var _session_active: bool = false

## The map the player is currently in, for the LOD band assignment.
var _player_map_id: StringName = &""

## `map_id(StringName) -> Array[StringName]` of the maps reachable from it in ONE exit. Built
## once from the map catalog at session start: the MID band is "one hop from the player", and
## recomputing that from `MapData.exits` on every arrival would be a scan per transition.
var _map_neighbours: Dictionary = {}


## Begin a world-simulation session — FAIL-CLOSED, committing nothing until every step passed.
##
## The dependencies are all REQUIRED, and each one is required for a concrete reason rather
## than for symmetry:
##   * `characters` — the cast are real `CharacterState`s and this is where they are
##     registered; without it the simulation would have to invent a parallel character model,
##     which `CHARACTER_SYSTEM.md` §1 and B9 both forbid.
##   * `sects` / `factions` — authored actors enrol through them (so the sect roster stays the
##     single membership authority, D-015) and authored events move influence through them.
##   * `relationship` — relationship events apply deltas through it, so clamping, history and
##     symmetry are preserved (B11).
##   * `map_ids` — the LOD band is a map-graph question; `{ map_id -> MapData }`.
## `world_seed` identifies the world; a run passes one derived from its run id.
##
## The session is reported ACTIVE only after ALL of these succeeded:
##   1. the catalog exists, loads and validates,
##   2. every authored actor's `home_map_id` names a real map,
##   3. the clock and the seeded RNG seam are valid and the state/service were built,
##   4. every authored actor's `CharacterState` was created and registered in the registry,
##   5. every authored actor was enrolled into its authored sect (and faction, if any) THROUGH
##      the owning service,
##   6. every actor got a simulation record,
##   7. every authored event validated against the live stores AND its relationship edge
##      exists,
##   8. every authored event was queued,
##   9. bands were assigned and the derived `sim_state` caches agree with the records.
##
## Everything is built into LOCALS and committed at the very end (L-025), so a failure leaves
## no observable half-session: `is_session_active()` stays false and every getter stays empty.
## Returns false (loud) on any failure; `Main` treats that as FATAL for New Game and unwinds.
func start_session(
		characters: CharacterRegistry,
		sects: SectService,
		factions: FactionService,
		relationship: RelationshipService,
		map_ids: Dictionary,
		world_seed: int = DEFAULT_WORLD_SEED) -> bool:
	if _session_active and _service != null:
		return true

	# 1. Catalog (boundary-validated).
	var catalog := _load_catalog()
	if catalog == null:
		return _fail_start("catalog missing, unloadable or invalid")

	# 2. Dependencies.
	if characters == null:
		return _fail_start("no CharacterRegistry was provided; the simulation records state "
			+ "ABOUT characters and must not invent a parallel character model")
	if sects == null or sects.get_store() == null:
		return _fail_start("no SectService/SectStore was provided, so authored actors could "
			+ "not be enrolled and sect influence could not be moved by its owner")
	if factions == null or factions.get_store() == null:
		return _fail_start("no FactionService/FactionStore was provided")
	if relationship == null:
		return _fail_start("no RelationshipService was provided, so relationship events "
			+ "would have nowhere to apply their deltas")
	if map_ids.is_empty():
		return _fail_start("no map catalog was provided, so no LOD band could be computed")
	var map_errors := catalog.validation_errors_against_maps(map_ids)
	if not map_errors.is_empty():
		return _fail_start("actor/map mismatch: %s" % str(map_errors))

	# 3. Clock + seeded RNG + state + service.
	var clock := WorldClock.new(
		catalog.ticks_per_hour, catalog.hours_per_day,
		catalog.days_per_season, catalog.seasons_per_year)
	if not clock.is_valid():
		return _fail_start("the authored calendar is invalid")
	var rng := RngService.new(world_seed)
	if not rng.is_valid():
		return _fail_start("world seed %d is not usable" % world_seed)
	var state := WorldSimulationState.create(clock, rng, catalog.event_log_capacity)
	if state == null:
		return _fail_start("could not build the simulation state")
	var service := WorldSimulationService.new(state, catalog)
	if not service.is_usable():
		return _fail_start("could not build a usable simulation service")
	service.set_sect_service(sects)
	service.set_faction_service(factions)
	service.set_relationship_service(relationship)
	service.set_character_resolver(characters.resolver())

	# 4-6. The cast: a real CharacterState, authoritative enrolment, then a sim record.
	for actor_data in catalog.actors_sorted():
		if not _admit_actor(actor_data, characters, sects, factions, service):
			return _fail_start("could not admit actor '%s' (see errors above)" % actor_data.id)

	# 7-8. Events: validate against the LIVE stores, ensure edges, then queue.
	if not service.prepare_events():
		return _fail_start("authored events failed validation (see errors above)")
	if not service.schedule_authored_events():
		return _fail_start("authored events could not be queued (see errors above)")

	# 9. Bands + the derived character caches.
	_map_neighbours = _build_neighbour_index(map_ids)
	service.assign_bands(_player_map_id, _adjacent_to(_player_map_id))
	service.sync_character_caches()
	if not service.verify_character_caches():
		return _fail_start("the derived CharacterState.sim_state caches do not match the "
			+ "authoritative simulation records")

	# Commit: only now does the session exist.
	_catalog = catalog
	_state = state
	_service = service
	_session_active = true

	# The authored opening beat, AFTER the commit: it is simulated time passing in a world
	# that already exists, not part of building it. Keeping it outside the fail-closed build
	# also means a tick failure cannot leave a half-constructed session behind.
	if catalog.ticks_on_session_start > 0:
		_service.advance_ticks(catalog.ticks_on_session_start)
	return true


## Admit one authored actor: build its character, register it, enrol it through the owning
## services, then give it a simulation record. Returns false (loud) at the first failure,
## having reported which step it was.
func _admit_actor(
		actor_data: WorldSimActorData,
		characters: CharacterRegistry,
		sects: SectService,
		factions: FactionService,
		service: WorldSimulationService) -> bool:
	if actor_data == null or not actor_data.is_valid():
		push_error("[worldsim] invalid actor data in the catalog")
		return false
	# The character may already exist (a hydrated save, or an actor the world shares with
	# another system). Reuse it rather than refusing: `CharacterRegistry.add` deliberately
	# never replaces a live state, and a second `CharacterState` for one id would be two
	# answers to "who is this".
	if not characters.has(actor_data.id):
		var character := CharacterState.create_from_template(
			actor_data.character_template, actor_data.id)
		if character == null:
			push_error("[worldsim] actor '%s': could not build a CharacterState from template "
				% actor_data.id + "'%s'" % actor_data.character_template.id)
			return false
		if not characters.add(character):
			return false
	# Membership goes through the OWNING service, so the sect roster stays authoritative and
	# `CharacterState.sect_id`/`faction_id` stay derived caches (D-015). A rejected enrolment
	# fails the session: a world that started with an actor the sect does not know about would
	# have membership no system owned (the L-025 class of half-session).
	if actor_data.sect_id != &"":
		if not sects.join_member(
				actor_data.sect_id, actor_data.id, actor_data.sect_rank_id):
			push_error("[worldsim] actor '%s' could not join sect '%s' at rank '%s'"
				% [actor_data.id, actor_data.sect_id, actor_data.sect_rank_id])
			return false
	if actor_data.faction_id != &"":
		if not factions.join_member(actor_data.faction_id, actor_data.id):
			push_error("[worldsim] actor '%s' could not take the side of faction '%s'"
				% [actor_data.id, actor_data.faction_id])
			return false
	return service.register_actor(actor_data)


## Report a start failure loudly and leave NO half-session behind. Always false.
##
## It cannot un-enrol actors from sects/factions: those services own that state and the
## session is being abandoned anyway, so `Main` unwinds the whole stack (Sect and Faction
## sessions included) immediately after. That is exactly why the simulation is started LAST
## and torn down FIRST — the ordering is what makes this failure recoverable without this
## class having to reach into somebody else's store (D-047).
func _fail_start(reason: String) -> bool:
	push_error("[worldsim] session start aborted: %s" % reason)
	_session_active = false
	_service = null
	_state = null
	_catalog = null
	_map_neighbours = {}
	return false


## End the session: drop the state/service (RefCounted, freed with the last reference). Safe
## to call more than once.
func end_session() -> void:
	_session_active = false
	_service = null
	_state = null
	_catalog = null
	_player_map_id = &""
	_map_neighbours = {}


func is_session_active() -> bool:
	return _session_active


func get_service() -> WorldSimulationService:
	return _service


func get_state() -> WorldSimulationState:
	return _state


func get_catalog() -> WorldSimCatalog:
	return _catalog


func get_player_map_id() -> StringName:
	return _player_map_id


# --- The explicit gameplay beat ---------------------------------------------

## The player arrived in `map_id`: re-assign LOD bands around the new position and advance the
## world by the authored per-transition cost.
##
## This is THE beat (see the class note). Called by `WorldRuntime` after a successful map
## transition — it owns the "the player is now here" fact and already locates its siblings the
## same way for the sect and politics views. Returns the number of ticks processed (0 before a
## session exists, which is the normal case for the very first map: the hub loads during the
## WORLD session, before this session is started, and `start_session` then assigns bands
## itself).
func on_player_arrived(map_id: StringName) -> int:
	_player_map_id = map_id
	if not _session_active or _service == null:
		return 0
	_service.assign_bands(_player_map_id, _adjacent_to(_player_map_id))
	if _catalog.ticks_per_map_transition <= 0:
		return 0
	return _service.advance_ticks(_catalog.ticks_per_map_transition)


## Simulation time promised but not yet spent (the catch-up debt). 0 with no session.
func pending_catch_up_ticks() -> int:
	if _service == null:
		return 0
	return _service.pending_catch_up_ticks()


## The read-only presentation view. Always a valid object: an "unavailable" view when there is
## no session, so the HUD never null-checks. Built on demand, never per frame.
func get_view() -> WorldSimView:
	if not _session_active or _state == null:
		return WorldSimView.make_unavailable()
	return WorldSimView.make(_state)


# --- The map graph (the MID band) -------------------------------------------

## `{ map_id -> Array[StringName] }` of one-hop neighbours, from each map's authored exits.
##
## Built ONCE per session rather than per arrival. Exits are directed in the data, but
## adjacency for LOD purposes is symmetric — "one hop away from the player" is about distance,
## not about which way a door opens — so each exit is recorded in BOTH directions. Without
## that, a map reachable only by walking INTO it would never host MID actors, and an actor
## standing one room away would be simulated as if they were on another continent.
## Keys are `StringName` throughout, matching `MapCatalog.build_lookup()`'s convention and
## `WorldSimActor.location_map_id`'s type. Keeping ONE key type end to end is deliberate: a
## `Dictionary` keyed by `String` and probed with a `StringName` is the kind of mismatch that
## silently answers "not found" and would quietly demote every MID actor to FAR — a bug with
## no error message, visible only as a world that felt less alive than it should.
static func _build_neighbour_index(map_ids: Dictionary) -> Dictionary:
	var index := {}
	for key in map_ids:
		index[StringName(String(key))] = {}
	for key in map_ids:
		var data: MapData = map_ids[key]
		if data == null:
			continue
		var from_key := StringName(String(key))
		for map_exit in data.exits:
			if map_exit == null or map_exit.to_map_id == &"":
				continue
			var to_key := StringName(String(map_exit.to_map_id))
			if not index.has(to_key):
				continue  # an exit to a map that is not in the catalog; MapData validates it
			(index[from_key] as Dictionary)[to_key] = true
			(index[to_key] as Dictionary)[from_key] = true
	return index


## The set of maps one hop from `map_id`, as a Dictionary used as a set (the band assignment
## does membership tests, which a Dictionary answers in constant time while an Array would
## scan).
func _adjacent_to(map_id: StringName) -> Dictionary:
	var neighbours: Variant = _map_neighbours.get(map_id, null)
	if typeof(neighbours) != TYPE_DICTIONARY:
		return {}
	return neighbours


# --- Loading (boundary-validated) -------------------------------------------

func _load_catalog() -> WorldSimCatalog:
	if not ResourceLoader.exists(WORLD_SIM_CATALOG_PATH):
		push_error("[worldsim] catalog missing: %s" % WORLD_SIM_CATALOG_PATH)
		return null
	var cat := load(WORLD_SIM_CATALOG_PATH) as WorldSimCatalog
	if cat == null:
		push_error("[worldsim] catalog failed to load as WorldSimCatalog")
		return null
	if not cat.is_valid():
		push_error("[worldsim] invalid world-sim catalog: %s" % str(cat.validation_errors()))
		return null
	return cat
