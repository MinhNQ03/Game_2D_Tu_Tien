extends Resource
class_name WorldSimEventData
## WorldSimEventData — Aetheria data (one authored, recurring world event).
##
## The scheduled half of the simulation drivers (`docs/WORLD_SIMULATION.md` §3): an event with
## a first due tick and an optional period, which on firing applies a bounded change THROUGH
## the owning system's service. This is where the seeded RNG is actually consumed — the
## magnitude is drawn from `[magnitude_min, magnitude_max]` on the world-simulation stream.
##
## WHY THE EVENT KINDS MAP ONTO OTHER SYSTEMS' SERVICES
## World Simulation owns world EVOLUTION, not world STATE. A sect's influence belongs to
## `SectService`, a faction's to `FactionService`, a relationship dimension to
## `RelationshipService` — so an event names a target and a magnitude, and the simulation asks
## the owner to apply it (`SYSTEM_DEPENDENCY_MATRIX.md` §5: "No system mutates another
## system's authoritative collection"). An event that wrote `SectState.influence` directly
## would be the D-015 defect reintroduced from a new direction.
##
## WHAT IS DELIBERATELY NOT HERE (`docs/SOCIAL_DESIGN.md` §5, B10): succession, schism, coup,
## purge, war resolution. Those are RULES over this substrate and belong to the later phases
## that own them. Phase 08 ships the substrate and three event kinds that exercise all three
## service seams, so the later rules have something proven to build on.

## What the event does when it fires. Closed vocabulary; each value corresponds to exactly one
## authoritative service.
enum Kind {
	## `SectService.adjust_influence(target_id, magnitude)`.
	SECT_INFLUENCE,
	## `FactionService.adjust_influence(target_id, magnitude)`.
	FACTION_INFLUENCE,
	## `RelationshipService.apply_delta(edge_id, dimension, magnitude, cause)` on the edge
	## between `target_id` and `secondary_id`.
	RELATIONSHIP_SHIFT,
}

## Localization keys for the kinds, index-aligned with `Kind`, for the world-event feed.
const KIND_NAME_KEYS := [
	&"WORLDSIM_EVENT_SECT_INFLUENCE",
	&"WORLDSIM_EVENT_FACTION_INFLUENCE",
	&"WORLDSIM_EVENT_RELATIONSHIP_SHIFT",
]

## Stable id (`wevent_*`). Also the scheduling key, so an id must be unique in the catalog.
@export var id: StringName = &""

## Which service seam this event drives.
@export var kind: int = Kind.SECT_INFLUENCE

## The primary subject: a sect id, a faction id, or the first endpoint of a relationship.
@export var target_id: StringName = &""

## The second endpoint, for `RELATIONSHIP_SHIFT` only. Empty for the influence kinds.
@export var secondary_id: StringName = &""

## The relationship dimension to move, for `RELATIONSHIP_SHIFT` only. One of the six frozen
## dimensions (CL-12); validated against the live config at session start, not here, because
## the dimension list is authored in `relationship_config.tres` and is not visible from a data
## resource.
@export var dimension: StringName = &""

## The first tick this event is due, measured from the start of the world. Must be > 0: an
## event due at tick 0 would fire before the world has advanced at all, i.e. during session
## start, which would make "the world as authored" and "the world after one tick"
## indistinguishable.
@export var first_tick: int = 1

## Ticks between repeats. 0 = fire exactly once. Must not be negative.
@export var period_ticks: int = 0

## The INCLUSIVE magnitude range drawn from the seeded stream on each firing. May be negative
## (influence falls, affinity sours) — that is the point of a world that moves on its own.
@export var magnitude_min: int = 1
@export var magnitude_max: int = 1


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id must be set")
	if kind < 0 or kind >= Kind.size():
		errors.append("kind %d is not a known Kind ordinal" % kind)
		return errors  # every check below is kind-specific
	if target_id == &"":
		errors.append("target_id must be set")
	if first_tick <= 0:
		errors.append("first_tick must be > 0 (got %d): an event due at tick 0 would fire "
			% first_tick + "before the world has advanced at all")
	if period_ticks < 0:
		errors.append("period_ticks must be >= 0 (got %d); 0 means fire once" % period_ticks)
	if magnitude_max < magnitude_min:
		errors.append("magnitude range is inverted: [%d, %d]" % [magnitude_min, magnitude_max])
	if magnitude_min == 0 and magnitude_max == 0:
		# A guaranteed zero magnitude still consumes a draw and emits an event that changes
		# nothing — a simulated number no player could ever encounter, which
		# `SOCIAL_DESIGN.md` §7 calls out as cost without content.
		errors.append("magnitude range [0, 0] can never change anything; an event that "
			+ "cannot be felt is cost without content")
	if kind == Kind.RELATIONSHIP_SHIFT:
		if secondary_id == &"":
			errors.append("RELATIONSHIP_SHIFT requires a secondary_id (the other endpoint)")
		elif secondary_id == target_id:
			errors.append("RELATIONSHIP_SHIFT endpoints must differ (both are '%s')"
				% target_id)
		if dimension == &"":
			errors.append("RELATIONSHIP_SHIFT requires a dimension to move")
	else:
		if secondary_id != &"":
			errors.append("secondary_id '%s' is only meaningful for RELATIONSHIP_SHIFT"
				% secondary_id)
		if dimension != &"":
			errors.append("dimension '%s' is only meaningful for RELATIONSHIP_SHIFT"
				% dimension)
	return errors


## True when this event repeats rather than firing once.
func is_recurring() -> bool:
	return period_ticks > 0


## The localization key for `kind`, or the first key (loud) for an unknown ordinal.
static func kind_name_key(kind_ordinal: int) -> StringName:
	if kind_ordinal < 0 or kind_ordinal >= KIND_NAME_KEYS.size():
		push_error("[worldsim] no name key for event kind ordinal %d" % kind_ordinal)
		return KIND_NAME_KEYS[0]
	return KIND_NAME_KEYS[kind_ordinal]
