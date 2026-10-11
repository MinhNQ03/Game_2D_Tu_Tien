extends Resource
class_name AmbienceProfileData
## AmbienceProfileData — Aetheria presentation (how a map is LIT, D-073 §3).
##
## One named state of light — dusk, night — as numbers a `MapAmbience` applies: the tint the
## whole playfield is multiplied by, and how strongly the map's own lights (its lanterns, a
## vein) burn in it. Presentation data only: nothing in gameplay reads it and it changes no
## rule. Which profile a map wears is DERIVED from the story's current beat; it is never stored.
##
## GENERATED. `data/ambience/*.tres` are written by `tools/aetheria_art_pipeline/build.py
## ambience` from the `ambience` section of `style/aetheria_style.yaml`, so the colours are
## the Visual DNA's roles and there is one place to change them.

@export var id: StringName = &""
## What the world canvas is multiplied by. White is the map as authored.
@export var tint: Color = Color.WHITE
## The map's lanterns: colour, strength, and how unsteadily they burn (0 = steady).
@export var lantern_color: Color = Color.WHITE
@export_range(0.0, 2.0) var lantern_energy: float = 0.0
@export_range(0.0, 1.0) var lantern_flicker: float = 0.0
## A vein's own light: colour, strength, and the depth of its slow pulse (0 = steady).
@export var vein_color: Color = Color.WHITE
@export_range(0.0, 2.0) var vein_energy: float = 0.0
@export_range(0.0, 1.0) var vein_pulse: float = 0.0
## Seconds a map takes to change INTO this profile from another one (not on arrival).
@export_range(0.0, 4.0) var transition_seconds: float = 0.8


func is_valid() -> bool:
	return id != &"" and transition_seconds >= 0.0


## The mean of the tint's channels: how much of the authored brightness survives. A profile
## that drops below `MapAmbience.MIN_TINT_LEVEL` would hide the playfield, and is refused.
func tint_level() -> float:
	return (tint.r + tint.g + tint.b) / 3.0
