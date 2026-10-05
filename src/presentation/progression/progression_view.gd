extends RefCounted
class_name ProgressionView
## ProgressionView — Aetheria presentation (read-only snapshot of the player's level/XP).
##
## The immutable thing the HUD's progression row renders. Resolved scalars only — never a
## `CharacterState`, never a `ProgressionService`, never the curve. Built by
## `ProgressionRuntime` when XP changes and pushed through `WorldRuntime` → `MapBase` → HUD,
## never polled per frame (`05-performance-testing.md`), which is the same path the sect,
## politics and world-sim views already take.
##
## WHY A DTO AND NOT THE STATE. Presentation holding a `CharacterState` would let a HUD write
## to the authority — the thing §5 of the phase brief forbids and the thing
## `03-architecture.md` forbids generally. Handing over numbers makes "the UI owns no
## progression truth" structural rather than a convention someone has to remember.
##
## WHAT IT DELIBERATELY DOES NOT CARRY:
##   * **cumulative lifetime XP** — the player tracks progress toward the next level, not a
##     career total, and no current consumer needs it (L-005: no field without a consumer).
##   * **realm / cảnh giới** — a different axis entirely, owned by Phase 12. Level must never
##     be dressed up as a realm (`docs/PROGRESSION_CULTIVATION_DESIGN.md` §1), so there is no
##     realm-shaped field here to be tempted into filling with a level.
##   * **anything unlocked** — level is NEVER an access gate (C-002). A view with an "unlocks"
##     list would be the first step toward one.

## False before a progression session exists. The HUD then hides the row rather than
## rendering `Lv 0` or an empty meter, so "no progression yet" and "a fresh character" cannot
## look the same — the same contract the health gauge uses for an unreported value.
var available: bool = false

## The player's current level, DERIVED from their XP by the service (never stored).
var level: int = 0

## XP earned inside the current level, and what the current level costs in total. Together
## they are the readable pair ("20 / 45") that the meter writes as text, because
## `docs/UI_UX_BIBLE.md` §4 requires colour never to be the only carrier of meaning.
var xp_into_level: int = 0
var xp_for_next: int = 0

## Progress toward the next level in [0, 1]. Carried pre-computed so the HUD performs no
## progression arithmetic of its own — a UI that divides is a UI that can divide differently
## from the authority.
var progress: float = 0.0

## True at the top of the authored curve. The HUD shows a COMPLETE meter and a "max" reading
## instead of `0 / 0`, which is what the raw numbers would say there.
var at_ceiling: bool = false


## The "no progression session" view. A valid object, never null, so the HUD never null-checks
## before reading (the same contract as `SectMembershipView.make_empty`).
static func make_empty() -> ProgressionView:
	return ProgressionView.new()


## Build from the service's answers about `state`.
##
## Takes the SERVICE and the STATE rather than raw numbers, so every figure in the view comes
## from the one authority and the view cannot drift from it by computing something itself.
static func make(service: ProgressionService, state: CharacterState) -> ProgressionView:
	var view := ProgressionView.new()
	if service == null or not service.is_ready() or state == null:
		return view
	view.available = true
	view.level = service.level_of(state)
	view.xp_into_level = service.xp_into_level(state)
	view.xp_for_next = service.xp_for_next_level(state)
	view.progress = service.progress_fraction(state)
	view.at_ceiling = service.is_at_ceiling(state)
	return view
