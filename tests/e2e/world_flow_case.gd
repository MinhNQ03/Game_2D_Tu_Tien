extends TestCase
## E2E world/map-flow assertions (Phase 03 reopen, D-019 isolation + D-022 data-driven).
## A normal TestCase reusing the shared assert_* API, driven ONLY by the dedicated entrypoint
## `tests/e2e/run_world_flow.gd` in its OWN isolated Godot process (D-019 / L-010).
##
## It exercises the REAL world/map boundary end to end, through the REAL input pipeline
## (L-016/L-017): it NEVER calls `MapBase._unhandled_input`, `WorldRuntime.request_map_transition`,
## or `SceneRouter.request_transition` directly to drive gameplay. Semantic input is fed via
## `Input.parse_input_event` with real key events (the engine then dispatches `_input`/
## `_unhandled_input` and updates the InputMap action state). The ONLY headless concession is
## the Area2D sensor overlap: a real game-loop raises `body_entered`, which the headless `-s`
## process does not do reliably, so we emit the exit zone's OWN `body_entered(player)` signal
## (the exact signal the sensor raises) — the REAL MapBase handler then runs. A genuine
## semantic MOVEMENT step is also performed so the InputService movement path is exercised.
##
## Flow: real main.tscn → MainMenu.new_game_pressed → WorldRuntime → SceneRouter → hub map →
## persistent player → real movement → stand in exit (teleport setup) + real interact key →
## field → back → repeat >= 20 round trips (per-round + no-leak invariants) → real open_menu
## key → clean return to menu + player freed.

## The bootstrap script, for the frozen session-lifecycle order constants (D-047). Comparing
## the OBSERVED teardown against them is what keeps `tests/unit/bootstrap/test_session_lifecycle.gd`
## (which pins the constant) and this file (which pins the behaviour) from drifting apart.
const MainScript := preload("res://src/bootstrap/main.gd")

const MAIN_SCENE_PATH := "res://main.tscn"
const INTERACT := &"interact"
const OPEN_MENU := &"open_menu"
const MOVE_RIGHT := &"move_right"
const MOVE_UP := &"move_up"
const MOVE_DOWN := &"move_down"
const SECT_PANEL := &"sect_panel"
const CULTIVATE := &"cultivate"
const ROUND_TRIPS := 20

## Camera-follow probe geometry (D-036). The maps are 960x576 from (16,16), so the centre
## band is where a follow camera is free of its limit clamp and can actually travel.
const CAMERA_PROBE_START_X := 420.0
const CAMERA_PROBE_Y := 304.0
## Frames to let `position_smoothing` settle before sampling the camera; it eases, so a
## single-frame sample is not a stable baseline.
const CAMERA_SETTLE_FRAMES := 45
## Frames of held movement - long enough that travel clearly exceeds easing noise.
const CAMERA_PROBE_MOVE_FRAMES := 30
const REQUIRED_AUTOLOADS := [
	"EventBus", "GameState", "Localization", "InputService", "SceneRouter",
]

## The frozen reverse-dependency teardown order (D-047), as a literal — so this file states
## the contract rather than only restating whatever the bootstrap currently does.
const EXPECTED_TEARDOWN_ORDER := [
	&"DialogueRuntime", &"QuestRuntime",
	&"NpcRuntime", &"PetRuntime", &"SkillRuntime", &"EquipmentRuntime", &"InventoryRuntime",
	&"CultivationRuntime",
	&"KnowledgeRuntime",
	&"ProgressionRuntime", &"RewardRuntime", &"CombatRuntime", &"WorldSimulationRuntime",
	&"FactionRuntime", &"SectRuntime", &"RelationshipRuntime", &"WorldRuntime", &"GameState",
]


func test_real_world_map_flow() -> void:
	# --- 1. real autoloads present; none duplicated -------------------------------
	for autoload_name in REQUIRED_AUTOLOADS:
		assert_eq(_count_named(autoload_name), 1,
			"exactly one /root/%s (no duplicate autoload)" % autoload_name)

	var gs: Node = scene_tree.root.get_node_or_null("GameState")
	var router: Node = scene_tree.root.get_node_or_null("SceneRouter")
	var input: Node = scene_tree.root.get_node_or_null("InputService")
	if gs == null or router == null or input == null:
		assert_true(false, "core autoloads missing")
		return

	assert_eq(gs.get_phase(), gs.Phase.BOOT, "fresh GameState autoload starts at BOOT")

	# --- 2. boot the REAL main scene ---------------------------------------------
	var packed: PackedScene = load(MAIN_SCENE_PATH)
	var main: Node = packed.instantiate()
	scene_tree.root.add_child(main)
	await scene_tree.process_frame

	assert_eq(gs.get_phase(), gs.Phase.MENU, "boot reached MENU before any input")

	# --- 3. New Game via the REAL menu intent → hub map --------------------------
	var ui: Node = main.get_node_or_null("UI")
	if ui == null or ui.get_child_count() == 0:
		assert_true(false, "no MainMenu under UI")
		_teardown(main)
		return
	var menu: Node = ui.get_child(0)
	assert_true(menu.has_signal("new_game_pressed"), "menu exposes new_game_pressed")
	menu.emit_signal("new_game_pressed")
	await scene_tree.process_frame

	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "running after New Game")
	assert_eq(router.get_current_key(), "map_hub", "New Game loads the hub map first (Phase 03)")
	assert_eq(gs.call("get_current_map_id"), &"map_hub", "GameState records the hub")
	assert_true(input.call("is_gameplay_active"), "entering the map set GAMEPLAY input context")

	var world_runtime := _find_world_runtime(main)
	if world_runtime == null:
		assert_true(false, "WorldRuntime missing under Main/Systems")
		_teardown(main)
		return

	# Phase 05 (D-026): a RelationshipRuntime sibling must exist under Main/Systems, be a
	# non-autoload node, and persist (same instance) across every map swap. Capture its id now.
	var relationship_runtime := _find_relationship_runtime(main)
	assert_not_null(relationship_runtime, "RelationshipRuntime exists under Main/Systems")
	var relationship_id := -1
	if relationship_runtime != null:
		relationship_id = relationship_runtime.get_instance_id()
		assert_true(relationship_runtime.call("is_session_active"),
			"RelationshipRuntime session active after New Game")
		assert_eq(_count_named("RelationshipRuntime"), 0,
			"RelationshipRuntime is NOT an autoload (not under /root)")

	# Phase 06 (Sect): a SectRuntime sibling must exist under Main/Systems, be a non-autoload
	# node, run a session, and have enrolled the player into the authored start sect. Capture
	# its id to assert it survives map swaps.
	var sect_runtime := _find_sect_runtime(main)
	assert_not_null(sect_runtime, "SectRuntime exists under Main/Systems")
	var sect_runtime_id := -1
	if sect_runtime != null:
		sect_runtime_id = sect_runtime.get_instance_id()
		assert_true(sect_runtime.call("is_session_active"),
			"SectRuntime session active after New Game")
		assert_eq(_count_named("SectRuntime"), 0,
			"SectRuntime is NOT an autoload (not under /root)")
		assert_eq(sect_runtime.call("get_player_sect_id"), &"sect_azure_cloud",
			"player enrolled in the authored start sect")

	# Phase 07 (Faction): a FactionRuntime sibling must exist under Main/Systems, be a
	# non-autoload node and run a session. It is started LAST (it reads the sect store + the
	# relationship graph) and must therefore be ended FIRST, which §7 below asserts.
	var faction_runtime := _find_faction_runtime(main)
	assert_not_null(faction_runtime, "FactionRuntime exists under Main/Systems")
	var faction_runtime_id := -1
	if faction_runtime != null:
		faction_runtime_id = faction_runtime.get_instance_id()
		assert_true(faction_runtime.call("is_session_active"),
			"FactionRuntime session active after New Game")
		assert_eq(_count_named("FactionRuntime"), 0,
			"FactionRuntime is NOT an autoload (not under /root)")
		# The C-003 guard: Phase 07 enrols nobody, so the player holds no political identity.
		assert_eq(faction_runtime.call("get_player_instance_id"), &"player",
			"the faction session knows the player (for the view only)")

	# Phase 08 (World Simulation): the fifth sibling. It is started LAST (it reads all four
	# subsystems above) and must be ended FIRST, which §7b asserts against the real trace.
	var sim_runtime := _find_world_sim_runtime(main)
	assert_not_null(sim_runtime, "WorldSimulationRuntime exists under Main/Systems")
	var sim_runtime_id := -1
	var sim_tick_at_start := -1
	if sim_runtime != null:
		sim_runtime_id = sim_runtime.get_instance_id()
		assert_true(sim_runtime.call("is_session_active"),
			"WorldSimulationRuntime session active after New Game")
		assert_eq(_count_named("WorldSimulationRuntime"), 0,
			"WorldSimulationRuntime is NOT an autoload (not under /root)")
		# THE "no entity nodes" GUARANTEE, in the real application: a simulated cast costs
		# zero nodes in every band (`docs/WORLD_SIMULATION.md` §2/§6).
		assert_eq(sim_runtime.get_child_count(), 0,
			"the world simulation spawned NO nodes for its cast")
		var sim_state: WorldSimulationState = sim_runtime.call("get_state")
		assert_not_null(sim_state, "the simulation exposes its state")
		if sim_state != null:
			assert_true(sim_state.actor_count() >= 2,
				"the authored cast is simulated (got %d)" % sim_state.actor_count())
			sim_tick_at_start = sim_state.tick()
			# Arriving in the hub is the one explicit beat, and Main pushes it right after
			# starting the session — so the world has already moved off tick 0.
			assert_true(sim_tick_at_start > 0,
				"arriving in the hub advanced the world clock (got tick %d)"
					% sim_tick_at_start)
			# The cast is in the SHARED character registry, not a private copy.
			var registry: CharacterRegistry = world_runtime.call("get_character_registry")
			assert_not_null(registry, "WorldRuntime owns the shared character registry")
			if registry != null:
				assert_true(registry.count() >= 3,
					"the registry holds the player AND the simulated cast (got %d)"
						% registry.count())
				assert_true(registry.has(&"player"), "including the player")
				for sim_actor in sim_state.actors_sorted():
					assert_true(registry.has(sim_actor.instance_id),
						"simulated actor '%s' has a CharacterState in the SHARED registry"
							% sim_actor.instance_id)

	# Phase 06 final hardening (§3): the FORBIDDEN combination is "lifecycle RUNNING + a live
	# world + a character carrying a sect id + an INACTIVE sect session" — a running game whose
	# sect membership no subsystem owns. New Game now treats a sect failure as fatal, so
	# reaching RUNNING at all implies the sect session is live. Assert that implication here
	# (a regression would show as RUNNING with the sect subsystem dark).
	if gs.get_phase() == gs.Phase.RUNNING:
		assert_true(sect_runtime != null and sect_runtime.call("is_session_active"),
			"RUNNING implies a live SectRuntime session (the forbidden half-session state "
			+ "cannot be reached)")

	# §11: there is ONE relationship graph. The sect session's declared diplomacy must be
	# mirrored into the graph the RelationshipRuntime owns — not a private second graph.
	if relationship_runtime != null and sect_runtime != null:
		var rel_service: RelationshipService = relationship_runtime.call("get_service")
		assert_not_null(rel_service, "the relationship session exposes its service")
		if rel_service != null:
			var mirrored := rel_service.get_store().get_edge(
				SectService.edge_id(&"sect_azure_cloud", &"sect_crimson_flame"))
			assert_not_null(mirrored,
				"the authored Sect↔Sect enmity is mirrored into the SHARED relationship graph")
			if mirrored != null:
				assert_eq(mirrored.relationship_type, &"ENEMY",
					"the mirrored edge carries the declared type")

	var player: Node = world_runtime.call("get_player")
	assert_not_null(player, "WorldRuntime owns a persistent player")
	if player == null:
		_teardown(main)
		return
	var player_id := player.get_instance_id()  # proven-persistent identity across all maps

	# Phase 04 (D-023): the player is bound to ONE authoritative CharacterState that must NOT
	# be recreated on a map swap. Capture its identity now and assert it persists below.
	var character = world_runtime.call("get_player_character")
	assert_not_null(character, "WorldRuntime built the player's CharacterState")
	var character_id := -1
	if character != null:
		character_id = character.get_instance_id()
		assert_eq(String(character.instance_id), "player", "player state has the stable id")
		assert_true(character.is_alive(), "player starts ALIVE")
		# Phase 06 / D-015: the player's DERIVED cache matches the authoritative sect roster.
		if sect_runtime != null:
			var player_sect: SectState = sect_runtime.call("get_player_sect")
			assert_not_null(player_sect, "player's authoritative SectState resolves")
			if player_sect != null:
				assert_true(player_sect.is_member(character.instance_id),
					"player is on the authoritative sect roster")
				assert_eq(character.sect_id, player_sect.id,
					"CharacterState.sect_id matches the roster sect")
				assert_eq(character.sect_rank, player_sect.rank_of(character.instance_id),
					"CharacterState.sect_rank matches the roster rank")

	var hub_map: Node = router.get_current_scene()
	assert_true(_player_is_in_map(player, hub_map), "player is parented inside the hub map")

	# Camera limits are data-driven from MapData.bounds (Rect2(16,16,960,576) — D-036).
	_assert_camera_limits(hub_map, 16, 16, 976, 592, "hub")

	# --- 3b. Sect is VISIBLE in the HUD + the panel toggles via REAL input (Phase 06) ----
	var hud := _find_gameplay_hud(hub_map)
	assert_not_null(hud, "the hub map owns a GameplayHUD")
	if hud != null:
		# The HUD renders the player's sect: the localized name appears somewhere, and NO raw
		# sect id leaks into any label.
		var hud_text := _all_label_text(hud)
		var loc: Node = scene_tree.root.get_node_or_null("Localization")
		var sect_name := String(loc.call("t", "SECT_AZURE_CLOUD_NAME")) if loc != null else ""
		assert_true(sect_name != "" and (sect_name in hud_text),
			"HUD shows the localized sect name")
		for t in hud_text:
			assert_false(t.contains("sect_azure_cloud"),
				"no raw sect id leaks into the HUD (%s)" % t)
		# §7: the sect panel's resource summary must render localized names, never the
		# internal content ids the domain keys its resource dict by. Measured on the SECT
		# PANEL, the surface that renders those ids: since Phase 19 the HUD also holds the
		# journal's prose, and one of these ids ("pills") is an ordinary English word there
		# ("the two pills Lạc Hà owes its watch") — a substring match over the whole HUD
		# was reporting on English, not on a leak.
		var sect_panels := hud.find_children("*", "SectPanel", true, false)
		assert_eq(sect_panels.size(), 1, "the HUD owns one sect panel")
		var sect_text := _all_label_text(sect_panels[0]) if not sect_panels.is_empty() else []
		assert_true(sect_text.size() >= 4,
			"the sect panel's labels were read (%d)" % sect_text.size())
		for t in sect_text:
			for raw_resource_id in ["spirit_stones", "pills", "manpower"]:
				assert_false(t.contains(raw_resource_id),
					"no raw resource id '%s' leaks into the sect panel (%s)"
						% [raw_resource_id, t])
		# Toggle the Sect detail panel via a REAL `sect_panel` key event (bounded retry for
		# input-dispatch frame timing). It starts closed, opens on the key.
		assert_false(hud.call("is_sect_panel_open"), "sect panel starts closed")
		for _attempt in range(8):
			await _fire_action(SECT_PANEL)
			await scene_tree.process_frame
			if bool(hud.call("is_sect_panel_open")):
				break
		assert_true(hud.call("is_sect_panel_open"), "a real sect_panel key opened the panel")

	# --- 4. a REAL semantic MOVEMENT step (proves InputService movement path) -----
	await _prove_movement(player, input, hub_map)

	# --- 4b. a REAL attack key DAMAGES a REAL target (Phase 09, D-007) -----------
	await _prove_combat(main, player, hub_map)

	# --- 4c. CULTIVATION + KNOWLEDGE through real keys (Phase 12) ----------------
	await _prove_cultivation(main, player, hub_map)

	# --- 4d. ITEMS: pick up, open the satchel, choose and use through real keys (P13) ---
	await _prove_inventory(main, player, hub_map)

	# --- 4e. EQUIPMENT: wear and wield through the satchel with real keys (P14) ---------
	await _prove_equipment(main, player, hub_map)

	# --- 4f. TECHNIQUE A (Phong) on the training post through the real skill key (P15) ---
	await _prove_technique_phong(main, player, hub_map)

	# --- 5. first transition hub → field via REAL interact input -----------------
	await _interact_to_transition(player, "map_hub")
	assert_eq(router.get_current_key(), "map_field", "real interact transitioned hub → field")
	assert_eq(gs.call("get_current_map_id"), &"map_field", "GameState now records the field")
	var field_map: Node = router.get_current_scene()
	assert_eq(player.get_instance_id(), player_id, "SAME player instance after transition")
	assert_true(_player_is_in_map(player, field_map), "player re-parented into the field map")
	_assert_camera_limits(field_map, 16, 16, 976, 592, "field")

	# --- 5b. A REAL ENCOUNTER in the field (Phase 10) ----------------------------
	await _prove_encounter(main, player, field_map)

	# --- 5c. TECHNIQUE B (Lôi): learn it in the woods, bolt a wolf (P15) -------------
	await _prove_technique_loi(main, player, field_map)

	# --- 6. >= 20 round trips, per-round invariants + no orphan leak -------------
	await scene_tree.process_frame
	var baseline: float = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	for i in range(ROUND_TRIPS):
		var from_key := str(router.call("get_current_key"))
		await _interact_to_transition(player, from_key)
		var now_key := str(router.call("get_current_key"))
		assert_ne(now_key, from_key, "round %d: map changed (%s -> %s)" % [i, from_key, now_key])
		assert_eq(player.get_instance_id(), player_id, "round %d: SAME player instance" % i)
		# The authoritative CharacterState is NOT recreated on a map swap (D-023 invariant):
		# WorldRuntime owns one for the session and the SAME player node keeps carrying it.
		var round_character = world_runtime.call("get_player_character")
		assert_true(round_character != null and round_character.get_instance_id() == character_id,
			"round %d: SAME CharacterState instance (not recreated on map swap)" % i)
		# The RelationshipRuntime (and its graph) is the SAME instance across the map swap too
		# (D-026): it lives under Main/Systems and is never freed/rebuilt by a content swap.
		var round_rel := _find_relationship_runtime(main)
		assert_true(round_rel != null and round_rel.get_instance_id() == relationship_id,
			"round %d: SAME RelationshipRuntime instance (survives map swap)" % i)
		# The SectRuntime (+ the player's SectState membership) is the SAME across the swap
		# (Phase 06): it lives under Main/Systems and is never freed/rebuilt by a content swap.
		var round_sect := _find_sect_runtime(main)
		assert_true(round_sect != null and round_sect.get_instance_id() == sect_runtime_id,
			"round %d: SAME SectRuntime instance (survives map swap)" % i)
		if round_sect != null:
			assert_eq(round_sect.call("get_player_sect_id"), &"sect_azure_cloud",
				"round %d: player's sect membership persists across the swap" % i)
		assert_eq(_count_player_instances(scene_tree.root), 1, "round %d: exactly one Player" % i)
		var active: Node = router.get_current_scene()
		assert_true(_player_is_in_map(player, active), "round %d: player in active map" % i)
		var world: Node = main.get_node_or_null("World")
		if world != null:
			assert_eq(world.get_child_count(), 1, "round %d: one active content scene" % i)
		assert_eq(gs.call("get_current_map_id"), StringName(now_key),
			"round %d: GameState map id matches router" % i)
		assert_false(router.call("is_transitioning"), "round %d: router not stuck" % i)
	# --- 6b. THE WORLD MOVED WHILE THE PLAYER TRAVELLED (Phase 08) ---------------
	# This is the payoff assertion for the whole phase: 20 real map transitions are 20 real
	# gameplay beats, so simulated time must have passed and the world must have DONE
	# something — without a single node having been spawned for the cast.
	if sim_runtime != null and sim_tick_at_start >= 0:
		var sim_state_after: WorldSimulationState = sim_runtime.call("get_state")
		assert_not_null(sim_state_after, "the simulation is still live after the round trips")
		if sim_state_after != null:
			assert_true(sim_state_after.tick() > sim_tick_at_start,
				("the world clock advanced across %d map transitions (%d -> %d): simulated "
					+ "time passes on real gameplay beats, not on a timer")
					% [ROUND_TRIPS, sim_tick_at_start, sim_state_after.tick()])
			assert_true(sim_state_after.event_log().size() > 0,
				"and the world actually DID something while the player travelled")
			# Bands followed the player. The shipped world is two ADJACENT maps, so the cast
			# is NEAR/MID and nobody is FAR — asserted as the census it should be rather than
			# as a hopeful ">= 0".
			var census := sim_state_after.band_census()
			assert_eq(census[WorldSimActor.Band.NEAR] + census[WorldSimActor.Band.MID],
				sim_state_after.actor_count(),
				("every actor is NEAR or MID in the shipped two-map world, because both maps "
					+ "are adjacent; FAR becomes reachable when a third, non-adjacent map is "
					+ "authored (census %s)") % str(census))
			assert_true(census[WorldSimActor.Band.NEAR] > 0,
				"and somebody is in the player's own map")
		assert_eq(sim_runtime.get_child_count(), 0,
			"still ZERO nodes for the simulated cast after %d transitions" % ROUND_TRIPS)
		assert_eq(sim_runtime.get_instance_id(), sim_runtime_id,
			"and it is the SAME WorldSimulationRuntime instance (survives map swaps)")
		# The HUD renders the world date, localized, with no raw id or token leaking.
		var sim_hud := _find_gameplay_hud(router.get_current_scene())
		if sim_hud != null:
			var sim_text := _all_label_text(sim_hud)
			for t in sim_text:
				var line := String(t)
				assert_false(line.contains("WORLDSIM_"),
					"no raw world-sim localization key leaks into the HUD (%s)" % line)
				assert_false(line.contains("actor_"),
					"no raw actor id leaks into the HUD (%s)" % line)
				assert_false(line.contains("{year}") or line.contains("{subject}"),
					"no unsubstituted placeholder leaks into the HUD (%s)" % line)
			# Found BY NAME, not by "some label contains a 1" — the first version of this
			# check was satisfied by any label anywhere that happened to contain a digit,
			# which is the kind of assertion that passes forever after the feature breaks.
			var date_label := _find_label_named(sim_hud, "WorldDate")
			var event_label := _find_label_named(sim_hud, "WorldEvent")
			assert_not_null(date_label, "the HUD has a world-date label")
			assert_not_null(event_label, "and a world-event label")
			if date_label != null:
				assert_true(date_label.visible, "the date line is shown during a session")
				assert_ne(date_label.text, "", "and carries text")
				# It must be a localized SENTENCE, not a bare number dump.
				assert_true(date_label.text.length() > 4,
					"the date reads as a localized line, not a bare value (got '%s')"
						% date_label.text)
			if event_label != null:
				assert_true(event_label.visible, "the event line is shown")
				assert_ne(event_label.text, "",
					"and names what the world last did (the feed is non-empty by now)")

	await scene_tree.process_frame
	await scene_tree.process_frame
	var after: float = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	assert_true(after <= baseline + 2.0,
		"no orphan growth across %d round trips (%d -> %d)"
		% [ROUND_TRIPS, int(baseline), int(after)])
	assert_true(is_instance_valid(player), "player still alive after %d transitions" % ROUND_TRIPS)
	assert_eq(player.get_instance_id(), player_id, "still the SAME player after all transitions")

	# --- 7. Esc steps BACK and ASKS; only a confirmation leaves (D-068, audit AUD-02) ---
	# Nothing is saved before Phase 23, so one key press must never end the session.
	var leave_hud := _find_hud(router.get_current_scene())
	var input_service: Node = scene_tree.root.get_node("InputService")
	for _attempt in 4:
		await _fire_action(SECT_PANEL)
		await scene_tree.process_frame
		if leave_hud.is_sect_panel_open():
			break
	assert_true(leave_hud.is_sect_panel_open(), "the sect panel is open")
	await _fire_action(OPEN_MENU)
	await scene_tree.process_frame
	assert_false(leave_hud.is_sect_panel_open(), "a REAL Esc closed the open panel")
	assert_eq(leave_hud.session_prompt_kind(), GameplayHUD.PROMPT_NONE,
		"and asked nothing: it stepped back ONE level")
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "the session is still running")
	await _fire_action(OPEN_MENU)
	await scene_tree.process_frame
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "asking is not leaving")
	if gs.get_phase() != gs.Phase.RUNNING or not is_instance_valid(leave_hud):
		return  # one Esc ended the session: the HUD is gone, nothing below can be asked
	assert_eq(leave_hud.session_prompt_kind(), GameplayHUD.PROMPT_LEAVE,
		"with nothing open, Esc ASKS whether to leave")
	assert_true(is_instance_valid(player), "the player is untouched")
	assert_eq(int(input_service.call("current_context")), int(input_service.Context.UI_MODAL),
		"the question holds the keys")
	await _fire_action(OPEN_MENU)
	await scene_tree.process_frame
	assert_eq(leave_hud.session_prompt_kind(), GameplayHUD.PROMPT_NONE,
		"a second Esc answers 'stay': Esc pressed twice never leaves")
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "still running")
	assert_true(bool(input_service.call("is_gameplay_active")), "and control is back")
	await _fire_action(OPEN_MENU)
	await scene_tree.process_frame
	assert_eq(leave_hud.session_prompt_kind(), GameplayHUD.PROMPT_LEAVE, "asked again")
	await _fire_action(INTERACT)
	await scene_tree.process_frame
	assert_eq(gs.get_phase(), gs.Phase.MENU, "the confirm key ended the session back to MENU")
	assert_false(gs.is_session_active(), "session ended")
	assert_eq(router.get_current_key(), "", "no content scene after returning to menu")
	assert_false(is_instance_valid(player), "the persistent player was freed on session end")
	# The relationship subsystem persists as a node but ends its session on return to menu.
	if relationship_runtime != null and is_instance_valid(relationship_runtime):
		assert_false(relationship_runtime.call("is_session_active"),
			"RelationshipRuntime session ended on return to menu")
	# The sect subsystem likewise ends its session + clears its state on return to menu.
	if sect_runtime != null and is_instance_valid(sect_runtime):
		assert_false(sect_runtime.call("is_session_active"),
			"SectRuntime session ended on return to menu")
		assert_eq(sect_runtime.call("get_player_sect_id"), &"",
			"SectRuntime cleared the player's sect on session end")
	# And the faction subsystem, which is ended FIRST but must still be fully down.
	if faction_runtime != null and is_instance_valid(faction_runtime):
		assert_eq(faction_runtime.get_instance_id(), faction_runtime_id,
			"the FactionRuntime NODE survived the session (only its session ended)")
		assert_false(faction_runtime.call("is_session_active"),
			"FactionRuntime session ended on return to menu")
		assert_null(faction_runtime.call("get_store"),
			"FactionRuntime dropped its store on session end")
	# And the world simulation, which is ended FIRST of all five.
	if sim_runtime != null and is_instance_valid(sim_runtime):
		assert_false(sim_runtime.call("is_session_active"),
			"WorldSimulationRuntime session ended on return to menu")
		assert_null(sim_runtime.call("get_state"),
			"and it dropped its simulation state")
		assert_eq(sim_runtime.call("get_player_map_id"), &"",
			"and cleared the player's location")

	# --- 7b. THE TEARDOWN ORDER ITSELF (D-047) ----------------------------------
	# This is the assertion the Phase-07 defect needed: `_on_return_to_menu()` had drifted to
	# ending World and Relationship BEFORE Faction and Sect — i.e. it tore out the relationship
	# graph and the player's CharacterState while the two subsystems defined in terms of them
	# were still unwinding. Every gate stayed green because "all four sessions are down
	# afterwards" is true for ANY order; only the SEQUENCE distinguishes correct from broken.
	var trace: Array = main.call("get_last_teardown_order")
	assert_eq(str(trace), str(EXPECTED_TEARDOWN_ORDER),
		"the real return-to-menu tore the session down in exact reverse dependency order "
		+ "(expected %s, got %s)" % [str(EXPECTED_TEARDOWN_ORDER), str(trace)])
	# Tie the observed behaviour back to the documented constant, so neither can drift alone.
	var derived: Array[StringName] = []
	var start_order: Array = MainScript.SESSION_START_ORDER
	for i in range(start_order.size() - 1, -1, -1):
		derived.append(StringName(start_order[i]))
	derived.append(StringName(MainScript.SESSION_OWNER_STEP))
	assert_eq(str(trace), str(derived),
		"and that order IS the reverse of Main.SESSION_START_ORDER + the session owner")

	# --- 8. cleanup / isolation --------------------------------------------------
	_teardown(main)
	await scene_tree.process_frame
	assert_false(is_instance_valid(main), "Main freed after cleanup (no orphan)")
	for autoload_name in REQUIRED_AUTOLOADS:
		assert_eq(_count_named(autoload_name), 1,
			"still exactly one /root/%s after teardown" % autoload_name)
	assert_eq(gs.get_phase(), gs.Phase.MENU, "GameState remains in a legal phase after teardown")


# --- helpers -----------------------------------------------------------------

func _find_world_runtime(main: Node) -> Node:
	var systems := main.get_node_or_null("Systems")
	if systems == null:
		return null
	for child in systems.get_children():
		if child is WorldRuntime:
			return child
	return null


func _find_relationship_runtime(main: Node) -> Node:
	var systems := main.get_node_or_null("Systems")
	if systems == null:
		return null
	for child in systems.get_children():
		if child is RelationshipRuntime:
			return child
	return null


func _find_sect_runtime(main: Node) -> Node:
	var systems := main.get_node_or_null("Systems")
	if systems == null:
		return null
	for child in systems.get_children():
		if child is SectRuntime:
			return child
	return null


func _find_faction_runtime(main: Node) -> Node:
	var systems := main.get_node_or_null("Systems")
	if systems == null:
		return null
	for child in systems.get_children():
		if child is FactionRuntime:
			return child
	return null


func _find_world_sim_runtime(main: Node) -> Node:
	var systems := main.get_node_or_null("Systems")
	if systems == null:
		return null
	for child in systems.get_children():
		if child is WorldSimulationRuntime:
			return child
	return null


## The GameplayHUD inside the active map (a CanvasLayer named "GameplayHUD" MapBase adds).
func _find_gameplay_hud(map: Node) -> Node:
	if map == null:
		return null
	return map.get_node_or_null("GameplayHUD")


## The first `Label` named `label_name` anywhere under `node`, or null. Finding a label by NAME
## is what makes an assertion about it specific: "some label contains a digit" is satisfied by
## any other label on screen and would keep passing after the feature it checks has broken.
func _find_label_named(node: Node, label_name: String) -> Label:
	if node is Label and node.name == label_name:
		return node as Label
	for child in node.get_children():
		var found := _find_label_named(child, label_name)
		if found != null:
			return found
	return null


## Every Label's text anywhere under `node` (recursive) — for asserting rendered UI content.
func _all_label_text(node: Node) -> Array:
	var out: Array = []
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		out += _all_label_text(child)
	return out


func _player_is_in_map(player: Node, map: Node) -> bool:
	if player == null or not is_instance_valid(player) or map == null:
		return false
	var p := player.get_parent()
	while p != null:
		if p == map:
			return true
		p = p.get_parent()
	return false


## Count Player instances anywhere under root (duplicate-player guard).
func _count_player_instances(node: Node) -> int:
	var n := 0
	if node is Player:
		n += 1
	for child in node.get_children():
		n += _count_player_instances(child)
	return n


func _assert_camera_limits(map: Node, l: int, t: int, r: int, b: int, tag: String) -> void:
	var cam := map.get_node_or_null("Camera2D")
	if cam == null or not (cam is Camera2D):
		assert_true(false, "%s map has no Camera2D" % tag)
		return
	var c := cam as Camera2D
	assert_eq(c.limit_left, l, "%s camera limit_left" % tag)
	assert_eq(c.limit_top, t, "%s camera limit_top" % tag)
	assert_eq(c.limit_right, r, "%s camera limit_right" % tag)
	assert_eq(c.limit_bottom, b, "%s camera limit_bottom" % tag)


## Drive a genuine semantic MOVEMENT: press move_right (real key event + action state), let
## the Player poll InputService.get_move_vector() in its own _physics_process, then release.
##
## Also proves the camera FOLLOWS (D-036): the map's Camera2D is a plain child node, so
## before this it stayed at its authored position and the player simply walked out of frame
## once the view became smaller than the map. Asserting "the camera moved toward the player"
## is the observable contract — not "the camera equals the player", because position
## smoothing eases it over several frames.
func _prove_movement(player: Node, input: Node, map: Node) -> void:
	if not (player is Node2D):
		return
	var p := player as Node2D
	var cam := map.get_node_or_null("Camera2D") as Camera2D

	# Start near the map CENTRE, not at the edge. A follow camera is clamped by the
	# MapData-driven limits to `[limit_left + half_view, limit_right - half_view]`, so from
	# an edge position the camera is pinned and "did it move?" would be unanswerable. The
	# centre is comfortably inside that band, so a correct follow MUST produce travel.
	p.global_position = Vector2(CAMERA_PROBE_START_X, CAMERA_PROBE_Y)
	# Let position smoothing settle ON the player before taking the baseline, otherwise the
	# baseline is sampled mid-ease from the camera's authored position and the comparison is
	# meaningless (it can even ease the "wrong" way).
	for _s in range(CAMERA_SETTLE_FRAMES):
		await scene_tree.physics_frame
	var start_x: float = p.global_position.x
	var cam_start_x: float = cam.global_position.x if cam != null else 0.0

	Input.action_press(MOVE_RIGHT)
	for _i in range(CAMERA_PROBE_MOVE_FRAMES):
		await scene_tree.physics_frame
	Input.action_release(MOVE_RIGHT)
	await scene_tree.physics_frame
	assert_true(p.global_position.x > start_x,
		"player moved right via a real semantic move action (InputService path)")
	assert_true(input.call("is_gameplay_active"), "still GAMEPLAY context after movement")

	assert_not_null(cam, "the map has a Camera2D to follow with")
	if cam != null:
		for _j in range(CAMERA_SETTLE_FRAMES):
			await scene_tree.physics_frame
		assert_true(cam.global_position.x > cam_start_x,
			"camera tracked the player right instead of staying put (cam %.1f -> %.1f, "
			% [cam_start_x, cam.global_position.x]
			+ "player %.1f -> %.1f)" % [start_x, p.global_position.x])
		# And it must never be dragged outside the authored map bounds.
		assert_true(cam.global_position.x >= float(cam.limit_left)
			and cam.global_position.x <= float(cam.limit_right),
			"camera stayed within the horizontal map limits while following")


## Stand the player in the active map's exit zone (teleport setup) and fire the exit via the
## REAL input pipeline: emit the sensor's real `body_entered` (headless Area2D concession,
## L-016) so MapBase sets its active exit, then feed a REAL `interact` key event through
## `Input.parse_input_event` (no direct `_unhandled_input` call). Retries a bounded number of
## frames so input-dispatch frame timing can't cause a false negative. Waits for the swap.
func _interact_to_transition(player: Node, from_key: String) -> void:
	var router := scene_tree.root.get_node_or_null("SceneRouter")
	var active: Node = router.call("get_current_scene") if router != null else null
	var zone := _first_exit_zone(active)
	assert_not_null(zone, "active map '%s' has an exit zone" % from_key)
	if zone == null:
		return
	# Teleport the player onto the zone (setup) and raise the sensor's real signal so the
	# REAL MapBase handler sets _active_exit (headless physics won't raise it on its own).
	if player is Node2D:
		(player as Node2D).global_position = (zone as Node2D).global_position
	zone.emit_signal("body_entered", player)
	await scene_tree.process_frame

	# Fire the interact action via the REAL input pipeline, bounded-retry until the map swaps.
	for _attempt in range(8):
		await _fire_action(INTERACT)
		await scene_tree.process_frame
		if router != null and str(router.call("get_current_key")) != from_key:
			break
	await scene_tree.process_frame


## First MapExitZone (Node2D) in a map's Exits, or null.
func _first_exit_zone(map: Node) -> Node2D:
	if map == null:
		return null
	var exits := map.get_node_or_null("Exits")
	if exits == null:
		return null
	for zone in exits.get_children():
		if zone is MapExitZone and zone is Node2D:
			return zone as Node2D
	return null


## Feed a REAL key press+release for `action` through the engine input pipeline. The engine
## updates the InputMap action state (so is_*_just_pressed is true) AND dispatches
## `_input`/`_unhandled_input` to in-tree nodes on the processed frame. No direct handler call.
## Prove a REAL ENCOUNTER in the real app (Phase 10): the field is populated from data, the
## creature hunts, the player kills it with a REAL attack key, and the corpse stops being an
## actor.
##
## This is the gate that would catch an enemy that spawns but never acts, acts but cannot be
## hit, or dies but keeps hunting — none of which a unit test on the brain can see, because
## each one is a WIRING failure between systems that are individually correct.
func _prove_encounter(main: Node, player: Node2D, map: Node) -> void:
	var combat := main.get_node_or_null("Systems/CombatRuntime")
	assert_not_null(combat, "the CombatRuntime subsystem exists")
	if combat == null:
		return
	# The field is populated FROM DATA on arrival — nothing in the scene authors a creature.
	var spawned: int = int(combat.call("enemy_count"))
	assert_true(spawned >= 1,
		"arriving in the field spawned the authored creatures (got %d)" % spawned)
	assert_eq(int(combat.call("living_enemy_count")), spawned, "and all of them are alive")

	var enemies: Array = combat.call("enemies")
	var enemy := enemies[0] as Node2D
	assert_not_null(enemy, "the first creature is a node")
	if enemy == null:
		return
	var registry: CombatHurtboxRegistry = combat.call("get_registry")
	assert_true(registry.has(enemy.call("instance_id")),
		"it is registered as a combat target, so the player can hit it")

	# IT HUNTS. Stand next to it and let the real session tick drive its brain; the state must
	# leave IDLE/PATROL for the encounter chain.
	player.global_position = enemy.global_position + Vector2(60, 0)
	var hunted := false
	for _i in 240:
		await scene_tree.process_frame
		var state := String(enemy.call("ai_state_name"))
		if state == "ALERT" or state == "CHASE" or state == "ATTACK" or state == "RECOVER":
			hunted = true
			break
	assert_true(hunted,
		"the creature noticed the player and started hunting (state=%s)"
			% String(enemy.call("ai_state_name")))

	# THE PLAYER CAN KILL IT, through the real input pipeline. The attack key is fed as a real
	# key event and the observable effect is polled over a bounded number of frames (L-016);
	# the player is re-placed inside reach each round because the creature keeps moving.
	var attack_component := player.get_node_or_null("AttackComponent") as AttackComponent
	assert_not_null(attack_component, "the player is armed")
	if attack_component == null:
		return
	var start_hp: int = int(enemy.call("get_current_health"))
	for _round in 40:
		if bool(enemy.call("is_dead")):
			break
		player.global_position = enemy.global_position - Vector2(16, 0)
		attack_component.set_facing(Vector2.RIGHT)
		await _fire_action(&"attack")
		for _i in 24:
			await scene_tree.process_frame
			if bool(enemy.call("is_dead")):
				break
	assert_true(int(enemy.call("get_current_health")) < start_hp,
		"real attack keys damaged the creature (hp %d -> %d)"
			% [start_hp, int(enemy.call("get_current_health"))])
	assert_true(bool(enemy.call("is_dead")),
		"and killed it (hp %d)" % int(enemy.call("get_current_health")))

	# PROGRESSION (Phase 11): the kill that just happened must have paid, through the real
	# chain — enemy death → CombatRuntime.enemy_defeated → ProgressionRuntime → the player's
	# authoritative CharacterState → the HUD. Asserted HERE, immediately after a kill driven
	# by real attack keys, because that is the only place in the suite where the whole path
	# from a player's keypress to a changed level is observable.
	#
	# NOTHING here calls `grant_for_defeat`, `grant_xp` or `set_total_xp`. The phase brief is
	# explicit that an E2E must not fake the player's achievement, and an E2E that did would
	# stay green while the announcement, the subscription or the reward authoring was broken
	# (L-017).
	await _prove_progression(main, map)

	# DEATH CLEANUP, observed in the real app rather than in a harness.
	assert_false(registry.has(enemy.call("instance_id")),
		"a corpse is no longer targetable, so the player stops swinging at nothing")
	assert_eq(String(enemy.call("ai_state_name")), "IDLE", "its brain was reset")
	var resting := enemy.global_position
	var player_hp_before: int = int(player.call("get_current_health"))
	for _i in 60:
		await scene_tree.process_frame
	assert_eq(enemy.global_position, resting, "it does not move after death")
	assert_eq(int(player.call("get_current_health")), player_hp_before,
		"and lands no hit from beyond the grave")
	# THE PLAYER CAN CONTINUE: still alive, still armed, still able to act.
	assert_false(bool(player.call("is_dead")), "the player survived the encounter")
	assert_true(attack_component.is_armed(), "and can still attack")


## Prove the WHOLE combat path with a REAL attack key: InputService gate → `Player` →
## `AttackComponent` → `AttackStateMachine` → `CombatService` → the target's health.
##
## It drives the boundary it advertises (L-017): the swing is started by a real `InputEventKey`
## for the bound `attack` action, fed through `Input.parse_input_event` so the engine updates
## the action state and dispatches it, exactly as a key press does in a real frame. Nothing
## here calls `request_attack()` or `resolve_hit()` directly — a test that did would stay green
## while the input gate, the component wiring or the registry was broken.
##
## It asserts the OBSERVABLE END STATE — the target lost health — not that a signal fired.
## "The attack resolved" is satisfied by a swing that hits nothing; only a health drop proves
## the hit landed, and this is the one assertion that would have caught an unarmed player, an
## unregistered target, or an empty registry (L-029: a pipeline whose only path is the fallback).
func _prove_combat(main: Node, player: Node2D, map: Node) -> void:
	var combat := main.get_node_or_null("Systems/CombatRuntime")
	assert_not_null(combat, "the CombatRuntime subsystem exists under Main/Systems")
	if combat == null:
		return
	assert_true(bool(combat.call("is_session_active")),
		"the combat session is live inside a running game")
	var registry: CombatHurtboxRegistry = combat.call("get_registry")
	assert_not_null(registry, "the session exposes a hurtbox registry")
	if registry == null:
		return
	# The player must be ARMED, and it must be a target itself — an attacker that cannot be
	# hit back is a one-way fight nobody notices until something tries.
	assert_true(registry.has(&"player"), "the player is registered as a target")
	assert_true(int(combat.call("armed_count")) >= 1, "at least one attacker is armed")

	# A REAL target authored into the map, not one the test spawned. A combat system with
	# nothing in the shipped world to hit is a no-op with documentation (L-029).
	var targets: Array[Node] = map.call("get_combat_targets")
	assert_true(targets.size() >= 1,
		"the hub map declares at least one combat target (got %d)" % targets.size())
	if targets.is_empty():
		return
	var target := targets[0] as Node2D
	assert_not_null(target, "the declared target is a Node2D")
	if target == null:
		return
	assert_true(target.has_method("get_current_health"), "the target exposes its health")

	# Stand next to it and face it, then swing. Position is set directly (this is not the
	# movement boundary — section 4 already proved that with real input) and the facing is
	# pushed the way the player pushes it every physics frame.
	var before := int(target.call("get_current_health"))
	assert_true(before > 0, "the target starts alive (hp %d)" % before)
	player.global_position = target.global_position - Vector2(18, 0)
	var attack_component := player.get_node_or_null("AttackComponent") as AttackComponent
	assert_not_null(attack_component, "the player carries an AttackComponent")
	if attack_component == null:
		return
	assert_true(attack_component.is_armed(),
		"and CombatRuntime armed it (an unarmed player is a dead attack key)")
	attack_component.set_facing(Vector2.RIGHT)

	# The PLAYER's own visual, so the action animation can be observed on the primary actor
	# (D-056). The integration suite proves the creature's; this is the only place the PLAYER's
	# runs on the real path — built at runtime by `Player._apply_visual_profile()` from the
	# template's `sprite_set_ref`, and required to find its sibling `AttackComponent` itself.
	# Reached through the PUBLIC accessor, not by node name: `get_visual_component()` is the
	# documented seam, so this cannot break on a node rename — and it is called TYPED, so a
	# renamed accessor fails at parse time instead of as a runtime `call()` error.
	var typed_player := player as Player
	assert_not_null(typed_player, "the persistent player is a Player")
	var visual: CharacterVisualComponent = (
		typed_player.get_visual_component() if typed_player != null else null)
	assert_not_null(visual,
		("the player built a CharacterVisualComponent from its template's sprite_set_ref — "
			+ "without it there is no action layer to drive on the actor the player controls"))
	var action_seen := false
	var action_columns := {}

	# Feed the REAL key and let the lifecycle run. The hit lands in ACTIVE, which is one
	# windup away, so the effect is polled over a bounded number of frames rather than
	# guessed at a single one (L-016: `is_action_just_pressed` timing after a synthetic press
	# is fragile, so poll the observable effect instead of betting on a frame).
	await _fire_action(&"attack")
	var after := before
	for _i in 240:
		await scene_tree.process_frame
		# Sampled inside the SAME loop that waits for the damage, so what is observed is the
		# animation during the very swing that landed the hit — not a later one.
		if visual != null and visual.is_action_playing():
			action_seen = true
			action_columns[visual.get_column()] = true
		after = int(target.call("get_current_health"))
		if after < before:
			break
	assert_true(after < before,
		("a REAL attack key damaged the target through the whole chain — InputService gate, "
			+ "AttackComponent, the state machine's hit window, CombatService and the "
			+ "target's own health (hp %d -> %d)") % [before, after])
	assert_true(attack_component.damage_dealt() > 0,
		"and the component recorded the damage it applied (%d)"
			% attack_component.damage_dealt())

	# AND THE PLAYER VISIBLY SWUNG (D-056). The same real key that produced the damage above
	# put the player's own sprite into its ACTION layer and moved it through more than one
	# frame. Without this the feature's evidence for its PRIMARY actor was "a screenshot looks
	# different", which is an inference, not a proof — the integration suite only ever covered
	# the creature.
	assert_true(action_seen,
		("the real attack key drove the PLAYER's action animation, not only the damage — if "
			+ "this fails the player's visual never bound to its AttackComponent and the "
			+ "character swings with no animation at all"))
	assert_true(action_columns.size() >= 2,
		("and the animation advanced through more than one frame during the swing (saw %s) — "
			+ "a pose that renders one frame is a freeze, not a swing") % str(
				action_columns.keys()))


## Prove the REAL progression loop paid for the kill that just happened (Phase 11).
##
## Called right after `_prove_encounter` has killed a creature with real attack keys, so the
## XP it asserts was earned by the player's own input and not written by the test.
##
## It checks the whole chain at its OBSERVABLE ends: the authoritative `CharacterState.xp`
## moved, the derived level moved with it, and the HUD is showing the progression row. Any one
## of those alone could pass while the path was broken — a granted XP with no HUD row is a
## reward the player never learns about, and a visible row over an unchanged total is a UI
## reading a number nothing updated.
func _prove_progression(main: Node, map: Node) -> void:
	var progression := main.get_node_or_null("Systems/ProgressionRuntime")
	assert_not_null(progression, "the ProgressionRuntime subsystem exists under Main/Systems")
	if progression == null:
		return
	assert_true(bool(progression.call("is_session_active")),
		"the progression session is live inside a running game")
	assert_eq(_count_named("ProgressionRuntime"), 0,
		"ProgressionRuntime is NOT an autoload (the budget stays at five — D-017)")

	var world_runtime := _find_world_runtime(main)
	if world_runtime == null:
		return
	var character: CharacterState = world_runtime.call("get_player_character")
	assert_not_null(character, "the world session owns the player's CharacterState")
	if character == null:
		return

	# THE AUTHORITY MOVED. The creature the player just killed carries an authored
	# `xp_reward`, and this is the number that must have landed on the player.
	assert_true(character.xp > 0,
		("killing a creature with real attack keys granted XP to the authoritative "
			+ "CharacterState (xp=%d) — the whole reason Phase 11 exists") % character.xp)

	var view: ProgressionView = progression.call("build_view")
	assert_true(view.available, "and the progression view is available")
	assert_true(view.level >= 2,
		("the player LEVELLED from that kill (level=%d, xp=%d). The authored curve's first "
			+ "step is reachable from one kill on purpose: the first level-up is where the "
			+ "player learns the loop exists") % [view.level, character.xp])
	# The level is DERIVED, so it must agree with the stored XP rather than being a second
	# number that happens to look right.
	var service: ProgressionService = progression.call("get_service")
	assert_not_null(service, "the session exposes its service")
	if service != null:
		assert_eq(view.level, service.level_of(character),
			"the view's level is the one derived from the stored XP, not a copy")

	# AND THE PLAYER CAN SEE IT. A reward nobody is told about is not a progression system.
	#
	# The HUD is located by TYPE in the map's own tree rather than through a getter, so this
	# assertion needs no production API that exists only for a test.
	var hud := _find_hud(map)
	assert_not_null(hud, "the active map owns a GameplayHUD")
	if hud != null:
		assert_true(hud.is_progression_visible(),
			("the HUD is showing the level/XP row after the first kill — a granted reward the "
				+ "player is never told about is not a progression system"))


## The `GameplayHUD` in a map's tree, or null.
func _find_hud(node: Node) -> GameplayHUD:
	if node == null:
		return null
	if node is GameplayHUD:
		return node as GameplayHUD
	for child in node.get_children():
		# Explicitly typed: a recursive call's return type is not yet resolved, so `:=` would
		# infer Variant and fail the warning-as-error compile (GD001 / L-020).
		var found: GameplayHUD = _find_hud(child)
		if found != null:
			return found
	return null


func _fire_action(action: StringName) -> void:
	var press := _key_event_for(action, true)
	if press == null:
		# Fallback: action with no key binding — still drive via the action state so the
		# gate check is real (should not happen for interact/open_menu which bind keys).
		Input.action_press(action)
		await scene_tree.process_frame
		Input.action_release(action)
		return
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await scene_tree.process_frame
	var release := _key_event_for(action, false)
	if release != null:
		Input.parse_input_event(release)
		Input.flush_buffered_events()
	await scene_tree.process_frame


## Build an InputEventKey from the first physical key bound to `action`, or null if none.
func _key_event_for(action: StringName, pressed: bool) -> InputEventKey:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := InputEventKey.new()
			k.physical_keycode = (e as InputEventKey).physical_keycode
			k.keycode = (e as InputEventKey).keycode
			k.pressed = pressed
			return k
	return null


func _count_named(node_name: String) -> int:
	var count := 0
	for child in scene_tree.root.get_children():
		if child.name == node_name:
			count += 1
	return count


func _teardown(main: Node) -> void:
	for a in [MOVE_RIGHT, INTERACT, OPEN_MENU]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	if main == null or not is_instance_valid(main):
		return
	if main.get_parent() != null:
		main.get_parent().remove_child(main)
	main.queue_free()


## Prove Phase 12 in the REAL app: the cultivate key refuses with a reason away from the
## method, a REAL interact at the stele grants the method through the Knowledge Core, a REAL
## cultivate key sits the player at the Lạc Hà spring and tu vi accumulates over real frames,
## a full step breaks through into Hậu Thiên 1 (the HUD names it), and a REAL move key rises.
## Placement is setup (as with exits); every ACTION is a key event.
func _prove_cultivation(main: Node, player: Node2D, map: Node) -> void:
	var knowledge := main.get_node_or_null("Systems/KnowledgeRuntime") as KnowledgeRuntime
	var cultivation := main.get_node_or_null("Systems/CultivationRuntime") as CultivationRuntime
	assert_not_null(knowledge, "the KnowledgeRuntime subsystem exists")
	assert_not_null(cultivation, "the CultivationRuntime subsystem exists")
	if knowledge == null or cultivation == null:
		return
	assert_true(knowledge.is_session_active() and cultivation.is_session_active(),
		"both Phase-12 sessions are live")
	var hud := _find_hud(map)
	var spring := map.get_node_or_null("CultivationSites/LacHaSpring") as Node2D
	var stele := map.get_node_or_null("KnowledgeSources/LacHaStele") as Node2D
	var inventory := main.get_node_or_null("Systems/InventoryRuntime") as InventoryRuntime
	assert_not_null(spring, "the hub has the Lạc Hà spring")
	assert_not_null(stele, "the hub has the Lạc Hà stele")
	assert_not_null(inventory, "the InventoryRuntime subsystem exists")
	if spring == null or stele == null or hud == null or inventory == null:
		return
	var state: CharacterState = player.call("get_character_state")
	assert_eq(state.realm_id, &"realm_pham", "a new run starts mortal")
	assert_true(hud.is_cultivation_visible(), "the HUD shows the tu vi meter")

	var loc := scene_tree.root.get_node("Localization")

	# 1. At the spring without the method: the key REFUSES, and says why — on the frame it is
	# refused, even with a pickup notice on screen (D-063 D1: it used to wait 2.6s behind it).
	var pill := map.get_node_or_null("Pickups/HubPill1") as Node2D
	assert_not_null(pill, "a pickup lies on the way to the spring")
	if pill == null:
		return
	player.global_position = pill.global_position  # setup: walk onto the pickup
	for _i in 6:
		await scene_tree.physics_frame
	assert_true(inventory.is_collected(&"pickup_hubpill1"),
		"the pill pickup is REALLY collected (is_collected), not merely stepped on")
	player.global_position = spring.global_position + Vector2(0, 26)
	for _i in 4:
		await scene_tree.physics_frame
	# Earlier proofs walked over other pickups, so their notices may still be up or waiting: the
	# claim is RELATIVE — whatever was on screen or waiting before the press is kept after it.
	assert_eq(hud.notice_kind(), GameplayHUD.NOTICE_PASSIVE, "a pickup notice is on screen")
	var waiting_before_c: Array[StringName] = [&"UI_ITEM_GAINED"]
	waiting_before_c.append_array(hud.pending_notice_keys())
	# Read the HUD from INSIDE the semantic event: connected after `WorldRuntime`, this runs
	# once the refusal has been routed, in the same call stack — no frame can pass in between.
	var refused := {}
	var on_refused := func(reason: StringName) -> void:
		refused["reason"] = reason
		refused["text"] = hud.notice_text()
		refused["kind"] = hud.notice_kind()
		refused["tick"] = Engine.get_physics_frames()
	cultivation.cultivation_refused.connect(on_refused)
	var pressed_tick := Engine.get_physics_frames()
	await _press_through_physics(CULTIVATE)
	cultivation.cultivation_refused.disconnect(on_refused)
	assert_eq(cultivation.phase(), CultivationRuntime.Phase.IDLE, "no method: nobody sits")
	assert_eq(refused.get("reason"), CultivationRuntime.REFUSE_NO_METHOD, "refused for the method")
	assert_eq(refused.get("text"), String(loc.call("t", "UI_CULTIVATE_NO_METHOD")),
		"the HUD says why on the frame the refusal is decided, ahead of the pickup notice")
	assert_eq(refused.get("kind"), GameplayHUD.NOTICE_ANSWER, "as an ANSWER")
	assert_true(int(refused.get("tick", 1 << 30)) - pressed_tick <= 2,
		"decided within two physics ticks of the press")
	assert_eq(hud.pending_notice_keys(), waiting_before_c,
		"every pickup notice is kept: the interrupted one first, then the ones that waited")

	# 2. Two more pickups beside the stele, then a REAL interact: the first lesson is on screen
	# on the frame it is learned, ahead of the pickups (D-063 D2: it used to wait 5.8s); the
	# second lesson next; every pickup notice kept, in the order it happened.
	for path in ["Pickups/HubManualPhong", "Pickups/HubRobe"]:
		var pickup := map.get_node_or_null(path) as Node2D
		assert_not_null(pickup, "%s lies beside the stele" % path)
		if pickup != null:
			player.global_position = pickup.global_position  # setup: walk onto it
			for _i in 6:
				await scene_tree.physics_frame
	# The manual and robe sit 12.8px apart (reach 14px): one placement collects both.
	# Prove via the authority, not via visibility.
	assert_true(inventory.is_collected(&"pickup_hubmanualphong"),
		"the manual pickup is REALLY collected (is_collected)")
	assert_true(inventory.is_collected(&"pickup_hubrobe"),
		"the robe pickup is REALLY collected (is_collected)")
	# The stele is SOLID (D-063 A2): approach it ON FOOT with a REAL held key from the south. The
	# walk must STOP at the plinth — outside it — and the stele must be readable from there.
	player.global_position = stele.global_position + Vector2(0, 44)  # setup: south of the stele
	for _i in 4:
		await scene_tree.physics_frame
	assert_true(await _walk_until_blocked(player, MOVE_UP, 180),
		"walking north into the stele stops against it")
	assert_true(player.global_position.y >= stele.global_position.y + 11.5,
		"the walk stopped OUTSIDE the plinth (feet at %.1f, the plinth's front edge at %.1f)"
			% [player.global_position.y, stele.global_position.y])
	assert_true(map.call("active_knowledge_source") != null,
		"and the stele is readable from where the body stopped")
	# Whatever is on screen before the press (the refusal, or a pickup notice it gave way to)
	# is accounted for: a passive notice goes back to its lane first, a refusal is superseded.
	var waiting_before_e: Array[StringName] = [&"UI_HUD_KNOWLEDGE_GAINED"]
	if hud.notice_kind() == GameplayHUD.NOTICE_PASSIVE:
		waiting_before_e.append(&"UI_ITEM_GAINED")
	waiting_before_e.append_array(hud.pending_notice_keys())
	var lesson := {}
	var on_learned := func(knowledge_id: StringName, _source: StringName) -> void:
		if not lesson.has("id"):
			lesson["id"] = knowledge_id
			lesson["text"] = hud.notice_text()
			lesson["kind"] = hud.notice_kind()
	knowledge.knowledge_gained.connect(on_learned)
	for _attempt in 6:
		await _fire_action(INTERACT)
		if knowledge.get_service().knows(&"know_dan_khi_quyet"):
			break
	knowledge.knowledge_gained.disconnect(on_learned)
	assert_true(knowledge.get_service().knows(&"know_dan_khi_quyet"),
		"a real interact at the stele granted the method through the Knowledge Core")
	assert_true(knowledge.get_service().knows(&"know_lac_ha_stele_record"),
		"and the record (a non-gating payoff)")
	assert_eq(lesson.get("id"), &"know_dan_khi_quyet", "the method is learned first")
	assert_true(String(lesson.get("text", "")).contains(
		String(loc.call("t", "KNOW_DAN_KHI_QUYET_NAME"))),
		"and is on screen on the frame it is learned (got '%s')" % lesson.get("text", ""))
	assert_eq(lesson.get("kind"), GameplayHUD.NOTICE_RESULT, "as a RESULT")
	assert_eq(hud.pending_notice_keys(), waiting_before_e,
		"the second lesson waits next, then every pickup notice in the order it happened (the "
			+ "superseded refusal is not re-shown)")
	assert_true(waiting_before_e.count(&"UI_ITEM_GAINED") >= 3,
		"including the three pickups walked over for this proof")
	assert_false(hud.notice_backlog_overflowed(), "a normal backlog")
	# Push on: the plinth still holds. Then leave: the body never traps the player.
	var pinned := player.global_position
	assert_eq(await _hold_move(MOVE_UP, 20), 20, "the push held the key for all 20 physics frames")
	assert_true(player.global_position.y >= pinned.y - 0.5,
		"pushing on does not pass through the stele (%.1f -> %.1f)"
			% [pinned.y, player.global_position.y])
	assert_eq(await _hold_move(MOVE_DOWN, 30), 30, "the way back held the key for 30 frames")
	assert_true(player.global_position.y > pinned.y + 8.0,
		"and the player walks away freely (%.1f -> %.1f)" % [pinned.y, player.global_position.y])

	# 3. Sit at the spring with a REAL cultivate key; tu vi accumulates over real frames.
	player.global_position = spring.global_position + Vector2(0, 26)
	for _i in 4:
		await scene_tree.physics_frame
	for _attempt in 6:
		await _press_through_physics(CULTIVATE)
		if cultivation.phase() != CultivationRuntime.Phase.IDLE:
			break
	assert_ne(cultivation.phase(), CultivationRuntime.Phase.IDLE, "a real C key sat the player")
	for _i in 180:
		await scene_tree.physics_frame
	assert_true(state.cultivation_progress > 0,
		"tu vi accumulated over real frames (%d)" % state.cultivation_progress)

	# 4. Fill the step THROUGH THE SERVICE (setup, not a write around the authority), then a
	# REAL key breaks through.
	cultivation.get_service().gather(state, 999)
	for _attempt in 6:
		await _press_through_physics(CULTIVATE)
		if cultivation.phase() == CultivationRuntime.Phase.BREAKTHROUGH:
			break
	assert_eq(cultivation.phase(), CultivationRuntime.Phase.BREAKTHROUGH, "breaking through")
	for _i in 140:
		await scene_tree.physics_frame
	assert_eq([state.realm_id, state.realm_layer], [&"realm_hau_thien", 1],
		"the player is now Hậu Thiên 1")
	# The banner is never lost (D-063): on screen, or waiting only behind an answer to the
	# player's own action (the stele's second lesson may still be up) — then shown.
	assert_true(hud.is_breakthrough_banner_visible() or hud.is_breakthrough_pending(),
		"the HUD holds the breakthrough announcement")
	await _wait_until(func() -> bool: return hud.is_breakthrough_banner_visible(), 300)
	assert_true(hud.is_breakthrough_banner_visible(), "the HUD announces the breakthrough")

	# 5. A REAL move key rises from the seat.
	Input.action_press(MOVE_RIGHT)
	for _i in 4:
		await scene_tree.physics_frame
	Input.action_release(MOVE_RIGHT)
	assert_eq(cultivation.phase(), CultivationRuntime.Phase.IDLE, "moving ended the sitting")


## Hold a REAL move key until the body stops moving (it walked into something) or `frames`
## run out. True when it was stopped — against a solid thing, not by the key being released.
func _walk_until_blocked(player: Node2D, action: StringName, frames: int) -> bool:
	Input.action_press(action)
	var last := player.global_position
	var still := 0
	var blocked := false
	for _i in frames:
		await scene_tree.physics_frame
		if not Input.is_action_pressed(action):
			break  # the key was let go: whatever stopped the body, it was not proven blocked
		still = still + 1 if player.global_position.distance_to(last) < 0.05 else 0
		last = player.global_position
		if still >= 6:
			blocked = true
			break
	Input.action_release(action)
	await scene_tree.physics_frame
	return blocked


## Press, hold across `frames` PHYSICS frames, release, one more frame. Returns how many of those
## frames the key was OBSERVED held, so a caller can assert the hold it claims really happened.
func _hold_move(action: StringName, frames: int) -> int:
	Input.action_press(action)
	var held := 0
	for _i in frames:
		await scene_tree.physics_frame
		if Input.is_action_pressed(action):
			held += 1
	Input.action_release(action)
	await scene_tree.physics_frame
	return held


## Hold `action` across PHYSICS frames, then release. The cultivation runtime reads its intent
## in `_physics_process`; a press and release that both land between two physics ticks (which a
## key event flushed on a process frame can do headless) is never seen there.
func _press_through_physics(action: StringName) -> void:
	Input.action_press(action)
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	Input.action_release(action)
	await scene_tree.physics_frame


## Prove Phase 13 in the REAL app: walking onto a pickup collects it once; a REAL `inventory` key
## opens the satchel (and the world stops taking the move keys); REAL move keys choose a row; a
## REAL interact uses it (the manual teaches through the Knowledge Core); the key closes it.
func _prove_inventory(main: Node, player: Node2D, map: Node) -> void:
	var inventory := main.get_node_or_null("Systems/InventoryRuntime") as InventoryRuntime
	var knowledge := main.get_node_or_null("Systems/KnowledgeRuntime") as KnowledgeRuntime
	assert_not_null(inventory, "the InventoryRuntime subsystem exists")
	if inventory == null or knowledge == null:
		return
	var hud := _find_hud(map)
	var pill := map.get_node_or_null("Pickups/HubPill1") as Node2D
	var manual := map.get_node_or_null("Pickups/HubManualPhong") as Node2D
	assert_true(pill != null and manual != null, "the hub has its pickups")
	if pill == null or manual == null or hud == null:
		return
	for target in [pill, manual]:
		player.global_position = (target as Node2D).global_position
		for _i in 6:
			await scene_tree.physics_frame
	assert_eq(inventory.count_of(&"item_bo_huyet_dan"), 2, "walking onto the pills took both")
	assert_eq(inventory.count_of(&"item_manual_phong"), 1, "and the manual")
	assert_false(pill.visible, "a collected pickup leaves the world")

	for _attempt in 6:
		await _fire_action(&"inventory")
		if hud.is_inventory_open():
			break
	assert_true(hud.is_inventory_open(), "a real I key opened the satchel")
	var panel := hud.inventory_panel()
	# Other pickups lie on paths earlier proofs walk (the jian by the training post), so the
	# satchel holds AT LEAST the pills and the manual.
	assert_true(panel.row_count() >= 2, "it lists every kind of item held (%d)" % panel.row_count())
	var start := player.global_position
	for _attempt in 8:
		if panel.selected_item_id() == &"item_manual_phong":
			break
		await _fire_action(&"move_down")
	assert_eq(panel.selected_item_id(), &"item_manual_phong", "a real move key chose the manual")
	assert_true(player.global_position.distance_to(start) < 1.0,
		"and the player did not walk while the satchel was open")
	for _attempt in 6:
		await _fire_action(INTERACT)
		if knowledge.get_service().knows(&"know_thanh_phong_chuong"):
			break
	assert_true(knowledge.get_service().knows(&"know_thanh_phong_chuong"),
		"a real E read the manual: the Clear-Wind Palm is known")
	assert_eq(inventory.count_of(&"item_manual_phong"), 0, "and the manual was consumed")
	for _attempt in 6:
		await _fire_action(&"inventory")
		if not hud.is_inventory_open():
			break
	assert_false(hud.is_inventory_open(), "the key closed it")
	var input := scene_tree.root.get_node_or_null("InputService")
	assert_true(bool(input.call("is_gameplay_active")), "and input is back with the world")


## Prove Phase 14 in the REAL app: pick up the jian and the robe, wear both through the satchel
## with real keys, and see the body change — attack power up through the stat view, the jian's
## thrust armed, the robe drawn — then take the jian off again.
func _prove_equipment(main: Node, player: Node2D, map: Node) -> void:
	var equipment := main.get_node_or_null("Systems/EquipmentRuntime") as EquipmentRuntime
	assert_not_null(equipment, "the EquipmentRuntime subsystem exists")
	var hud := _find_hud(map)
	if equipment == null or hud == null:
		return
	for path in ["Pickups/HubSword", "Pickups/HubRobe"]:
		var pickup := map.get_node_or_null(path) as Node2D
		assert_not_null(pickup, "%s exists" % path)
		if pickup != null:
			player.global_position = pickup.global_position
			for _i in 6:
				await scene_tree.physics_frame
	var bare_attack := int(player.call("get_attack_power"))
	for item_id in [&"item_kiem_thanh_thiet", &"item_dao_bao_thanh_van"]:
		for _attempt in 6:
			await _fire_action(&"inventory")
			if hud.is_inventory_open():
				break
		var panel := hud.inventory_panel()
		for _attempt in 8:
			if panel.selected_item_id() == item_id and not panel.selected_is_equipped():
				break
			await _fire_action(&"move_down")
		for _attempt in 6:
			await _fire_action(INTERACT)
			if equipment.is_worn(item_id):
				break
		assert_true(equipment.is_worn(item_id), "a real E wore '%s'" % item_id)
		for _attempt in 6:
			await _fire_action(&"inventory")
			if not hud.is_inventory_open():
				break
	assert_eq(int(player.call("get_attack_power")), bare_attack + 3,
		"the jian adds its attack through the stat view")
	var attack := player.get_node("AttackComponent") as AttackComponent
	assert_eq(attack.attack_data().id, &"attack_player_kiem", "the jian's thrust is armed")
	var visual := player.call("get_visual_component") as CharacterVisualComponent
	assert_eq(visual.get_sprite().texture.resource_path.get_file(), "player_daobao_idle.png",
		"the body is drawn in the Thanh Vân robe")
	assert_eq(equipment.unequip_item(&"item_kiem_thanh_thiet"), &"", "and the jian comes off")
	assert_eq(int(player.call("get_attack_power")), bare_attack, "attack back to bare")




## Wait real physics frames until `predicate` holds (bounded).
func _wait_until(predicate: Callable, frames: int) -> void:
	for _i in frames:
		if predicate.call():
			return
		await scene_tree.physics_frame


## Prove technique A in the REAL app: the manual read in the satchel proof taught the Clear-Wind
## Palm (the player is Hậu Thiên 1), the dock shows it, linh khí refills, and a REAL skill key
## casts it at the training post: the cast roots the player, the post is struck, qi is spent and
## the cooldown runs.
func _prove_technique_phong(main: Node, player: Node2D, map: Node) -> void:
	var skills := main.get_node_or_null("Systems/SkillRuntime") as SkillRuntime
	assert_not_null(skills, "the SkillRuntime subsystem exists")
	var hud := _find_hud(map)
	var post := map.get_node_or_null("CombatTargets/TrainingDummy") as Node2D
	if skills == null or hud == null or post == null:
		return
	assert_true(skills.knows(&"tech_thanh_phong_chuong"),
		"reading the manual as a Hậu Thiên cultivator taught the Clear-Wind Palm")
	assert_true(hud.skill_dock().visible and hud.skill_dock().slot_count() >= 1,
		"the skill dock shows the learned technique")
	await _wait_until(func() -> bool: return skills.qi() >= 10.0, 900)
	assert_true(skills.qi() >= 10.0, "linh khí refilled over real frames (%.1f)" % skills.qi())
	player.global_position = post.global_position + Vector2(-26, 2)
	Input.action_press(&"move_right")
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	Input.action_release(&"move_right")
	for _i in 4:
		await scene_tree.physics_frame
	var post_hp := int(post.call("get_current_health"))
	var released: Array = []
	skills.cast_released.connect(func(id: StringName, hits: int) -> void: released.append(hits))
	for _attempt in 4:
		await _press_through_physics(&"skill_1")
		if skills.cast_state().is_casting() or not released.is_empty():
			break
	assert_true(bool(player.call("is_cast_rooted")) or not released.is_empty(),
		"a real 1 key began the cast, and the caster is rooted")
	await _wait_until(func() -> bool: return not released.is_empty(), 120)
	assert_eq(released.size(), 1, "the palm was released once")
	assert_true(int(post.call("get_current_health")) < post_hp or int(released[0]) > 0,
		"the training post was struck by the wind")
	assert_true(skills.cooldown_left(&"tech_thanh_phong_chuong") > 0.0, "the cooldown runs")


## Prove technique B in the REAL app: walk onto the Thunder-Finger manual in the woods, read it
## through the satchel's own use path, and loose a bolt at a living wolf with a REAL 2 key.
func _prove_technique_loi(main: Node, player: Node2D, map: Node) -> void:
	var skills := main.get_node_or_null("Systems/SkillRuntime") as SkillRuntime
	var inventory := main.get_node_or_null("Systems/InventoryRuntime") as InventoryRuntime
	var combat := main.get_node_or_null("Systems/CombatRuntime") as CombatRuntime
	var manual := map.get_node_or_null("Pickups/FieldManualLoi") as Node2D
	if skills == null or inventory == null or combat == null or manual == null:
		assert_true(false, "the field has the Thunder-Finger manual and the runtimes exist")
		return
	player.global_position = manual.global_position
	for _i in 6:
		await scene_tree.physics_frame
	assert_eq(inventory.count_of(&"item_manual_loi"), 1, "the manual was picked up")
	assert_eq(inventory.use(&"item_manual_loi"), &"", "reading it teaches")
	assert_true(skills.knows(&"tech_loi_chi"), "the Thunder Finger is learned")
	var wolf: Enemy = null
	for enemy in combat.enemies():
		if not enemy.is_dead():
			wolf = enemy
	if wolf == null:
		assert_true(false, "a living wolf remains to test the bolt on")
		return
	await _wait_until(func() -> bool: return skills.qi() >= 16.0, 1200)
	var wolf_hp := wolf.get_current_health()
	player.global_position = wolf.global_position + Vector2(-90, 0)
	Input.action_press(&"move_right")
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	Input.action_release(&"move_right")
	player.global_position = wolf.global_position + Vector2(-90, 0)
	var struck: Array = []
	skills.bolt_struck.connect(func(at: Vector2) -> void: struck.append(at))
	for _attempt in 4:
		await _press_through_physics(&"skill_2")
		if skills.cast_state().is_casting():
			break
	await _wait_until(func() -> bool: return not struck.is_empty(), 180)
	assert_eq(struck.size(), 1, "the bolt flew and struck once")
	assert_true(wolf.get_current_health() < wolf_hp or wolf.is_dead(),
		"the wolf was hurt by the bolt")
	assert_true(wolf.is_dead() or wolf.ai().is_stunned(),
		"and Lôi's Choáng landed: the wolf is stunned (or the bolt finished it)")

