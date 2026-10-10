extends Resource
class_name AiProfileData
## AiProfileData — Aetheria data (one enemy's BEHAVIOUR TUNING, Phase 10).
##
## The numbers an `AiBrain` reads to decide. Separate from `EnemyData` on purpose: a profile is
## a reusable *behaviour archetype* ("frontier skirmisher", "ambusher", "guard") that several
## creatures can share, while `EnemyData` is one creature's identity and stats. Merging them
## would mean copying a dozen tuning values every time a second creature wanted the same
## behaviour, and then having them drift.
##
## IT CONTAINS NO LOGIC AND NO BRANCHES. There is no `behaviour_type` enum here that a brain
## switches on — that would put AI logic in data, which `02-game-design.md`'s extensibility rule
## forbids in the other direction too: data describes, the domain decides. A genuinely new
## BEHAVIOUR is a new brain state (code, with a test); a different *flavour* of the same
## behaviour is this resource.

## Stable content id (`ai_*`).
@export var id: StringName = &""

# --- Perception ---------------------------------------------------------------

## Distance at which the enemy notices a target, in pixels.
@export var detect_radius: float = 160.0

## Distance at which it gives up and goes home. MUST be larger than `detect_radius`, or the
## enemy oscillates between noticing and forgetting at the same spot — a hysteresis band, not
## a single threshold. `is_valid()` enforces it.
@export var lose_interest_radius: float = 260.0

## How far it will stray from its spawn point before returning, in pixels. This is what keeps
## an encounter LOCAL: without it a single wolf can be walked across the whole map.
@export var leash_radius: float = 320.0

# --- Decision cadence ---------------------------------------------------------

## Seconds between DECISIONS. Movement is executed every tick; only the choice is throttled
## (`05-performance-testing.md`: no per-frame AI thinking). Larger = cheaper and more readable
## (the player can see a committed decision); too large = the enemy feels deaf.
@export var decision_interval: float = 0.2

# --- Movement -----------------------------------------------------------------

## Speed multiplier while chasing, applied to the enemy's `move_speed` stat.
@export var chase_speed_scale: float = 1.0

## Speed multiplier while patrolling or returning home — slower, so "hunting you" and
## "wandering" are visibly different states rather than the same motion with a different name.
@export var patrol_speed_scale: float = 0.45

# --- State timings ------------------------------------------------------------

## How long it pauses on first noticing a target. This is a TELEGRAPH, not a delay: it is the
## window in which the player can see that they have been spotted (`COMBAT_DESIGN.md` §7 —
## telegraph language is learned once and must be visible).
@export var alert_seconds: float = 0.35

## How long it backs off after a swing. The signature of this archetype: it does not stand in
## your face trading hits, it disengages and re-closes, which is what punishes standing still.
@export var recover_seconds: float = 0.6

## How long it idles before wandering again.
@export var idle_seconds: float = 1.2

## How long one patrol leg lasts before picking a new direction.
@export var patrol_seconds: float = 1.5

## Distance it tries to keep while recovering, in pixels — it backs off to about here.
@export var recover_distance: float = 72.0


## True when the tuning is self-consistent. Loud about WHICH field is wrong, because a content
## error that only says "invalid" sends the author through the whole file.
# --- Home: a spawn point, or an OWNER (Phase 16) -------------------------------------
#
# The brain has always had a HOME it returns to. For an enemy that is where it spawned; for an
# ally it is its owner, a home that MOVES. These three values are what make the one state
# machine serve both, and their defaults are exactly the enemy behaviour that shipped — an
# enemy profile that authors none of them is unchanged.

## How far from home an IDLE creature tolerates before going back, in pixels. 0 = it never
## follows (an enemy idles wherever its patrol left it). An ally sets this: it is the distance
## at which a companion starts walking after its owner.
@export var follow_radius: float = 0.0

## How close to home counts as ARRIVED, in pixels. A tolerance, not a target: without one the
## creature jitters around the point forever. An ally's is its standing distance from the
## owner; with `follow_radius` above it, the two form the band that makes following stable
## (walk when beyond the one, stop when inside the other).
@export var home_arrival_radius: float = 8.0

## Speed scale while RETURNING home. 0 = use `patrol_speed_scale` (an enemy ambles back). An
## ally must be able to keep up with an owner who walks faster than it patrols.
@export var return_speed_scale: float = 0.0


## The speed scale a RETURN actually uses.
func effective_return_speed_scale() -> float:
	return return_speed_scale if return_speed_scale > 0.0 else patrol_speed_scale


func is_valid() -> bool:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if detect_radius <= 0.0:
		problems.append("detect_radius must be > 0 (got %.1f)" % detect_radius)
	# The hysteresis band is the point: equal radii make the enemy flicker between noticing
	# and forgetting while standing at exactly that distance.
	if lose_interest_radius <= detect_radius:
		problems.append("lose_interest_radius (%.1f) must EXCEED detect_radius (%.1f) so "
			% [lose_interest_radius, detect_radius] + "notice/forget is a band, not a knife edge")
	if leash_radius <= 0.0:
		problems.append("leash_radius must be > 0 (got %.1f)" % leash_radius)
	if decision_interval <= 0.0:
		problems.append("decision_interval must be > 0 (got %.3f) or the AI thinks every frame"
			% decision_interval)
	if chase_speed_scale <= 0.0:
		problems.append("chase_speed_scale must be > 0 (got %.2f)" % chase_speed_scale)
	if patrol_speed_scale <= 0.0:
		problems.append("patrol_speed_scale must be > 0 (got %.2f)" % patrol_speed_scale)
	for field in ["alert_seconds", "recover_seconds", "idle_seconds", "patrol_seconds"]:
		var value: float = float(get(field))
		if value <= 0.0:
			problems.append("%s must be > 0 (got %.3f)" % [field, value])
	if recover_distance <= 0.0:
		problems.append("recover_distance must be > 0 (got %.1f)" % recover_distance)
	if follow_radius < 0.0:
		problems.append("follow_radius must be >= 0 (got %.1f)" % follow_radius)
	if home_arrival_radius <= 0.0:
		problems.append("home_arrival_radius must be > 0 (got %.1f)" % home_arrival_radius)
	# The band is the point: at equal radii a follower arrives and leaves on the same pixel.
	if follow_radius > 0.0 and follow_radius <= home_arrival_radius:
		problems.append("follow_radius (%.1f) must EXCEED home_arrival_radius (%.1f)"
			% [follow_radius, home_arrival_radius])
	if follow_radius > 0.0 and follow_radius >= leash_radius:
		problems.append("follow_radius (%.1f) must be inside leash_radius (%.1f)"
			% [follow_radius, leash_radius])
	if return_speed_scale < 0.0:
		problems.append("return_speed_scale must be >= 0 (got %.2f)" % return_speed_scale)
	if problems.is_empty():
		return true
	push_error("[ai-profile] '%s' is invalid: %s" % [id, "; ".join(problems)])
	return false
