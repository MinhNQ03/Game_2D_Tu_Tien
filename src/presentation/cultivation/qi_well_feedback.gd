extends Node2D
class_name QiWellFeedback
## QiWellFeedback — Aetheria presentation (the qi rising from a vein, as a body PERCEIVES it).
##
## A child of a `CultivationSite`. It draws the qi welling up from the site — thin wisps that
## rise, drift and thin out — at the strength the `CultivationRuntime` says the current body
## perceives it (`CultivationSite.perceived()`): nothing for a mortal walking past, the full flow
## for a Hậu Thiên cultivator within sensing range. The realm changes what the player SEES
## (`PROGRESSION_CULTIVATION_DESIGN.md` §4 perception), and this is where that is visible.
##
## A BROKEN vein's wisps surge and ebb with the same deterministic flow the runtime gathers by
## (`CultivationSiteData.flow_factor`), so what the eye sees and what the cultivator receives
## agree. Costs nothing while unperceived: `_process` runs only while there is something to draw.

const WISPS := 6
const RISE_PX := 26.0
const QI_COLOUR := Color(0.70, 0.96, 0.86)

var _site: CultivationSite = null
var _time: float = 0.0
var _drawn: float = 0.0


func _ready() -> void:
	_site = get_parent() as CultivationSite
	z_index = 1


func _process(delta: float) -> void:
	if _site == null:
		set_process(false)
		return
	var strength := _site.perceived()
	if strength <= 0.0 and _drawn <= 0.0:
		return
	_time += delta
	_drawn = strength
	queue_redraw()


func _draw() -> void:
	if _site == null or _drawn <= 0.0 or _site.site == null:
		return
	var flow := _site.site.flow_factor(_time)
	var spread := _site.site.radius_px * 0.45
	for i in WISPS:
		var u := fposmod(_time * (0.22 + 0.05 * flow) + float(i) / float(WISPS), 1.0)
		var x := (float(i) - float(WISPS - 1) * 0.5) / float(WISPS) * spread * 2.0
		x += sin(_time * 1.3 + float(i) * 1.7) * 2.0
		var y := -u * RISE_PX * (0.7 + 0.3 * flow)
		var colour := QI_COLOUR
		colour.a = _drawn * 0.7 * sin(u * PI) * clampf(flow, 0.3, 1.4)
		var p := Vector2(x, y).round()
		draw_rect(Rect2(p, Vector2(1, 2)), colour)
