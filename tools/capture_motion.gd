extends SceneTree
## capture_motion — Aetheria MOTION capture harness (D-057B).
##
## `capture_ui.gd` proves a layout; it cannot prove a motion. A walk that slides, a strike whose
## effect starts beside the hand, a post that does not react, grass that sways in lockstep —
## every one of those passes a single screenshot and every unit test. This harness boots the
## REAL application in a REAL window, drives it with the SAME semantic input a player uses
## (`Input.action_press` / key events through `Input.parse_input_event` — never a direct call
## into gameplay), and writes FRAME STRIPS: the same world-space box around the subject,
## captured frame after frame and laid side by side, so motion can be read the way an animator
## reads it.
##
## The one concession is SETUP: the player is placed beside a subject (as the E2E flows place
## it on an exit zone) so a strip does not spend its frames walking across the map. Everything
## after the placement is input and the real runtime.
##
## USAGE (needs a display; do NOT pass --headless)
##     godot --path . --resolution 1280x720 -s res://tools/capture_motion.gd -- out/dir
##
## Scenarios: walk_stop_turn, strike_the_post, slash_the_post, ambient, cultivation,
## techniques, golden, field_fight, pet, shop, dialogue, session, quest (second user argument
## runs one; a third picks the language, `vi` or `en`, default the saved setting).
##
## OUTPUT: `<out>/motion_<scenario>.png` strips (each cell = one captured frame, magnified 2x
## on top of the camera's own zoom) and `<out>/scene_<name>.png` full frames. Exit code 1 if any
## scenario could not run — a missing strip must never look like a passing one.
##
## A BUILD-TIME TOOL: nothing in the game depends on it.

const MAIN_SCENE := "res://main.tscn"
const SETTLE_FRAMES := 12
const MENU_WAIT_FRAMES := 240
## Each strip cell is this many SCREEN pixels square around its subject, then magnified.
const CELL_PX := 160
const MAGNIFY := 2

var _out_dir := "user://motion_captures"
## Optional: run only the scenario with this name (second user argument).
var _only := ""
## Optional: the language to capture in (third user argument); "" keeps the saved setting.
var _language := ""
var _written: Array[String] = []
var _failed := false
var _main: Node = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_dir = String(args[0])
	if args.size() >= 2:
		_only = String(args[1])
	if args.size() >= 3:
		_language = String(args[2])
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(_main)
	await _settle()
	var menu := await _await_menu()
	if menu == null or not menu.has_signal("new_game_pressed"):
		_fail("no main menu to start a game from")
		_finish()
		return
	if _language != "":
		var loc := root.get_node_or_null("Localization")
		if loc == null or not bool(loc.call("set_language", _language)) \
				or String(loc.call("get_language")) != _language:
			_fail("could not switch to language '%s'" % _language)
			_finish()
			return
	menu.emit_signal("new_game_pressed")
	await _settle()
	await _settle()

	if _only == "" or _only == "walk_stop_turn":
		print("[capture_motion] scenario walk_stop_turn")
		await _scenario_walk_stop_turn()
	if _only == "" or _only == "strike_the_post":
		print("[capture_motion] scenario strike_the_post")
		await _scenario_strike_the_post()
	if _only == "" or _only == "slash_the_post":
		print("[capture_motion] scenario slash_the_post")
		await _scenario_slash_the_post()
	if _only == "" or _only == "ambient":
		print("[capture_motion] scenario ambient")
		await _scenario_ambient()
	if _only == "" or _only == "cultivation":
		print("[capture_motion] scenario cultivation")
		await _scenario_cultivation()
	if _only == "" or _only == "techniques":
		print("[capture_motion] scenario techniques")
		await _scenario_techniques()
	if _only == "" or _only == "golden":
		print("[capture_motion] scenario golden")
		await _scenario_golden()
	if _only == "pet":
		print("[capture_motion] scenario pet")
		await _scenario_pet()
	if _only == "shop":
		print("[capture_motion] scenario shop")
		await _scenario_shop()
	if _only == "dialogue":
		print("[capture_motion] scenario dialogue")
		await _scenario_dialogue()
	if _only == "session":
		print("[capture_motion] scenario session")
		await _scenario_session()
	if _only == "quest":
		print("[capture_motion] scenario quest")
		await _scenario_quest()
	if _only == "" or _only == "field_fight":
		print("[capture_motion] scenario field_fight")
		await _scenario_field_fight()
	_finish()


# === Scenarios ==============================================================

## Walk right across open ground, stop, then reverse: stride cadence, the settle, the turn.
func _scenario_walk_stop_turn() -> void:
	var player := _player()
	if player == null:
		_fail("walk: no player")
		return
	player.global_position = Vector2(300, 312)
	await _settle()
	await _shot("scene_hub")
	Input.action_press(&"move_right")
	var walk := await _strip(func() -> Vector2: return player.global_position + Vector2(0, -20),
		16, 2)
	Input.action_release(&"move_right")
	var stop := await _strip(func() -> Vector2: return player.global_position + Vector2(0, -20),
		8, 1)
	Input.action_press(&"move_left")
	var turn := await _strip(func() -> Vector2: return player.global_position + Vector2(0, -20),
		8, 1)
	Input.action_release(&"move_left")
	_save_strip("motion_walk", walk)
	_save_strip("motion_stop", stop)
	_save_strip("motion_turn", turn)
	await _settle()


## Strike the training post from its left: the coil, the release from the palm, the post's
## wobble about its footing and the straw that falls from it.
func _scenario_strike_the_post() -> void:
	var player := _player()
	var post := _map_node("CombatTargets/TrainingDummy") as Node2D
	if player == null or post == null:
		_fail("strike: no player or training post")
		return
	player.global_position = post.global_position + Vector2(-26, 2)
	# Face the post through the real input path, then let go.
	Input.action_press(&"move_right")
	await process_frame
	await process_frame
	Input.action_release(&"move_right")
	await _settle()
	var focus := func() -> Vector2: return post.global_position + Vector2(-14, -16)
	await _press(&"attack")
	var frames := await _strip(focus, 24, 1)
	_save_strip("motion_strike_post", frames)
	await _settle()


## D-063 A3: the sword cut with the jian equipped. The default `strike_the_post` uses the
## bare-fisted loadout (the jian is a hub pickup), so it exercises the fallback body — this
## scenario picks the jian up and wears it through the real inventory UI first, then strikes
## the same post. Mirrors tests/e2e/world_flow_case.gd's equip flow; deterministic setup.
func _scenario_slash_the_post() -> void:
	var player := _player()
	var post := _map_node("CombatTargets/TrainingDummy") as Node2D
	if player == null or post == null:
		_fail("slash: no player or training post")
		return
	if not await _equip_hub_sword(player):
		_fail("slash: could not equip the jian")
		return
	if not await _capture_slash_strip(player, post,
			"motion_slash_post", "player_proto_slash.png"):
		return
	await _settle()
	# The second player look (D-063 A3 review): the Thanh Van robe swaps the body to the
	# daobao profile — its own sheet, anchors and depths. Worn as DETERMINISTIC SETUP like
	# the sword above (the inventory-UI path is proven by tests/e2e/world_flow_case.gd);
	# everything after the setup is real input + real runtime.
	if not await _equip_daobao_robe(player):
		_fail("slash: could not equip the Thanh Van robe")
		return
	if not await _capture_slash_strip(player, post,
			"motion_slash_post_daobao", "player_daobao_slash.png"):
		return
	await _settle()


## One guarded slash capture for a single look: positions the player, drives a REAL attack
## input, and verifies — LOUDLY — that the swing actually happened. The jian must still be
## worn, the attack lifecycle must have started, the visual must be in ACTION_SLASH showing
## this profile's slash sheet, and at least one captured frame must belong to the slash.
## Anything less calls `_fail()` instead of writing a successful-looking strip.
func _capture_slash_strip(player: Node2D, post: Node2D, strip_name: String,
		slash_file: String) -> bool:
	var main := root.get_node_or_null("Main")
	var equipment := main.get_node_or_null("Systems/EquipmentRuntime") \
		if main != null else null
	var attack_comp := player.get_node_or_null("AttackComponent") as AttackComponent
	var visual := player.call("get_visual_component") as CharacterVisualComponent
	if equipment == null or attack_comp == null or visual == null:
		_fail("slash: missing equipment, attack or visual component")
		return false
	player.global_position = post.global_position + Vector2(-26, 2)
	Input.action_press(&"move_right")
	await process_frame
	await process_frame
	Input.action_release(&"move_right")
	await _settle()
	if not bool(equipment.call("is_worn", &"item_kiem_thanh_thiet")):
		_fail("slash: the jian is no longer equipped")
		return false
	var focus := func() -> Vector2: return post.global_position + Vector2(-14, -16)
	await _press(&"attack")
	# The lifecycle is real-time: poll briefly for the input to land, then demand proof.
	# (Polling, not a fixed wait: on a slow frame the press can take a few frames to
	# register, but the 440 ms lifecycle far outlasts the poll window.)
	var started := false
	for _i in 15:
		await process_frame
		if attack_comp.state() != AttackStateMachine.State.READY:
			started = true
			break
	if not started:
		_fail("slash: the attack input did not start the lifecycle")
		return false
	if visual.current_action() != CharacterVisualComponent.ACTION_SLASH:
		_fail("slash: the visual did not enter ACTION_SLASH")
		return false
	var tex: Texture2D = visual.get_sprite().texture
	if tex == null or tex.resource_path.get_file() != slash_file:
		_fail("slash: the visual is not showing %s" % slash_file)
		return false
	var frames: Array[Image] = []
	var saw_slash := false
	for _i in 24:
		await process_frame
		if visual.current_action() == CharacterVisualComponent.ACTION_SLASH:
			saw_slash = true
		frames.append(_cell(focus.call()))
	if not saw_slash:
		_fail("slash: no captured frame belonged to the slash action")
		return false
	_save_strip(strip_name, frames)
	return true


## The hub robe, worn as DETERMINISTIC SETUP like the sword above: proves the daobao
## profile path of the slash, not the inventory UI.
func _equip_daobao_robe(player: Node2D) -> bool:
	var pickup := _map_node("Pickups/HubRobe") as Node2D
	if pickup == null:
		_fail("slash: no HubRobe pickup in this map")
		return false
	player.global_position = pickup.global_position
	for _i in 6:
		await physics_frame
	var main := root.get_node_or_null("Main")
	var equipment := main.get_node_or_null("Systems/EquipmentRuntime") \
		if main != null else null
	if equipment == null:
		_fail("slash: no EquipmentRuntime")
		return false
	var err: StringName = equipment.call("equip", &"item_dao_bao_thanh_van")
	if err != &"":
		_fail("slash: robe equip refused (%s)" % err)
		return false
	if not bool(equipment.call("is_worn", &"item_dao_bao_thanh_van")):
		_fail("slash: equip reported success but the robe is not worn")
		return false
	for _i in 3:
		await process_frame
	var visual := player.call("get_visual_component") as CharacterVisualComponent
	if visual == null:
		_fail("slash: the player has no visual component")
		return false
	var tex: Texture2D = visual.get_sprite().texture
	if tex == null or tex.resource_path.get_file() != "player_daobao_idle.png":
		_fail("slash: the robe did not swap the body to the daobao look")
		return false
	return true


## Pick up the hub jian, then wear it as DETERMINISTIC SETUP (sanctioned by this harness's
## own docstring and the playtest's L-017 exception): the wear-via-inventory-UI path is
## proven by tests/e2e/world_flow_case.gd (3/3 green) — this scenario captures the slash
## VISUAL, not the inventory UI. Everything after the setup is real input + real runtime.
func _equip_hub_sword(player: Node2D) -> bool:
	var pickup := _map_node("Pickups/HubSword") as Node2D
	if pickup == null:
		_fail("slash: no HubSword pickup in this map")
		return false
	player.global_position = pickup.global_position
	for _i in 6:
		await physics_frame
	var main := root.get_node_or_null("Main")
	var equipment := main.get_node_or_null("Systems/EquipmentRuntime") \
		if main != null else null
	if equipment == null:
		_fail("slash: no EquipmentRuntime")
		return false
	var err: StringName = equipment.call("equip", &"item_kiem_thanh_thiet")
	if err != &"":
		_fail("slash: equip refused (%s)" % err)
		return false
	if not bool(equipment.call("is_worn", &"item_kiem_thanh_thiet")):
		_fail("slash: equip reported success but the jian is not worn")
		return false
	return true


## Two moments a beat apart over the banners and a tree: the wind must have MOVED them, and not
## all by the same amount (no synchronized wallpaper).
func _scenario_ambient() -> void:
	var banner := _map_node("Visual/Decor/BannerW") as Node2D
	# the Blender-built broadleaf by the outpost (D-062): its canopy wears the shared sway
	var tree := _map_node("Visual/Decor/Prop_TreeNE") as Node2D
	if banner == null or tree == null:
		_fail("ambient: hub decor missing")
		return
	var player := _player()
	if player != null:
		player.global_position = banner.global_position + Vector2(20, 60)
	await _settle()
	var frames: Array[Image] = []
	for i in 6:
		frames.append(_cell(banner.global_position + Vector2(20, -24)))
		for _f in 20:
			await process_frame
	_save_strip("motion_banner_wind", frames)
	if player != null:
		player.global_position = tree.global_position + Vector2(40, 40)
	await _settle()
	frames = []
	for i in 6:
		frames.append(_cell(tree.global_position + Vector2(0, -66)))
		for _f in 20:
			await process_frame
	_save_strip("motion_tree_wind", frames)


## Read the stele, sit at the spring, break through: the seated pose, the qi a mortal barely
## senses, the macro release and the wind it pushes into the grass.
func _scenario_cultivation() -> void:
	var player := _player()
	var stele := _map_node("KnowledgeSources/LacHaStele") as Node2D
	var spring := _map_node("CultivationSites/LacHaSpring") as Node2D
	var cultivation := _main.get_node_or_null("Systems/CultivationRuntime") as CultivationRuntime
	if player == null or stele == null or spring == null or cultivation == null:
		_fail("cultivation: hub pieces missing")
		return
	player.global_position = stele.global_position + Vector2(0, 14)
	await _settle()
	await _press(&"interact")
	await _settle()
	await _shot("scene_stele_read")
	player.global_position = spring.global_position + Vector2(0, 26)
	await _settle()
	await _hold(&"cultivate")
	var focus := func() -> Vector2: return spring.global_position + Vector2(0, -10)
	var sit := await _strip(focus, 16, 3)
	_save_strip("motion_meditate_mortal", sit)
	cultivation.get_service().gather(player.call("get_character_state"), 999)
	await _hold(&"cultivate")
	var burst := await _strip(focus, 32, 4)
	_save_strip("motion_breakthrough", burst)
	await _shot("scene_after_breakthrough")
	var seated := await _strip(focus, 8, 6)
	_save_strip("motion_meditate_hau_thien", seated)
	Input.action_press(&"move_up")
	await _settle()
	Input.action_release(&"move_up")
	await _settle()


## Both techniques in the real app: the Clear-Wind Palm at the training post, then the Thunder
## Finger at a wolf. Setup goes THROUGH the services (method + breakthrough + knowledge), never
## around them; the casts are real skill keys.
func _scenario_techniques() -> void:
	var player := _player()
	var knowledge := _main.get_node_or_null("Systems/KnowledgeRuntime") as KnowledgeRuntime
	var cultivation := _main.get_node_or_null("Systems/CultivationRuntime") as CultivationRuntime
	var skills := _main.get_node_or_null("Systems/SkillRuntime") as SkillRuntime
	var post := _map_node("CombatTargets/TrainingDummy") as Node2D
	if player == null or knowledge == null or skills == null or post == null:
		_fail("techniques: pieces missing")
		return
	var state: CharacterState = player.call("get_character_state")
	knowledge.grant(&"know_dan_khi_quyet", &"capture")
	if state.realm_id == &"realm_pham":
		cultivation.get_service().gather(state, 999)
		cultivation.get_service().breakthrough(state)
		cultivation.realm_advanced.emit(state.realm_id, state.realm_layer, true)
	knowledge.grant(&"know_thanh_phong_chuong", &"capture")
	knowledge.grant(&"know_loi_chi", &"capture")
	while skills.qi() < 30.0:
		await physics_frame
	player.global_position = post.global_position + Vector2(-30, 2)
	await _hold(&"move_right")
	await _settle()
	await _shot("scene_dock")
	var focus := func() -> Vector2: return post.global_position + Vector2(-16, -14)
	await _hold(&"skill_1")
	var phong := await _strip(focus, 24, 1)
	_save_strip("motion_phong", phong)
	while skills.qi() < 16.0:
		await physics_frame
	player.global_position = post.global_position + Vector2(-110, 2)
	for _i in 4:
		await _settle()  # let the follow camera arrive before sampling
	await _hold(&"skill_2")
	var loi_focus := func() -> Vector2: return player.global_position + Vector2(50, -14)
	var loi: Array[Image] = []
	for i in 24:
		await process_frame
		loi.append(_cell(loi_focus.call()))
		if i == 3 or i == 8:
			await _shot("scene_loi_%d" % i)
	_save_strip("motion_loi", loi)


## Hold an action across a few frames (the way a hand presses a key), then release.
func _hold(action: StringName) -> void:
	Input.action_press(action)
	for _i in 4:
		await physics_frame
	Input.action_release(action)
	await process_frame


## Into the field through the real exit, then a mist wolf: its telegraphed bite on the player,
## and the player's strike landing on it.
func _scenario_field_fight() -> void:
	var player := _player()
	if player == null:
		_fail("field: no player")
		return
	if not await _travel_through_first_exit(player):
		_fail("field: the exit did not transition")
		return
	await _settle()
	await _shot("scene_field")
	var wolf := _first_enemy()
	if wolf == null:
		_fail("field: no enemy spawned")
		return
	# Stand within the wolf's reach and wait: it hunts, telegraphs, bites.
	player.global_position = wolf.global_position + Vector2(-30, 4)
	var bite := await _strip(func() -> Vector2:
		return (wolf.global_position + player.global_position) * 0.5 + Vector2(0, -14), 30, 2)
	_save_strip("motion_wolf_bite", bite)
	# Face the wolf through input, then strike it.
	var toward := (wolf.global_position - player.global_position).normalized()
	var key := &"move_right" if toward.x >= 0.0 else &"move_left"
	Input.action_press(key)
	await process_frame
	await process_frame
	Input.action_release(key)
	await _press(&"attack")
	var strike := await _strip(func() -> Vector2:
		return (wolf.global_position + player.global_position) * 0.5 + Vector2(0, -14), 22, 1)
	_save_strip("motion_strike_wolf", strike)
	await _settle()
	await _shot("scene_field_after")


## The linh thú (Phase 16), by name only (it changes the session, so it is not part of the
## default run): the stray by the yard and its prompt, befriending it, the hound following a
## walking player, then the field — it closes on a wolf and bites.
func _scenario_pet() -> void:
	var player := _player()
	var stray := _map_node("Interactables/StrayHound") as Node2D
	var pets := _main.get_node_or_null("Systems/PetRuntime") as PetRuntime
	if player == null or stray == null or pets == null:
		_fail("pet: hub pieces missing")
		return
	player.global_position = stray.global_position + Vector2(-22, 2)
	await _settle()
	await _shot("scene_pet_stray")
	var idle := await _strip(func() -> Vector2: return stray.global_position + Vector2(0, -8),
		8, 6)
	_save_strip("motion_pet_stray_idle", idle)
	await _press(&"interact")
	await _settle()
	if not pets.is_out():
		_fail("pet: interact did not befriend the stray")
		return
	await _shot("scene_pet_befriended")
	var pet := pets.active_pet()
	# Up into the open square: no canopy between the pair and the camera.
	Input.action_press(&"move_up")
	var follow := await _strip(func() -> Vector2:
		return (pet.global_position + player.global_position) * 0.5 + Vector2(0, -12), 16, 4)
	Input.action_release(&"move_up")
	_save_strip("motion_pet_follow", follow)
	await _settle()
	await _settle()
	await _shot("scene_pet_beside")
	await _hold(&"pet_summon")
	await _settle()
	await _shot("scene_pet_dismissed")
	await _hold(&"pet_summon")
	await _settle()
	if not await _travel_through_first_exit(player):
		_fail("pet: the exit did not transition")
		return
	await _settle()
	var wolf := _first_enemy()
	pet = pets.active_pet()
	if wolf == null or pet == null:
		_fail("pet: no wolf, or the pet did not cross the map change")
		return
	player.global_position = wolf.global_position + Vector2(70, 6)
	# The pet WALKS from the map entrance to its owner (it never teleports), so wait for it to
	# reach the fight before the strip starts — bounded, and a pet that never arrives fails.
	var arrived := false
	for _i in 900:
		await physics_frame
		if pet.global_position.distance_to(wolf.global_position) < 40.0:
			arrived = true
			break
	if not arrived:
		_fail("pet: it never closed on the wolf")
		return
	var fight := await _strip(func() -> Vector2:
		return (wolf.global_position + pet.global_position) * 0.5 + Vector2(0, -12), 32, 3)
	_save_strip("motion_pet_fight", fight)
	await _shot("scene_pet_fight")


## The shop (Phase 17), by name only: Kha Thản at the field's edge — the prompt that names him,
## his shop on the buying side, the selling side, a refusal, and the same shop once he has
## taken against the player (the adjusted AND base price both showing).
##
## SETUP, stated plainly: the pills and stones are real pickups the player is stood on, and the
## last frame's regard is STAGED through the relationship service to show the mark-up colours
## (the `dialogue` scenario reaches an adjusted price by really talking to him). Every action
## after a placement is a real key. Since Phase 18 his shop is his conversation's "Trade"
## answer: interact (talk), interact (past the greeting), interact (Trade).
func _scenario_shop() -> void:
	var player := _player()
	var pill := _map_node("Pickups/HubPill1") as Node2D
	var npcs := _main.get_node_or_null("Systems/NpcRuntime") as NpcRuntime
	var relationship := _main.get_node_or_null("Systems/RelationshipRuntime") as RelationshipRuntime
	if player == null or pill == null or npcs == null or relationship == null:
		_fail("shop: pieces missing")
		return
	player.global_position = pill.global_position
	await _settle()
	if not await _travel_through_first_exit(player):
		_fail("shop: the exit did not transition")
		return
	await _settle()
	for stone_name: String in ["FieldStone1", "FieldStone2"]:
		var stone := _map_node("Pickups/%s" % stone_name) as Node2D
		if stone != null:
			player.global_position = stone.global_position
			await _settle()
	var ko := _map_node("Interactables/KoThan") as Node2D
	if ko == null:
		_fail("shop: Kha Thản is not in the field")
		return
	player.global_position = ko.global_position + Vector2(60, 6)
	await _settle()
	Input.action_press(&"move_left")
	for _i in 12:
		await physics_frame
	Input.action_release(&"move_left")
	await _settle()
	await _shot("scene_npc_prompt")
	await _press(&"interact")
	var talk := await _strip(func() -> Vector2: return ko.global_position + Vector2(8, -18), 8, 4)
	_save_strip("motion_npc_talk", talk)
	await _settle()
	await _press(&"interact")
	await _settle()
	await _press(&"interact")
	await _settle()
	if not npcs.is_shop_open():
		_fail("shop: interact did not open the shop")
		return
	await _settle()
	await _shot("scene_shop_buy")
	await _press(&"move_right")
	await _settle()
	await _shot("scene_shop_sell")
	await _press(&"interact")
	await _settle()
	await _press(&"move_left")
	await _settle()
	await _press(&"move_down")
	await _settle()
	await _press(&"move_down")
	await _settle()
	await _press(&"interact")
	await _settle()
	await _shot("scene_shop_refusal")
	var service := relationship.get_service()
	service.create_edge(&"edge_capture_ko_player",
		RelationshipEndpoint.for_character(&"actor_scout_ko"),
		RelationshipEndpoint.for_character(&"player"))
	service.set_dimension(&"edge_capture_ko_player", &"affinity", -60, &"capture")
	npcs.view_changed.emit()
	await _settle()
	await _shot("scene_shop_disliked")
	await _press(&"open_menu")
	await _settle()
	await _shot("scene_shop_closed")


## Dialogue (Phase 18), by name only: two people, one box. The elder in Lạc Hà (an answer that
## appears only once the stele has been read, respect earned, a precept taught) and the scout
## at the field's edge (news that pleases him, then "Trade" handing over to his shop at the
## price that earns).
##
## SETUP, stated plainly: the player is PLACED beside each person, the stele and the pickups,
## and the stray is befriended so the pet prompt is in the closed-HUD frame. Every action after
## a placement is a real key; nothing is written to a runtime.
func _scenario_dialogue() -> void:
	var player := _player()
	var dialogue := _main.get_node_or_null("Systems/DialogueRuntime") as DialogueRuntime
	var npcs := _main.get_node_or_null("Systems/NpcRuntime") as NpcRuntime
	var shen := _map_node("Interactables/ShenBuqi") as Node2D
	var stele := _map_node("KnowledgeSources/LacHaStele") as Node2D
	var hound := _map_node("Interactables/StrayHound") as Node2D
	if player == null or dialogue == null or npcs == null or shen == null or stele == null:
		_fail("dialogue: pieces missing")
		return
	if hound != null:
		player.global_position = hound.global_position + Vector2(-18, 4)
		await _settle()
		await _press(&"interact")
		await _settle()
	await _stand_beside(player, shen)
	await _shot("scene_dialogue_prompt")
	await _press(&"interact")
	await _settle()
	if not dialogue.is_open():
		_fail("dialogue: interact did not open the elder's conversation")
		return
	await _shot("scene_dialogue_elder_greet")
	await _press(&"interact")
	await _settle()
	await _shot("scene_dialogue_elder_unread")
	await _press(&"open_menu")
	await _settle()
	await _shot("scene_dialogue_closed_hud")
	player.global_position = stele.global_position + Vector2(0, 20)
	await _settle()
	await _press(&"interact")
	await _settle()
	await _stand_beside(player, shen)
	await _press(&"interact")
	await _settle()
	await _press(&"interact")
	await _settle()
	await _shot("scene_dialogue_elder_choices")
	await _press(&"interact")
	var elder_talk := await _strip(
		func() -> Vector2: return shen.global_position + Vector2(8, -18), 8, 4)
	_save_strip("motion_dialogue_elder_talk", elder_talk)
	await _shot("scene_dialogue_elder_approve")
	await _press(&"interact")
	await _settle()
	await _press(&"interact")
	await _settle()
	await _shot("scene_dialogue_elder_teach")
	await _press(&"interact")
	await _settle()
	await _choose(&"shen_leave")
	await _shot("scene_dialogue_elder_leave_selected")
	await _press(&"interact")
	await _settle()
	if dialogue.is_open():
		_fail("dialogue: the leave answer did not end the elder's conversation")
		return
	if not await _travel_through_first_exit(player):
		_fail("dialogue: the exit did not transition")
		return
	await _settle()
	for stone_name: String in ["FieldStone1", "FieldStone2"]:
		var stone := _map_node("Pickups/%s" % stone_name) as Node2D
		if stone != null:
			player.global_position = stone.global_position
			await _settle()
	var ko := _map_node("Interactables/KoThan") as Node2D
	if ko == null:
		_fail("dialogue: Kha Thản is not in the field")
		return
	await _stand_beside(player, ko)
	await _press(&"interact")
	var ko_talk := await _strip(
		func() -> Vector2: return ko.global_position + Vector2(8, -18), 8, 4)
	_save_strip("motion_dialogue_ko_talk", ko_talk)
	await _shot("scene_dialogue_ko_greet")
	await _press(&"interact")
	await _settle()
	await _shot("scene_dialogue_ko_hub")
	await _press(&"move_down")
	await _settle()
	await _press(&"move_down")
	await _settle()
	await _press(&"interact")
	await _settle()
	await _shot("scene_dialogue_ko_price")
	await _press(&"interact")
	await _settle()
	await _shot("scene_dialogue_ko_pleased")
	await _press(&"interact")
	await _settle()
	await _press(&"interact")
	await _settle()
	if not npcs.is_shop_open() or dialogue.is_open():
		_fail("dialogue: 'Trade' did not hand over to the shop")
		return
	await _shot("scene_dialogue_to_shop")
	await _press(&"open_menu")
	await _settle()
	await _shot("scene_dialogue_after_shop")


## The session itself (D-068), by name only: the companion standing BESIDE its owner, Esc
## asking before it leaves, and a real defeat ending the run in words.
##
## SETUP, stated plainly: the player is placed beside the stray and, for the defeat, in a Vụ
## Lang's den. The bites, the fall and every key press are the game's own.
func _scenario_session() -> void:
	var player := _player()
	var hound := _map_node("Interactables/StrayHound") as Node2D
	var combat := _main.get_node_or_null("Systems/CombatRuntime") as CombatRuntime
	if player == null or hound == null or combat == null:
		_fail("session: pieces missing")
		return
	player.global_position = hound.global_position + Vector2(-18, 4)
	await _settle()
	await _press(&"interact")
	await _settle()
	for move: StringName in [&"move_left", &"move_up"]:
		Input.action_press(move)
		for _i in 50:
			await physics_frame
		Input.action_release(move)
		for _i in 80:
			await physics_frame
	await _shot("scene_session_pet_beside")
	await _press(&"sect_panel")
	await _settle()
	await _press(&"open_menu")
	await _settle()
	await _shot("scene_session_esc_closed_panel")
	await _press(&"open_menu")
	await _settle()
	await _shot("scene_session_leave_question")
	await _press(&"open_menu")
	await _settle()
	# Sent away with its own key: a companion would win the fight this frame needs lost.
	await _press(&"pet_summon")
	await _settle()
	if not await _travel_through_first_exit(player):
		_fail("session: the exit did not transition")
		return
	await _settle()
	var wolf := combat.enemies()[0] as Node2D
	player.global_position = wolf.global_position + Vector2(30, 0)
	var fallen := false
	for _i in 4000:
		await physics_frame
		if bool(player.call("is_dead")):
			fallen = true
			break
	if not fallen:
		_fail("session: the player was not defeated")
		return
	await _settle()
	await _shot("scene_session_defeat")


## Both shipped quests (Phase 19), start to finish: the purpose line at spawn, the elder's
## ask and its explicit choice, the journal, the question before a task is given back, the
## scout's errand, the knowledge route, a reward refused by a full satchel and then paid, the
## pills carried to the scout.
##
## SETUP, stated plainly: the player is PLACED beside each person and the stele, and the
## satchel is filled and emptied through `InventoryRuntime` for the refusal frame. Every
## answer, every panel and every map change is a real key.
func _scenario_quest() -> void:
	var player := _player()
	var quests := _main.get_node_or_null("Systems/QuestRuntime") as QuestRuntime
	var inventory := _main.get_node_or_null("Systems/InventoryRuntime") as InventoryRuntime
	var shen := _map_node("Interactables/ShenBuqi") as Node2D
	var stele := _map_node("KnowledgeSources/LacHaStele") as Node2D
	if player == null or quests == null or inventory == null or shen == null or stele == null:
		_fail("quest: pieces missing")
		return
	await _settle()
	await _shot("scene_quest_01_spawn_lead")
	player.global_position = stele.global_position + Vector2(0, 20)
	await _settle()
	await _press(&"interact")
	await _settle()
	if not await _open_talk(player, shen):
		return
	await _choose(&"shen_task_ask")
	await _press(&"interact")
	await _settle()
	await _shot("scene_quest_02_elder_why")
	await _press(&"interact")
	await _settle()
	await _shot("scene_quest_03_elder_offer")
	await _press(&"interact")
	await _settle()
	if quests.get_service().phase_of(&"quest_unquiet_vein") != QuestService.Phase.ACTIVE:
		_fail("quest: the elder's task was not accepted")
		return
	await _shot("scene_quest_04_accepted")
	await _press(&"interact")
	await _settle()
	await _press(&"quest_journal")
	await _settle()
	await _shot("scene_quest_05_journal_active")
	await _press(&"quest_journal")
	await _settle()
	if not await _open_talk(player, shen):
		return
	await _choose(&"shen_task_about")
	await _press(&"interact")
	await _settle()
	await _choose(&"shen_task_giveup")
	await _press(&"interact")
	await _settle()
	await _shot("scene_quest_06_abandon_question")
	await _press(&"interact")  # the answer under the cursor KEEPS the task
	await _settle()
	await _press(&"open_menu")
	await _settle()
	if not await _travel_through_first_exit(player):
		_fail("quest: the exit did not transition")
		return
	await _settle()
	var ko := _map_node("Interactables/KoThan") as Node2D
	if ko == null or not await _open_talk(player, ko):
		_fail("quest: Kha Thản could not be talked to")
		return
	await _shot("scene_quest_07_ko_hub_five")
	await _choose(&"ko_pills_ask")
	await _press(&"interact")
	await _settle()
	await _shot("scene_quest_08_ko_offer")
	await _press(&"interact")
	await _settle()
	await _shot("scene_quest_09_ko_taken")
	await _press(&"interact")
	await _settle()
	if not await _open_talk(player, ko):
		return
	await _choose(&"ko_ask_woods")
	await _press(&"interact")
	await _settle()
	await _press(&"interact")
	await _settle()
	await _press(&"open_menu")
	# The answers to this press drain first; then the passive "ready" line has the band.
	for _i in 600:
		await process_frame
		if _hud() != null and _hud().purpose_text() != "" \
				and _hud().notice_text().contains(_hud().purpose_text()):
			break
	await _shot("scene_quest_10_ready_notice")
	await _press(&"quest_journal")
	await _settle()
	await _shot("scene_quest_11_journal_ready_and_active")
	await _press(&"quest_journal")
	await _settle()
	if not await _travel_through_first_exit(player):
		_fail("quest: the way back did not transition")
		return
	await _settle()
	shen = _map_node("Interactables/ShenBuqi") as Node2D
	var bag := inventory.get_bag()
	inventory.give(&"item_kiem_thanh_thiet", bag.capacity)  # SETUP: a full satchel
	var blades := inventory.count_of(&"item_kiem_thanh_thiet")
	if not await _open_talk(player, shen):
		return
	await _choose(&"shen_task_report_word")
	await _press(&"interact")
	await _settle()
	await _shot("scene_quest_12_reward_refused")
	await _press(&"open_menu")
	await _settle()
	inventory.take(&"item_kiem_thanh_thiet", blades)  # SETUP: room made
	if not await _open_talk(player, shen):
		return
	await _choose(&"shen_task_report_word")
	await _press(&"interact")
	await _settle()
	if quests.get_service().phase_of(&"quest_unquiet_vein") != QuestService.Phase.COMPLETED:
		_fail("quest: the elder's task was not completed")
		return
	await _shot("scene_quest_13_reward_paid")
	for _i in 600:
		await process_frame
		if _hud() != null and _hud().notice_text().contains("×2"):
			break
	await _shot("scene_quest_14_reward_received")
	await _press(&"interact")
	await _settle()
	await _press(&"quest_journal")
	await _settle()
	await _shot("scene_quest_15_journal_done_and_ready")
	await _press(&"quest_journal")
	await _settle()
	if not await _travel_through_first_exit(player):
		_fail("quest: the road to the scout did not transition")
		return
	await _settle()
	ko = _map_node("Interactables/KoThan") as Node2D
	if ko == null or not await _open_talk(player, ko):
		return
	await _choose(&"ko_pills_give")
	await _press(&"interact")
	await _settle()
	if quests.get_service().phase_of(&"quest_treeline_pills") != QuestService.Phase.COMPLETED:
		_fail("quest: the scout's errand was not completed")
		return
	await _shot("scene_quest_16_ko_done")
	await _press(&"interact")
	await _settle()
	await _press(&"quest_journal")
	await _settle()
	await _shot("scene_quest_17_journal_all_done")


## The HUD of the active map, or null.
func _hud() -> GameplayHUD:
	var map := _current_map()
	var found := map.find_children("*", "GameplayHUD", true, false) if map != null else []
	return found[0] as GameplayHUD if not found.is_empty() else null


## Walk beside `who`, open their conversation with a real key and pass the greeting.
func _open_talk(player: Node2D, who: Node2D) -> bool:
	var dialogue := _main.get_node_or_null("Systems/DialogueRuntime") as DialogueRuntime
	await _stand_beside(player, who)
	await _press(&"interact")
	await _settle()
	if dialogue == null or not dialogue.is_open():
		_fail("the conversation did not open")
		return false
	await _press(&"interact")
	await _settle()
	return true


## Move the cursor to `choice_id` with real move keys (bounded; a lost press is retried).
func _choose(choice_id: StringName) -> void:
	var hud := _hud()
	var panel := hud.dialogue_panel() if hud != null else null
	if panel == null or not panel.choice_ids().has(choice_id):
		_fail("'%s' is not offered" % choice_id)
		return
	for _i in 8:
		if panel.selected_choice_id() == choice_id:
			break
		await _press(&"move_down")
		await _settle()
	if panel.selected_choice_id() != choice_id:
		_fail("'%s' could not be selected" % choice_id)


## SETUP + a short real walk: stand to the right of `who`, just out of reach, and walk in.
func _stand_beside(player: Node2D, who: Node2D) -> void:
	player.global_position = who.global_position + Vector2(60, 6)
	await _settle()
	Input.action_press(&"move_left")
	for _i in 12:
		await physics_frame
	Input.action_release(&"move_left")
	await _settle()


## THE GOLDEN COMBAT SCENE (D-062 CP10): the benchmark frame. Thôn Lạc Hà, the protagonist at
## the training yard meeting a Vụ Lang at range with Lôi Chỉ (the bolt crosses the yard between
## them), Lâm Nguyệt (the second golden actor, the same pipeline) watching from the grass, the
## full HUD.
##
## SETUP, stated plainly: the realm, the techniques and the wolf are placed through the
## runtimes' public API (a spawn table built here, `CombatRuntime.spawn_from_table`), and Lâm
## Nguyệt is a visual figure placed for the frame — there is no NPC system before P16, and this
## scene does not pretend one. Everything after the setup is real input and the real runtime.
## Writes `golden_combat.png` (the frame with the most technique on screen), the frames around
## it, and `golden_combat.json`: where the HUD, the actors and the screen are, for the benchmark.
func _scenario_golden() -> void:
	var player := _player()
	var knowledge := _main.get_node_or_null("Systems/KnowledgeRuntime") as KnowledgeRuntime
	var cultivation := _main.get_node_or_null("Systems/CultivationRuntime") as CultivationRuntime
	var skills := _main.get_node_or_null("Systems/SkillRuntime") as SkillRuntime
	var combat := _main.get_node_or_null("Systems/CombatRuntime")
	var host := _map_node("CombatTargets")
	if player == null or knowledge == null or skills == null or combat == null or host == null:
		_fail("golden: pieces missing")
		return
	var state: CharacterState = player.call("get_character_state")
	knowledge.grant(&"know_dan_khi_quyet", &"capture")
	if state.realm_id == &"realm_pham":
		cultivation.get_service().gather(state, 999)
		cultivation.get_service().breakthrough(state)
		cultivation.realm_advanced.emit(state.realm_id, state.realm_layer, true)
	knowledge.grant(&"know_thanh_phong_chuong", &"capture")
	knowledge.grant(&"know_loi_chi", &"capture")
	# Lâm Nguyệt on the square, facing the yard.
	var lin := CharacterVisualComponent.new()
	lin.name = "GoldenLinYue"
	_map_node("Visual/Decor").add_child(lin)
	lin.setup(load("res://data/characters/visual/cultivator_f_visual.tres"))
	lin.global_position = Vector2(560, 372)
	lin.update_facing(Vector2(1, 0.4), false)
	# The player at the yard, READY (full linh khí) before the wolf exists — a wolf released
	# while the pool refills simply bites (the second take showed a defeated player).
	player.global_position = Vector2(628, 440)
	while skills.qi() < 30.0:
		await physics_frame
	await _hold(&"move_right")
	var table := EnemySpawnTableData.new()
	table.map_id = &"map_hub"
	table.enemies = [load("res://data/enemies/enemy_mist_wolf.tres")]
	table.positions = PackedVector2Array([Vector2(800, 436)])
	combat.call("spawn_from_table", table, host)
	var wolf := _first_enemy()
	if wolf == null:
		_fail("golden: the wolf did not spawn")
		return
	# Let it come: cast when it is within the cone's reach — bounded, because a wolf that is
	# left to circle bites (the first take waited for a 58px approach and the frame showed a
	# defeated player).
	var waited := 0
	# A RANGED exchange (the bolt's reach): the wolf is met at a distance, not in the bite.
	while wolf.global_position.distance_to(player.global_position) > 150.0 and waited < 120:
		await physics_frame
		waited += 1
	# Every rendered frame from the key press on — the gather, the release and the blade's
	# travel are a handful of frames each, and sampling every third one missed the gather.
	var best := -1
	var best_score := -1.0
	var frames: Array[Image] = []
	var rects: Array = []
	# SLOW MOTION for the capture only: reading a frame back stalls the renderer, physics runs
	# several steps to catch up, and a quarter-second bolt crossed the yard between two reads.
	Engine.time_scale = 0.25
	Input.action_press(&"skill_2")
	for i in 30:
		if i == 4:
			Input.action_release(&"skill_2")
		await process_frame
		var image := root.get_texture().get_image()
		frames.append(image)
		rects.append(_actor_rects(player, wolf, lin))
		var score := _technique_on_screen(image)
		if score > best_score:
			best_score = score
			best = i
	Engine.time_scale = 1.0
	for i in frames.size():
		frames[i].save_png("%s/golden_%02d.png" % [_out_dir, i])
	if best < 0 or frames[best].save_png("%s/golden_combat.png" % _out_dir) != OK:
		_fail("golden: could not write the golden frame")
		return
	_written.append("golden_combat.png")
	# the regions OF THE CHOSEN FRAME (the first take wrote them after the wolf had closed in)
	_write_golden_regions(rects[best])
	lin.queue_free()


## How much TECHNIQUE is on screen: playfield pixels within reach of the Phong hues the cast
## draws (`CastFeedback.PHONG` / `PHONG_LIGHT`), never the HUD corners. Picks the frame at the
## release, not a guess at a frame count. (A saturation test picked lit grass.)
func _technique_on_screen(image: Image) -> float:
	var size := image.get_size()
	var hits := 0
	for y in range(int(size.y * 0.2), int(size.y * 0.85), 2):
		for x in range(int(size.x * 0.2), int(size.x * 0.8), 2):
			var c := image.get_pixel(x, y)
			for hue in [CastFeedback.PHONG, CastFeedback.PHONG_LIGHT, CastFeedback.LOI,
					CastFeedback.LOI_LIGHT]:
				if absf(c.r - hue.r) + absf(c.g - hue.g) + absf(c.b - hue.b) < 0.16:
					hits += 1
					break
	return float(hits)


## The actors' screen rects in the CURRENT frame.
func _actor_rects(player: Node2D, wolf: Node2D, lin: Node2D) -> Dictionary:
	var canvas := root.get_canvas_transform()
	var actors := {}
	for entry in [["player", player, Vector2(32, 48)], ["second_actor", lin, Vector2(32, 48)],
			["enemy", wolf, Vector2(32, 32)]]:
		var node := entry[1] as Node2D
		var box: Vector2 = entry[2]
		var feet: Vector2 = canvas * node.global_position
		var scale := canvas.get_scale().x
		actors[entry[0]] = [feet.x - box.x * scale * 0.5, feet.y - box.y * scale,
			box.x * scale, box.y * scale]
	return actors


## Screen rects of what the benchmark compares: the HUD's visible surfaces and the actors of the
## chosen frame. Written beside the frame, so a score is about THIS frame's composition.
func _write_golden_regions(actors: Dictionary) -> void:
	var hud_rects: Array = []
	var hud := _map_node("GameplayHUD")
	if hud != null:
		var hud_root := hud.get_node_or_null("HudRoot") as Control
		if hud_root != null:
			for child in hud_root.get_children():
				var control := child as Control
				if control == null or not control.visible or control.size.x <= 0.0:
					continue
				var r := control.get_global_rect()
				hud_rects.append([control.name, r.position.x, r.position.y, r.size.x, r.size.y])
	var data := {"screen": [root.size.x, root.size.y], "actors": actors, "hud": hud_rects}
	var file := FileAccess.open("%s/golden_combat.json" % _out_dir, FileAccess.WRITE)
	if file == null:
		_fail("golden: could not write the regions")
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	_written.append("golden_combat.json")


# === Helpers ================================================================

func _player() -> Node2D:
	var host := _map_node("PlayerHost")
	if host == null:
		return null
	for child in host.get_children():
		if child is CharacterBody2D:
			return child as Node2D
	return null


func _current_map() -> Node:
	var router := root.get_node_or_null("SceneRouter")
	return router.call("get_current_scene") if router != null else null


func _map_node(path: String) -> Node:
	var map := _current_map()
	return map.get_node_or_null(path) if map != null else null


func _first_enemy() -> Node2D:
	var host := _map_node("CombatTargets")
	if host == null:
		return null
	for child in host.get_children():
		if child is CharacterBody2D:
			return child as Node2D
	return null


func _travel_through_first_exit(player: Node2D) -> bool:
	var router := root.get_node_or_null("SceneRouter")
	var before := String(router.call("get_current_key")) if router != null else ""
	var exits := _map_node("Exits")
	if exits == null or exits.get_child_count() == 0:
		return false
	var zone := exits.get_child(0) as Node2D
	player.global_position = zone.global_position
	for _i in 4:
		await physics_frame
	zone.emit_signal("body_entered", player)
	for _attempt in 8:
		await _press(&"interact")
		await process_frame
		if router != null and String(router.call("get_current_key")) != before:
			return true
	return false


## Press and release `action` through the real input pipeline (a key event when one is bound).
func _press(action: StringName) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var down := InputEventKey.new()
			down.physical_keycode = (e as InputEventKey).physical_keycode
			down.keycode = (e as InputEventKey).keycode
			down.pressed = true
			Input.parse_input_event(down)
			Input.flush_buffered_events()
			await process_frame
			var up := down.duplicate() as InputEventKey
			up.pressed = false
			Input.parse_input_event(up)
			Input.flush_buffered_events()
			return
	Input.action_press(action)
	await process_frame
	Input.action_release(action)


## Capture `count` cells, one every `every` rendered frames, around `focus.call()`.
func _strip(focus: Callable, count: int, every: int) -> Array[Image]:
	var frames: Array[Image] = []
	for _i in count:
		for _f in every:
			await process_frame
		frames.append(_cell(focus.call()))
	return frames


## One magnified cell of the CURRENT frame, centred on a world point.
func _cell(world: Vector2) -> Image:
	var image := root.get_texture().get_image()
	var screen := root.get_canvas_transform() * world
	var half := CELL_PX / 2
	var rect := Rect2i(int(screen.x) - half, int(screen.y) - half, CELL_PX, CELL_PX)
	rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var cell := Image.create(CELL_PX, CELL_PX, false, Image.FORMAT_RGBA8)
	if rect.size.x > 0 and rect.size.y > 0:
		cell.blit_rect(image.get_region(rect), Rect2i(Vector2i.ZERO, rect.size), Vector2i.ZERO)
	cell.resize(CELL_PX * MAGNIFY, CELL_PX * MAGNIFY, Image.INTERPOLATE_NEAREST)
	return cell


func _save_strip(strip_name: String, frames: Array[Image]) -> void:
	if frames.is_empty():
		_fail("%s: no frames" % strip_name)
		return
	var size := frames[0].get_size()
	var per_row := 8
	var rows := int(ceil(float(frames.size()) / float(per_row)))
	var sheet := Image.create(size.x * mini(per_row, frames.size()), size.y * rows, false,
		Image.FORMAT_RGBA8)
	for i in frames.size():
		var at := Vector2i((i % per_row) * size.x, int(float(i) / float(per_row)) * size.y)
		sheet.blit_rect(frames[i], Rect2i(Vector2i.ZERO, size), at)
	var file := "%s/%s.png" % [_out_dir, strip_name]
	if sheet.save_png(file) != OK:
		_fail("could not write %s" % file)
		return
	_written.append(file.get_file())


func _shot(shot_name: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	var file := "%s/%s.png" % [_out_dir, shot_name]
	if image == null or image.save_png(file) != OK:
		_fail("could not write %s" % file)
		return
	_written.append(file.get_file())


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await process_frame


func _await_menu() -> Node:
	for _i in MENU_WAIT_FRAMES:
		var ui := _main.get_node_or_null("UI")
		if ui != null:
			# The MENU specifically: other UI (a fade, a toast) may be the first child.
			for child in ui.get_children():
				if not child.is_queued_for_deletion() and child.has_signal("new_game_pressed"):
					return child
		await process_frame
	return null


func _fail(reason: String) -> void:
	push_error("[capture_motion] %s" % reason)
	_failed = true


func _finish() -> void:
	for action in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)
	print("[capture_motion] wrote %d file(s) to %s" % [_written.size(), _out_dir])
	for name in _written:
		print("[capture_motion]   %s" % name)
	if _main != null:
		_main.get_parent().remove_child(_main)
		_main.free()
	quit(1 if _failed else 0)
