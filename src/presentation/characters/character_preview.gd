extends Node2D
## CharacterPreview — Aetheria presentation (dev-only visual showcase, Phase 05 / D-026).
##
## A PRESENTATION-ONLY preview that instantiates a `CharacterVisualComponent` for each of the
## four initial archetype `CharacterVisualProfileData` resources and lays them out in a row so
## the art pipeline can be eyeballed. It is NOT part of the game flow — it is never the first
## scene and nothing in `Main` loads it (the gameplay flow Menu → Hub ↔ Field → Menu is
## unchanged). The visual-pipeline test drives these same profiles headless.
##
## Debug labels here are developer text, intentionally NOT routed through Localization (they
## are not user-facing production UI — `07-localization.md`).

const VisualComponentScript := preload(
	"res://src/presentation/characters/character_visual_component.gd")

## The four archetype visual profiles previewed (data-driven; add an entry to show more).
const PROFILE_PATHS := [
	"res://data/characters/visual/player_visual.tres",
	"res://data/characters/visual/cultivator_f_visual.tres",
	"res://data/characters/visual/elder_visual.tres",
	"res://data/characters/visual/merchant_visual.tres",
]

const SPACING_X := 48
const BASE_X := 48
const BASE_Y := 96


func _ready() -> void:
	_build_preview()


## Build one visual component per profile, spaced along X, each facing DOWN. Returns the
## number successfully built (used by the test). A missing/invalid profile is skipped loudly.
func build() -> int:
	return _build_preview()


func _build_preview() -> int:
	var built := 0
	var x := BASE_X
	for path in PROFILE_PATHS:
		if not ResourceLoader.exists(path):
			push_error("[preview] visual profile missing: %s" % path)
			x += SPACING_X
			continue
		var profile := load(path) as CharacterVisualProfileData
		var visual := VisualComponentScript.new() as CharacterVisualComponent
		visual.position = Vector2(x, BASE_Y)
		add_child(visual)
		if visual.setup(profile):
			built += 1
		x += SPACING_X
	return built
