extends RefCounted
class_name ChronicleView
## ChronicleView — Aetheria presentation (what the Chronicle shows, Phase 20, D-072 §8).
##
## A read-only snapshot of keys and numbers, assembled by `WorldRuntime` from the owners
## (story, knowledge, the character registry, the relationship graph, the player's own stat
## component). It holds no truth. What the HUD is already told by its owners — health, level
## and XP, the realm, the bag, the techniques, the companion, the place — reaches the book
## from the HUD's own copies of those views and is NOT repeated here (D-073 §4): one feed per
## fact.

## The dimensions the people page says, in order. Each is named and banded on its own.
const SHOWN_DIMENSIONS: Array[StringName] = [&"affinity", &"trust", &"respect"]
## A dimension shown only when it is not at its default (a rivalry is news; its absence is not).
const SHOWN_WHEN_SET: Array[StringName] = [&"rivalry", &"fear", &"debt"]

var available: bool = false
# --- the story page
var chapter_title_key: StringName = &""
var objective_key: StringName = &""
## Record keys of the beats completed, oldest first, then of the decisions made.
var records: Array[StringName] = []
var decisions: Array[StringName] = []
# --- who you are
var origin_name_key: StringName = &""
var origin_problem_key: StringName = &""
var origin_edge_key: StringName = &""
var origin_cost_key: StringName = &""
var origin_goal_key: StringName = &""
## Record keys of what this Origin alone has noticed so far (D-073), in the order authored.
var noticed: Array[StringName] = []
# --- body: the stats combat itself reads, from the player's stat component
var stats_available: bool = false
var attack: int = 0
var defense: int = 0
var move_speed: int = 0
# --- what is known: {name_key, desc_key}
var knowledge: Array[Dictionary] = []
## Who has been met: { name_key, title_key,
##   regard: [ { dimension, value, minimum, maximum } ]   one per dimension shown, in order,
##   notes:  [ record_key ] }   the recorded decisions that moved this person's regard.
var people: Array[Dictionary] = []
