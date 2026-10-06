extends Node2D
class_name StatusFeedback
## StatusFeedback — Aetheria presentation (a status a creature is under, Phase 15).
##
## Today one status: CHOÁNG (stun, `COMBAT_DESIGN.md` §3), drawn as violet sparks circling the
## head — the Lôi colour, because Lôi is what buys interruption — for exactly as long as the
## creature's AI reports it stunned. It reads `AIComponent.stun_remaining()` and decides nothing.

const LOI := Color(0.74, 0.62, 1.0)

var _time: float = 0.0


func _ready() -> void:
	z_index = 1


func _ai() -> AIComponent:
	var parent := get_parent()
	return parent.get_node_or_null("AIComponent") as AIComponent if parent != null else null


func _process(delta: float) -> void:
	var ai := _ai()
	if ai == null:
		return
	if ai.is_stunned() or _time > 0.0:
		_time = _time + delta if ai.is_stunned() else 0.0
		queue_redraw()


func _draw() -> void:
	var ai := _ai()
	if ai == null or not ai.is_stunned():
		return
	for i in 3:
		var angle := _time * 6.0 + float(i) * TAU / 3.0
		var at := Vector2(0, -26) + Vector2(cos(angle) * 8.0, sin(angle) * 3.0)
		var spark := LOI
		spark.a = 0.85
		draw_rect(Rect2(at.round() - Vector2(1, 0), Vector2(3, 1)), spark)
		draw_rect(Rect2(at.round() - Vector2(0, 1), Vector2(1, 3)), spark)
