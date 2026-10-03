extends RefCounted
class_name SectMembershipView
## SectMembershipView — Aetheria presentation (immutable read-only sect view, §21).
##
## A one-way DTO the UI renders. It carries LOCALIZATION KEYS + already-resolved scalar
## numbers — never a mutable `SectState`, never a raw gameplay object. The HUD/panel read
## these fields and resolve the keys through `Localization`; they NEVER reach into domain
## state or run sect rules (`03-architecture.md`: UI reads a view, owns no truth).
##
## Built once (by `SectRuntime`) from the authoritative state + its template, and rebuilt when
## membership changes — not polled/rebuilt per frame (`05-performance-testing.md`).
##
## A `null`/"not a member" situation is represented by `is_member == false` (the UI shows a
## localized "no sect" state), NOT by a null view — so the UI never crashes on no-sect.

var is_member: bool = false

## Localization keys (resolved by the UI; never literal strings here).
var sect_name_key: StringName = &""
var doctrine_key: StringName = &""
var rank_name_key: StringName = &""

## Sect archetype (SectTemplateData.SectType int) + tier, for a localized type label + number.
var sect_type: int = 0
var tier: int = 1

## Resolved scalars.
var reputation: int = 0        ## reputation in a chosen scope (world standing)
var influence: int = 0
var territory_count: int = 0

## Presentation emblem resource path (from the template; "" = none). The UI loads it; the
## domain never sees it.
var emblem_ref: String = ""

## A compact resource summary `{ resource_id(String) -> quantity(int) }` (copy; read-only).
var resource_summary: Dictionary = {}


## Build a "not a member" view (player has no sect). The UI renders a localized empty state.
static func make_empty() -> SectMembershipView:
	return SectMembershipView.new()


## Build a populated view from an authoritative SectState + its template + the viewer's rank.
## `reputation_scope` selects which reputation scope to surface (world standing by default).
static func make(
		state: SectState,
		template: SectTemplateData,
		viewer_rank_id: StringName,
		reputation_scope: StringName = &"world") -> SectMembershipView:
	var view := SectMembershipView.new()
	if state == null or template == null:
		return view  # stays "not a member" rather than a half-built view
	view.is_member = true
	view.sect_name_key = template.name_key
	view.doctrine_key = template.doctrine_key
	view.sect_type = template.sect_type
	view.tier = template.tier
	view.emblem_ref = template.emblem_ref
	var rank := template.find_rank(viewer_rank_id)
	view.rank_name_key = rank.name_key if rank != null else &""
	view.reputation = state.get_reputation(reputation_scope)
	view.influence = state.influence
	view.territory_count = state.territory().size()
	view.resource_summary = state.resources()
	return view
