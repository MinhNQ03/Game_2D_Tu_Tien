extends Node2D
class_name PickupFeedback
## PickupFeedback — Aetheria presentation (how an item lying in the world looks, Phase 13).
##
## A child of a `WorldItem`: the item's own icon bobbing gently over a small contact shadow, with
## a periodic glint, so a pickup reads as something to take rather than floor detail. Colour is a
## presentation decision, so it lives here and not on the gameplay node (L-036).

const SHADOW := Color(0.05, 0.06, 0.09, 0.35)
const GLINT := Color(1, 1, 1, 0.9)

var _item: WorldItem = null
var _time: float = 0.0


func _ready() -> void:
	_item = get_parent() as WorldItem
	_time = fposmod(global_position.x * 0.37, 2.0)  # deterministic phase per placement


func _process(delta: float) -> void:
	if _item == null or not _item.visible:
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	if _item == null or _item.item == null:
		return
	var tex: Texture2D = _item.item.world_icon if _item.item.world_icon != null \
		else _item.item.icon
	if tex == null:
		return
	draw_rect(Rect2(Vector2(-5, -1), Vector2(10, 2)), SHADOW)
	var bob := roundf(sin(_time * 2.2) * 1.5)
	# Centred on its own size, resting 2px above the shadow (whole pixels: never a half-pixel
	# seam under nearest filtering).
	var top_left := Vector2(-floorf(tex.get_width() / 2.0), -tex.get_height() - 2 + bob)
	draw_texture(tex, top_left)
	if fposmod(_time, 2.4) < 0.18:
		draw_rect(Rect2(top_left + Vector2(5, 3), Vector2(1, 1)), GLINT)
