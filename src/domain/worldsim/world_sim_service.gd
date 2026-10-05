extends RefCounted
class_name WorldSimulationService
## WorldSimulationService — Aetheria domain (the world's evolution engine).
##
## The single path through which simulated time passes and the world changes
## (`docs/WORLD_SIMULATION.md`). It owns a `WorldSimulationState` (the persistent tier) and
## nothing else: every other piece of world state belongs to the system that already owns it.
##
## WHAT IT OWNS vs WHAT IT ASKS FOR — the rule that keeps this from becoming a GameManager:
##   * **Owns:** the world clock, the seeded RNG streams, each actor's LOD band + routine
##     position, the scheduled-event queue, the catch-up debt, the world-event feed. Plus one
##     field on somebody else's object: `CharacterState.sim_state`, which
##     `docs/CHARACTER_SYSTEM.md` §5 reserves for the simulation and which is kept as a
##     DERIVED CACHE of this service's own actor records (the D-015 shape).
##   * **Asks for:** everything else. A sect's influence moves through
##     `SectService.adjust_influence`, a faction's through `FactionService.adjust_influence`, a
##     relationship dimension through `RelationshipService.apply_delta`. It never writes
##     `SectState.influence`, never touches `RelationshipEdge.dimensions`, never adds anybody
##     to a roster by hand (`SYSTEM_DEPENDENCY_MATRIX.md` §5). Those services keep their own
##     clamping, history, symmetry and signals — which is exactly why going through them is
##     not a formality.
##
## DETERMINISM IS THE PRODUCT, not a nice-to-have. Every ordering comes from an explicit sort,
## every random value comes from one named seeded stream, there is no wall clock anywhere, and
## a magnitude is drawn BEFORE its application is attempted so that a rejected application
## cannot change how far the stream has advanced. The contract the tests assert is:
## `same seed + same initial state + same K ticks == same authoritative world`.
##
## LOD IS A COST MODEL, NOT A STATE MODEL. An actor's activity is a pure function of
## `(tick, schedule)` (see `WorldSimActor`), so the band changes only how often the simulation
## LOOKS at an actor — never what it would see. Per-tick work is therefore
## `O(near+mid actors + due events)`, not `O(whole cast)`, and promotion across bands cannot
## lose or invent state.
##
## Pure domain `RefCounted`: GDScript signals, no Node, no `/root`, no filesystem, no
## presentation (`03-architecture.md`).

## One tick of simulated time has passed. Emitted once per processed tick, AFTER that tick's
## events have been applied, so a listener reading state on this signal sees the tick's result.
signal world_tick(tick: int)

## A scheduled world event fired and was applied. `magnitude` is the value actually drawn.
signal world_event_triggered(
	event_id: StringName, kind: int, target_id: StringName, magnitude: int)

## A simulated actor's abstract activity changed (TRAINING → MISSION → …). Emitted only for
## observed (NEAR/MID) actors: a FAR actor's activity is computed on demand, so emitting for
## the whole cast every tick would be the per-frame storm LOD exists to avoid.
signal actor_state_changed(instance_id: StringName, activity: int)

## An actor crossed an LOD band (promotion or demotion).
signal actor_band_changed(instance_id: StringName, band: int)

## Edge-id namespace for the character↔character edges this simulation creates. MUST differ
## from `SectService`'s `"sect_rel:"` and `FactionService`'s `"faction_rel:"`, or two mirrors
## would collide on a pair and the second `create_edge` would be rejected as a duplicate id.
const EDGE_PREFIX := "worldsim_rel:"

## The cause recorded on every relationship delta this simulation applies, so a history entry
## can be attributed to the world moving on its own rather than to a player action.
const RELATIONSHIP_CAUSE := &"WORLD_SIM"

var _state: WorldSimulationState = null
var _catalog: WorldSimCatalog = null

# --- The seams it mutates THROUGH (never around) -----------------------------
var _sects: SectService = null
var _factions: FactionService = null
var _relationship: RelationshipService = null
## `(StringName) -> CharacterState`, normally `CharacterRegistry.resolver()`.
var _character_resolver: Callable = Callable()

## The one stream this service draws from.
var _stream: RngStream = null


func _init(state: WorldSimulationState, catalog: WorldSimCatalog) -> void:
	_state = state
	_catalog = catalog
	if _state != null and _state.rng() != null:
		_stream = _state.rng().stream(RngService.STREAM_WORLD_SIM)


## True when the service has everything it needs to run at all (a state, a catalog and a
## usable stream). Checked by the runtime before it reports a session active.
func is_usable() -> bool:
	return _state != null and _catalog != null and _stream != null


func get_state() -> WorldSimulationState:
	return _state


func get_catalog() -> WorldSimCatalog:
	return _catalog


func set_sect_service(service: SectService) -> void:
	_sects = service


func set_faction_service(service: FactionService) -> void:
	_factions = service


func set_relationship_service(service: RelationshipService) -> void:
	_relationship = service


func set_character_resolver(resolver: Callable) -> void:
	_character_resolver = resolver


# --- Setup: the cast ---------------------------------------------------------

## Begin simulating the character `actor_data` describes. The `CharacterState` must ALREADY
## exist in the registry — this service creates simulation records, never characters, so that
## "who exists" has exactly one owner (`CharacterRegistry`).
##
## Rejects (loud, false): a null/invalid authoring resource, a character the resolver cannot
## find, an already-simulated actor, and a schedule that is not in the catalog. Nothing is
## written on a rejection.
func register_actor(actor_data: WorldSimActorData) -> bool:
	if not is_usable():
		push_error("[worldsim] register_actor: the service is not usable")
		return false
	if actor_data == null or not actor_data.is_valid():
		push_error("[worldsim] register_actor: null/invalid actor data")
		return false
	if _state.has_actor(actor_data.id):
		push_error("[worldsim] register_actor: '%s' is already simulated" % actor_data.id)
		return false
	if _catalog.find_schedule(actor_data.schedule.id) == null:
		push_error("[worldsim] register_actor '%s': schedule '%s' is not in the catalog"
			% [actor_data.id, actor_data.schedule.id])
		return false
	var character := _resolve_character(actor_data.id)
	if character == null:
		push_error(("[worldsim] register_actor '%s': no CharacterState resolves for that id; "
			+ "the simulation records state ABOUT characters and never invents them")
			% actor_data.id)
		return false
	var record := WorldSimActor.create(
		actor_data.id, actor_data.schedule.id, actor_data.home_map_id, _state.tick())
	if record == null:
		return false
	# Seed the derived activity from the clock so a freshly registered actor reports its real
	# routine position immediately rather than a default until the first tick.
	record.recompute_activity(actor_data.schedule, _state.tick())
	if not _state.add_actor(record):
		return false
	_sync_sim_cache(record)
	return true


## Queue every authored event at its `first_tick`. Call once, after the cast is registered.
## Returns false (loud) if any event cannot be queued — a world that silently dropped one of
## its authored events would be a world the content author cannot reason about.
func schedule_authored_events() -> bool:
	if not is_usable():
		push_error("[worldsim] schedule_authored_events: the service is not usable")
		return false
	for event in _catalog.events_sorted():
		if not _state.schedule_event(event.id, event.first_tick):
			push_error("[worldsim] could not queue authored event '%s'" % event.id)
			return false
	return true


## Validate that every authored event could ACTUALLY be applied, and that each relationship
## event's edge exists — FAIL CLOSED before the world starts.
##
## This is the check that keeps the tick loop honest. A tick cannot abort halfway (the clock
## has already moved and a draw has already been consumed), so the only safe place to discover
## "this event names a sect that does not exist" or "there is no RelationshipService to apply
## this through" is BEFORE any time passes. It is the same reasoning D-038/D-047 applied to the
## sect and faction mirrors: the dependency is not optional, so its absence is a start failure
## rather than a skipped step at runtime.
##
## For `RELATIONSHIP_SHIFT` it also CREATES the character↔character edge if missing. All edge
## creation happens here, never inside a tick: creation can fail, and a failure mid-tick would
## leave the world in a state that depended on when the player happened to walk somewhere.
func prepare_events() -> bool:
	if not is_usable():
		push_error("[worldsim] prepare_events: the service is not usable")
		return false
	for event in _catalog.events_sorted():
		match event.kind:
			WorldSimEventData.Kind.SECT_INFLUENCE:
				if not _prepare_sect_event(event):
					return false
			WorldSimEventData.Kind.FACTION_INFLUENCE:
				if not _prepare_faction_event(event):
					return false
			WorldSimEventData.Kind.RELATIONSHIP_SHIFT:
				if not _prepare_relationship_event(event):
					return false
			_:
				push_error("[worldsim] event '%s' has unknown kind %d"
					% [event.id, event.kind])
				return false
	return true


func _prepare_sect_event(event: WorldSimEventData) -> bool:
	if _sects == null:
		push_error(("[worldsim] event '%s' moves sect influence but no SectService is "
			+ "installed; the sect store owns that number and this simulation will not "
			+ "write it directly") % event.id)
		return false
	if _sects.get_store() == null or not _sects.get_store().has(event.target_id):
		push_error("[worldsim] event '%s' names sect '%s', which is not in the sect store"
			% [event.id, event.target_id])
		return false
	return true


func _prepare_faction_event(event: WorldSimEventData) -> bool:
	if _factions == null:
		push_error(("[worldsim] event '%s' moves faction influence but no FactionService is "
			+ "installed") % event.id)
		return false
	if _factions.get_store() == null or not _factions.get_store().has(event.target_id):
		push_error("[worldsim] event '%s' names faction '%s', which is not in the faction "
			% [event.id, event.target_id] + "store")
		return false
	return true


## Validate + ENSURE the edge for a relationship event (see `prepare_events`).
func _prepare_relationship_event(event: WorldSimEventData) -> bool:
	if _relationship == null:
		push_error(("[worldsim] event '%s' shifts a relationship but no RelationshipService "
			+ "is installed; relationship dimensions live on edges in the ONE graph and this "
			+ "simulation will not keep a second copy") % event.id)
		return false
	if not _relationship.has_dimension(event.dimension):
		push_error(("[worldsim] event '%s' shifts dimension '%s', which the relationship "
			+ "config does not define") % [event.id, event.dimension])
		return false
	for endpoint_id in [event.target_id, event.secondary_id]:
		if not _state.has_actor(endpoint_id):
			push_error(("[worldsim] event '%s' names '%s', which is not a simulated actor; "
				+ "a relationship the simulation moves must be between characters it knows")
				% [event.id, endpoint_id])
			return false
	var eid := edge_id(event.target_id, event.secondary_id)
	var store := _relationship.get_store()
	if store != null and store.get_edge(eid) != null:
		return true  # already there (hydrated save, or a second event on the same pair)
	var edge := _relationship.create_edge(
		eid,
		RelationshipEndpoint.for_character(event.target_id),
		RelationshipEndpoint.for_character(event.secondary_id),
		&"ACQUAINTED", true, false)
	if edge == null:
		push_error("[worldsim] event '%s': could not create the edge '%s' it needs"
			% [event.id, eid])
		return false
	return true


## Deterministic, stable edge id for a simulated character pair: endpoints sorted so A-B and
## B-A map to the SAME id (one edge per pair), namespaced away from the sect/faction mirrors.
static func edge_id(a: StringName, b: StringName) -> StringName:
	var sa := String(a)
	var sb := String(b)
	if sa <= sb:
		return StringName("%s%s|%s" % [EDGE_PREFIX, sa, sb])
	return StringName("%s%s|%s" % [EDGE_PREFIX, sb, sa])


# --- LOD bands ---------------------------------------------------------------

## Recompute every actor's band from the player's position: the player's own map is NEAR, a
## map in `adjacent_map_ids` is MID, everything else is FAR
## (`docs/WORLD_SIMULATION.md` §2). Returns how many actors changed band.
##
## The MAP GRAPH is passed in rather than read here, deliberately: which maps are adjacent is
## a `MapData.exits` question, and a domain service that loaded the map catalog would be
## reaching into content it has no business knowing (`03-architecture.md` layer direction).
## `WorldSimulationRuntime` walks the graph and hands the answer down.
##
## A promoted actor's activity is recomputed IMMEDIATELY, so it is correct the moment anyone
## looks at it rather than at the next tick. That is what makes a band change lossless: the
## value it catches up to is exactly the value it would have had if it had been observed all
## along (see `WorldSimActor`'s note).
func assign_bands(player_map_id: StringName, adjacent_map_ids: Dictionary) -> int:
	if not is_usable():
		push_error("[worldsim] assign_bands: the service is not usable")
		return 0
	var changed := 0
	for actor in _state.actors_sorted():
		var band := WorldSimActor.Band.FAR
		if actor.location_map_id == player_map_id and player_map_id != &"":
			band = WorldSimActor.Band.NEAR
		elif adjacent_map_ids.has(actor.location_map_id):
			band = WorldSimActor.Band.MID
		# Through the STATE, so its observed-actor index stays in step with the band. Calling
		# `actor.set_band()` here directly would leave a promoted actor out of the per-tick
		# working set, silently, forever.
		if not _state.set_actor_band(actor.instance_id, band):
			continue
		changed += 1
		_refresh_actor(actor, _state.tick())
		actor_band_changed.emit(actor.instance_id, band)
	return changed


# --- The engine --------------------------------------------------------------

## Advance the world by `count` ticks, BOUNDED by the authored catch-up budget.
##
## Returns how many ticks were actually processed. Anything beyond the budget becomes
## CARRY-OVER and is processed by the following calls, in order, never dropped
## (`docs/WORLD_SIMULATION.md` §5 / B15). So:
##   * `advance_ticks(10)` with a budget of 64 → processes 10, no debt;
##   * `advance_ticks(100)` with a budget of 64 → processes 64, leaves 36 of debt;
##   * the next `advance_ticks(1)` → processes 37 (the debt first, then the new tick).
##
## Processing N ticks as `a + b` is IDENTICAL to processing them in one call, because each tick
## is processed independently and in order and the debt is always drained before new time is
## added. That equality is asserted by test, because it is the whole reason a bounded catch-up
## is allowed to exist.
func advance_ticks(count: int) -> int:
	if not is_usable():
		push_error("[worldsim] advance_ticks: the service is not usable")
		return 0
	if count <= 0:
		push_error("[worldsim] advance_ticks requires a positive count (got %d)" % count)
		return 0
	_state.add_carry_over(count)
	var budget := _catalog.catch_up_budget_ticks
	var to_process := _state.drain_carry_over(budget)
	var processed := 0
	for _i in to_process:
		if not _process_one_tick():
			break
		processed += 1
	if processed < to_process:
		# A tick failed to start (only possible on an invalid clock). Put the unspent time
		# back rather than losing it — "no dropped ticks" has no exceptions.
		_state.add_carry_over(to_process - processed)
	return processed


## Simulation time promised but not yet spent.
func pending_catch_up_ticks() -> int:
	return _state.carry_over_ticks() if _state != null else 0


## One tick: move the clock, fire everything due, refresh the observed actors, announce.
func _process_one_tick() -> bool:
	if not _state.clock().advance(1):
		return false
	var now := _state.clock().tick()
	for entry in _state.take_due_events(now):
		_fire_event(StringName(String(entry.get("event_id", ""))), now)
	for actor in _state.observed_actors_sorted():
		var schedule := _catalog.find_schedule(actor.schedule_id)
		if schedule == null:
			push_error("[worldsim] actor '%s' keeps schedule '%s', which is not in the catalog"
				% [actor.instance_id, actor.schedule_id])
			continue
		if actor.recompute_activity(schedule, now):
			_sync_sim_cache(actor)
			actor_state_changed.emit(actor.instance_id, actor.activity())
	world_tick.emit(now)
	return true


## Fire one scheduled event: draw its magnitude, apply it through the owning service, log it,
## announce it, and reschedule it if it recurs.
##
## THE DRAW HAPPENS FIRST, unconditionally. If the application were attempted first and the
## draw skipped on failure, then a content bug in one event would change how far the stream had
## advanced and therefore every later event in the world — a local mistake with global,
## invisible consequences. A failed application is reported loudly and the world stays
## deterministic. `prepare_events()` is what makes such a failure a bug rather than a
## possibility.
func _fire_event(event_id: StringName, now: int) -> void:
	var event := _catalog.find_event(event_id)
	if event == null:
		push_error("[worldsim] tick %d: queued event '%s' is not in the catalog"
			% [now, event_id])
		return
	var magnitude := _stream.next_range(event.magnitude_min, event.magnitude_max)
	if not _apply_event(event, magnitude):
		push_error(("[worldsim] tick %d: event '%s' could not be applied (its target or "
			+ "service changed after prepare_events validated it); the draw was still "
			+ "consumed so the world stays deterministic") % [now, event_id])
	else:
		_state.append_log({
			"tick": now,
			"event_id": String(event.id),
			"kind": event.kind,
			"target_id": String(event.target_id),
			"magnitude": magnitude,
		})
		world_event_triggered.emit(event.id, event.kind, event.target_id, magnitude)
	if event.is_recurring():
		_state.schedule_event(event.id, now + event.period_ticks)


## Apply one event THROUGH the service that owns the state it changes. Returns false (quiet —
## the caller reports with the tick context) when the owning service rejects it.
func _apply_event(event: WorldSimEventData, magnitude: int) -> bool:
	match event.kind:
		WorldSimEventData.Kind.SECT_INFLUENCE:
			if _sects == null:
				return false
			return _sects.adjust_influence(event.target_id, magnitude) >= 0
		WorldSimEventData.Kind.FACTION_INFLUENCE:
			if _factions == null:
				return false
			return _factions.adjust_influence(event.target_id, magnitude) >= 0
		WorldSimEventData.Kind.RELATIONSHIP_SHIFT:
			if _relationship == null:
				return false
			# `apply_delta` returning false means "no effect" (already clamped at a bound),
			# which is a legitimate outcome rather than a failure: a rivalry that is already
			# maxed out cannot rise further. The edge's existence was proven in
			# `prepare_events`, so a genuine error here would have been reported by the
			# service itself.
			_relationship.apply_delta(
				edge_id(event.target_id, event.secondary_id),
				event.dimension, magnitude, RELATIONSHIP_CAUSE)
			return true
	return false


# --- Reads -------------------------------------------------------------------

## The actor's CURRENT activity, derived from the clock — correct for EVERY band, including a
## FAR actor that has not been looked at for a thousand ticks.
##
## This, not the cached field, is what a caller should read. The cache exists only so a
## transition can be detected; a read that went through it would be stale for FAR actors and
## would make the answer depend on the player's travel history.
func activity_of(instance_id: StringName) -> int:
	var actor := _state.get_actor(instance_id) if _state != null else null
	if actor == null:
		push_error("[worldsim] activity_of: '%s' is not a simulated actor" % instance_id)
		return WorldSimScheduleData.Activity.RESTING
	var schedule := _catalog.find_schedule(actor.schedule_id)
	if schedule == null:
		push_error("[worldsim] activity_of '%s': schedule '%s' is not in the catalog"
			% [instance_id, actor.schedule_id])
		return WorldSimScheduleData.Activity.RESTING
	return schedule.activity_at(actor.elapsed_at(_state.clock().tick()))


## Bring an actor's cached activity + character cache up to date at `now` (used on promotion).
func _refresh_actor(actor: WorldSimActor, now: int) -> void:
	var schedule := _catalog.find_schedule(actor.schedule_id)
	if schedule == null:
		return
	actor.recompute_activity(schedule, now)
	_sync_sim_cache(actor)


# --- The `CharacterState.sim_state` derived cache ---------------------------

## Write an actor's compact snapshot into its `CharacterState.sim_state`.
##
## `sim_state` is a CACHE, not the authority (`docs/CHARACTER_SYSTEM.md` §5 reserves the field
## for the simulation; the authority is the `WorldSimActor` record here). The relationship is
## the same one `SectService` has with `CharacterState.sect_id` (D-015), and it exists for the
## same reason: another system holding a character should be able to ask that character what it
## is doing without reaching into this service.
func _sync_sim_cache(actor: WorldSimActor) -> void:
	var character := _resolve_character(actor.instance_id)
	if character == null:
		push_warning("[worldsim] sim cache: '%s' does not resolve" % actor.instance_id)
		return
	character.sim_state = actor.sim_state_cache()


## Rebuild every actor's `sim_state` cache FROM the authoritative records (the records win).
func sync_character_caches() -> void:
	if _state == null:
		return
	for actor in _state.actors_sorted():
		_sync_sim_cache(actor)


## True when every actor's `CharacterState.sim_state` agrees with its authoritative record.
## Reports each disagreement loudly — detecting drift, never papering over it, exactly as
## `SectService.verify_character_cache()` does for membership.
func verify_character_caches() -> bool:
	if _state == null:
		return true
	if not _character_resolver.is_valid():
		return true  # character checks disabled (pure-record unit tests)
	var consistent := true
	for actor in _state.actors_sorted():
		var character := _resolve_character(actor.instance_id)
		if character == null:
			push_error("[worldsim] cache check: actor '%s' does not resolve"
				% actor.instance_id)
			consistent = false
			continue
		if not actor.matches_sim_state_cache(character.sim_state):
			push_error("[worldsim] cache check: '%s' sim_state %s disagrees with the record %s"
				% [actor.instance_id, str(character.sim_state),
					str(actor.sim_state_cache())])
			consistent = false
	return consistent


func _resolve_character(instance_id: StringName) -> CharacterState:
	if not _character_resolver.is_valid():
		return null
	return _character_resolver.call(instance_id)
