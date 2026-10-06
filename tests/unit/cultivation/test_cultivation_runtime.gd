extends TestCase
## `CultivationRuntime` — tọa thiền and đột phá as a running state machine (Phase 12), driven
## with exact deltas through its public `tick()` / `request_cultivate()` against a stub world:
## a map holding real `CultivationSite`s and a player with a real hurtbox.

const KnowledgeScript := preload("res://src/gameplay/world/knowledge_runtime.gd")
const CultivationScript := preload("res://src/gameplay/world/cultivation_runtime.gd")
const SiteScript := preload("res://src/gameplay/cultivation/cultivation_site.gd")
const HurtboxScript := preload("res://src/gameplay/components/hurtbox_component.gd")
const SPRING := "res://data/cultivation/site_lac_ha_spring.tres"
const BROKEN := "res://data/cultivation/site_broken_vein.tres"


class StubMap extends Node2D:
	func get_cultivation_sites() -> Array[Node]:
		var out: Array[Node] = []
		for child in get_children():
			if child is CultivationSite:
				out.append(child)
		return out


class StubWorld extends Node:
	var map: Node = null
	var player: Node = null

	func get_active_map() -> Node:
		return map

	func get_player() -> Node:
		return player


class StubPlayer extends Node2D:
	func take_damage(amount: int) -> int:
		return amount


var _world: StubWorld
var _knowledge: KnowledgeRuntime
var _cultivation: CultivationRuntime
var _state: CharacterState
var _player: StubPlayer


func _setup(site_path: String) -> CultivationSite:
	_world = StubWorld.new()
	var map := StubMap.new()
	var site: CultivationSite = SiteScript.new()
	site.site = load(site_path)
	site.position = Vector2(100, 100)
	map.add_child(site)
	_player = StubPlayer.new()
	_player.position = Vector2(100, 110)
	var hurtbox: HurtboxComponent = HurtboxScript.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.entity_id = &"player"
	_player.add_child(hurtbox)
	map.add_child(_player)
	_world.map = map
	_world.player = _player
	_world.add_child(map)
	add_to_tree(_world)
	_knowledge = KnowledgeScript.new()
	add_to_tree(_knowledge)
	assert_true(_knowledge.start_session(), "knowledge session")
	_state = CharacterState.new()
	_state.instance_id = &"inst_p"
	_state.realm_id = &"realm_pham"
	_cultivation = CultivationScript.new()
	add_to_tree(_cultivation)
	assert_true(_cultivation.start_session(_state, _knowledge, _world), "cultivation session")
	return site


func _teardown() -> void:
	_cultivation.end_session()
	_knowledge.end_session()
	free_node(_cultivation)
	free_node(_knowledge)
	free_node(_world)


func _run(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		_cultivation.tick(1.0 / 60.0)
		t += 1.0 / 60.0


func test_each_refusal_says_why() -> void:
	_setup(SPRING)
	var refusals: Array = []
	_cultivation.cultivation_refused.connect(func(key: StringName) -> void: refusals.append(key))
	_player.position = Vector2(400, 400)
	_cultivation.request_cultivate()
	_player.position = Vector2(100, 110)
	_cultivation.request_cultivate()
	assert_eq(refusals, [CultivationRuntime.REFUSE_NO_SITE, CultivationRuntime.REFUSE_NO_METHOD],
		"away from a vein: no site; at the spring without the method: no method")
	assert_eq(_cultivation.phase(), CultivationRuntime.Phase.IDLE, "and nobody sat down")
	_teardown()


func test_a_mortal_cannot_survive_the_broken_vein() -> void:
	_setup(BROKEN)
	_knowledge.grant(&"know_dan_khi_quyet", &"t")
	var refusals: Array = []
	_cultivation.cultivation_refused.connect(func(key: StringName) -> void: refusals.append(key))
	_cultivation.request_cultivate()
	assert_eq(refusals, [CultivationRuntime.REFUSE_TOO_STRONG], "the realm gate refuses")
	_state.set_cultivation(&"realm_hau_thien", 1, 0)
	_cultivation.request_cultivate()
	assert_eq(_cultivation.phase(), CultivationRuntime.Phase.SETTLING, "Hậu Thiên 1 may sit")
	_run(1.0)
	assert_true(_knowledge.get_service().knows(&"know_broken_vein_flow"),
		"a body that can sense it learns what the broken vein is doing")
	_teardown()


func test_sit_gather_break_through_and_keep_sitting() -> void:
	_setup(SPRING)
	_knowledge.grant(&"know_dan_khi_quyet", &"t")
	var advanced: Array = []
	_cultivation.realm_advanced.connect(func(r: StringName, l: int, c: bool) -> void:
		advanced.append([r, l, c]))
	_cultivation.request_cultivate()
	assert_eq(_cultivation.phase(), CultivationRuntime.Phase.SETTLING, "settling into the seat")
	_run(CultivationRuntime.SETTLE_SECONDS * 0.5)
	assert_eq(_state.cultivation_progress, 0, "no qi is drawn while still settling")
	_run(CultivationRuntime.SETTLE_SECONDS)
	assert_eq(_cultivation.phase(), CultivationRuntime.Phase.GATHERING, "then gathering")
	_run(5.0)
	var gained := _state.cultivation_progress
	# 2.0/s at the spring x 0.6 mortal efficiency = 1.2/s
	assert_true(gained >= 5 and gained <= 7, "about 6 tu vi in 5s (got %d)" % gained)
	_run(40.0)
	assert_eq(_state.cultivation_progress, 30, "the step fills and waits")
	assert_true(_cultivation.build_view().can_breakthrough, "the view says it is ready")
	_cultivation.request_cultivate()
	assert_eq(_cultivation.phase(), CultivationRuntime.Phase.BREAKTHROUGH, "breaking through")
	_run(CultivationRuntime.BREAKTHROUGH_RELEASE_AT - 0.1)
	assert_eq(_state.realm_id, &"realm_pham", "nothing changes before the release")
	_run(0.2)
	assert_eq(advanced, [[&"realm_hau_thien", 1, true]], "the realm changes AT the release")
	_run(CultivationRuntime.BREAKTHROUGH_SECONDS)
	assert_eq(_cultivation.phase(), CultivationRuntime.Phase.GATHERING, "and keeps sitting")
	_teardown()


func test_a_blow_interrupts_and_an_unreleased_breakthrough_changes_nothing() -> void:
	_setup(SPRING)
	_knowledge.grant(&"know_dan_khi_quyet", &"t")
	_state.cultivation_progress = 0
	var ended: Array = []
	_cultivation.meditation_ended.connect(func(r: StringName) -> void: ended.append(r))
	_cultivation.request_cultivate()
	_run(0.5)
	_state.set_cultivation(&"realm_pham", 0, 30)
	_cultivation.request_cultivate()
	_run(0.5)
	(_player.get_node("HurtboxComponent") as HurtboxComponent).apply_hit(3, false, Vector2.LEFT)
	_cultivation.tick(1.0 / 60.0)
	assert_eq(ended, [CultivationRuntime.END_STRUCK], "struck mid-breakthrough: interrupted")
	assert_eq([_state.realm_id, _state.cultivation_progress], [&"realm_pham", 30],
		"nothing changed and no tu vi was lost")
	_teardown()


func test_perception_follows_the_realm() -> void:
	var site := _setup(SPRING)
	_cultivation.tick(0.016)
	assert_eq(site.perceived(), 0.0, "a mortal walking past perceives nothing")
	_state.set_cultivation(&"realm_hau_thien", 1, 0)
	_cultivation.tick(0.016)
	assert_eq(site.perceived(), 1.0, "Hậu Thiên senses the qi within its radius")
	_player.position = Vector2(100, 100 + 96 + 64)
	_cultivation.tick(0.016)
	assert_eq(site.perceived(), 0.0, "and not far beyond it")
	_teardown()
