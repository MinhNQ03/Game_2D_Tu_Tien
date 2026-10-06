extends Node2D
class_name CultivationSite
## CultivationSite — Aetheria gameplay (a place in a map where qi wells up, Phase 12).
##
## The map-side half of a `CultivationSiteData`: WHERE the vein surfaces. Authored in a map scene
## under `CultivationSites`, found by `MapBase.get_cultivation_sites()`, and read by the
## `CultivationRuntime`, which decides everything about sitting here. Reach is a DISTANCE test
## from the site's origin, not an `Area2D`: it works headless (L-016) and costs one subtraction.
##
## PERCEPTION. Whether a body can SEE the qi here depends on its realm (Hậu Thiên: "sense qi
## nearby"), so the runtime pushes a perceived strength in [0, 1] each frame it changes, and the
## qi-well presentation beside the landmark reads it. The site decides nothing about it.

@export var site: CultivationSiteData = null

var _perceived: float = 0.0


func _ready() -> void:
	if site == null or not site.is_valid():
		push_error("[site] '%s' has no valid CultivationSiteData: %s" % [name,
			str(site.validation_errors()) if site != null else "null"])


func site_id() -> StringName:
	return site.id if site != null else &""


## True when `world_point` is close enough to draw on this site.
func reaches(world_point: Vector2) -> bool:
	return site != null and global_position.distance_to(world_point) <= site.radius_px


## Set by the runtime: how strongly the current cultivator perceives this site's qi (0 = not at
## all). Presentation reads it; nothing else does.
func set_perceived(strength: float) -> void:
	_perceived = clampf(strength, 0.0, 1.0)


func perceived() -> float:
	return _perceived
