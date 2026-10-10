extends TestCase
## Phase-16 Pet / Linh Thú E2E case (D-019 isolation: run by `run_pet_flow.gd` in its OWN
## process, against the real autoloads).
##
## It boots the real application and drives it the way a player does — every ACTION is a real
## key event or a held semantic action; only placement (standing near something) is setup, as
## in the world flow. The loop it proves:
##
##   no pet: the summon key answers with a reason  →  WALK up to the stray  →  the prompt names
##   the verb  →  interact befriends it (owned, active, out, the stray is gone)  →  it FOLLOWS
##   a walking player without teleporting  →  the summon key sends it away and calls it back
##   (never two bodies)  →  it crosses a map change with the player  →  it fights a wolf
##   through real combat, the kill pays the player once and the pet its share once  →  return
##   to menu frees everything, PetRuntime first.

const MainScript := preload("res://src/bootstrap/main.gd")

const MAIN_SCENE_PATH := "res://main.tscn"
const INTERACT := &"interact"
const OPEN_MENU := &"open_menu"
const ATTACK := &"attack"
const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const PET_SUMMON := &"pet_summon"
const HOUND := &"pet_hoang_khuyen"


func test_real_pet_flow() -> void:
	var gs: Node = scene_tree.root.get_node_or_null("GameState")
	var router: Node = scene_tree.root.get_node_or_null("SceneRouter")
	var input: Node = scene_tree.root.get_node_or_null("InputService")
	var loc: Node = scene_tree.root.get_node_or_null("Localization")
	if gs == null or router == null or input == null or loc == null:
		assert_true(false, "core autoloads missing")
		return

	var main: Node = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	scene_tree.root.add_child(main)
	await scene_tree.process_frame
	var menu: Node = main.get_node("UI").get_child(0)
	menu.emit_signal("new_game_pressed")
	await scene_tree.process_frame
	assert_eq(router.call("get_current_key"), "map_hub", "New Game loads the hub")

	var pets := main.get_node_or_null("Systems/PetRuntime") as PetRuntime
	var combat := main.get_node_or_null("Systems/CombatRuntime") as CombatRuntime
	var world: Node = main.get_node_or_null("Systems/WorldRuntime")
	assert_not_null(pets, "PetRuntime exists under Main/Systems")
	if pets == null or combat == null or world == null:
		_teardown(main)
		return
	assert_true(pets.is_session_active(), "its session is live in a running game")
	assert_eq(_count_root("PetRuntime"), 0, "PetRuntime is NOT an autoload (budget stays five)")
	var player := world.call("get_player") as Node2D
	var map: Node = router.call("get_current_scene")
	var hud := _find_hud(map)
	assert_not_null(hud, "the hub owns a GameplayHUD")

	# --- 1. no pet: the key answers, nothing spawns --------------------------------
	assert_false(hud.is_pet_prompt_visible(), "with no pet the HUD shows no pet prompt")
	await _press_through_physics(PET_SUMMON)
	assert_eq(hud.notice_text(), String(loc.call("t", "UI_PET_NONE")),
		"the summon key with no pet is ANSWERED with a reason, not ignored")
	assert_eq(hud.notice_kind(), GameplayHUD.NOTICE_ANSWER, "as an answer to the key")
	assert_eq(_count_pets(), 0, "and no body appeared")

	# --- 2. walk up to the stray: the prompt names the verb ------------------------
	var stray := map.get_node_or_null("Interactables/StrayHound") as PetEncounter
	assert_not_null(stray, "the hub has the stray hound")
	if stray == null:
		_teardown(main)
		return
	assert_true(stray.is_available(), "it is offered")
	player.global_position = stray.global_position + Vector2(-70, 0)
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	assert_null(map.call("active_interactable"), "70 px away it is out of reach")
	var before_walk := player.global_position
	Input.action_press(MOVE_RIGHT)
	await _wait_until(func() -> bool: return map.call("active_interactable") == stray, 180)
	Input.action_release(MOVE_RIGHT)
	await scene_tree.physics_frame
	assert_true(player.global_position.x > before_walk.x + 20.0,
		"the player WALKED into reach with a real move key (%.1f px)"
			% (player.global_position.x - before_walk.x))
	assert_eq(map.call("active_interactable"), stray, "in reach, the stray is the interactable")
	var befriend := String(loc.call("t", "UI_HUD_PET_BEFRIEND"))
	assert_true(_label_texts(hud).has(befriend),
		"and the interact prompt names the verb (%s)" % befriend)

	# --- 3. interact befriends it ---------------------------------------------------
	for _attempt in 6:
		await _fire_action(INTERACT)
		if pets.get_service().store().owns(HOUND):
			break
	var store := pets.get_service().store()
	assert_true(store.owns(HOUND), "a REAL interact key befriended the stray")
	assert_eq(store.active_id(), HOUND, "it is the active pet")
	assert_eq(store.owned_count(), 1, "owned exactly once (repeated presses never duplicate)")
	assert_true(pets.is_out(), "and it is out beside the player")
	assert_eq(_count_pets(), 1, "exactly one pet body exists")
	assert_false(stray.is_available(), "the stray is no longer offered")
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	assert_null(map.call("active_interactable"), "so the interact prompt has nothing to name")
	var name := String(loc.call("t", "PET_HOANG_KHUYEN_NAME"))
	assert_true(name in hud.notice_text(),
		"the HUD says who joined ('%s')" % hud.notice_text())
	assert_true(hud.is_pet_prompt_visible(), "and the pet prompt appeared")
	assert_eq(hud.pet_prompt_text(), String(loc.call("t", "UI_HUD_PET_DISMISS")),
		"offering what the key does now: send it away")
	var pet := pets.active_pet()
	assert_true(pet.visual() != null, "the pet is drawn from its CharacterVisualProfileData")

	# --- 4. it follows a walking player, never teleporting --------------------------
	var speed := pet.get_move_speed()
	var physics_step := 1.0 / float(Engine.physics_ticks_per_second)
	var worst := 0.0
	var previous := pet.global_position
	var player_start := player.global_position
	Input.action_press(MOVE_LEFT)
	for _i in 120:
		await scene_tree.physics_frame
		worst = maxf(worst, pet.global_position.distance_to(previous))
		previous = pet.global_position
	Input.action_release(MOVE_LEFT)
	for _i in 90:
		await scene_tree.physics_frame
		worst = maxf(worst, pet.global_position.distance_to(previous))
		previous = pet.global_position
	# It comes to rest BESIDE its owner, not on them (audit AUD-04: it used to stop 1 px away,
	# depending on where in the brain's 0.2 s cadence the owner happened to stop — so several
	# walk-and-stop cycles are measured, not one). Neither the walk in nor its idle amble may
	# carry it inside its standing distance; the allowance is two physics steps of overshoot.
	var closest := INF
	for move: StringName in [MOVE_RIGHT, MOVE_LEFT, MOVE_RIGHT, MOVE_LEFT, MOVE_RIGHT, MOVE_LEFT]:
		Input.action_press(move)
		for _i in 55:
			await scene_tree.physics_frame
		Input.action_release(move)
		for _i in 75:
			await scene_tree.physics_frame
			closest = minf(closest, pet.global_position.distance_to(player.global_position))
	var ally := pet.data().ai_profile
	var standoff := ally.home_arrival_radius - 2.0 * speed * physics_step
	assert_true(closest >= standoff,
		"the companion never stood on the player (closest %.1f px, standing distance %.1f)"
			% [closest, standoff])
	var walked := player_start.distance_to(player.global_position)
	var gap := pet.global_position.distance_to(player.global_position)
	assert_true(walked > 150.0, "the player walked a real distance (%.1f px)" % walked)
	assert_true(worst <= speed * physics_step * 1.5 + 0.5,
		"no physics frame moved the pet beyond its speed (worst %.2f px, speed step %.2f)"
			% [worst, speed * physics_step])
	assert_true(gap <= pet.data().ai_profile.follow_radius + 14.0,
		"and it ended beside the player (%.1f px away after a %.1f px walk)" % [gap, walked])

	# --- 5. the key sends it away and calls it back; never two bodies ----------------
	await _press_through_physics(PET_SUMMON)
	await scene_tree.process_frame
	assert_false(pets.is_out(), "the summon key dismissed it")
	assert_eq(_count_pets(), 0, "its body is freed")
	assert_eq(combat.ally_count(), 0, "and combat ticks no ally")
	assert_eq(hud.pet_prompt_text(), String(loc.call("t", "UI_HUD_PET_SUMMON")),
		"the prompt now offers to call it")
	await _press_through_physics(PET_SUMMON)
	await scene_tree.process_frame
	assert_true(pets.is_out(), "the key called it back")
	assert_eq(_count_pets(), 1, "one body, not two")
	assert_eq(combat.ally_count(), 1, "one ally")

	# --- 6. it crosses a map change with the player ----------------------------------
	var hub_body := pets.active_pet()
	await _interact_to_transition(player, "map_hub")
	assert_eq(router.call("get_current_key"), "map_field", "the player travelled to the field")
	await scene_tree.process_frame
	assert_false(is_instance_valid(hub_body), "the hub's pet body was freed with the hub")
	assert_true(pets.is_out(), "and the pet is out again in the field")
	assert_eq(_count_pets(), 1, "exactly one body after the map change")
	map = router.call("get_current_scene")
	pet = pets.active_pet()
	assert_true(map.is_ancestor_of(pet), "its body lives in the NEW map")
	assert_true(pet.global_position.distance_to(player.global_position) < 60.0,
		"beside the player where they arrived")
	hud = _find_hud(map)
	assert_true(hud.is_pet_prompt_visible(), "the new map's HUD shows the pet prompt at once")

	# --- 7. it fights: real combat, rewards once --------------------------------------
	var wolf := combat.enemies()[0]
	var character: CharacterState = world.call("get_player_character")
	var player_xp_before := character.xp
	var defeats: Array = []
	var snapshot := {}
	var on_defeat := func(reward_id: StringName, xp: int) -> void:
		defeats.append([reward_id, xp])
		if defeats.size() == 1:
			snapshot["player_xp"] = character.xp
			snapshot["pet_xp"] = store.xp_of(HOUND)
	combat.enemy_defeated.connect(on_defeat)
	player.global_position = wolf.global_position + Vector2(64, 0)
	var pet_attack := pet.get_node("AttackComponent") as AttackComponent
	# First the pet alone: it must reach the wolf and land a real, resolved hit.
	await _wait_until(func() -> bool: return pet_attack.damage_dealt() > 0 or wolf.is_dead(),
		900)
	assert_true(pet_attack.damage_dealt() > 0,
		"the pet engaged the wolf and its bite landed through CombatService (%d damage, %d swings)"
			% [pet_attack.damage_dealt(), pet_attack.swings_resolved()])
	assert_eq(pet.ai().target(), wolf if not wolf.is_dead() else null,
		"its target is the living hostile")
	# Then the player joins with the real attack key, as a player would.
	var frames := 0
	while defeats.is_empty() and frames < 1500 and not bool(player.call("is_dead")):
		var toward := wolf.global_position.x - player.global_position.x
		await _hold(MOVE_LEFT if toward < 0.0 else MOVE_RIGHT, 2)
		await _fire_action(ATTACK)
		for _i in 20:
			await scene_tree.physics_frame
		frames += 26
	combat.enemy_defeated.disconnect(on_defeat)
	assert_true(defeats.size() >= 1, "the wolf was defeated in a shared fight")
	if not defeats.is_empty():
		var reward := int(defeats[0][1])
		var ids := {}
		for row in defeats:
			assert_false(ids.has(row[0]), "no reward id was announced twice (%s)" % row[0])
			ids[row[0]] = true
		assert_eq(int(snapshot["player_xp"]) - player_xp_before, reward,
			"the kill paid the PLAYER its XP exactly once (%d), through the progression owner"
				% reward)
		var share := int(floor(float(reward) * pets.active_pet().data().xp_share_percent / 100.0)) \
			if pets.is_out() else int(snapshot["pet_xp"])
		assert_eq(int(snapshot["pet_xp"]), share,
			"and the PET its authored share exactly once (%d)" % share)
		assert_true(int(snapshot["pet_xp"]) > 0, "which is a real amount")
	assert_eq(store.owned_count(), 1, "the fight never duplicated the pet")

	# --- 8. return to menu frees everything -------------------------------------------
	for a in [MOVE_LEFT, MOVE_RIGHT, ATTACK]:
		Input.action_release(a)
	# Esc ASKS (D-068); the confirm key leaves.
	await _fire_action(OPEN_MENU)
	await scene_tree.process_frame
	assert_eq(gs.get_phase(), gs.Phase.RUNNING, "one Esc only asks")
	await _fire_action(INTERACT)
	await scene_tree.process_frame
	await scene_tree.process_frame
	assert_eq(gs.get_phase(), gs.Phase.MENU, "confirming returned to the menu")
	assert_false(pets.is_session_active(), "the pet session ended")
	assert_eq(_count_pets(), 0, "no pet body survives the session")
	var trace: Array = main.call("get_last_teardown_order")
	assert_true(trace.find(&"PetRuntime") >= 0
			and trace.find(&"PetRuntime") < trace.find(&"SkillRuntime"),
		"PetRuntime was torn down before everything it reads (%s)" % str(trace))

	_teardown(main)
	await scene_tree.process_frame
	assert_false(is_instance_valid(main), "Main freed after cleanup (no orphan)")


# --- helpers -----------------------------------------------------------------

func _find_hud(node: Node) -> GameplayHUD:
	if node == null:
		return null
	if node is GameplayHUD:
		return node as GameplayHUD
	for child in node.get_children():
		var found: GameplayHUD = _find_hud(child)
		if found != null:
			return found
	return null


func _label_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	_collect_label_texts(node, out)
	return out


func _collect_label_texts(node: Node, out: Array[String]) -> void:
	var label := node as Label
	if label != null and label.is_visible_in_tree():
		out.append(label.text)
	for child in node.get_children():
		_collect_label_texts(child, out)


func _count_pets() -> int:
	return _count_pets_in(scene_tree.root)


func _count_pets_in(node: Node) -> int:
	var count := 1 if node is Pet and not node.is_queued_for_deletion() else 0
	for child in node.get_children():
		count += _count_pets_in(child)
	return count


func _count_root(node_name: String) -> int:
	var count := 0
	for child in scene_tree.root.get_children():
		if child.name == node_name:
			count += 1
	return count


func _wait_until(predicate: Callable, frames: int) -> void:
	for _i in frames:
		if predicate.call():
			return
		await scene_tree.physics_frame


func _hold(action: StringName, frames: int) -> void:
	Input.action_press(action)
	for _i in frames:
		await scene_tree.physics_frame
	Input.action_release(action)
	await scene_tree.physics_frame


## Hold `action` across PHYSICS frames, then release: `PetRuntime` reads its intent in the
## physics tick, where a press and release between two ticks would never be seen.
func _press_through_physics(action: StringName) -> void:
	Input.action_press(action)
	await scene_tree.physics_frame
	await scene_tree.physics_frame
	Input.action_release(action)
	await scene_tree.physics_frame


func _fire_action(action: StringName) -> void:
	var press := _key_event_for(action, true)
	if press == null:
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


func _key_event_for(action: StringName, pressed: bool) -> InputEventKey:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := InputEventKey.new()
			k.physical_keycode = (e as InputEventKey).physical_keycode
			k.keycode = (e as InputEventKey).keycode
			k.pressed = pressed
			return k
	return null


func _interact_to_transition(player: Node2D, from_key: String) -> void:
	var router := scene_tree.root.get_node_or_null("SceneRouter")
	var active: Node = router.call("get_current_scene")
	var exits := active.get_node_or_null("Exits")
	var zone: Node2D = null
	if exits != null:
		for child in exits.get_children():
			if child is MapExitZone:
				zone = child
				break
	assert_not_null(zone, "the active map has an exit zone")
	if zone == null:
		return
	player.global_position = zone.global_position
	zone.emit_signal("body_entered", player)
	await scene_tree.process_frame
	for _attempt in 8:
		await _fire_action(INTERACT)
		await scene_tree.process_frame
		if str(router.call("get_current_key")) != from_key:
			break
	await scene_tree.process_frame


func _teardown(main: Node) -> void:
	for a in [MOVE_LEFT, MOVE_RIGHT, INTERACT, OPEN_MENU, ATTACK, PET_SUMMON]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	if main == null or not is_instance_valid(main):
		return
	if main.get_parent() != null:
		main.get_parent().remove_child(main)
	main.queue_free()
