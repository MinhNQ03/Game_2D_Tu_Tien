extends Resource
class_name CultivationSiteData
## CultivationSiteData — Aetheria data (a place where qi wells up, Phase 12).
##
## Qi is NOT ambient in Aetheria (`XIANXIA_IDENTITY_CONTRACT.md`: it wells up through veins), so
## cultivation happens AT a site, and every qi visual has this site as its source. A site is
## data: how strongly it flows, whether it flows steadily, and what body it takes to sit in it.
##
## STABILITY is a real difference, not a label: a steady vein gives a constant flow; a broken
## one surges and ebbs (a deterministic pulse — never a random draw) and gives more on average,
## but it is only SURVIVABLE from `required_realm` (§4: "which cultivation methods are
## survivable" is a realm capability). Below that, the site refuses the cultivator.

enum Stability { STEADY, BROKEN }

@export var id: StringName = &""
@export var name_key: StringName = &""

## Tu vi per second a body with efficiency 1.0 keeps from this site's flow (mean, for BROKEN).
@export var qi_per_second: float = 1.0

@export var stability: Stability = Stability.STEADY

## How far from the site's centre a cultivator can sit and still draw on it, in pixels.
@export var radius_px: float = 40.0

## The realm (and layer within it) a body must have reached to survive this site. Empty =
## anyone who knows how to draw qi.
@export var required_realm: StringName = &""
@export var required_layer: int = 0

## Knowledge a cultivator needs to draw on this site at all — a mortal who has never been
## taught a method sits at a vein and feels nothing. Read through the Knowledge Core.
@export var required_knowledge: Array[StringName] = []


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"" or not String(id).begins_with("site_"):
		errors.append("id must be a non-empty 'site_*' id (got '%s')" % id)
	if name_key == &"":
		errors.append("name_key is empty")
	if qi_per_second <= 0.0:
		errors.append("qi_per_second must be > 0 (got %f)" % qi_per_second)
	if radius_px <= 0.0:
		errors.append("radius_px must be > 0 (got %f)" % radius_px)
	if required_realm == &"" and required_layer != 0:
		errors.append("required_layer without a required_realm")
	return errors


## The flow at `t` seconds into a sitting, as a multiple of `qi_per_second`. STEADY is 1.0. BROKEN
## surges and ebbs on a fixed, irregular pulse (two incommensurate periods, mean 1.0): the
## cultivator feels the vein running wrong, and the same sitting always flows the same way.
func flow_factor(t: float) -> float:
	if stability == Stability.STEADY:
		return 1.0
	return 1.0 + 0.55 * sin(t * 1.9) + 0.25 * sin(t * 4.7 + 1.1)
