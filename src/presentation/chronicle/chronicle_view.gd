extends RefCounted
class_name ChronicleView
## ChronicleView — Aetheria presentation (what the Chronicle shows, Phase 20, D-072 §8).
##
## A read-only snapshot of keys and numbers, assembled by `WorldRuntime` from the owners
## (story, knowledge, the character registry and the relationship graph). It holds no truth.

var available: bool = false
# --- the story page
var chapter_title_key: StringName = &""
var objective_key: StringName = &""
## Record keys of the beats completed, oldest first, then of the decisions made.
var records: Array[StringName] = []
var decisions: Array[StringName] = []
# --- the self page
var origin_name_key: StringName = &""
var origin_problem_key: StringName = &""
var origin_edge_key: StringName = &""
var origin_cost_key: StringName = &""
var origin_goal_key: StringName = &""
# --- what is known: {name_key, desc_key}
var knowledge: Array[Dictionary] = []
# --- who has been met: {name_key, title_key, affinity, trust, respect}
var people: Array[Dictionary] = []
