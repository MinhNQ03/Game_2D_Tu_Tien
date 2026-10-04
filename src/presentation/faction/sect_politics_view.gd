extends RefCounted
class_name SectPoliticsView
## SectPoliticsView — Aetheria presentation (read-only view of ONE sect's internal politics).
##
## The immutable snapshot the Faction panel renders. It carries LOCALIZATION KEYS and SCALARS
## only — never a `FactionState`, never a service, never a raw content id destined for the
## screen (§21). Presentation therefore cannot reach back into the domain through this object,
## and the panel needs no knowledge of how influence shares or dominance are computed.
##
## Built on demand by `FactionRuntime.get_politics_view()`, never per frame.
##
## It is a VIEW, not a cache: every number here was read from the authoritative store at build
## time, so a stale view is simply replaced by a fresh one rather than updated in place.

## One row of the landscape — one faction, as the player can currently see it.
##
## A nested class rather than a second file: a row has no meaning outside the view that owns
## it, and it is never serialized, stored or passed to the domain.
class Row extends RefCounted:
	## Localization keys (resolved by the panel through `Localization`).
	var name_key: StringName = &""
	var doctrine_key: StringName = &""
	## `FactionTemplateData.Stance` ordinal — the panel maps it to a `FACTION_STANCE_*` key.
	var stance: int = 0
	## Raw weight within the sect, and that weight as an integer percent of the sect total.
	var influence: int = 0
	var influence_share: int = 0
	## True for the faction currently holding the most sway (deterministic, see
	## `FactionService.dominant_faction_of`).
	var is_dominant: bool = false
	## True when this is the side the player has taken.
	var is_player_faction: bool = false
	## How this faction stands toward the PLAYER'S faction: &"ALLIED", &"RIVAL" or &"" when
	## there is no declared relation (or the player has taken no side). Pre-resolved here so
	## the panel never has to query the relationship graph itself.
	var relation_to_player_faction: StringName = &""
	## Display keys of this faction's goals, already ordered by descending priority with a
	## deterministic tie-break.
	var goal_keys: Array[StringName] = []
	## Presentation emblem ref (may be ""), resolved by the panel.
	var emblem_ref: String = ""


## False when there is no live faction session at all — the panel then shows a localized
## "no politics to show" state rather than an empty table that looks like a bug.
var is_available: bool = false

## The sect whose politics this describes (for the panel's own bookkeeping, not displayed).
var sect_id: StringName = &""

## True when the top two factions are within the contested margin — the sect's direction is
## genuinely in dispute. Shown as a word, never as colour alone (`UI_UX_BIBLE.md` §4).
var is_contested: bool = false

## Total declared influence across the sect's factions (the denominator of every share).
var total_influence: int = 0

## One row per faction, ordered by DESCENDING influence then ascending name key, so the panel
## never has to sort and two runs always render the same order.
var rows: Array[Row] = []


## The "no session" view. Every field stays at its empty default so a panel that forgets to
## check `is_available` still renders nothing rather than garbage.
static func make_unavailable() -> SectPoliticsView:
	return SectPoliticsView.new()


## Build the view for `sect_id` from the authoritative service.
##
## Returns an UNAVAILABLE view (not a half-built one) when the service is null, mirroring
## `SectMembershipView.make`: a partially-populated view is worse than an absent one, because
## the panel would render some real numbers beside some defaults with no way to tell them
## apart. A sect that simply has NO factions yields an AVAILABLE view with zero rows — that is
## a real, displayable answer ("this sect has no internal factions"), not a failure.
static func make(
		service: FactionService,
		sect_id: StringName,
		player_instance_id: StringName) -> SectPoliticsView:
	if service == null or sect_id == &"":
		return make_unavailable()
	var store := service.get_store()
	if store == null:
		return make_unavailable()

	var view := SectPoliticsView.new()
	view.is_available = true
	view.sect_id = sect_id
	view.total_influence = service.total_influence_of_sect(sect_id)
	view.is_contested = service.is_contested(sect_id)

	var dominant := service.dominant_faction_of(sect_id)
	var dominant_id: StringName = dominant.id if dominant != null else &""
	var player_faction := service.faction_of(sect_id, player_instance_id) \
		if player_instance_id != &"" else null
	var player_faction_id: StringName = player_faction.id if player_faction != null else &""

	var built: Array[Row] = []
	for faction in store.factions_of_sect(sect_id):
		var state := faction as FactionState
		var template := service.template_for(state.id)
		if template == null:
			continue  # already reported by the service; skip rather than show a blank row
		built.append(_make_row(
			service, state, template, dominant_id, player_faction, player_faction_id))

	built.sort_custom(_compare_rows)
	view.rows = built
	return view


static func _make_row(
		service: FactionService,
		state: FactionState,
		template: FactionTemplateData,
		dominant_id: StringName,
		player_faction: FactionState,
		player_faction_id: StringName) -> Row:
	var row := Row.new()
	row.name_key = template.name_key
	row.doctrine_key = template.doctrine_key
	row.stance = state.stance
	row.influence = state.influence
	row.influence_share = service.influence_share(state.id)
	row.is_dominant = state.id == dominant_id and dominant_id != &""
	row.is_player_faction = state.id == player_faction_id and player_faction_id != &""
	row.relation_to_player_faction = _relation_to(player_faction, state)
	var keys: Array[StringName] = []
	for goal in template.goals_by_priority():
		keys.append(goal.name_key)
	row.goal_keys = keys
	row.emblem_ref = template.emblem_ref
	return row


## How `other` stands toward the player's faction. &"" when the player has taken no side, when
## `other` IS the player's faction, or when no relation is declared.
##
## Read from the FACTION STATE's declared lists rather than from the relationship graph
## directly: the declared lists and the mirrored edges are kept transactionally in step by
## `FactionService`, and reading the state keeps this presentation builder free of any
## knowledge of edge ids or graph structure.
static func _relation_to(player_faction: FactionState, other: FactionState) -> StringName:
	if player_faction == null or player_faction.id == other.id:
		return &""
	if player_faction.is_allied_with(other.id):
		return &"ALLIED"
	if player_faction.is_rival_of(other.id):
		return &"RIVAL"
	return &""


## Strongest influence first; ties broken by name key so the order is total and reproducible
## (two factions on equal influence would otherwise render in store order, which is stable but
## unrelated to anything the player can see).
static func _compare_rows(a: Row, b: Row) -> bool:
	if a.influence != b.influence:
		return a.influence > b.influence
	return String(a.name_key) < String(b.name_key)
