extends WorldInteractable
class_name WorldNpc
## WorldNpc — Aetheria gameplay (a person standing in the world, Phase 17).
##
## The BODY of a character who already exists: an NPC is an ordinary `CharacterState` in the
## session's `CharacterRegistry` (built from a `CharacterTemplateData`, the way the player and
## every world-simulation actor are) — there is no NPC state class. This node says WHERE that
## character stands in a map and lets the player walk up and talk; it owns no persistent truth.
##
## `NpcRuntime` binds it on map arrival: it resolves `character_id` in the registry (realizing
## the character from `character_template` only if the session has not already) and hands the
## state here. Unbound, it is hidden and cannot be interacted with — fail closed.
##
## SOLID: a person has mass. A small body at the feet (WORLD layer) stops a walk; the reach is
## a distance well outside it, as for every interactable (D-063 A2).

const KIND := &"npc"
const VisualComponentScript := preload(
	"res://src/presentation/characters/character_visual_component.gd")

## Seconds a gesture runs when the profile authors a sheet for it.
const TALK_SECONDS := 0.9
const BODY_RADIUS := 5.0

## The character's `instance_id` in the `CharacterRegistry`.
@export var character_id: StringName = &""
## Who this is: realizes the character if the session has not, and names the look
## (`sprite_set_ref`).
@export var character_template: CharacterTemplateData = null
## Which way they stand when nobody is talking to them.
@export var rest_facing: Vector2 = Vector2.DOWN

var _state: CharacterState = null
var _visual: CharacterVisualComponent = null
var _talk_left: float = 0.0


func _init() -> void:
	prompt_key = &"UI_HUD_TALK_ACTION"
	reach_px = 30.0


func _ready() -> void:
	visible = false
	set_process(false)
	var body := StaticBody2D.new()
	body.name = "Body"
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BODY_RADIUS
	shape.shape = circle
	shape.position = Vector2(0, -BODY_RADIUS)
	body.add_child(shape)
	add_child(body)


## Give this body its character. False (loud, and the body stays hidden) when the state is
## missing, is someone else, or has no usable look.
func bind(state: CharacterState) -> bool:
	if state == null or state.instance_id != character_id:
		push_error("[npc] '%s' cannot be bound: no CharacterState '%s'" % [name, character_id])
		return false
	if character_template == null or character_template.sprite_set_ref == "":
		push_error("[npc] '%s' has no template look to draw" % name)
		return false
	var profile := load(character_template.sprite_set_ref) as CharacterVisualProfileData
	if profile == null or not profile.is_valid():
		push_error("[npc] '%s': '%s' is not a valid visual profile"
			% [name, character_template.sprite_set_ref])
		return false
	if _visual == null:
		_visual = VisualComponentScript.new() as CharacterVisualComponent
		_visual.name = "CharacterVisualComponent"
		add_child(_visual)
		if not _visual.setup(profile):
			_visual.queue_free()
			_visual = null
			return false
	_state = state
	_visual.update_facing(rest_facing, false)
	visible = true
	return true


func unbind() -> void:
	_state = null
	visible = false


func character() -> CharacterState:
	return _state


func visual() -> CharacterVisualComponent:
	return _visual


func interaction_kind() -> StringName:
	return KIND


func interaction_id() -> StringName:
	return character_id


func is_available() -> bool:
	return visible and _state != null


## The prompt names the person ("Talk to Kha Thản").
func prompt_args() -> Dictionary:
	return {"name": _state.name_key} if _state != null else {}


## Turn to whoever is at `world_point` (the player who just spoke to them).
func face_toward(world_point: Vector2) -> void:
	if _visual == null:
		return
	var toward := world_point - global_position
	if toward.length() > 0.5:
		_visual.update_facing(toward.normalized(), false)


## The talk gesture: the shared action layer's `talk` action, clocked here. A look that authors
## no talk sheet simply keeps its idle — presentation degrades, nothing else changes.
func greet() -> bool:
	return gesture(CharacterVisualComponent.ACTION_TALK)


## Play `action` — an action of the SHARED `CharacterVisualComponent` layer — as a one-shot
## gesture (Phase 18: a dialogue line names the gesture it is said with). Presentation only:
## false, and the idle kept, when the look authors no sheet for it.
func gesture(action: StringName) -> bool:
	if _visual == null or action == &"" or not _visual.play_action(action):
		return false
	_talk_left = TALK_SECONDS
	set_process(true)
	return true


func is_greeting() -> bool:
	return _talk_left > 0.0


func _process(delta: float) -> void:
	advance(delta)


## Public and delta-driven so a test can step the gesture exactly.
func advance(delta: float) -> void:
	if _talk_left <= 0.0:
		set_process(false)
		return
	_talk_left = maxf(0.0, _talk_left - delta)
	if _visual != null:
		_visual.drive_action(1.0 - _talk_left / TALK_SECONDS)
		if _talk_left == 0.0:
			_visual.end_action()
	if _talk_left == 0.0:
		set_process(false)
