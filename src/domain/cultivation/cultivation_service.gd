extends RefCounted
class_name CultivationService
## CultivationService — Aetheria domain (THE cảnh giới rules, Phase 12).
##
## The second progression axis (`PROGRESSION_CULTIVATION_DESIGN.md` §1): chunky, deliberate,
## capability-granting — never level, never XP, never a smooth number. This is the ONLY place a
## cultivation position is decided:
##
##   * `gather()` adds tu vi toward the next step, capped at that step's cost (a full step waits
##     for a breakthrough — surplus is lost, not banked, so sitting longer is not a shortcut);
##   * `breakthrough()` advances one step — the next layer, or from a realm's last layer (or from
##     PHÀM) into the next realm's layer 1 — when the step is full AND the next realm's
##     `entry_knowledge` is held. Knowledge is READ through `KnowledgeService` (D-040 / C-012),
##     never copied. A structural tier is never attemptable.
##
## Deterministic: no chance roll. Breakthrough success rates are explicitly NOT frozen (§11), and
## a rule that rolled could not be tested without pinning an RNG; when a rate is designed it
## arrives as data plus a seeded stream, the way `CombatService` rolls crits.
##
## It reads capability for everyone else: perception, qi capacity, gather efficiency, and
## whether a body meets a realm requirement (`meets`) — the one comparison every gate uses, so
## "at least Hậu Thiên 3" means the same thing to a site, a technique and a map.

var _ladder: RealmLadderData = null
var _knowledge: KnowledgeService = null


func _init(ladder: RealmLadderData = null, knowledge: KnowledgeService = null) -> void:
	if ladder == null:
		return
	if not ladder.is_valid():
		push_error("[cultivation] refusing an invalid ladder '%s': %s"
			% [ladder.id, str(ladder.validation_errors())])
		return
	_ladder = ladder
	_knowledge = knowledge


func is_ready() -> bool:
	return _ladder != null


func ladder() -> RealmLadderData:
	return _ladder


# === Reading a position =======================================================

## The realm `state` is in. An unset realm id is the ladder's floor: everyone starts mortal.
func realm_of(state: CharacterState) -> RealmData:
	if _ladder == null or state == null:
		return null
	if state.realm_id == &"":
		return _ladder.first()
	return _ladder.realm(state.realm_id)


## Tu vi needed for the next step from where `state` stands (0 when there is no next step).
func step_cost(state: CharacterState) -> int:
	var realm := realm_of(state)
	if realm == null or realm.structural or realm.step_costs.is_empty():
		return 0
	return realm.step_costs[realm.row_for(state.realm_layer)]


## In [0, 1]: how full the current step is.
func step_fraction(state: CharacterState) -> float:
	var cost := step_cost(state)
	if cost <= 0:
		return 0.0
	return clampf(float(state.cultivation_progress) / float(cost), 0.0, 1.0)


## Where the next step would land: [realm, layer], or an empty array when there is none.
func next_step(state: CharacterState) -> Array:
	var realm := realm_of(state)
	if realm == null or realm.structural:
		return []
	if realm.layer_count > 0 and state.realm_layer < realm.layer_count:
		return [realm, state.realm_layer + 1]
	var next := _ladder.next_of(realm.id)
	if next == null or next.structural:
		return []
	return [next, 1 if next.layer_count > 0 else 0]


## Why `state` cannot break through right now, or REASON_NONE when it can.
func breakthrough_blocker(state: CharacterState) -> StringName:
	if _ladder == null:
		return CultivationResult.REASON_NOT_READY
	if state == null:
		return CultivationResult.REASON_NO_STATE
	if realm_of(state) == null:
		return CultivationResult.REASON_UNKNOWN_REALM
	var step := next_step(state)
	if step.is_empty():
		return CultivationResult.REASON_CEILING
	if state.cultivation_progress < step_cost(state):
		return CultivationResult.REASON_INSUFFICIENT
	if not missing_knowledge(state).is_empty():
		return CultivationResult.REASON_MISSING_KNOWLEDGE
	return CultivationResult.REASON_NONE


func can_breakthrough(state: CharacterState) -> bool:
	return breakthrough_blocker(state) == CultivationResult.REASON_NONE


## The knowledge the NEXT step requires that `state`'s holder lacks (only a step into a new
## realm has requirements). Read through the Knowledge Core; with no knowledge service bound,
## every requirement is unmet — fail closed, never open.
func missing_knowledge(state: CharacterState) -> Array[StringName]:
	var out: Array[StringName] = []
	var step := next_step(state)
	if step.is_empty():
		return out
	var target: RealmData = step[0]
	var current := realm_of(state)
	if target == current:
		return out
	for knowledge_id in target.entry_knowledge:
		if _knowledge == null or not _knowledge.knows(knowledge_id):
			out.append(knowledge_id)
	return out


# === Capability (the non-damage dimensions, §4) ================================

func perception_px(state: CharacterState) -> float:
	var realm := realm_of(state)
	if realm == null or realm.perception_px.is_empty():
		return 0.0
	return realm.perception_px[realm.row_for(state.realm_layer)]


func qi_capacity(state: CharacterState) -> int:
	var realm := realm_of(state)
	if realm == null or realm.qi_capacity.is_empty():
		return 0
	return realm.qi_capacity[realm.row_for(state.realm_layer)]


func gather_efficiency(state: CharacterState) -> float:
	var realm := realm_of(state)
	if realm == null or realm.gather_efficiency.is_empty():
		return 0.0
	return realm.gather_efficiency[realm.row_for(state.realm_layer)]


## True when `state` has reached at least `realm_id` (layer `layer` inside it). An empty
## requirement is always met. The ONE comparison every realm gate uses.
func meets(state: CharacterState, realm_id: StringName, layer: int = 0) -> bool:
	if realm_id == &"":
		return true
	var mine := realm_of(state)
	var wanted := _ladder.realm(realm_id) if _ladder != null else null
	if mine == null or wanted == null:
		return false
	if mine.order != wanted.order:
		return mine.order > wanted.order
	return state.realm_layer >= layer


# === Deciding a new position (the only mutators) =================================

## Add `amount` tu vi toward the next step, capped at its cost. Rejected when the step is
## already full (REASON_FULL) or there is no step (REASON_CEILING).
func gather(state: CharacterState, amount: int) -> CultivationResult:
	var result := CultivationResult.make(state)
	if _ladder == null:
		return result.reject(CultivationResult.REASON_NOT_READY)
	if state == null:
		return result.reject(CultivationResult.REASON_NO_STATE)
	if amount < 0:
		push_error("[cultivation] refusing a negative gather (%d)" % amount)
		return result.reject(CultivationResult.REASON_NEGATIVE)
	if next_step(state).is_empty():
		return result.reject(CultivationResult.REASON_CEILING)
	var cost := step_cost(state)
	if state.cultivation_progress >= cost:
		return result.reject(CultivationResult.REASON_FULL)
	var realm := realm_of(state)
	state.set_cultivation(realm.id, state.realm_layer,
		mini(cost, state.cultivation_progress + amount))
	return result.commit(state)


## Advance one step if `breakthrough_blocker` allows it; the step's tu vi is spent.
func breakthrough(state: CharacterState) -> CultivationResult:
	var result := CultivationResult.make(state)
	var blocker := breakthrough_blocker(state)
	if blocker != CultivationResult.REASON_NONE:
		if blocker == CultivationResult.REASON_MISSING_KNOWLEDGE:
			result.missing = missing_knowledge(state)
		return result.reject(blocker)
	var step := next_step(state)
	var target: RealmData = step[0]
	state.set_cultivation(target.id, int(step[1]), 0)
	return result.commit(state)
