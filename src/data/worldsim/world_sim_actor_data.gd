extends Resource
class_name WorldSimActorData
## WorldSimActorData — Aetheria data (one authored background character the world simulates).
##
## Adding somebody to the living world is THIS plus a catalog line — no code
## (`02-game-design.md` extensibility rule). It is pure authoring: an identity, the character
## template they are built from, the routine they keep, where they live, and the sect/faction
## they belong to.
##
## IT IS NOT A SECOND CHARACTER MODEL. `WorldSimulationRuntime` builds a real
## `CharacterState` from `character_template` and registers it in the shared
## `CharacterRegistry`, so a simulated elder is the same kind of object as the player
## (`docs/CHARACTER_SYSTEM.md` §1: "the player is a Character too"). There is deliberately no
## `WorldCharacterState`: a parallel model would be a second answer to "who is this person"
## and would have to be kept in sync with the first forever.
##
## MEMBERSHIP IS A REQUEST, NOT A FACT. `sect_id`/`sect_rank`/`faction_id` are what the
## session ASKS for; the enrolment goes through `SectService.join_member` /
## `FactionService.join_member`, so the sect roster stays the single membership authority
## (D-015) and the character's own `sect_id` stays a derived cache. If the authored request is
## illegal (unknown sect, rank not on the ladder, faction in the wrong sect), the service
## refuses and the session fails closed — the world never starts with membership nobody owns.

## Stable id (`actor_*`). Also used as the character's `instance_id`, because a simulated
## actor and the character it realizes are one thing with one identity — two ids would invite
## the two from drifting apart.
@export var id: StringName = &""

## The character definition this actor is built from. REQUIRED: without it there is no
## `CharacterState`, and an actor with no character is simulation with nobody in it.
@export var character_template: CharacterTemplateData = null

## The routine the actor keeps. REQUIRED for the same reason: the activity is a pure function
## of (tick, schedule), so no schedule means no activity to report at any band.
@export var schedule: WorldSimScheduleData = null

## The map the actor lives in (`MapData.id`). Drives the LOD band: the player's current map is
## NEAR, a map reachable from it in one exit is MID, everything else is FAR
## (`docs/WORLD_SIMULATION.md` §2). Validated against the real map catalog by
## `WorldSimCatalog.validation_errors_against_maps()`, which is the first place both catalogs
## exist together.
@export var home_map_id: StringName = &""

## The sect to enrol into, and the rank to enrol at. Both or neither: a rank with no sect has
## nowhere to apply, and a sect with no rank cannot be joined (the service requires one).
@export var sect_id: StringName = &""
@export var sect_rank_id: StringName = &""

## Optional faction within that sect to take the side of. Requires `sect_id` — a faction is
## internal to a sect, and the faction service refuses anyone who is not on the parent sect's
## roster (D-015). Leaving it empty is the normal case: most of a sect has not taken a side.
@export var faction_id: StringName = &""


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id must be set")
	if character_template == null:
		errors.append("character_template must be set (an actor with no character is "
			+ "simulation with nobody in it)")
	elif not character_template.is_valid():
		errors.append("character_template '%s' is invalid: %s"
			% [character_template.id, str(character_template.validation_errors())])
	if schedule == null:
		errors.append("schedule must be set")
	elif not schedule.is_valid():
		errors.append("schedule '%s' is invalid: %s"
			% [schedule.id, str(schedule.validation_errors())])
	if home_map_id == &"":
		errors.append("home_map_id must be set (it decides the LOD band)")
	if sect_id == &"" and sect_rank_id != &"":
		errors.append("sect_rank_id '%s' is set but sect_id is empty: a rank has nowhere to "
			% sect_rank_id + "apply without a sect")
	if sect_id != &"" and sect_rank_id == &"":
		errors.append("sect_id '%s' is set but sect_rank_id is empty: joining a sect requires "
			% sect_id + "a rank from its ladder")
	if faction_id != &"" and sect_id == &"":
		errors.append("faction_id '%s' is set but sect_id is empty: a faction is internal to "
			% faction_id + "a sect and its members must be on that sect's roster (D-015)")
	return errors
