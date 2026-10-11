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
var origin_problem_key: StringName = &""
var origin_edge_key: StringName = &""
var origin_cost_key: StringName = &""
## Record keys of the beats completed (oldest first) and of the options chosen.
var records: Array[StringName] = []
var decisions: Array[StringName] = []
## Who the player has spoken to, in the order they met.
var met: Array[StringName] = []
## Record keys of what this Origin alone has noticed so far (D-073).
var noticed: Array[StringName] = []
## `character_id -> [record_key]`: the decisions that moved that person's regard.
var decisions_about: Dictionary = {}
