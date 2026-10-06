extends Node
class_name CultivationRuntime
## CultivationRuntime — Aetheria gameplay (tọa thiền and đột phá in a running session, Phase 12).
##
## A per-session node under `Main/Systems`, like `ProgressionRuntime`: no autoload, no manager.
## It turns the semantic `cultivate` intent into the cultivation STATE MACHINE and asks
## `CultivationService` — the only owner of the rules — for every decision:
##
##   IDLE ──cultivate, at a site──▶ SETTLING ──0.4s──▶ GATHERING ──cultivate, step full──▶
##   BREAKTHROUGH ──(release)──▶ GATHERING          any state ──move/attack/struck──▶ IDLE
##
## * You cultivate AT A SITE (qi is not ambient), and only if the Knowledge Core says you know a
##   method, and only a site your body can survive (`CultivationSiteData`). Each refusal is
##   announced with a reason the HUD can say — a key that does nothing is a broken key.
## * GATHERING draws the site's flow (surging and ebbing at a BROKEN vein) times the body's
##   efficiency into tu vi through `CultivationService.gather()`. A full step waits.
## * BREAKTHROUGH is DELIBERATE: pressed again with a full step. It takes `BREAKTHROUGH_SECONDS`
##   and the realm changes at `BREAKTHROUGH_RELEASE_AT` — the moment the presentation releases,
##   so the flash, the wind and the new realm are one event (M-5.3).
## * Moving, swinging or being struck ends a sitting at once (a breakthrough interrupted before
##   its release changes nothing; tu vi is never lost to an interruption).
##
## It PERCEIVES for the player: each frame it tells every site of the active map how strongly
## the current body senses its qi (Hậu Thiên: "sense qi nearby"; a mortal senses only the vein
## it is sitting in, faintly). Presentation reads that; nothing else does.
##
## It owns no presentation. `CultivationFeedback` on the player binds to it and READS its state
## (phase, phase time, site, rate), the way `AttackFeedback` reads an `AttackComponent`; the HUD
## gets a `CultivationView` through `WorldRuntime`.

signal meditation_started(site_id: StringName)
signal meditation_ended(reason: StringName)
signal breakthrough_started()
signal realm_advanced(realm_id: StringName, layer: int, changed_realm: bool)
## A `cultivate` press that could not start or continue; `reason_key` is a localization key.
signal cultivation_refused(reason_key: StringName)
## The visible cultivation state changed (progress, phase, reach): rebuild the HUD view.
signal view_changed()

const LADDER_PATH := "res://data/progression/realm_ladder.tres"
const CULTIVATE_ACTION := &"cultivate"

## Descending into the seat. No qi is drawn until the body is settled.
const SETTLE_SECONDS := 0.4
## The whole breakthrough, and the instant inside it when the realm changes.
const BREAKTHROUGH_SECONDS := 2.6
const BREAKTHROUGH_RELEASE_AT := 1.7

## How far past its perception radius a body still faintly senses qi (a fade, not a wall).
const PERCEPTION_FADE_PX := 32.0
## What a MORTAL with a method senses of the vein it is sitting in: a little, never the flow.
const MORTAL_SITTING_PERCEPTION := 0.35

## Knowledge the broken vein teaches the first time a body that can sense it sits there.
const BROKEN_VEIN_OBSERVATION := &"know_broken_vein_flow"

enum Phase { IDLE, SETTLING, GATHERING, BREAKTHROUGH }

const END_STOOD := &"stood"
const END_MOVED := &"moved"
const END_ATTACKED := &"attacked"
const END_STRUCK := &"struck"
const END_LEFT_SITE := &"left_site"
const END_SESSION := &"session"

const REFUSE_NO_SITE := &"UI_CULTIVATE_NO_SITE"
const REFUSE_NO_METHOD := &"UI_CULTIVATE_NO_METHOD"
const REFUSE_TOO_STRONG := &"UI_CULTIVATE_SITE_TOO_STRONG"
const REFUSE_MISSING_KNOWLEDGE := &"UI_CULTIVATE_MISSING_KNOWLEDGE"
const REFUSE_CEILING := &"UI_CULTIVATE_CEILING"

var _service: CultivationService = null
var _character: CharacterState = null
var _knowledge: KnowledgeRuntime = null
var _world: Node = null
var _input: Node = null
var _session_active: bool = false

var _phase: Phase = Phase.IDLE
var _phase_time: float = 0.0
var _sit_time: float = 0.0
var _site: CultivationSite = null
var _carry: float = 0.0
var _released: bool = false
var _struck: bool = false

var _player: Node2D = null
var _player_attack: AttackComponent = null
var _player_hurtbox: HurtboxComponent = null

var _sites_map_id: int = 0
var _sites: Array[CultivationSite] = []
var _view_signature: String = ""


func _ready() -> void:
	set_physics_process(false)


## Begin a session for the player's `character`. Needs the session's knowledge runtime (the
## method and breakthrough prerequisites are READ through it) and the world runtime (where the
## player and the active map are). Fails closed and loud (L-025).
func start_session(character: CharacterState, knowledge: KnowledgeRuntime, world: Node) -> bool:
	if _session_active:
		push_error("[cultivation-rt] start_session called while a session is already active")
		return false
	if character == null:
		return _fail_start("no player CharacterState was supplied")
	if knowledge == null or not knowledge.is_session_active():
		return _fail_start("no active KnowledgeRuntime: prerequisites could never be read")
	if world == null or not is_instance_valid(world):
		return _fail_start("no WorldRuntime: there is no map to find a site in")
	if not ResourceLoader.exists(LADDER_PATH):
		return _fail_start("the realm ladder is missing: %s" % LADDER_PATH)
	var ladder := load(LADDER_PATH) as RealmLadderData
	if ladder == null or not ladder.is_valid():
		return _fail_start("the realm ladder is invalid: %s"
			% (str(ladder.validation_errors()) if ladder != null else "did not load"))
	var service := CultivationService.new(ladder, knowledge.get_service())
	if not service.is_ready():
		return _fail_start("the CultivationService refused the ladder")
	if service.realm_of(character) == null:
		return _fail_start("the player's realm '%s' is not on the ladder" % character.realm_id)
	_service = service
	_character = character
	_knowledge = knowledge
	_world = world
	_input = get_node_or_null("/root/InputService")
	_session_active = true
	_reset_sitting()
	set_physics_process(true)
	view_changed.emit()
	return true


func _fail_start(reason: String) -> bool:
	push_error("[cultivation-rt] cultivation session NOT started: %s" % reason)
	return false


func end_session() -> void:
	if _phase != Phase.IDLE:
		_end_sitting(END_SESSION)
	_unbind_player()
	set_physics_process(false)
	_service = null
	_character = null
	_knowledge = null
	_world = null
	_sites.clear()
	_sites_map_id = 0
	_session_active = false


func is_session_active() -> bool:
	return _session_active


func get_service() -> CultivationService:
	return _service


# === Readouts (presentation, HUD, tests) =======================================

func phase() -> Phase:
	return _phase


func phase_time() -> float:
	return _phase_time


## The site being sat at, or null.
func active_site() -> CultivationSite:
	return _site if _site != null and is_instance_valid(_site) else null


## Tu vi per second being drawn right now (0 unless GATHERING).
func gather_rate() -> float:
	if _phase != Phase.GATHERING or active_site() == null:
		return 0.0
	return (_site.site.qi_per_second * _site.site.flow_factor(_sit_time)
		* _service.gather_efficiency(_character))


## How strongly the current body perceives qi at `site` (0 = not at all).
func perceived_at(site: CultivationSite) -> float:
	return site.perceived() if site != null and is_instance_valid(site) else 0.0


## The nearest site of the active map within reach of the player, or null.
func site_in_reach() -> CultivationSite:
	if _player == null or not is_instance_valid(_player):
		return null
	for site in _sites_of_active_map():
		if site.reaches(_player.global_position):
			return site
	return null


func build_view() -> CultivationView:
	var view := CultivationView.make_empty()
	if not _session_active:
		return view
	var realm := _service.realm_of(_character)
	view.available = true
	view.realm_name_key = realm.name_key if realm != null else &""
	view.layer = _character.realm_layer
	view.progress = _character.cultivation_progress
	view.step_cost = _service.step_cost(_character)
	view.fraction = _service.step_fraction(_character)
	var blocker := _service.breakthrough_blocker(_character)
	view.can_breakthrough = blocker == CultivationResult.REASON_NONE
	view.blocked_by_knowledge = blocker == CultivationResult.REASON_MISSING_KNOWLEDGE
	view.at_ceiling = _service.next_step(_character).is_empty()
	match _phase:
		Phase.IDLE:
			view.activity = CultivationView.Activity.IDLE
		Phase.BREAKTHROUGH:
			view.activity = CultivationView.Activity.BREAKING_THROUGH
		_:
			view.activity = CultivationView.Activity.MEDITATING
	view.site_in_reach = site_in_reach() != null
	return view


# === The clock =================================================================

func _physics_process(delta: float) -> void:
	tick(delta)


## Advance the session by `delta` seconds. PUBLIC and delta-driven so tests step it with exact
## deltas (L-016), like `AttackComponent.advance`.
func tick(delta: float) -> void:
	if not _session_active:
		return
	_bind_player()
	_update_perception()
	_handle_input()
	_advance(delta)
	_emit_view_if_changed()


## Ask to cultivate, exactly as the semantic action does (the E2E drives the real key; unit
## tests call this). Context-dependent, the way the HUD prompt says: sit down at a site; break
## through on a full step; otherwise stand up.
func request_cultivate() -> void:
	if not _session_active:
		return
	_bind_player()
	match _phase:
		Phase.IDLE:
			_try_sit()
		Phase.GATHERING:
			var blocker := _service.breakthrough_blocker(_character)
			if blocker == CultivationResult.REASON_NONE:
				_begin_breakthrough()
			elif blocker == CultivationResult.REASON_MISSING_KNOWLEDGE:
				cultivation_refused.emit(REFUSE_MISSING_KNOWLEDGE)
				_end_sitting(END_STOOD)
			elif blocker == CultivationResult.REASON_CEILING:
				cultivation_refused.emit(REFUSE_CEILING)
				_end_sitting(END_STOOD)
			else:
				_end_sitting(END_STOOD)
		_:
			pass  # settling or breaking through: the press is absorbed, not queued


## The player was struck (connected to its hurtbox).
func _on_player_damaged(amount: int, _is_critical: bool, _push: Vector2 = Vector2.ZERO) -> void:
	if amount > 0 and _phase != Phase.IDLE:
		_struck = true


func _handle_input() -> void:
	if _input == null:
		return
	if _input.call("is_gameplay_action_just_pressed", CULTIVATE_ACTION):
		request_cultivate()


func _advance(delta: float) -> void:
	if _phase == Phase.IDLE:
		return
	var reason := _interruption()
	if reason != &"":
		_end_sitting(reason)
		return
	_phase_time += delta
	match _phase:
		Phase.SETTLING:
			if _phase_time >= SETTLE_SECONDS:
				_set_phase(Phase.GATHERING)
		Phase.GATHERING:
			_sit_time += delta
			_gather(delta)
		Phase.BREAKTHROUGH:
			if not _released and _phase_time >= BREAKTHROUGH_RELEASE_AT:
				_release()
			if _phase_time >= BREAKTHROUGH_SECONDS:
				_set_phase(Phase.GATHERING)


## Why the sitting must end now, or &"" — checked every tick while seated.
func _interruption() -> StringName:
	if _struck:
		return END_STRUCK
	if active_site() == null or _player == null or not is_instance_valid(_player):
		return END_LEFT_SITE
	if not _site.reaches(_player.global_position):
		return END_LEFT_SITE
	if _input != null:
		var intent: Vector2 = _input.call("get_move_vector")
		if intent != Vector2.ZERO:
			return END_MOVED
	if _player_attack != null and _player_attack.state() != AttackStateMachine.State.READY:
		return END_ATTACKED
	return &""


func _try_sit() -> void:
	var site := site_in_reach()
	if site == null:
		cultivation_refused.emit(REFUSE_NO_SITE)
		return
	var data := site.site
	if _knowledge == null or not _knowledge.get_service().knows_all(data.required_knowledge):
		cultivation_refused.emit(REFUSE_NO_METHOD)
		return
	if not _service.meets(_character, data.required_realm, data.required_layer):
		cultivation_refused.emit(REFUSE_TOO_STRONG)
		return
	_site = site
	_carry = 0.0
	_sit_time = 0.0
	_struck = false
	_set_phase(Phase.SETTLING)
	meditation_started.emit(data.id)


func _gather(delta: float) -> void:
	# The first sitting at a broken vein by a body that can SENSE it teaches what the flow is
	# doing — a non-gating payoff of perception (§7: knowledge must also reward when it does not
	# gate). The service is idempotent, so this is safe every tick and announces once.
	if _site.site.stability == CultivationSiteData.Stability.BROKEN \
			and _service.perception_px(_character) > 0.0:
		_knowledge.grant(BROKEN_VEIN_OBSERVATION, _site.site_id())
	_carry += gather_rate() * delta
	var whole := int(_carry)
	if whole <= 0:
		return
	_carry -= float(whole)
	var result := _service.gather(_character, whole)
	if not result.accepted:
		_carry = 0.0  # a full step wastes the surplus: sitting longer is not a shortcut


func _begin_breakthrough() -> void:
	_released = false
	_set_phase(Phase.BREAKTHROUGH)
	breakthrough_started.emit()


## The release: the realm changes HERE, at the presentation's peak.
func _release() -> void:
	_released = true
	var result := _service.breakthrough(_character)
	if not result.accepted:
		# Prerequisites changed under the attempt (they cannot today; fail visibly if they do).
		push_error("[cultivation-rt] breakthrough refused at release: %s" % result.describe())
		cultivation_refused.emit(REFUSE_MISSING_KNOWLEDGE)
		return
	realm_advanced.emit(result.realm_after, result.layer_after, result.changed_realm())


func _set_phase(next: Phase) -> void:
	_phase = next
	_phase_time = 0.0


func _end_sitting(reason: StringName) -> void:
	_reset_sitting()
	meditation_ended.emit(reason)


func _reset_sitting() -> void:
	_phase = Phase.IDLE
	_phase_time = 0.0
	_sit_time = 0.0
	_site = null
	_carry = 0.0
	_released = false
	_struck = false


# === Perception =================================================================

## Tell every site of the active map how strongly this body senses it. Cheap: a map has a
## handful of sites, and the value only changes as the player moves or advances.
func _update_perception() -> void:
	var radius := _service.perception_px(_character)
	for site in _sites_of_active_map():
		var strength := 0.0
		if _player != null and is_instance_valid(_player) and radius > 0.0:
			var d := site.global_position.distance_to(_player.global_position)
			strength = clampf(1.0 - (d - radius) / PERCEPTION_FADE_PX, 0.0, 1.0)
		if site == active_site() and _phase != Phase.IDLE:
			strength = maxf(strength, MORTAL_SITTING_PERCEPTION)
		site.set_perceived(strength)


func _sites_of_active_map() -> Array[CultivationSite]:
	var map: Node = _world.call("get_active_map") if _world != null else null
	if map == null or not is_instance_valid(map):
		_sites.clear()
		_sites_map_id = 0
		return _sites
	if map.get_instance_id() != _sites_map_id:
		_sites.clear()
		_sites_map_id = map.get_instance_id()
		if map.has_method("get_cultivation_sites"):
			for node: Node in map.call("get_cultivation_sites"):
				if node is CultivationSite:
					_sites.append(node as CultivationSite)
	return _sites


# === The player ==================================================================

func _bind_player() -> void:
	var player: Node = _world.call("get_player") if _world != null else null
	if player == _player and (player == null or is_instance_valid(player)):
		return
	_unbind_player()
	if player == null or not (player is Node2D):
		return
	_player = player as Node2D
	_player_attack = _player.get_node_or_null("AttackComponent") as AttackComponent
	_player_hurtbox = _player.get_node_or_null("HurtboxComponent") as HurtboxComponent
	if _player_hurtbox != null:
		_player_hurtbox.damaged.connect(_on_player_damaged)
	var feedback := _player.get_node_or_null("CultivationFeedback")
	if feedback != null and feedback.has_method("bind_runtime"):
		feedback.call("bind_runtime", self)


func _unbind_player() -> void:
	if _player_hurtbox != null and is_instance_valid(_player_hurtbox) \
			and _player_hurtbox.damaged.is_connected(_on_player_damaged):
		_player_hurtbox.damaged.disconnect(_on_player_damaged)
	if _player != null and is_instance_valid(_player):
		var feedback := _player.get_node_or_null("CultivationFeedback")
		if feedback != null and feedback.has_method("bind_runtime"):
			feedback.call("bind_runtime", null)
	_player = null
	_player_attack = null
	_player_hurtbox = null


func _emit_view_if_changed() -> void:
	var signature := "%s|%d|%d|%d|%s" % [_character.realm_id, _character.realm_layer,
		_character.cultivation_progress, _phase, site_in_reach() != null]
	if signature != _view_signature:
		_view_signature = signature
		view_changed.emit()
