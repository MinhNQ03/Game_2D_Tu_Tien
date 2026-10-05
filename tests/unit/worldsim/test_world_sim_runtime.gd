extends TestCase
## Unit tests for `WorldSimulationRuntime` (Phase 08) — the per-session owner.
##
## Three things are asserted here that the domain tests cannot see:
##   1. **It is a plain Node under Systems, not an autoload**, and it SPAWNS NOTHING in any
##      band — the "Far band has no entity nodes" guarantee, checked by counting children
##      rather than by trusting a comment.
##   2. **It does no per-frame work.** No `_process`, no `_physics_process`, no `Timer`, no
##      wall-clock read. This is checked by reading the SOURCE, because the cheapest way for
##      this class to betray its whole design is for somebody to add a `_process` that "just"
##      accumulates delta, and no behavioural test would notice.
##   3. **Its start is FAIL-CLOSED on every dependency**, leaving no observable half-session
##      (L-025): a missing dependency must make `is_session_active()` false and every getter
##      empty, not merely log a warning.
##
## It runs against the REAL shipped content (the world-sim, sect, faction, map and relationship
## catalogs), because the thing most worth knowing is that the authored world actually starts.
##
## The runtime is a Node, so every instance is freed (L-019), and the fixture clears the
## resolver `Callable`s it hands to services so the capture of `self` cannot close an
## uncollectable reference cycle (L-030).

const RuntimeScript := preload("res://src/gameplay/world/world_sim_runtime.gd")
const RegistryScript := preload("res://src/domain/character/character_registry.gd")

const SectStoreScript := preload("res://src/domain/sect/sect_store.gd")
const SectServiceScript := preload("res://src/domain/sect/sect_service.gd")
const FactionStoreScript := preload("res://src/domain/faction/faction_store.gd")
const FactionServiceScript := preload("res://src/domain/faction/faction_service.gd")
const RelStoreScript := preload("res://src/domain/relationship/relationship_store.gd")
const RelServiceScript := preload("res://src/domain/relationship/relationship_service.gd")

const RUNTIME_SOURCE_PATH := "res://src/gameplay/world/world_sim_runtime.gd"
const SECT_CATALOG_PATH := "res://data/sects/sect_catalog.tres"
const FACTION_CATALOG_PATH := "res://data/factions/faction_catalog.tres"
const MAP_CATALOG_PATH := "res://data/maps/map_catalog.tres"
const REL_CONFIG_PATH := "res://data/relationship/relationship_config.tres"

## Per-frame work this class must never contain. `Timer`/`Time`/`OS` are listed alongside the
## engine callbacks because "advance the clock from real seconds" is the specific temptation —
## it would make the world non-reproducible and un-advanceable by a future server
## (`MULTIPLAYER_PLAN.md` §7).
const FORBIDDEN_PER_FRAME := [
	"func _process", "func _physics_process", "Timer", "Time.get_ticks",
	"Time.get_unix_time", "OS.get_ticks", "randomize(", "randi(", "randf(",
]

var _registry: CharacterRegistry = null
var _sects: SectService = null
var _factions: FactionService = null
var _relationship: RelationshipService = null


func after_each() -> void:
	if _sects != null:
		_sects.set_character_resolver(Callable())
	if _factions != null:
		_factions.set_character_resolver(Callable())
	_registry = null
	_sects = null
	_factions = null
	_relationship = null


# --- fixture: the real shipped world, minus the player ----------------------

## Build the live sect + faction + relationship world from the SHIPPED catalogs, exactly the
## way `SectRuntime`/`FactionRuntime` do. Returns false if the content cannot be composed, so
## a caller bails instead of reporting a misleading failure.
func _build_real_world() -> bool:
	_registry = RegistryScript.new()

	var cfg := load(REL_CONFIG_PATH) as RelationshipConfigData
	if cfg == null:
		return false
	var rel_store: RelationshipStore = RelStoreScript.new(cfg)
	_relationship = RelServiceScript.new(rel_store, cfg)

	var sect_catalog := load(SECT_CATALOG_PATH) as SectCatalog
	if sect_catalog == null or not sect_catalog.is_valid():
		return false
	var sect_store: SectStore = SectStoreScript.new()
	_sects = SectServiceScript.new(sect_store)
	_sects.set_relationship_service(_relationship)
	_sects.set_character_resolver(_registry.resolver())
	for tmpl in sect_catalog.sects:
		if tmpl == null or not _sects.register_sect(SectState.create_from_template(tmpl), tmpl):
			return false
	if not _sects.apply_default_diplomacy():
		return false

	var faction_catalog := load(FACTION_CATALOG_PATH) as FactionCatalog
	if faction_catalog == null or not faction_catalog.is_valid():
		return false
	var faction_store: FactionStore = FactionStoreScript.new()
	_factions = FactionServiceScript.new(faction_store)
	_factions.set_sect_store(sect_store)
	_factions.set_relationship_service(_relationship)
	_factions.set_character_resolver(_registry.resolver())
	for tmpl in faction_catalog.factions:
		if tmpl == null \
				or not _factions.register_faction(
					FactionState.create_from_template(tmpl), tmpl):
			return false
	if not _factions.validate_against_sects():
		return false
	if not _factions.apply_default_politics():
		return false
	return true


func _map_lookup() -> Dictionary:
	var catalog := load(MAP_CATALOG_PATH) as MapCatalog
	if catalog == null or not catalog.is_valid():
		return {}
	return catalog.build_lookup()


func _runtime() -> WorldSimulationRuntime:
	var node: WorldSimulationRuntime = RuntimeScript.new()
	node.name = "WorldSimulationRuntime"
	return node


# === 1-2. Shape ==============================================================

func test_01_it_is_a_plain_node_and_not_an_autoload() -> void:
	var runtime := _runtime()
	assert_true(runtime is Node, "it is a Node")
	assert_true(add_to_tree(runtime), "it can live in the tree")
	# NOT an autoload: the D-017 budget stays at five, so nothing named like this may sit
	# directly under /root.
	var autoloaded := 0
	for child in scene_tree.root.get_children():
		if child.name == "WorldSimulationRuntime":
			autoloaded += 1
	assert_eq(autoloaded, 1,
		"only the node this test parented is there — there is no WorldSimulationRuntime "
		+ "AUTOLOAD (the budget is frozen at 5, D-017)")
	assert_false(runtime.is_session_active(), "a fresh runtime has no session")
	assert_null(runtime.get_service(), "and no service")
	assert_null(runtime.get_state(), "and no state")
	assert_eq(runtime.pending_catch_up_ticks(), 0, "and no catch-up debt")
	var view: WorldSimView = runtime.get_view()
	assert_not_null(view, "get_view never returns null")
	assert_false(view.available, "but reports unavailable with no session")
	free_node(runtime)


## THE PER-FRAME GUARD. Read from the source, because a behavioural test cannot distinguish
## "has no `_process`" from "has a `_process` that happened not to matter in this test".
func test_02_the_runtime_does_no_per_frame_work() -> void:
	var file := FileAccess.open(RUNTIME_SOURCE_PATH, FileAccess.READ)
	assert_not_null(file, "the runtime source is readable")
	if file == null:
		return
	var source := file.get_as_text()
	file.close()
	# Strip comments: the class note legitimately DISCUSSES `_process` and `Timer` to explain
	# why they are absent, and a guard that fired on its own documentation would be deleted by
	# the next person who hit it.
	var code_lines: Array[String] = []
	for raw in source.split("\n"):
		var line := String(raw)
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		var comment_at := line.find("#")
		code_lines.append(line.substr(0, comment_at) if comment_at >= 0 else line)
	var code := "\n".join(code_lines)
	for forbidden in FORBIDDEN_PER_FRAME:
		assert_false(code.contains(String(forbidden)),
			("the world simulation runtime must contain no '%s': simulated time passes on "
				+ "EXPLICIT gameplay beats, and a real-time or randomised driver would make "
				+ "the world non-reproducible and un-advanceable by a future server")
				% String(forbidden))


# === 3-5. Fail-closed start ==================================================

## Every dependency is REQUIRED, and its absence must leave NO observable session (L-025) —
## not a warning and a half-built world.
func test_03_a_missing_dependency_leaves_no_half_session() -> void:
	if not _build_real_world():
		assert_true(false, "the shipped sect/faction content could not be composed")
		return
	var maps := _map_lookup()
	assert_false(maps.is_empty(), "the shipped map catalog loads")

	var cases := {
		"no character registry": [null, _sects, _factions, _relationship, maps],
		"no sect service": [_registry, null, _factions, _relationship, maps],
		"no faction service": [_registry, _sects, null, _relationship, maps],
		"no relationship service": [_registry, _sects, _factions, null, maps],
		"no map catalog": [_registry, _sects, _factions, _relationship, {}],
	}
	var names: Array = cases.keys()
	names.sort()
	for name in names:
		var args: Array = cases[name]
		var runtime := _runtime()
		add_to_tree(runtime)
		var started: bool = runtime.start_session(
			args[0], args[1], args[2], args[3], args[4])
		assert_false(started, "starting with %s is REJECTED" % String(name))
		# The whole point of L-025: a failure is invisible by construction.
		assert_false(runtime.is_session_active(),
			"and no session is observable afterwards (%s)" % String(name))
		assert_null(runtime.get_service(), "no service (%s)" % String(name))
		assert_null(runtime.get_state(), "no state (%s)" % String(name))
		assert_null(runtime.get_catalog(), "no catalog (%s)" % String(name))
		assert_false(runtime.get_view().available, "no view (%s)" % String(name))
		free_node(runtime)


## An invalid world seed must be an explicit refusal, not a silent substitution (B20).
func test_04_an_invalid_seed_is_refused() -> void:
	if not _build_real_world():
		return
	var runtime := _runtime()
	add_to_tree(runtime)
	assert_false(runtime.start_session(
		_registry, _sects, _factions, _relationship, _map_lookup(), -1),
		"a negative world seed is refused")
	assert_false(runtime.is_session_active(), "and leaves no session")
	free_node(runtime)


## THE REAL AUTHORED WORLD STARTS. This is the assertion that would catch a content error (a
## renamed sect, a rank not on the ladder, an event naming a stranger) before a player hits it.
func test_05_the_shipped_world_starts_and_spawns_nothing() -> void:
	if not _build_real_world():
		return
	var runtime := _runtime()
	add_to_tree(runtime)
	var started: bool = runtime.start_session(
		_registry, _sects, _factions, _relationship, _map_lookup())
	assert_true(started, "the SHIPPED world simulation starts")
	if not started:
		free_node(runtime)
		return
	assert_true(runtime.is_session_active(), "the session is active")
	var state: WorldSimulationState = runtime.get_state()
	assert_not_null(state, "it exposes its state")
	assert_true(state.actor_count() >= 2, "with the authored cast simulated (got %d)"
		% state.actor_count())
	assert_true(state.pending_count() >= 1, "and the authored events queued")

	# THE "FAR HAS NO ENTITY NODES" GUARANTEE, checked by counting rather than by trusting:
	# Phase 08 instantiates nothing in ANY band, so a simulated cast of N costs zero nodes.
	assert_eq(runtime.get_child_count(), 0,
		("the simulation created NO child nodes for its %d actors — background characters are "
			+ "pure serializable state, not entities (`WORLD_SIMULATION.md` §2)")
			% state.actor_count())

	# Every actor's character really is in the SHARED registry, not a private copy.
	for actor in state.actors_sorted():
		assert_true(_registry.has(actor.instance_id),
			"actor '%s' has a CharacterState in the shared registry" % actor.instance_id)
		var character: CharacterState = _registry.get_character(actor.instance_id)
		assert_false(character.sim_state.is_empty(),
			"and carries a sim_state cache (%s)" % actor.instance_id)
		# Membership went through the OWNING service, so the sect roster knows them (D-015).
		if character.sect_id != &"":
			var sect: SectState = _sects.get_store().get_sect(character.sect_id)
			assert_not_null(sect, "the sect '%s' exists" % character.sect_id)
			if sect != null:
				assert_true(sect.is_member(actor.instance_id),
					"'%s' is on the authoritative sect roster" % actor.instance_id)
	assert_true(runtime.get_service().verify_character_caches(),
		"and every derived sim_state cache agrees with its record")

	# Idempotent: a second start with a live session is a no-op that reports success.
	assert_true(runtime.start_session(
		_registry, _sects, _factions, _relationship, _map_lookup()),
		"a second start with an active session is an idempotent no-op")
	free_node(runtime)


# === 6-7. The explicit beat + teardown ======================================

## Arriving in a map is THE beat: it re-assigns bands and advances the world by the authored
## per-transition cost. Nothing else moves the clock.
func test_06_arriving_in_a_map_is_what_advances_the_world() -> void:
	if not _build_real_world():
		return
	var runtime := _runtime()
	add_to_tree(runtime)
	if not runtime.start_session(
			_registry, _sects, _factions, _relationship, _map_lookup()):
		free_node(runtime)
		return
	var state: WorldSimulationState = runtime.get_state()
	var catalog: WorldSimCatalog = runtime.get_catalog()
	var before := state.tick()

	var processed: int = runtime.on_player_arrived(&"map_hub")
	assert_eq(processed, catalog.ticks_per_map_transition,
		"one arrival advances the world by exactly the authored cost")
	assert_eq(state.tick(), before + catalog.ticks_per_map_transition, "the clock moved")
	assert_eq(runtime.get_player_map_id(), &"map_hub", "and the player's location is recorded")

	# Bands follow the player: an actor living in the arrival map is NEAR.
	var near_found := false
	for actor in state.actors_sorted():
		if actor.location_map_id == &"map_hub":
			assert_eq(actor.band(), WorldSimActor.Band.NEAR,
				"'%s' lives in the arrival map and is NEAR" % actor.instance_id)
			near_found = true
	assert_true(near_found, "the shipped cast includes somebody in the hub")

	# Arriving somewhere else moves the bands with the player.
	runtime.on_player_arrived(&"map_field")
	for actor in state.actors_sorted():
		if actor.location_map_id == &"map_hub":
			assert_ne(actor.band(), WorldSimActor.Band.NEAR,
				"'%s' is no longer NEAR once the player left" % actor.instance_id)

	# The view is available and carries a real date + the feed's latest entry.
	var view: WorldSimView = runtime.get_view()
	assert_true(view.available, "the view is available during a session")
	assert_eq(view.tick, state.tick(), "and reports the live tick")
	assert_true(view.year >= 1 and view.season >= 1 and view.day >= 1,
		"with a 1-based date (got y%d s%d d%d)" % [view.year, view.season, view.day])
	free_node(runtime)


## Ending the session drops everything, is safe to repeat, and leaves the NODE alive (only its
## session ends) — the contract `Main`'s ordered teardown relies on.
func test_07_end_session_clears_everything_and_is_repeatable() -> void:
	if not _build_real_world():
		return
	var runtime := _runtime()
	add_to_tree(runtime)
	if not runtime.start_session(
			_registry, _sects, _factions, _relationship, _map_lookup()):
		free_node(runtime)
		return
	runtime.on_player_arrived(&"map_hub")
	assert_true(runtime.is_session_active(), "the session is live")

	runtime.end_session()
	assert_false(runtime.is_session_active(), "end_session clears the session")
	assert_null(runtime.get_service(), "the service is dropped")
	assert_null(runtime.get_state(), "the state is dropped")
	assert_null(runtime.get_catalog(), "the catalog is dropped")
	assert_eq(runtime.get_player_map_id(), &"", "the player location is cleared")
	assert_false(runtime.get_view().available, "and the view reports unavailable")
	assert_eq(runtime.pending_catch_up_ticks(), 0, "no debt survives the session")
	runtime.end_session()
	assert_false(runtime.is_session_active(), "calling it again is safe")
	# The beat is a no-op with no session, rather than an error that would spam the log every
	# time the player moved between menus.
	assert_eq(runtime.on_player_arrived(&"map_hub"), 0,
		"an arrival with no session advances nothing")
	assert_true(is_instance_valid(runtime), "the NODE itself survives (only its session ends)")
	free_node(runtime)
