extends RefCounted
class_name StorySceneView
## StorySceneView — Aetheria presentation DTO (the step of a story scene now on screen).
##
## Plain keys and a portrait path. Built by `StoryRuntime`, read by the HUD; it holds no state
## and decides nothing.

var scene_id: StringName = &""
var step_index: int = 0
var step_count: int = 0
## The scene is somewhere else: the map behind it is covered.
var elsewhere: bool = false
## An elsewhere scene's illustration (`res://` path), or "" for the bare ink ground.
var backdrop_ref: String = ""
## A `StorySceneStepData.Kind`.
var kind: int = 0
var text_key: StringName = &""
## A CARD's time line.
var sub_key: StringName = &""
## A LINE's speaker: their name key and portrait ("" when none is authored).
var speaker_name_key: StringName = &""
var portrait_path: String = ""


func is_last_step() -> bool:
	return step_index >= step_count - 1
