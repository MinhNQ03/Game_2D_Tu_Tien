extends RefCounted
class_name WorldSimView
## WorldSimView — Aetheria presentation (read-only snapshot of the world's time + last event).
##
## The immutable thing the HUD renders. Localization keys and scalars ONLY — never a
## `WorldSimulationState`, never a service, never a raw content id destined for the screen.
## Built on demand by `WorldSimulationRuntime.get_view()` (on arrival in a map / on a world
## event), never per frame (`05-performance-testing.md`).
##
## WHAT IT DELIBERATELY DOES NOT CARRY, and why:
##   * **Band counts, actor records, stream positions, the pending queue, carry-over debt.**
##     Those are simulation internals. B18 is explicit that debug-only internals must not be
##     exposed to the player, and a HUD that showed "3 NEAR / 47 FAR" would be telling them
##     about the engine instead of about the world.
##   * **The SUBJECT of the last event** ("whose influence rose"). Naming it needs a
##     content-id → localization-key resolution for sects, factions and characters alike; the
##     faction side has `FactionService.template_for`, the sect side keeps its templates
##     private, and characters have no registry-wide name lookup until P-17. Adding a public
##     accessor purely to label a feed line is not a trade worth making yet, and printing the
##     raw id instead is forbidden (`07-localization.md`). So Phase 08 shows WHAT KIND of
##     thing happened and in which direction — which is enough for the player to notice that
##     the world moved while they were away, which is the whole point
##     (`SOCIAL_DESIGN.md` §7) — and the named chronicle arrives with the phase that can
##     name things.

## False when there is no live simulation session. The HUD then renders nothing at all rather
## than a date of year 0, which would look like a bug.
var available: bool = false

# --- World time (all derived from the single stored tick) --------------------
var tick: int = 0
var year: int = 1
var season: int = 1
var day: int = 1
var hour: int = 0
var total_days: int = 0

# --- The most recent world event (empty when nothing has happened yet) -------

## Localization key for the event KIND (`WORLDSIM_EVENT_*`), or `&""` when the feed is empty.
var last_event_kind_key: StringName = &""

## The magnitude actually applied. Its SIGN is the information the player reads — something
## rose or fell — so it is carried signed rather than as an absolute with a separate flag.
var last_event_magnitude: int = 0

## The tick the event happened on, so the HUD can say how long ago it was in world time.
var last_event_tick: int = 0


## The "there is no simulation" view. A valid object with `available == false`, never null, so
## the HUD never has to null-check before reading.
static func make_unavailable() -> WorldSimView:
	return WorldSimView.new()


## Build the view from a live simulation state. Returns an unavailable view for a null state,
## so a caller that lost its session degrades to "show nothing" instead of crashing.
static func make(state: WorldSimulationState) -> WorldSimView:
	if state == null or state.clock() == null:
		return make_unavailable()
	var clock := state.clock()
	var view := WorldSimView.new()
	view.available = true
	view.tick = clock.tick()
	view.year = clock.year()
	view.season = clock.season_of_year()
	view.day = clock.day_of_season()
	view.hour = clock.hour_of_day()
	view.total_days = clock.total_days()
	var latest := state.latest_event()
	if not latest.is_empty():
		view.last_event_kind_key = WorldSimEventData.kind_name_key(int(latest.get("kind", 0)))
		view.last_event_magnitude = int(latest.get("magnitude", 0))
		view.last_event_tick = int(latest.get("tick", 0))
	return view


## True when there is an event worth showing.
func has_last_event() -> bool:
	return available and last_event_kind_key != &""
