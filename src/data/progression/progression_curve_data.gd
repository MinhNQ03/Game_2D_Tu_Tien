extends Resource
class_name ProgressionCurveData
## ProgressionCurveData — Aetheria data (the authored level/XP curve, Phase 11).
##
## CONTENT, not behaviour: it holds the cost of every level and answers questions ABOUT the
## curve. It never touches a character. `ProgressionService` is the only thing that mutates
## progression; this resource is what it reads.
##
## THE EXTENSIBILITY TEST THIS RESOURCE EXISTS TO PASS: retuning the whole progression ramp,
## or adding ten more levels, must be editing `xp_to_next` in a `.tres` — no code change, no
## `match level:` ladder, no threshold literal anywhere in a service
## (`02-game-design.md`: all tunable numbers live in data).
##
## ---------------------------------------------------------------------------
## THRESHOLD SEMANTICS (the one thing a reader must get right)
## ---------------------------------------------------------------------------
## `xp_to_next[i]` is the **incremental** cost to advance FROM level `min_level + i` TO
## `min_level + i + 1`. It is NOT a cumulative total.
##
##     min_level = 1, xp_to_next = [20, 45, 80]
##     level 1 -> 2 costs 20     (cumulative 20)
##     level 2 -> 3 costs 45     (cumulative 65)
##     level 3 -> 4 costs 80     (cumulative 145)
##     level 4 is `max_level()`  — no further cost is authored
##
## A character's stored XP is **CUMULATIVE LIFETIME XP**, and the level is **DERIVED** from it
## by walking this curve (`level_for_xp`). That is the central decision of Phase 11 and it is
## worth stating plainly: there is no stored level anywhere, so a stored level can never
## disagree with stored XP. The alternative — stepping a `level` field alongside an
## "xp toward next" field — gives two numbers that must be kept consistent by every code path
## that touches either, and the first path that forgets produces a character whose level and
## XP contradict each other in a save file (this project already undid exactly that shape of
## duplication for sect membership, D-015, and recorded the general rule in L-032).
##
## The cost is that `CharacterState` alone cannot answer "what level am I" — it needs this
## curve. That is accepted deliberately: the curve is content, the answer is a domain
## question, and the domain service is where domain questions belong.
##
## A consequence worth knowing: retuning this curve RE-DERIVES every existing character's
## level from their stored XP. For a balance patch that is the desirable behaviour (everyone
## is re-levelled consistently) rather than a migration problem.
##
## ---------------------------------------------------------------------------
## THE CEILING
## ---------------------------------------------------------------------------
## An authored array is finite, so a maximum level EXISTS — but it is a **data fact**
## (`max_level()` = `min_level + xp_to_next.size()`), never a code constant. Extending the
## game's level range is appending entries here. `02-game-design.md` forbids inventing a
## maximum silently; this makes the maximum explicit, derived, and movable by content.
##
## At the ceiling there is no next level, so there is nothing to progress toward: further XP
## is REJECTED by the service with a named reason rather than accumulating into a number that
## means nothing. A gauge filling toward a level that cannot arrive is the kind of lie
## `docs/UI_UX_BIBLE.md` forbids.
##
## ---------------------------------------------------------------------------
## WHAT THIS IS NOT
## ---------------------------------------------------------------------------
## Level is NOT cảnh giới. It is the fine-grained, combat-derived axis; the realm ladder is
## the chunky, capability-granting one (`docs/PROGRESSION_CULTIVATION_DESIGN.md` §1, CL-02).
## Nothing here may be read as a realm, and **level must never appear in an access condition**
## (C-002). This resource therefore exposes no "unlocks", no content ids and no gates — only
## costs — which is what keeps it structurally incapable of becoming a content gate.

## Stable content id (`curve_*`), so a test and a future second curve can name this one.
@export var id: StringName = &""

## The level a fresh character begins at. Authored rather than assumed to be 1, because a
## future NPC/elite curve may legitimately start higher.
@export var min_level: int = 1

## Incremental XP cost per level step — see THRESHOLD SEMANTICS above.
@export var xp_to_next: Array[int] = []


## The highest level this curve can reach: the last level for which no further cost exists.
func max_level() -> int:
	return min_level + xp_to_next.size()


## Is `level` the top of the authored curve (nothing left to progress toward)?
func is_ceiling(level: int) -> bool:
	return level >= max_level()


## Incremental XP needed to go from `level` to `level + 1`, or 0 at/after the ceiling (and for
## a level below the curve's start, which is a caller bug the service guards against).
func cost_from(level: int) -> int:
	var index := level - min_level
	if index < 0 or index >= xp_to_next.size():
		return 0
	return xp_to_next[index]


## CUMULATIVE XP required to have REACHED `level` from `min_level`.
##
## `cumulative_for_level(min_level)` is 0 by definition: a fresh character has earned nothing.
## Clamped at the ceiling so a level beyond the curve returns the curve's total rather than
## running off the array.
func cumulative_for_level(level: int) -> int:
	var total := 0
	var steps: int = clampi(level - min_level, 0, xp_to_next.size())
	for i in steps:
		total += xp_to_next[i]
	return total


## The level a character with `total_xp` cumulative XP has reached.
##
## THE DERIVATION. Walks the curve subtracting each step's cost while it is affordable, so the
## result is exact at a threshold (spending the last point of a cost DOES level) and never
## overshoots. Negative input clamps to `min_level` — the service rejects negative XP at the
## boundary, and this stays total rather than trusting it to.
func level_for_xp(total_xp: int) -> int:
	var remaining: int = maxi(0, total_xp)
	var level := min_level
	for i in xp_to_next.size():
		var cost: int = xp_to_next[i]
		if remaining < cost:
			break
		remaining -= cost
		level += 1
	return level


## XP earned INSIDE the current level — the numerator of "progress toward the next level".
func xp_into_level(total_xp: int) -> int:
	var level := level_for_xp(total_xp)
	return maxi(0, total_xp) - cumulative_for_level(level)


## Fraction of the way to the next level, in [0, 1]. Returns 1.0 at the ceiling: the bar is
## COMPLETE, which is the honest reading of "there is no next level" — a 0.0 there would
## render as "no progress" on a character who has earned everything the curve holds.
func progress_fraction(total_xp: int) -> float:
	var level := level_for_xp(total_xp)
	if is_ceiling(level):
		return 1.0
	var cost := cost_from(level)
	if cost <= 0:
		return 1.0
	return clampf(float(xp_into_level(total_xp)) / float(cost), 0.0, 1.0)


func is_valid() -> bool:
	return validation_errors().is_empty()


## Validate the authoring at the data boundary and name every problem.
##
## Fail-closed and LOUD, never silently repaired: a curve that quietly normalised bad
## authoring would ship a progression ramp nobody authored (`04-coding-standards.md`, L-024).
## The OWNER decides what to do with the failure — the runtime refuses to start a session.
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id is empty")
	if min_level < 1:
		errors.append("min_level must be >= 1 (got %d)" % min_level)
	if xp_to_next.is_empty():
		errors.append("xp_to_next is empty, so no level could ever be reached")
		return errors  # the per-step checks below have nothing to walk
	var previous := 0
	for i in xp_to_next.size():
		var cost: int = xp_to_next[i]
		if cost <= 0:
			errors.append(("xp_to_next[%d] must be > 0 (got %d) — a free or negative level "
				+ "step would make the level either instant or unreachable") % [i, cost])
		elif cost < previous:
			# A plateau is legal (two levels may cost the same); a DROP is not. A later level
			# that is cheaper than an earlier one inverts the ramp, so the player's sense that
			# progress is getting harder — the only thing an incremental curve communicates —
			# would reverse partway up.
			errors.append(("xp_to_next[%d] (%d) is cheaper than the step before it (%d); the "
				+ "curve must not decrease") % [i, cost, previous])
		previous = maxi(previous, cost)
	return errors
