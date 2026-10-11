extends RefCounted
class_name StoryView
## StoryView — Aetheria presentation DTO (what the story shows outside a scene, Phase 20).
##
## Plain keys. Built by `StoryRuntime` from the one story record; the HUD formats it.

## The current beat's objective — the story's candidate for the place plaque's purpose line.
var objective_key: StringName = &""
var chapter_title_key: StringName = &""
var origin_name_key: StringName = &""
## The Origin's standing personal goal.
var origin_goal_key: StringName = &""
