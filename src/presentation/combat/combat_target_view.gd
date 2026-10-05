extends RefCounted
class_name CombatTargetView
## CombatTargetView — Aetheria presentation (read-only snapshot of what the player is fighting).
##
## The immutable thing the target panel renders. Localization KEYS and resolved scalars only —
## never an `Enemy` node, never `EnemyData`, never a service. Built by `CombatRuntime` when a
## target's health changes or it dies; never polled per frame
## (`05-performance-testing.md`).
##
## WHAT IT DELIBERATELY DOES NOT CARRY, and why each one would be a lie right now (C15: show
## only information already backed by real data):
##   * **level** — Phase 11 owns level/XP. Nothing has one yet, and `02-game-design.md` is
##     explicit that level is never an access gate, so inventing one here would also invite the
##     numeric comparison the design forbids.
##   * **mana / linh khí** — the resource model is design-only (`COMBAT_DESIGN.md` §9).
##   * **realm** — enemies have no `CharacterState`, so there is no realm to read.
##   * **a stat breakdown** — attack/defense are inputs to the formula, not player-facing
##     information, and showing them would invite the player to do the arithmetic instead of
##     reading the fight.
## The threat RATING is carried instead, as a localization KEY: it communicates difficulty as a
## judgement ("frontier, low") rather than as a number to be out-grown.

## False when the player is not fighting anything. The HUD then hides the panel rather than
## rendering an empty frame, so "no target" and "a target at 0 HP" cannot look the same.
var has_target: bool = false

## Localization key for the creature's name (resolved by the UI, never a literal here).
var name_key: StringName = &""

## Localization key for its advisory threat rating. Empty is legal — a creature may have none.
var threat_key: StringName = &""

var current_health: int = 0
var max_health: int = 1

## True once it is dead. The panel keeps showing it briefly so the player sees WHAT they
## killed, instead of the information vanishing at the moment it is most satisfying.
var is_dead: bool = false


## The "not fighting anything" view. A valid object, never null, so the HUD never null-checks
## before reading (the same contract as `SectMembershipView.make_empty`).
static func make_empty() -> CombatTargetView:
	return CombatTargetView.new()


## Build from an authored creature plus its live health.
##
## Takes the DATA and the numbers rather than the node: the view must not hold a reference to
## an entity that may be freed a frame later, which is how a HUD ends up rendering a dangling
## object.
static func make(data: EnemyData, current: int, maximum: int, dead: bool) -> CombatTargetView:
	var view := CombatTargetView.new()
	if data == null:
		return view
	view.has_target = true
	view.name_key = data.name_key
	view.threat_key = data.threat_key
	view.current_health = maxi(0, current)
	view.max_health = maxi(1, maximum)
	view.is_dead = dead
	return view
