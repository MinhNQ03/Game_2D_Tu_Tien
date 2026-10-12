extends RefCounted
class_name FigureDais
## FigureDais — Aetheria presentation (the ground a figure stands on, drawn once, used twice).
##
## The satchel's CharacterCard and the identity screen's stage both stand their figure on the
## same thing: a dais — ground a tone above the plate, with one lit rim on its far side —
## over a soft contact shadow, so the figure stands IN the well and not on it. One drawing,
## so the two stages can never drift apart (`docs/VISUAL_CRAFT_WORKFLOW.md` proof U1: the
## dais is part of what makes a figure a presence, not an icon).
##
## IT DRAWS NOTHING ON ITS OWN. Call `draw_on` from a CanvasItem's draw callback, with the
## figure's feet in the canvas's own space. It owns no node, no state and no clock; removing
## every call changes no outcome, only the floor.

## The dais under the figure, in the figure's own pixels (half-widths), and its contact shadow.
const DAIS_RADIUS := Vector2(15.0, 4.0)
const SHADOW_RADIUS := Vector2(13.0, 3.0)
const ELLIPSE_POINTS := 24


## Draw the dais and the contact shadow under `feet`, in the canvas's space. `unit` is the
## figure's integer pixel scale: the dais is sized in the figure's own pixels, so it fits any
## body drawn at any of the game's integer scales.
static func draw_on(canvas: CanvasItem, feet: Vector2, unit: float) -> void:
	var dais := _ellipse(feet, DAIS_RADIUS * unit)
	canvas.draw_colored_polygon(dais, UIPalette.FIGURE_DAIS)
	# The far rim is lit: the ellipse's second half runs along it.
	canvas.draw_polyline(dais.slice(ELLIPSE_POINTS / 2, ELLIPSE_POINTS + 1),
		UIPalette.FIGURE_DAIS_RIM, 1.0)
	draw_shadow_on(canvas, feet, unit)


## Only the contact shadow: for a figure that stands on the world's own ground rather than on
## a stage (the Chronicle's band card).
static func draw_shadow_on(canvas: CanvasItem, feet: Vector2, unit: float) -> void:
	canvas.draw_colored_polygon(_ellipse(feet, SHADOW_RADIUS * unit),
		UIPalette.FIGURE_CONTACT_SHADOW)


## A closed ellipse (first point repeated last), starting at its right and going by the near
## side first — so its second half is the far rim.
static func _ellipse(centre: Vector2, radius: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in ELLIPSE_POINTS + 1:
		var angle := TAU * float(index) / float(ELLIPSE_POINTS)
		points.append(centre + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points
