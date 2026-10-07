extends TestCase
## Phase 15 — skills and techniques. Exit (`ROADMAP.md`): add a skill via data; cooldown / cost /
## gating tested; a knowledge-gated technique is withheld and then granted when the knowledge is
## acquired. Plus: CAST is one action with four phases; the cone uses the swing's hit test; a
## bolt strikes the first target on its path; Phong knocks back, Lôi stuns; a blow before the
## release breaks the cast and spends nothing.

const CATALOG := "res://data/techniques/technique_catalog.tres"
const KnowledgeScript := preload("res://src/gameplay/world/knowledge_runtime.gd")
const CultivationScript := preload("res://src/gameplay/world/cultivation_runtime.gd")
const SkillScript := preload("res://src/gameplay/world/skill_runtime.gd")
const HurtboxScript := preload("res://src/gameplay/components/hurtbox_component.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")


class StubWorld extends Node:
	var player: Node = null

	func get_active_map() -> Node:
		return null

	func get_player() -> Node:
		return player


class StubPlayer extends Node2D:
	func get_attack_power() -> int:
		return 12

	func take_damage(amount: int) -> int:
		return amount


class StubTarget extends Node2D:
	var hp := 200
	var knocked := Vector2.ZERO
	var stunned := 0.0

	func take_damage(amount: int) -> int:
		hp -= amount
		return amount

	func get_defense() -> int:
		return 2

	func is_dead() -> bool:
		return hp <= 0

	func apply_knockback(displacement: Vector2) -> void:
		knocked = displacement

	func apply_stun(seconds: float) -> void:
		stunned = seconds


class StubCombat extends Node:
	var service: CombatService
	var registry := CombatHurtboxRegistry.new()

	func get_service() -> CombatService:
		return service

	func get_registry() -> CombatHurtboxRegistry:
		return registry


func test_the_catalog_is_valid_canon_and_one_key_each() -> void:
	var catalog: TechniqueCatalogData = load(CATALOG)
	assert_true(catalog.is_valid(), "catalog: %s" % str(catalog.validation_errors()))
	var phong := catalog.entry(&"tech_thanh_phong_chuong")
	var loi := catalog.entry(&"tech_loi_chi")
	assert_eq([phong.element, loi.element], [&"elem_phong", &"elem_loi"], "canon elements")
	assert_eq([phong.skill.delivery, loi.skill.delivery],
		[SkillData.Delivery.CONE, SkillData.Delivery.BOLT], "two different deliveries")
	var bad: SkillData = phong.skill.duplicate()
	bad.element = &"elem_kim"
	assert_false(bad.is_valid(), "Kim (metal) is not one of Aetheria's four elements")


func test_the_cast_is_one_action_with_four_phases() -> void:
	var skill: SkillData = (load(CATALOG) as TechniqueCatalogData).entry(&"tech_loi_chi").skill
	var fsm := CastStateMachine.new()
	assert_true(fsm.try_begin(skill), "begins")
	assert_eq(fsm.state(), CastStateMachine.State.PREPARE, "PREPARE")
	assert_false(fsm.try_begin(skill), "one cast at a time")
	assert_false(fsm.advance(skill.prepare_seconds + 0.01), "no release yet")
	assert_eq(fsm.state(), CastStateMachine.State.CHANNEL, "CHANNEL")
	assert_true(fsm.advance(skill.channel_seconds), "the release begins exactly once")
	assert_eq(fsm.state(), CastStateMachine.State.RELEASE, "RELEASE")
	assert_false(fsm.interrupt(), "a released cast cannot be broken")
	fsm.advance(skill.release_seconds + skill.recover_seconds + 0.01)
	assert_eq(fsm.state(), CastStateMachine.State.READY, "and back to READY")
	fsm.try_begin(skill)
	assert_true(fsm.interrupt(), "a cast before its release can be broken")


func _session() -> Array:
	var world := StubWorld.new()
	var player := StubPlayer.new()
	var hurtbox: HurtboxComponent = HurtboxScript.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.entity_id = &"player"
	player.add_child(hurtbox)
	world.player = player
	world.add_child(player)
	add_to_tree(world)
	var combat := StubCombat.new()
	var rng: RngService = RngServiceScript.new(9)
	combat.service = CombatService.new(rng.stream(RngService.STREAM_COMBAT))
	add_to_tree(combat)
	var knowledge: KnowledgeRuntime = KnowledgeScript.new()
	add_to_tree(knowledge)
	knowledge.start_session()
	var state := CharacterState.new()
	state.instance_id = &"p"
	state.realm_id = &"realm_pham"
	var cultivation: CultivationRuntime = CultivationScript.new()
	add_to_tree(cultivation)
	cultivation.start_session(state, knowledge, world)
	var skills: SkillRuntime = SkillScript.new()
	add_to_tree(skills)
	assert_true(skills.start_session(state, world, knowledge, cultivation, combat), "session")
	return [world, combat, knowledge, cultivation, skills, state, player]


func _target(parts: Array, at: Vector2, id: StringName) -> StubTarget:
	var target := StubTarget.new()
	target.position = at
	var hurtbox: HurtboxComponent = HurtboxScript.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.entity_id = id
	hurtbox.radius = 8.0
	target.add_child(hurtbox)
	(parts[0] as Node).add_child(target)
	(parts[1] as StubCombat).registry.register(hurtbox)
	return target


func _end(parts: Array) -> void:
	(parts[4] as SkillRuntime).end_session()
	(parts[3] as CultivationRuntime).end_session()
	(parts[2] as KnowledgeRuntime).end_session()
	for i in [4, 3, 2, 1, 0]:
		free_node(parts[i])


func _run(skills: SkillRuntime, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		skills.tick(1.0 / 60.0)
		t += 1.0 / 60.0


## The knowledge gate: withheld without the manual's knowledge, and without the realm; learned
## the moment both are true — and only `TechniqueService` writes `technique_ids`.
func test_a_technique_is_withheld_then_granted_by_knowledge_and_realm() -> void:
	var parts := _session()
	var knowledge: KnowledgeRuntime = parts[2]
	var skills: SkillRuntime = parts[4]
	var state: CharacterState = parts[5]
	assert_false(skills.knows(&"tech_thanh_phong_chuong"), "a new run knows no technique")
	knowledge.grant(&"know_thanh_phong_chuong", &"t")
	assert_false(skills.knows(&"tech_thanh_phong_chuong"),
		"knowledge alone is not enough: a mortal body cannot hold it")
	assert_eq(skills.request_cast(&"tech_thanh_phong_chuong"), SkillRuntime.REFUSE_NOT_LEARNED,
		"and an unlearned technique is refused")
	state.set_cultivation(&"realm_hau_thien", 1, 0)
	(parts[3] as CultivationRuntime).realm_advanced.emit(&"realm_hau_thien", 1, true)
	assert_true(skills.knows(&"tech_thanh_phong_chuong"), "Hậu Thiên + the knowledge: learned")
	assert_eq(state.technique_ids, [&"tech_thanh_phong_chuong"] as Array[StringName],
		"recorded on the character")
	_end(parts)


func test_cost_cooldown_and_the_cone_release() -> void:
	var parts := _session()
	var skills: SkillRuntime = parts[4]
	var state: CharacterState = parts[5]
	state.set_cultivation(&"realm_hau_thien", 1, 0)
	(parts[2] as KnowledgeRuntime).grant(&"know_thanh_phong_chuong", &"t")
	skills.learn_available()
	_run(skills, 30.0)  # fill the pool
	var near := _target(parts, Vector2(30, 0), &"wolf_a")
	var behind := _target(parts, Vector2(-30, 0), &"wolf_b")
	var before := skills.qi()
	assert_eq(skills.request_cast(&"tech_thanh_phong_chuong"), &"", "the cast begins")
	assert_eq(skills.qi(), before, "no qi is spent before the release")
	_run(skills, 0.4)
	assert_true(near.hp < 200, "the cone struck the target in front")
	assert_eq(behind.hp, 200, "and not the one behind (the swing's own arc test)")
	assert_true(near.knocked.x > 30.0, "Phong shoved it away along the blow (%s)" % near.knocked)
	assert_true(skills.qi() < before - 9.0, "the cost was spent at the release")
	assert_eq(skills.request_cast(&"tech_thanh_phong_chuong"), SkillRuntime.REFUSE_BUSY,
		"still recovering from the cast: busy")
	_run(skills, 0.3)
	assert_eq(skills.request_cast(&"tech_thanh_phong_chuong"), SkillRuntime.REFUSE_COOLDOWN,
		"recast during the cooldown is refused")
	_run(skills, 3.0)
	assert_eq(skills.cooldown_left(&"tech_thanh_phong_chuong"), 0.0, "the cooldown ends")
	_end(parts)


func test_running_dry_is_refused_and_survivable() -> void:
	var parts := _session()
	var skills: SkillRuntime = parts[4]
	(parts[5] as CharacterState).set_cultivation(&"realm_hau_thien", 1, 0)
	(parts[2] as KnowledgeRuntime).grant(&"know_loi_chi", &"t")
	skills.learn_available()
	assert_eq(skills.qi(), 0.0, "learned as a mortal-turned-cultivator, the pool starts empty")
	assert_eq(skills.request_cast(&"tech_loi_chi"), SkillRuntime.REFUSE_QI, "not enough linh khí")
	assert_false(skills.cast_state().is_casting(), "and nothing else happens")
	_end(parts)


func test_the_bolt_strikes_the_first_target_on_its_path_and_stuns() -> void:
	var parts := _session()
	var skills: SkillRuntime = parts[4]
	(parts[5] as CharacterState).set_cultivation(&"realm_hau_thien", 9, 0)
	(parts[2] as KnowledgeRuntime).grant(&"know_loi_chi", &"t")
	skills.learn_available()
	_run(skills, 30.0)
	var first := _target(parts, Vector2(80, 0), &"wolf_a")
	var second := _target(parts, Vector2(150, 0), &"wolf_b")
	assert_eq(skills.request_cast(&"tech_loi_chi"), &"", "the bolt is cast")
	_run(skills, 1.0)
	assert_true(first.hp < 200, "the first target on the path is struck")
	assert_eq(second.hp, 200, "and the bolt stops there")
	assert_eq(first.stunned, 1.0, "Lôi stuns (Choáng)")
	assert_true(skills.bolts().is_empty(), "the bolt is spent")
	_end(parts)


## TRAVEL must read (D-062 §25): a bolt crosses a yard in a quarter second, so when it lands its
## whole path stays as an AFTERIMAGE for a moment, then dissipates and the feedback goes idle.
func test_a_landed_bolt_leaves_a_brief_afterimage_then_dissipates() -> void:
	var parts := _session()
	var skills: SkillRuntime = parts[4]
	(parts[5] as CharacterState).set_cultivation(&"realm_hau_thien", 9, 0)
	(parts[2] as KnowledgeRuntime).grant(&"know_loi_chi", &"t")
	skills.learn_available()
	_run(skills, 30.0)
	_target(parts, Vector2(120, 0), &"wolf_a")
	var feedback := CastFeedback.new()
	add_to_tree(feedback)
	feedback.bind_runtime(skills)
	assert_eq(skills.request_cast(&"tech_loi_chi"), &"", "the bolt is cast")
	var saw_flight := false
	var saw_afterimage := false
	for _i in 120:
		skills.tick(1.0 / 60.0)
		feedback.advance(1.0 / 60.0)
		saw_flight = saw_flight or not skills.bolts().is_empty()
		if skills.bolts().is_empty() and saw_flight and feedback.afterimage_count() > 0:
			saw_afterimage = true
			break
	assert_true(saw_flight, "the bolt was in flight")
	assert_true(saw_afterimage, "and on landing its path stays as an afterimage")
	for _i in 30:
		feedback.advance(1.0 / 60.0)
	assert_eq(feedback.afterimage_count(), 0, "the afterimage dissipates")
	feedback.bind_runtime(null)
	free_node(feedback)
	_end(parts)


func test_a_blow_before_the_release_breaks_the_cast_and_spends_nothing() -> void:
	var parts := _session()
	var skills: SkillRuntime = parts[4]
	(parts[5] as CharacterState).set_cultivation(&"realm_hau_thien", 1, 0)
	(parts[2] as KnowledgeRuntime).grant(&"know_loi_chi", &"t")
	skills.learn_available()
	_run(skills, 30.0)
	var before := skills.qi()
	var broken: Array = []
	skills.cast_interrupted.connect(func(id: StringName) -> void: broken.append(id))
	skills.request_cast(&"tech_loi_chi")
	_run(skills, 0.2)
	(parts[6].get_node("HurtboxComponent") as HurtboxComponent).apply_hit(4, false)
	skills.tick(1.0 / 60.0)
	assert_eq(broken, [&"tech_loi_chi"], "the cast was broken")
	assert_true(skills.qi() >= before, "and no qi was spent")
	assert_eq(skills.cooldown_left(&"tech_loi_chi"), 0.0, "nor any cooldown started")
	_end(parts)


## STRUCTURAL: only CharacterState's boundary (called by TechniqueService) writes technique_ids.
func test_only_the_technique_service_learns() -> void:
	var offenders: Array[String] = []
	_walk("res://src", offenders)
	assert_eq(offenders, [] as Array[String],
		"only TechniqueService may call add_technique(): %s" % str(offenders))


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			_walk(full, out)
		elif entry.ends_with(".gd") and not full.ends_with("technique_service.gd") \
				and not full.ends_with("character_state.gd"):
			var text := FileAccess.get_file_as_string(full)
			if ".add_technique(" in text or "technique_ids.append" in text:
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
