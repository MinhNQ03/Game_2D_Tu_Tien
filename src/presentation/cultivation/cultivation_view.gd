extends RefCounted
class_name CultivationView
## CultivationView — Aetheria presentation DTO (what the HUD shows about cảnh giới, Phase 12).
##
## A read-only snapshot built by `CultivationRuntime.build_view()` and pushed through
## `WorldRuntime` → `MapBase` → `GameplayHUD`, the same route `ProgressionView` takes. It carries
## localization KEYS and plain numbers — never a CharacterState, never a node (M-12.2).
##
## Two axes, two looks (`PROGRESSION_CULTIVATION_DESIGN.md` §1, D-054): the HUD shows this in
## its own row and hue, and names it "tu vi", which the level row deliberately never does.

## What the cultivator is doing right now, for the contextual prompt.
enum Activity { IDLE, MEDITATING, BREAKING_THROUGH }

var available: bool = false

var realm_name_key: StringName = &""
## 0 for a layerless realm (PHÀM).
var layer: int = 0

var progress: int = 0
var step_cost: int = 0
var fraction: float = 0.0

## The step is full and every prerequisite is met: a breakthrough can be attempted now.
var can_breakthrough: bool = false
## The step is full but knowledge is missing (the HUD says what is missing, not just "no").
var blocked_by_knowledge: bool = false
## No attemptable step remains in this build's content.
var at_ceiling: bool = false

var activity: Activity = Activity.IDLE
## A site the player could sit at right now (drives the contextual "cultivate" prompt).
var site_in_reach: bool = false


static func make_empty() -> CultivationView:
	return CultivationView.new()
