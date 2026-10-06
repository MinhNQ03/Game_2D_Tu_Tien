extends Node
class_name SkillRuntime
## SkillRuntime — Aetheria gameplay (techniques and their casts in a running session, Phase 15).
##
## Per-session node, last in the start order (it reads knowledge, cultivation, combat and the
## player). It owns, for one session:
##
##   * LEARNING — whenever knowledge is gained or a realm is reached, every technique whose
##     prerequisites are now met is learned through `TechniqueService` (the one writer of
##     `CharacterState.technique_ids`). A manual teaches knowledge; the knowledge teaches the
##     technique — Technique CONSUMES the Knowledge Core, never a copy (D-040).
##   * LINH KHÍ — a pool whose ceiling is the realm's `qi_capacity` (a mortal has none), refilling
##     slowly, and faster while seated in cultivation. Running dry is survivable: the cast is
##     refused with a reason, nothing else breaks.
##   * THE CAST — one `CastStateMachine` (PREPARE → CHANNEL → RELEASE → RECOVER). The caster is
##     rooted; a blow before the RELEASE breaks it and spends nothing; qi is spent and the
##     cooldown starts AT the release, when the force actually leaves.
##   * DELIVERY — a CONE resolves through `CombatService.resolve_hit` with the skill's own
##     geometry (no second hit formula); a BOLT is an analytic projectile ticked here that strikes
##     the first living target within reach of its path, damage from `DamageRules`.
##   * EFFECTS — Phong knocks the body back (collision-aware, `Enemy.apply_knockback`); Lôi stuns
##     (Choáng, `Enemy.apply_stun`). Gameplay, not presentation.
##
## Presentation (`CastFeedback` on the player, the dock in the HUD) READS this node's state and
## signals; nothing here draws.

signal technique_learned(technique_id: StringName)
signal cast_started(technique_id: StringName)
signal cast_released(technique_id: StringName, hits: int)
signal cast_interrupted(technique_id: StringName)
signal cast_refused(technique_id: StringName, reason_key: StringName)
signal bolt_struck(position: Vector2)
signal view_changed()

const CATALOG_PATH := "res://data/techniques/technique_catalog.tres"
const QI_REGEN_PER_SECOND := 1.5
const QI_REGEN_SEATED := 6.0
const PLAYER_ID := &"player"

const REFUSE_NOT_LEARNED := &"UI_SKILL_NOT_LEARNED"
const REFUSE_BUSY := &"UI_SKILL_BUSY"
const REFUSE_COOLDOWN := &"UI_SKILL_COOLDOWN"
const REFUSE_QI := &"UI_SKILL_NO_QI"
const REFUSE_SEATED := &"UI_SKILL_SEATED"

var _catalog: TechniqueCatalogData = null
var _service: TechniqueService = null
var _character: CharacterState = null
var _world: Node = null
var _knowledge: KnowledgeRuntime = null
var _cultivation: CultivationRuntime = null
var _combat: Node = null
var _input: Node = null
var _session_active: bool = false

var _qi: float = 0.0
var _cooldowns: Dictionary = {}  # technique id -> seconds left
var _fsm := CastStateMachine.new()
var _casting: TechniqueData = null
var _facing: Vector2 = Vector2.RIGHT
var _struck: bool = false
## Bolts in flight: { "id", "position", "direction", "travelled", "technique" }.
var _bolts: Array[Dictionary] = []
var _next_bolt: int = 0

var _player: Node2D = null
var _player_hurtbox: HurtboxComponent = null
var _view_signature := ""


func _ready() -> void:
	set_physics_process(false)


func start_session(character: CharacterState, world: Node, knowledge: KnowledgeRuntime,
		cultivation: CultivationRuntime, combat: Node) -> bool:
	if _session_active or character == null or world == null or knowledge == null \
			or cultivation == null or combat == null or not cultivation.is_session_active():
		push_error("[skill-rt] skill session NOT started: a dependency is missing")
		return false
	var catalog := load(CATALOG_PATH) as TechniqueCatalogData
	if catalog == null or not catalog.is_valid():
		push_error("[skill-rt] skill session NOT started: the technique catalog is invalid: %s"
			% (str(catalog.validation_errors()) if catalog != null else "missing"))
		return false
	_catalog = catalog
	_service = TechniqueService.new(knowledge.get_service(), cultivation.get_service())
	_character = character
	_world = world
	_knowledge = knowledge
	_cultivation = cultivation
	_combat = combat
	_input = get_node_or_null("/root/InputService")
	_qi = float(qi_capacity())
	_cooldowns = {}
	_bolts.clear()
	_fsm = CastStateMachine.new()
	_casting = null
	knowledge.knowledge_gained.connect(_on_knowledge_gained)
	cultivation.realm_advanced.connect(_on_realm_advanced)
	_session_active = true
	learn_available()
	set_physics_process(true)
	return true


func end_session() -> void:
	set_physics_process(false)
	if _knowledge != null and _knowledge.knowledge_gained.is_connected(_on_knowledge_gained):
		_knowledge.knowledge_gained.disconnect(_on_knowledge_gained)
	if _cultivation != null and _cultivation.realm_advanced.is_connected(_on_realm_advanced):
		_cultivation.realm_advanced.disconnect(_on_realm_advanced)
	_unbind_player()
	_catalog = null
	_service = null
	_character = null
	_world = null
	_knowledge = null
	_cultivation = null
	_combat = null
	_bolts.clear()
	_casting = null
	_session_active = false


func is_session_active() -> bool:
	return _session_active


# === Readouts ====================================================================

func catalog() -> TechniqueCatalogData:
	return _catalog


func knows(technique_id: StringName) -> bool:
	return _session_active and _character.technique_ids.has(technique_id)


func qi() -> float:
	return _qi


func qi_capacity() -> int:
	return _cultivation.get_service().qi_capacity(_character) if _cultivation != null else 0


func cooldown_left(technique_id: StringName) -> float:
	return float(_cooldowns.get(technique_id, 0.0))


func cast_state() -> CastStateMachine:
	return _fsm


func casting() -> TechniqueData:
	return _casting if _fsm.is_casting() else null


func cast_facing() -> Vector2:
	return _facing


func bolts() -> Array[Dictionary]:
	return _bolts


func build_view() -> SkillView:
	return SkillView.make(self)


# === Learning ======================================================================

## Learn every technique whose prerequisites are now met. Returns the ids learned.
func learn_available() -> Array[StringName]:
	var learned: Array[StringName] = []
	if not _session_active:
		return learned
	for technique in _catalog.entries:
		if _service.learn(_character, technique) == TechniqueService.LEARNED:
			learned.append(technique.id)
			technique_learned.emit(technique.id)
	if not learned.is_empty():
		view_changed.emit()
	return learned


func _on_knowledge_gained(_id: StringName, _source: StringName) -> void:
	learn_available()


func _on_realm_advanced(_realm: StringName, _layer: int, _changed: bool) -> void:
	_qi = minf(_qi, float(qi_capacity()))
	learn_available()


# === Casting ========================================================================

## Ask to cast `technique_id` (the skill key does exactly this). Returns &"" or the refusal's key.
func request_cast(technique_id: StringName) -> StringName:
	if not _session_active:
		return REFUSE_NOT_LEARNED
	_bind_player()
	var technique := _catalog.entry(technique_id)
	if technique == null or not knows(technique_id):
		return _refuse(technique_id, REFUSE_NOT_LEARNED)
	if _fsm.is_casting() or _player_swinging():
		return _refuse(technique_id, REFUSE_BUSY)
	if _cultivation.phase() != CultivationRuntime.Phase.IDLE:
		return _refuse(technique_id, REFUSE_SEATED)
	if cooldown_left(technique_id) > 0.0:
		return _refuse(technique_id, REFUSE_COOLDOWN)
	if _qi < float(technique.skill.qi_cost):
		return _refuse(technique_id, REFUSE_QI)
	if not _fsm.try_begin(technique.skill):
		return _refuse(technique_id, REFUSE_BUSY)
	_casting = technique
	_struck = false
	_facing = _player_facing()
	_set_rooted(true)
	cast_started.emit(technique_id)
	view_changed.emit()
	return &""


func _refuse(technique_id: StringName, reason: StringName) -> StringName:
	cast_refused.emit(technique_id, reason)
	return reason


func _physics_process(delta: float) -> void:
	tick(delta)


## Advance the session by `delta` (public for tests, like every runtime clock here).
func tick(delta: float) -> void:
	if not _session_active:
		return
	_bind_player()
	_regenerate(delta)
	for key: StringName in _cooldowns.keys():
		_cooldowns[key] = maxf(0.0, float(_cooldowns[key]) - delta)
	_handle_input()
	_advance_cast(delta)
	_tick_bolts(delta)
	_emit_view_if_changed()


func _regenerate(delta: float) -> void:
	var cap := float(qi_capacity())
	var seated := _cultivation.phase() != CultivationRuntime.Phase.IDLE
	_qi = minf(cap, _qi + (QI_REGEN_SEATED if seated else QI_REGEN_PER_SECOND) * delta)


func _handle_input() -> void:
	if _input == null:
		return
	for technique in _catalog.entries:
		if _input.call("is_gameplay_action_just_pressed", StringName("skill_%d" % technique.slot)):
			request_cast(technique.id)


func _advance_cast(delta: float) -> void:
	if not _fsm.is_casting():
		return
	if _struck and not _fsm.is_committed():
		_fsm.interrupt()
		var broken := _casting.id
		_casting = null
		_set_rooted(false)
		cast_interrupted.emit(broken)
		view_changed.emit()
		return
	if _fsm.advance(delta):
		_release()
	if not _fsm.is_casting():
		_casting = null
		_set_rooted(false)
		view_changed.emit()


func _release() -> void:
	var technique := _casting
	var skill := technique.skill
	_qi = maxf(0.0, _qi - float(skill.qi_cost))
	_cooldowns[technique.id] = skill.cooldown
	var hits := 0
	if skill.delivery == SkillData.Delivery.CONE:
		hits = _resolve_cone(skill)
	else:
		_spawn_bolt(technique)
	cast_released.emit(technique.id, hits)


func _resolve_cone(skill: SkillData) -> int:
	if _player == null or _combat == null:
		return 0
	var service: CombatService = _combat.call("get_service")
	var registry: CombatHurtboxRegistry = _combat.call("get_registry")
	if service == null or registry == null:
		return 0
	var origin := _player.global_position
	var results := service.resolve_hit(origin, _facing, int(_player.call("get_attack_power")),
		skill.as_attack(), registry.targets(PLAYER_ID))
	var hits := 0
	for result in results:
		var hurtbox := registry.get_hurtbox(result["target_id"])
		if hurtbox == null:
			continue
		var push := origin.direction_to(hurtbox.world_position())
		if push == Vector2.ZERO:
			push = _facing
		if hurtbox.apply_hit(int(result["damage"]), bool(result["is_critical"]), push) > 0:
			hits += 1
			_apply_effects(hurtbox, skill, push)
	return hits


func _apply_effects(hurtbox: HurtboxComponent, skill: SkillData, push: Vector2) -> void:
	var entity := hurtbox.get_parent()
	if entity == null:
		return
	if skill.knockback_px > 0.0 and entity.has_method("apply_knockback"):
		entity.call("apply_knockback", push * skill.knockback_px)
	if skill.stun_seconds > 0.0 and entity.has_method("apply_stun"):
		entity.call("apply_stun", skill.stun_seconds)


func _spawn_bolt(technique: TechniqueData) -> void:
	if _player == null:
		return
	_next_bolt += 1
	_bolts.append({
		"id": _next_bolt, "position": _player.global_position + Vector2(0, -16) + _facing * 10.0,
		"start": _player.global_position + Vector2(0, -16) + _facing * 10.0,
		"direction": _facing, "travelled": 0.0, "technique": technique,
	})


## Move every bolt; the first living target its path passes within reach of is struck.
func _tick_bolts(delta: float) -> void:
	if _bolts.is_empty() or _combat == null:
		return
	var registry: CombatHurtboxRegistry = _combat.call("get_registry")
	var finished: Array[Dictionary] = []
	for bolt in _bolts:
		var skill: SkillData = (bolt["technique"] as TechniqueData).skill
		var from: Vector2 = bolt["position"]
		var step := minf(skill.bolt_speed * delta, skill.range_px - float(bolt["travelled"]))
		var to := from + (bolt["direction"] as Vector2) * step
		var struck := _bolt_target(registry, from, to, skill.bolt_radius)
		if struck != null:
			var attack_power := int(_player.call("get_attack_power")) if _player != null else 0
			var power := DamageRules.compute_hit(attack_power, struck.defense(),
				skill.power_multiplier)
			var at := struck.world_position() + Vector2(0, -12)
			if struck.apply_hit(power, false, bolt["direction"]) > 0:
				_apply_effects(struck, skill, bolt["direction"])
			bolt_struck.emit(at)
			finished.append(bolt)
			continue
		bolt["position"] = to
		bolt["travelled"] = float(bolt["travelled"]) + step
		if float(bolt["travelled"]) >= skill.range_px:
			bolt_struck.emit(to)
			finished.append(bolt)
	for bolt in finished:
		_bolts.erase(bolt)


func _bolt_target(registry: CombatHurtboxRegistry, from: Vector2, to: Vector2,
		radius: float) -> HurtboxComponent:
	if registry == null:
		return null
	var best: HurtboxComponent = null
	var best_t := INF
	for target: Dictionary in registry.targets(PLAYER_ID):
		if bool(target["is_dead"]):
			continue
		# The body's centre, lifted to where a bolt at hand height passes it.
		var centre: Vector2 = (target["position"] as Vector2) + Vector2(0, -12)
		var closest := Geometry2D.get_closest_point_to_segment(centre, from, to)
		if closest.distance_to(centre) <= radius + float(target["radius"]):
			var t := from.distance_to(closest)
			if t < best_t:
				best_t = t
				best = registry.get_hurtbox(target["id"])
	return best


# === The player ====================================================================

func _bind_player() -> void:
	var player: Node = _world.call("get_player") if _world != null else null
	if player == _player:
		return
	_unbind_player()
	if player == null or not (player is Node2D):
		return
	_player = player as Node2D
	_player_hurtbox = _player.get_node_or_null("HurtboxComponent") as HurtboxComponent
	if _player_hurtbox != null:
		_player_hurtbox.damaged.connect(_on_player_damaged)
	var look := _player.get_node_or_null("CastFeedback")
	if look != null and look.has_method("bind_runtime"):
		look.call("bind_runtime", self)


func _unbind_player() -> void:
	if _player_hurtbox != null and is_instance_valid(_player_hurtbox) \
			and _player_hurtbox.damaged.is_connected(_on_player_damaged):
		_player_hurtbox.damaged.disconnect(_on_player_damaged)
	if _player != null and is_instance_valid(_player):
		if _player.has_method("set_cast_rooted"):
			_player.call("set_cast_rooted", false)
		var look := _player.get_node_or_null("CastFeedback")
		if look != null and look.has_method("bind_runtime"):
			look.call("bind_runtime", null)
	_player = null
	_player_hurtbox = null


func _on_player_damaged(amount: int, _critical: bool, _push: Vector2 = Vector2.ZERO) -> void:
	if amount > 0 and _fsm.is_casting():
		_struck = true


func _player_attack() -> AttackComponent:
	if _player == null or not is_instance_valid(_player):
		return null
	return _player.get_node_or_null("AttackComponent") as AttackComponent


func _player_facing() -> Vector2:
	var attack := _player_attack()
	if attack != null and attack.facing() != Vector2.ZERO:
		return attack.facing()
	return Vector2.RIGHT


func _player_swinging() -> bool:
	var attack := _player_attack()
	return attack != null and attack.state() != AttackStateMachine.State.READY


func _set_rooted(rooted: bool) -> void:
	if _player != null and is_instance_valid(_player) and _player.has_method("set_cast_rooted"):
		_player.call("set_cast_rooted", rooted)


func _emit_view_if_changed() -> void:
	var signature := "%d|%d|%d" % [int(_qi), _character.technique_ids.size(), _fsm.state()]
	for key: StringName in _cooldowns:
		signature += "|%d" % int(ceil(float(_cooldowns[key]) * 4.0))
	if signature != _view_signature:
		_view_signature = signature
		view_changed.emit()


func to_dict() -> Dictionary:
	var cooldowns := {}
	for key: StringName in _cooldowns:
		cooldowns[String(key)] = float(_cooldowns[key])
	return {"qi": _qi, "cooldowns": cooldowns}
