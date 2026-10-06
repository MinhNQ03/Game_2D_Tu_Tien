extends Node2D
class_name EquipmentFeedback
## EquipmentFeedback — Aetheria presentation (a wielded weapon, drawn on the body, Phase 14).
##
## Layered on the drawn body THROUGH ITS ANCHORS, never at a guessed offset: sheathed, the Kiếm
## crosses the back from the `core`, behind the body when the body faces the viewer and in front
## of it when the back is turned; in a swing it is IN the striking hand (`palm` anchor of the
## frame being drawn), pointing where the strike goes. The second consumer of the anchors after
## the strike's air (M-14.2). Presentation only: which attack the weapon swings with is gameplay
## (`EquipmentRuntime` → `AttackComponent.swap_attack`).

const STEEL := Color(0.86, 0.89, 0.93)
const STEEL_DARK := Color(0.52, 0.57, 0.64)
const HILT := Color(0.43, 0.27, 0.16)
const GUARD := Color(0.78, 0.66, 0.38)
const BLADE_PX := 13.0

var _family: StringName = &""


func _ready() -> void:
	set_process(false)


## Told by the player what it now wields (empty = nothing).
func show_weapon(weapon_family: StringName) -> void:
	_family = weapon_family
	set_process(_family != &"")
	queue_redraw()


func wielded() -> StringName:
	return _family


func _process(_delta: float) -> void:
	queue_redraw()


func _visual() -> CharacterVisualComponent:
	var parent := get_parent()
	return parent.get_node_or_null("CharacterVisualComponent") as CharacterVisualComponent \
		if parent != null else null


## Where the blade is right now: [hilt end, tip], in this node's space (for tests and `_draw`).
func blade_segment() -> PackedVector2Array:
	var visual := _visual()
	if _family == &"" or visual == null or not visual.has_anchor(&"core"):
		return PackedVector2Array()
	var facing := _facing_vector(visual.get_shown_direction())
	if visual.current_action() == CharacterVisualComponent.ACTION_ATTACK:
		var palm := visual.position + visual.anchor_point(CharacterVisualProfileData.POINT_PALM)
		return PackedVector2Array([(palm - facing * 3.0).round(),
			(palm + facing * BLADE_PX).round()])
	# Sheathed: diagonally across the back, hilt over the right shoulder.
	var core := visual.position + visual.anchor_point(CharacterVisualProfileData.POINT_CORE)
	return PackedVector2Array([(core + Vector2(6, -12)).round(), (core + Vector2(-6, 4)).round()])


func _draw() -> void:
	var visual := _visual()
	var segment := blade_segment()
	if segment.size() < 2 or visual == null:
		return
	var swinging := visual.current_action() == CharacterVisualComponent.ACTION_ATTACK
	var facing_away := visual.get_shown_direction() == CharacterVisualProfileData.Direction.UP
	# Layer: a sheathed blade is seen only where the back is; a swung blade is in front unless
	# the strike goes away from the viewer.
	var layer := 1 if (swinging and not facing_away) or (not swinging and facing_away) else 0
	if z_index != layer:
		z_index = layer
	if swinging:
		draw_line(segment[0], segment[1], STEEL, 1.0)
		draw_line(segment[0] + Vector2(0, 1), segment[1] + Vector2(0, 1), STEEL_DARK, 1.0)
		draw_rect(Rect2(segment[0] - Vector2(1, 1), Vector2(3, 3)), GUARD)
	else:
		draw_line(segment[0], segment[1], STEEL_DARK, 2.0)
		draw_rect(Rect2(segment[0] - Vector2(1, 1), Vector2(2, 3)), HILT)
		draw_rect(Rect2(segment[0] + Vector2(-2, 1), Vector2(4, 1)), GUARD)


static func _facing_vector(direction: int) -> Vector2:
	match direction:
		CharacterVisualProfileData.Direction.UP:
			return Vector2.UP
		CharacterVisualProfileData.Direction.LEFT:
			return Vector2.LEFT
		CharacterVisualProfileData.Direction.RIGHT:
			return Vector2.RIGHT
		_:
			return Vector2.DOWN
