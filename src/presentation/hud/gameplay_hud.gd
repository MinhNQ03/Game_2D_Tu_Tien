extends CanvasLayer
class_name GameplayHUD
## GameplayHUD — Aetheria presentation (in-map heads-up display, asset-backed pass).
##
## A screen-space (`CanvasLayer`) overlay that RENDERS a view of the running session. Its
## surfaces follow a WEIGHT LADDER (D-057, `docs/UI_UX_BIBLE.md` §3c): what the player
## tracks — identity, place, target — sits in framed pixel-art plaques (shared
## `UITheme`/`UIPalette` 9-slice assets); passive key hints sit on a quiet unframed band;
## transient announcements are bare outlined text.
##   - top-left   : the IDENTITY PLAQUE — portrait slot + name/title + level badge + health
##                  gauge + XP meter + sect chip, read as ONE unit under an ornamental
##                  divider (D-041; level/XP added in Phase 11),
##   - top-centre : the COMBAT TARGET plaque — what the player is fighting (Phase 10),
##   - top-right  : the map-name plaque (a localized place name under the same divider) plus
##                  the world date and the last world event (Phase 08),
##   - bottom-left: the CONTROL-PROMPT STRIP — five graphic key badges, left to right:
##                  **Attack · Interact · Sect · Politics · Menu**. Attack leads because it is
##                  the only verb there that changes the world rather than opening a panel
##                  (D-055-G); Interact is the one CONTEXTUAL row (it names a target, so off an
##                  exit it has no referent). Each row is a shared `UIPromptRow`, and each key
##                  glyph is resolved from its SEMANTIC action through
##                  `InputService.get_action_display_label` — this file names actions
##                  (`attack`, `interact`, …), never physical keys, so a rebind moves the
##                  prompts with it (L-003).
##
## D-041 changed the COMPOSITION only, never the data: the identity block used to be a flat
## stack where the sect chip was indistinguishable from the character's title (two muted hint
## lines in the same column), so the player could not tell "who I am" from "who I belong to".
## The divider + section gap make that boundary visible. Screen-edge spacing now comes from
## `UIPalette.HUD_MARGIN` rather than the generic `SPACE_MD`, so HUD framing can be retuned
## in one place without touching inner padding.
##
## It OWNS no truth. The owner pushes data in via `set_character()`, `set_map_name()`,
## `set_interact_available()`, `set_health()`, `set_progression_view()`, `set_target_view()`,
## `set_sect_view()`, `set_politics_view()` and `set_world_sim_view()`; the HUD only formats +
## displays. Key glyphs come from `InputService.get_action_display_label` (never raw keycodes,
## L-003). It refreshes on demand (owner call) and on language change — never per frame
## (`05-performance-testing.md`).
##
## WHICH GAUGES EXIST, AND WHY ONLY THOSE: health (Phase 09) and the XP meter + level badge
## (Phase 11) are shown because combat and progression now OWN those numbers. Mana and
## cultivation are still absent on purpose — `docs/UI_UX_BIBLE.md` forbids rendering a gauge
## for state no system owns, because a bar that looks right in a mock and shows nothing real in
## a build is worse than an absent one. Every gauge here hides until a value is pushed, so a
## HUD built outside a session shows no bar rather than a full one.

const PromptRowScript := preload("res://src/presentation/ui/components/ui_prompt_row.gd")
const SectPanelScript := preload("res://src/presentation/sect/sect_panel.gd")
const FactionPanelScript := preload("res://src/presentation/faction/faction_panel.gd")
const LevelUpFeedbackScript := preload(
	"res://src/presentation/progression/level_up_feedback.gd")

## The basic attack (D-055-G). A SEMANTIC action name only — the physical key is resolved
## through `InputService.get_action_display_label`, so rebinding updates the prompt and no
## physical keycode ever appears in presentation (L-003).
const ATTACK_ACTION := &"attack"
const INTERACT_ACTION := &"interact"
const OPEN_MENU_ACTION := &"open_menu"
const SECT_PANEL_ACTION := &"sect_panel"
const FACTION_PANEL_ACTION := &"faction_panel"
const CULTIVATE_ACTION := &"cultivate"
const INVENTORY_ACTION := &"inventory"
const PET_SUMMON_ACTION := &"pet_summon"

## The player asked to use an item from the bag (Phase 13). The HUD decides nothing: MapBase
## forwards it to WorldRuntime → InventoryRuntime.
signal inventory_use_requested(item_id: StringName, equipped: bool)
## Shop intents (Phase 17). The HUD forwards what the panel asked for; `NpcRuntime` decides.
signal shop_buy_requested(item_id: StringName)
signal shop_sell_requested(item_id: StringName)
signal shop_close_requested()
## Dialogue intents (Phase 18). The HUD forwards what the panel asked for; `DialogueRuntime`
## decides. A choice names the line it answers.
signal dialogue_choice_requested(node_id: StringName, choice_id: StringName)
signal dialogue_advance_requested()
signal dialogue_close_requested()

## Side of the small sect emblem chip in the identity panel. HUD-local: nothing else in the
## UI draws a chip this size, so it stays here rather than widening the shared palette.
const SECT_EMBLEM_PX := 20

## Height of the ornamental divider strips. The source art is 136x21 (measured, D-034) and is
## scaled to this band, so it reads as a thin engraved rule rather than a picture.
const DIVIDER_HEIGHT := 8

var _loc: Node = null
var _input: Node = null
var _bus: Node = null

# Pushed-in view state (presentation copies; the HUD never mutates the source).
var _name_key: StringName = &""
var _title_key: StringName = &""
var _map_name_key: StringName = &""
var _interact_available: bool = false
var _sect_view: SectMembershipView = null  # read-only sect view (Phase 06); may be null

var _name_label: Label
var _title_label: Label
var _map_label: Label
## World time + the last world event (Phase 08). Two muted lines under the place name.
var _world_date_label: Label
var _world_event_label: Label
var _portrait: TextureRect
## The player's health gauge (Phase 09). Hidden until a health value arrives, so a HUD built
## outside a combat session shows no gauge rather than a full bar for health nothing owns.
var _health_gauge: ProgressBar
## Level badge + XP meter (Phase 11). Both hidden until a progression view arrives.
var _level_label: Label
var _xp_meter: ProgressBar
## Transient centre-screen level-up announcement; owned by `_level_up` while it runs.
var _level_up_banner: Label
## The one-shot level-up celebration. Owned here; presentation-only; idle when not running.
var _level_up: LevelUpFeedback = null
## The last progression view pushed in, kept so `_refresh_text()` can re-resolve its strings
## on a language change without the progression session having to push again.
var _progression_view: ProgressionView = null
## The combat target plaque (Phase 10): what the player is fighting. Hidden with no target.
var _target_panel: PanelContainer
var _target_name_label: Label
var _target_threat_label: Label
var _target_gauge: ProgressBar
## Retires the target plaque a moment after a kill (see `set_target_view`).
var _target_linger: Timer
## The last target view pushed in, kept so `_refresh_text()` can re-resolve its keys on a
## language change without the combat session having to push again.
var _target_view: CombatTargetView = null
## True while a LIVE target is engaged, so engagement is detected as a transition.
var _engaged: bool = false
## The tu vi meter (Phase 12) under the XP meter; hidden until a cultivation view arrives.
var _cultivation_meter: ProgressBar
var _cultivation_view: CultivationView = null
## The contextual cultivate prompt: sit / rise / break through, by what the view allows.
var _cultivate_row: UIPromptRow
## The linh thú prompt (Phase 16): shown only once the player owns a pet.
var _pet_row: UIPromptRow
var _pet_view: PetView = null
## The verb the interact prompt shows: "Interact" at an exit, "Read" at a stele (Phase 12).
var _interact_label_key: StringName = &"UI_HUD_INTERACT_ACTION"
## THE BOTTOM BAND (D-063): one slot for a transient line and the MACRO breakthrough banner.
## Every notice has a KIND, chosen by whoever knows its cause (`WorldRuntime`):
##   PASSIVE — what happened around the player (an item picked up on the way). Waits its turn,
##             in arrival order; never jumps an answer; never dropped.
##   RESULT  — what the player's own action achieved (learned, used). Shown on the frame it
##             happens; results of ONE action keep their order; never dropped.
##   ANSWER  — why the player's action did not happen (a refusal, "nothing new"). Shown on the
##             frame it happens; the same answer again refreshes it; a newer answer or result
##             supersedes it — a stale refusal is never shown again (preemptible by design).
## Presentation priority in the slot: RESULT/ANSWER > breakthrough banner > PASSIVE. Whatever
## gives way is PRESERVED: an interrupted notice resumes for the time it had left, a paused
## banner resumes after the answers. Before D-063 one FIFO line held every notice for 3s, so a
## refusal waited behind pickups for 2.6-5.8s, and a full queue of 4 dropped the fifth.
const NOTICE_PASSIVE := &"passive"
const NOTICE_RESULT := &"result"
const NOTICE_ANSWER := &"answer"
var _notice_label: Label
var _notice_timer: Timer
## The notice in the slot now — {seq, kind, key, args, hold, frame} — or empty. `frame` is the
## process frame it was ANNOUNCED on: results announced on one frame are one action's results.
var _shown: Dictionary = {}
## Waiting notices, each lane in arrival (`seq`) order. Nothing in a lane is ever dropped.
var _immediate_lane: Array[Dictionary] = []
var _passive_lane: Array[Dictionary] = []
var _notice_seq: int = 0
var _backlog_overflowed: bool = false
## The banner gave way to an answer and resumes, for `_banner_hold` seconds, when the band frees.
var _banner_pending: bool = false
var _banner_hold: float = 0.0
var _breakthrough_banner: VBoxContainer
var _breakthrough_title: Label
var _breakthrough_realm: Label
var _breakthrough_timer: Timer
var _breakthrough_realm_key: StringName = &""
var _breakthrough_layer: int = 0
var _breakthrough_changed_realm: bool = false
var _attack_row: UIPromptRow
var _interact_row: UIPromptRow
var _menu_row: UIPromptRow
var _sect_row: UIPromptRow
var _faction_row: UIPromptRow

# Compact sect chip in the identity panel (emblem + name + rank + reputation).
var _sect_emblem: TextureRect
var _sect_name_label: Label
var _sect_rank_label: Label
# The toggleable Sect detail panel (owned here; hidden until the player opens it).
var _sect_panel: SectPanel
# The toggleable Sect Politics panel (Phase 07). Anchored on the opposite side of the screen
# from the sect panel so the player can read membership and politics side by side rather than
# having one cover the other.
var _faction_panel: FactionPanel
# The inventory panel (Phase 13): a MODAL reading surface — while open the HUD holds a UI_MODAL
# input context so the move keys choose a row instead of walking the player.
var _inventory_panel: InventoryPanel
var _inventory_modal: bool = false
## The shop (Phase 17): shown while a `ShopView` says a shop is open; holds a UI_MODAL context.
var _shop_panel: ShopPanel
var _shop_modal: bool = false
## The conversation (Phase 18): shown while a `DialogueView` says one is open; holds a UI_MODAL
## context. While it is open the prompt strip and the technique dock stand down (none of their
## keys act) and the announcement band rides above the box.
var _dialogue_panel: DialoguePanel
var _dialogue_modal: bool = false
var _prompt_strip: Control
var _notice_rest_top: float = 0.0
var _notice_rest_bottom: float = 0.0
## Arguments of the interact prompt's text (a person's prompt names them).
var _interact_label_args: Dictionary = {}
# The skill dock (Phase 15): bottom-centre (D-062), hidden until a technique is learned.
var _skill_dock: SkillDock
var _politics_view: SectPoliticsView = null  # read-only politics view; may be null
var _world_sim_view: WorldSimView = null  # read-only world-sim view (Phase 08); may be null
# The full-rect Control every HUD element hangs off. Held so the safe-area inset can be
# re-applied on a viewport change without rebuilding the HUD.
var _root: Control = null


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	_input = get_node_or_null("/root/InputService")
	_bus = get_node_or_null("/root/EventBus")
	_build_ui()
	if _bus != null and not _bus.is_connected("language_changed", _on_language_changed):
		_bus.connect("language_changed", _on_language_changed)
	_refresh()


func _exit_tree() -> void:
	_hide_dialogue()
	close_inventory()
	_hide_shop()
	# Stop the level-up celebration before the HUD leaves the tree. A map transition or a
	# return to the menu can land mid-effect, and an effect still decaying toward a colour on
	# a node that is being freed is writing `modulate` on a dangling target.
	if _level_up != null and is_instance_valid(_level_up):
		_level_up.cancel()
	if _bus != null and _bus.is_connected("language_changed", _on_language_changed):
		_bus.disconnect("language_changed", _on_language_changed)
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.disconnect(_on_viewport_resized)


func _build_ui() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root = root
	# The HUD must wear the shared theme like the menu does (D-034). A CanvasLayer cannot
	# hold a Theme, so it goes on this root Control and every panel/label below inherits the
	# asset-backed styles AND the text outline that keeps light text readable over map art.
	root.theme = UITheme.build()
	add_child(root)
	# Keep the whole HUD clear of whatever physically covers the window (a phone's notch,
	# rounded corners, a camera cutout — never a desktop dock, see `safe_area_insets`) and
	# re-apply it whenever the viewport changes: a rotation or a window resize changes what is
	# covered, and a HUD that only read it once would leave content under the notch.
	_apply_safe_area()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)

	# --- Top-left: the identity plaque -------------------------------------------
	# One plaque, two tiers: WHO I AM (portrait + name + title) above an ornamental divider,
	# WHO I BELONG TO (sect chip) below it. Before D-041 the sect lines were just two more
	# entries in the same column as the title, so the two kinds of identity blurred together.
	var identity_panel := _panel()
	# Named so a layout assertion can report WHICH plaque is wrong. The reserve test used to
	# print `@PanelContainer@5822=156`, which names nothing a reader can act on.
	identity_panel.name = "IdentityPlaque"
	identity_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	identity_panel.position = Vector2(UIPalette.HUD_MARGIN, UIPalette.HUD_MARGIN)
	root.add_child(identity_panel)

	var identity_body := VBoxContainer.new()
	identity_body.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	identity_panel.add_child(identity_body)

	# Tier 1, WHO I AM: the medallion row, then the realm meter across the plaque's width.
	var identity_tier := VBoxContainer.new()
	identity_tier.name = "IdentityTier"
	identity_tier.add_theme_constant_override("separation", UIPalette.ROW_GAP)
	identity_body.add_child(identity_tier)

	var identity_row := HBoxContainer.new()
	identity_row.name = "IdentityRow"
	# SPACE_SM: the medallion's own ring is the gap's visual edge, so the text sits close to it
	# and the plaque stays clear of the playfield centre (§3c).
	identity_row.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	identity_tier.add_child(identity_row)

	# The identity MEDALLION (D-062): the player's own pixel portrait, rendered by the art
	# pipeline from the SAME model as the sprite on the map, in a lacquer disc under an
	# antique-gold ring. Drawn at 1x with NEAREST — it is pixel art, and resampling a portrait
	# is how the old painted one went soft. The ring is part of the art, so nothing is drawn
	# over it (the old frame overlay existed only because the painted crop had none).
	var portrait_well := Control.new()
	portrait_well.name = "PortraitWell"
	portrait_well.custom_minimum_size = Vector2(UIPalette.MEDALLION_PX, UIPalette.MEDALLION_PX)
	portrait_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity_row.add_child(portrait_well)

	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.texture = UITheme.portrait_texture()
	_portrait.visible = _portrait.texture != null
	portrait_well.add_child(_portrait)

	var identity_text := VBoxContainer.new()
	identity_text.alignment = BoxContainer.ALIGNMENT_CENTER
	identity_text.add_theme_constant_override("separation", UIPalette.ROW_GAP)
	identity_row.add_child(identity_text)

	# The name shares its row with the LEVEL badge (Phase 11). Level belongs here, beside the
	# character's name, because it answers "who am I" at a glance — the phase brief ranks
	# "LEVEL must be easy to identify" first in the HUD hierarchy, and a number tucked under
	# two gauges is not at a glance. It is gold, which in this palette means structure and
	# attainment, and is the hue the XP meter below also uses so the pair reads as one idea.
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	identity_text.add_child(name_row)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_name_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_label)

	_level_label = Label.new()
	_level_label.name = "LevelBadge"
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_level_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_level_label.add_theme_color_override("font_color", UIPalette.GOLD_PRIMARY)
	# A width FLOOR so `Cấp 1` and `Cấp 20` do not resize the plaque as the player levels —
	# a plaque that changes width on a level-up would make the whole HUD twitch.
	_level_label.custom_minimum_size = Vector2(UIPalette.LEVEL_BADGE_MIN_WIDTH, 0)
	# Hidden until a progression view arrives, for the same reason the health gauge is: a
	# badge reading `Cấp 0` for progression nothing owns is worse than no badge.
	_level_label.visible = false
	name_row.add_child(_level_label)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_title_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	identity_text.add_child(_title_label)

	# The health gauge (Phase 09). It appears NOW and not earlier because combat finally owns
	# the value it shows — the UI bible forbids a gauge for state no system owns, since a bar
	# that looks right in a mock and shows nothing real in a build is worse than no bar.
	#
	# Styled by `UITheme.vitals_gauge()`, not here: C18 requires combat UI to use the shared
	# foundation, so the next gauge (mana, cultivation progress, a boss bar) inherits the same
	# look instead of being styled again by whoever adds it.
	_health_gauge = UITheme.vitals_gauge()
	# Hidden until a real value arrives. A gauge sitting at full for health nothing has
	# reported is the same lie as a gauge for a system that does not exist yet.
	_health_gauge.visible = false
	identity_text.add_child(_health_gauge)

	# The XP meter (Phase 11), directly under the health gauge and deliberately SUBORDINATE to
	# it: thinner, and gold where health is jade. Both separations are palette tokens and both
	# matter — the phase brief requires XP not to be confusable with HP, and these two sit one
	# above the other in the same plaque, which is the hardest place to tell two bars apart.
	# The meter also WRITES its value as text ("XP 20 / 45"), so the distinction survives for
	# a player who cannot use the colour at all (`docs/UI_UX_BIBLE.md` §4).
	_xp_meter = UITheme.xp_meter()
	_xp_meter.visible = false
	identity_text.add_child(_xp_meter)

	# The tu vi meter (Phase 12): the SECOND progression axis, in its own row and its own hue,
	# and it writes the realm's name in its value — "Phàm Nhân · 12/30" — so the player reads
	# WHAT they are becoming, not just how full a bar is. Hidden until a cultivation view arrives.
	# FULL PLAQUE WIDTH, under the medallion row (D-062 capture review): in the text column it
	# was ~160px, and "Commanding Heaven 9 · Complete" cannot fit that at a legible size — it
	# spilled past the plaque's edge. The realm is the longest line the plaque writes.
	_cultivation_meter = UITheme.cultivation_meter()
	_cultivation_meter.visible = false
	identity_tier.add_child(_cultivation_meter)

	# The level-up celebration drives the BADGE, not the meter: the meter's job is to be read
	# accurately, and a flashing bar is harder to read, while a badge catching light is
	# exactly the "something happened to me" signal a level-up wants. Presentation-only, and
	# idle (zero per-frame cost) until a level actually changes.
	# The transient level-up announcement. Anchored to the SCREEN CENTRE, deliberately outside
	# every plaque: a label that appears inside the identity plaque would grow it mid-
	# celebration, which both makes the HUD twitch and invalidates `TOP_PLAQUE_RESERVE` for
	# the duration of the effect (a hidden child contributes nothing to a container's minimum
	# size — the exact trap that produced four wrong values for that constant).
	#
	# The centre is also where it MEANS the most: the camera follows the player, so the player
	# is near the middle of the screen, and the announcement lands on them rather than in a
	# corner being reported about them.
	_level_up_banner = Label.new()
	_level_up_banner.name = "LevelUpBanner"
	_level_up_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_up_banner.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_level_up_banner.add_theme_color_override("font_color", UIPalette.GOLD_PRIMARY)
	# BOTTOM-CENTRE, in the band above the prompt strip — not the screen centre.
	#
	# Two capture-found defects led here. Centred, it printed across the player's body, because
	# the camera follows the player. Nudged up from the centre, it still did: the camera is
	# CLAMPED by the map limits, so the player's screen position moves and a fixed offset from
	# the centre just relocates the collision. A band the HUD already reserves cannot collide
	# with anything, at any resolution.
	_level_up_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_level_up_banner.offset_top -= UIPalette.LEVEL_UP_BANNER_BOTTOM_INSET
	_level_up_banner.offset_bottom -= UIPalette.LEVEL_UP_BANNER_BOTTOM_INSET
	_level_up_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_level_up_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_level_up_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_up_banner.visible = false
	root.add_child(_level_up_banner)

	_level_up = LevelUpFeedbackScript.new() as LevelUpFeedback
	_level_up.name = "LevelUpFeedback"
	add_child(_level_up)
	_level_up.bind_target(_level_label)
	_level_up.bind_banner(_level_up_banner)

	# The BREAKTHROUGH announcement (Phase 12): macro scale, so it is larger and holds longer
	# than the level-up banner — and it is two lines, the event and what the player became. It
	# lives in the bottom band like every announcement, one row above the level-up banner so the
	# two can never print over each other, and never over the playfield centre (§3c).
	_breakthrough_banner = VBoxContainer.new()
	_breakthrough_banner.name = "BreakthroughBanner"
	_breakthrough_banner.alignment = BoxContainer.ALIGNMENT_END
	_breakthrough_banner.add_theme_constant_override("separation", 0)
	_breakthrough_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_breakthrough_banner.offset_top -= UIPalette.ANNOUNCE_BOTTOM_INSET
	_breakthrough_banner.offset_bottom -= UIPalette.ANNOUNCE_BOTTOM_INSET
	_breakthrough_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_breakthrough_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_breakthrough_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_breakthrough_banner.visible = false
	root.add_child(_breakthrough_banner)
	_breakthrough_title = Label.new()
	_breakthrough_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_breakthrough_title.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_breakthrough_title.add_theme_color_override("font_color", UIPalette.GOLD_PRIMARY)
	_breakthrough_banner.add_child(_breakthrough_title)
	_breakthrough_realm = Label.new()
	_breakthrough_realm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_breakthrough_realm.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_BUTTON)
	_breakthrough_realm.add_theme_color_override("font_color", UIPalette.CULTIVATION_METER_FILL)
	_breakthrough_banner.add_child(_breakthrough_realm)
	_breakthrough_timer = Timer.new()
	_breakthrough_timer.name = "BreakthroughHold"
	_breakthrough_timer.one_shot = true
	_breakthrough_timer.timeout.connect(_on_breakthrough_timeout)
	add_child(_breakthrough_timer)

	# The NOTICE line: one transient sentence in the same band (knowledge learned, why the
	# cultivate key did nothing). A key press that silently does nothing reads as a bug.
	_notice_label = Label.new()
	_notice_label.name = "HudNotice"
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_notice_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT)
	_notice_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_notice_label.offset_top -= UIPalette.ANNOUNCE_BOTTOM_INSET
	_notice_label.offset_bottom -= UIPalette.ANNOUNCE_BOTTOM_INSET
	_notice_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_label.visible = false
	_notice_rest_top = _notice_label.offset_top
	_notice_rest_bottom = _notice_label.offset_bottom
	root.add_child(_notice_label)
	_notice_timer = Timer.new()
	_notice_timer.name = "NoticeHold"
	_notice_timer.one_shot = true
	_notice_timer.timeout.connect(_on_notice_timeout)
	add_child(_notice_timer)

	# The engraved rule that separates the two identity tiers. Same art as the menu title and
	# the sect panel header, so all three screens read as one design language (D-041).
	identity_body.add_child(_divider_strip())

	# Compact sect chip (Phase 06): emblem + sect name + rank. It now lives in the plaque's
	# SECOND tier (a sibling of the portrait row), not nested beside the character title.
	var sect_chip := HBoxContainer.new()
	sect_chip.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	identity_body.add_child(sect_chip)

	_sect_emblem = TextureRect.new()
	# Named so the tier-separation test can identify it structurally. It used to be found by
	# "the only TextureRect in the plaque", which stopped being true the moment the identity
	# row gained a painted portrait (D-044) — a name is the stable marker.
	_sect_emblem.name = "SectEmblem"
	_sect_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sect_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# EXPAND_IGNORE_SIZE is required for `custom_minimum_size` to actually govern: the
	# default EXPAND_KEEP_SIZE makes a TextureRect report its full texture as its minimum,
	# so the chip would grow to the emblem's native size and shove the layout around (D-034).
	_sect_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sect_emblem.custom_minimum_size = Vector2(SECT_EMBLEM_PX, SECT_EMBLEM_PX)
	_sect_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sect_chip.add_child(_sect_emblem)

	var sect_text := VBoxContainer.new()
	sect_text.add_theme_constant_override("separation", UIPalette.ROW_GAP)
	sect_chip.add_child(sect_text)

	_sect_name_label = Label.new()
	_sect_name_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_sect_name_label.add_theme_color_override("font_color", UIPalette.COLOR_TITLE)
	sect_text.add_child(_sect_name_label)

	_sect_rank_label = Label.new()
	_sect_rank_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_sect_rank_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	sect_text.add_child(_sect_rank_label)

	# --- Top-right: the map-name plaque -------------------------------------------
	# Stays top-RIGHT (a permanent top-centre banner would sit over the playfield), but it is
	# now a proper plaque instead of a shrink-wrapped chip: a minimum width so the place name
	# is centred in a stable frame, and the same ornamental rule under it. The place name is
	# the player's sense of WHERE they are, which the UI bible ranks as primary orientation
	# information — it should look authored, not like a debug readout.
	var map_panel := _panel()
	map_panel.name = "MapPlaque"
	map_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	map_panel.position = Vector2(-UIPalette.HUD_MARGIN, UIPalette.HUD_MARGIN)
	map_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_panel.custom_minimum_size = Vector2(UIPalette.HUD_MAP_PANEL_WIDTH, 0)
	root.add_child(map_panel)

	var map_body := VBoxContainer.new()
	map_body.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	map_panel.add_child(map_body)

	_map_label = Label.new()
	_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_map_label.add_theme_color_override("font_color", UIPalette.COLOR_TITLE)
	map_body.add_child(_map_label)

	map_body.add_child(_divider_strip())

	# World time + the last thing the world did on its own (Phase 08). It belongs UNDER the
	# place name because both answer orientation questions — "where am I" and "when is it" —
	# and the UI bible ranks orientation as primary. Two muted hint lines, not a panel of its
	# own: the player should be able to notice that the world moved without them
	# (`SOCIAL_DESIGN.md` §7) without a readout competing with the playfield for attention.
	_world_date_label = Label.new()
	_world_date_label.name = "WorldDate"
	_world_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world_date_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_world_date_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	map_body.add_child(_world_date_label)

	_world_event_label = Label.new()
	_world_event_label.name = "WorldEvent"
	_world_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world_event_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_world_event_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	_world_event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# +40% string length for vi↔en must not clip (`docs/UI_UX_BIBLE.md`), and this line is the
	# longest thing in a narrow plaque, so it wraps rather than widening the panel.
	_world_event_label.custom_minimum_size = Vector2(UIPalette.HUD_MAP_PANEL_WIDTH, 0)
	# CAPPED, so the plaque has a maximum height at all. This is the only label in a top
	# plaque sized by a sentence, and an unbounded plaque makes `TOP_PLAQUE_RESERVE`
	# unknowable — which is how the side panels came to overlap it. Two lines absorbs the
	# +40% vi<->en growth the UI bible requires; past that the line trims, because growing
	# over the playfield is worse than losing the tail of a passive hint.
	_world_event_label.max_lines_visible = UIPalette.HUD_WORLD_EVENT_MAX_LINES
	_world_event_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	map_body.add_child(_world_event_label)

	# --- Top-centre: the combat target plaque (Phase 10) --------------------------
	#
	# Between the two top plaques, which is the one region of the top strip nothing owns, and
	# centred because the thing you are FIGHTING belongs in the middle of your attention —
	# not tucked into a corner with your own identity or the date.
	#
	# Hidden until there is a target, so "not fighting anything" and "a target at 0 HP" can
	# never look the same. Built from the same `_panel()` as every other plaque, so it needs
	# no styling of its own (C18).
	_target_panel = _panel()
	_target_panel.name = "TargetPlaque"
	_target_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_panel.position = Vector2(0, UIPalette.HUD_MARGIN)
	_target_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_target_panel.custom_minimum_size = Vector2(UIPalette.HUD_MAP_PANEL_WIDTH, 0)
	_target_panel.visible = false
	root.add_child(_target_panel)

	var target_body := VBoxContainer.new()
	target_body.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	_target_panel.add_child(target_body)

	_target_name_label = Label.new()
	_target_name_label.name = "TargetName"
	_target_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_name_label.add_theme_font_size_override(
		"font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_target_name_label.add_theme_color_override("font_color", UIPalette.COLOR_TITLE)
	target_body.add_child(_target_name_label)

	_target_threat_label = Label.new()
	_target_threat_label.name = "TargetThreat"
	_target_threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_threat_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_target_threat_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	target_body.add_child(_target_threat_label)

	# The SAME gauge factory the player's health uses, so target health and player health are
	# read the same way. A second gauge styled differently would make the player learn two
	# readouts for one concept.
	_target_gauge = UITheme.vitals_gauge()
	target_body.add_child(_target_gauge)

	# One-shot timer that retires the plaque after a kill. A `Timer` rather than a `_process`
	# countdown: it costs nothing while stopped, which matters on a node that exists for the
	# whole session and is used for a second or two per fight.
	_target_linger = Timer.new()
	_target_linger.name = "TargetLinger"
	_target_linger.one_shot = true
	_target_linger.timeout.connect(_on_target_linger_timeout)
	_target_panel.add_child(_target_linger)

	# --- Bottom-left: control-prompt strip (graphic key badges) -------------------
	# On the quiet HINT BAND, not in a framed plaque (D-057): the prompts are the least
	# important text on screen, so they get the least weight that keeps them legible, and the
	# gold-cornered frame is kept for what the player actually tracks.
	var prompt_panel := _hint_band()
	prompt_panel.name = "PromptStrip"
	prompt_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	prompt_panel.position = Vector2(UIPalette.HUD_MARGIN, -UIPalette.HUD_MARGIN)
	prompt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Grow RIGHT from the left edge but never past it; `grow_horizontal` defaults to END,
	# which is what we want here — the explicit set documents that the row is bottom-LEFT
	# anchored and is why the prompts must stay narrow (one badge + one short label each).
	prompt_panel.grow_horizontal = Control.GROW_DIRECTION_END
	root.add_child(prompt_panel)
	_prompt_strip = prompt_panel

	var prompt_box := HBoxContainer.new()
	prompt_box.add_theme_constant_override("separation", UIPalette.SPACE_LG)
	prompt_panel.add_child(prompt_box)

	# ATTACK LEADS THE STRIP (D-055-G). It is the only verb here that changes the WORLD rather
	# than opening a panel, and it shipped in Phase 11 with no prompt at all — so the game's
	# central action was the one thing a player could not discover from the screen while
	# `T Sect` / `Y Politics` / `Esc Menu` were all advertised. Leftmost because the strip is
	# read left-to-right from the screen corner.
	_attack_row = PromptRowScript.new() as UIPromptRow
	_attack_row.name = "AttackPrompt"
	prompt_box.add_child(_attack_row)

	_interact_row = PromptRowScript.new() as UIPromptRow
	_interact_row.name = "InteractPrompt"
	prompt_box.add_child(_interact_row)

	# CONTEXTUAL like interact (Phase 12): shown only where cultivating means something — at a
	# vein, or while seated — and its verb says what the key will do NOW.
	_cultivate_row = PromptRowScript.new() as UIPromptRow
	_cultivate_row.name = "CultivatePrompt"
	_cultivate_row.visible = false
	prompt_box.add_child(_cultivate_row)

	# CONTEXTUAL too (Phase 16): absent until there is a pet to call, and its verb says what
	# the key will do NOW (call it, send it away) or why it will not (it is recovering).
	_pet_row = PromptRowScript.new() as UIPromptRow
	_pet_row.name = "PetPrompt"
	_pet_row.visible = false
	prompt_box.add_child(_pet_row)

	# All five rows are NAMED. Two were already, because a test looks them up; the other three
	# were anonymous, so a failure in the strip could only report Godot's generated node name
	# and could not say WHICH prompt was wrong (D-055 follow-up).
	_sect_row = PromptRowScript.new() as UIPromptRow
	_sect_row.name = "SectPrompt"
	prompt_box.add_child(_sect_row)

	_faction_row = PromptRowScript.new() as UIPromptRow
	_faction_row.name = "PoliticsPrompt"
	prompt_box.add_child(_faction_row)

	_menu_row = PromptRowScript.new() as UIPromptRow
	_menu_row.name = "MenuPrompt"
	prompt_box.add_child(_menu_row)

	# --- Sect detail panel (Phase 06): hidden until the player presses `sect_panel` ----
	# Anchored on the PANEL ITSELF, directly under `root`. The previous version wrapped it in
	# an empty size-0 Control and set `grow_horizontal = BEGIN` on that WRAPPER; growth
	# direction does not propagate to children, so the panel still grew END (rightwards) from
	# the right edge and ~95% of it sat outside the viewport — only a sliver of its jade frame
	# was visible, which read as "pressing T does nothing" (D-034).
	_sect_panel = SectPanelScript.new() as SectPanel
	_bound_side_panel(_sect_panel, false)
	_sect_panel.visible = false
	root.add_child(_sect_panel)

	# --- Sect Politics panel (Phase 07): hidden until the player presses `faction_panel` ---
	# Anchored CENTER_LEFT, opposite the sect panel, and growing END (rightwards) from the
	# left edge. Anchors and growth go on the panel ITSELF, never on a wrapper: growth does
	# not propagate to children, which is what pushed the Phase-06 sect panel off-screen
	# (D-034). Both panels may be open at once by design — membership and politics are two
	# halves of one question.
	_inventory_panel = InventoryPanel.new()
	_inventory_panel.name = "InventoryPanel"
	_bound_side_panel(_inventory_panel, true)
	_inventory_panel.visible = false
	_inventory_panel.use_requested.connect(func(item_id: StringName, equipped: bool) -> void:
		inventory_use_requested.emit(item_id, equipped))
	root.add_child(_inventory_panel)

	# The shop (Phase 17): one reading surface at a time, in the side-panel frame. On the RIGHT:
	# the keeper stands beside the player, and a camera clamped at a map edge puts them left
	# of centre as often as not — the right column is the one that never covers the two people
	# who are talking (seen in the first capture, where a left panel hid the keeper).
	_shop_panel = ShopPanel.new()
	_shop_panel.name = "ShopPanel"
	_bound_side_panel(_shop_panel, false)
	_shop_panel.visible = false
	_shop_panel.buy_requested.connect(func(item_id: StringName) -> void:
		shop_buy_requested.emit(item_id))
	_shop_panel.sell_requested.connect(func(item_id: StringName) -> void:
		shop_sell_requested.emit(item_id))
	root.add_child(_shop_panel)

	# The conversation (Phase 18): ONE bounded box at the bottom centre — below the playfield's
	# clear zone, where the two people talking are never covered. Its height is its content.
	_dialogue_panel = DialoguePanel.new()
	_dialogue_panel.name = "DialoguePanel"
	_dialogue_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dialogue_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dialogue_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dialogue_panel.position = Vector2(0, -UIPalette.HUD_MARGIN)
	_dialogue_panel.visible = false
	_dialogue_panel.choice_requested.connect(func(node_id: StringName, id: StringName) -> void:
		dialogue_choice_requested.emit(node_id, id))
	_dialogue_panel.advance_requested.connect(func() -> void:
		dialogue_advance_requested.emit())
	_dialogue_panel.resized.connect(_place_notice_band)
	root.add_child(_dialogue_panel)

	# The technique dock sits BOTTOM-CENTRE (D-062): the composition every action game reads —
	# the player's hands are under the player. It is below the playfield's clear zone and
	# below the announcement band, so it never covers the fight or a notice.
	_skill_dock = SkillDock.new()
	_skill_dock.name = "SkillDock"
	_skill_dock.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_skill_dock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_skill_dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skill_dock.position = Vector2(0, -UIPalette.HUD_MARGIN)
	root.add_child(_skill_dock)

	_faction_panel = FactionPanelScript.new() as FactionPanel
	_bound_side_panel(_faction_panel, true)
	_faction_panel.visible = false
	root.add_child(_faction_panel)


## Anchor a toggleable side panel as a BOUNDED BOX defined by the screen, not by its content.
##
## This is the fix for the panel that rendered without a frame and buried the control prompts.
## The old version anchored from the vertical centre with `grow_vertical = BOTH` and let the
## panel take its content's minimum size, so a long list grew past the top AND bottom of the
## viewport: the 9-slice frame is drawn at the panel's edges, and those edges were off-screen.
##
## Now all four sides are pinned to screen anchors, so the panel's height is
## `screen - margins - reserved prompt strip` at EVERY resolution and it is structurally
## incapable of overflowing or of entering the bottom strip the prompts own. Content longer
## than the box scrolls inside it (each panel owns a ScrollContainer) instead of escaping it.
func _bound_side_panel(panel: Control, on_left: bool) -> void:
	# LEFT_WIDE / RIGHT_WIDE pin top+bottom to the screen and give a full-height column; the
	# explicit offsets below then inset it. Using the and_offsets variant for the same reason
	# the menu needed it: the plain preset would preserve the current (minimum) rect.
	panel.set_anchors_and_offsets_preset(
		Control.PRESET_LEFT_WIDE if on_left else Control.PRESET_RIGHT_WIDE)
	if on_left:
		panel.offset_left = UIPalette.HUD_MARGIN
		panel.offset_right = UIPalette.HUD_MARGIN + UIPalette.SIDE_PANEL_WIDTH
	else:
		panel.offset_left = -(UIPalette.HUD_MARGIN + UIPalette.SIDE_PANEL_WIDTH)
		panel.offset_right = -UIPalette.HUD_MARGIN
	# Start BELOW the top plaque strip, not at the screen margin (D-050). A full-height side
	# panel anchored at `HUD_MARGIN` occupies the same region as the top-right map/world
	# plaque, and the sect panel was covering the place name completely — visible the moment
	# the panel was captured open, invisible to every test. Reserving the strip by name makes
	# "a side panel must not cover the plaque" arithmetic, the same way
	# `PROMPT_STRIP_RESERVE` protects the prompt row at the bottom.
	panel.offset_top = UIPalette.HUD_MARGIN + UIPalette.TOP_PLAQUE_RESERVE
	# Stop short of the bottom so the control prompts are never covered (the reserved strip).
	panel.offset_bottom = -(UIPalette.HUD_MARGIN + UIPalette.PROMPT_STRIP_RESERVE)
	# A bounded box must not be re-expanded by its own minimum size.
	panel.grow_horizontal = Control.GROW_DIRECTION_END if on_left \
		else Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_END


## Inset the whole HUD by whatever PHYSICALLY covers the window (notch, rounded corners,
## camera cutout). The arithmetic lives in `safe_area_insets` so it can be tested without a
## real display.
func _apply_safe_area() -> void:
	if _root == null:
		return
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vp := get_viewport()
	if vp == null:
		return
	var insets := safe_area_insets(OS.has_feature("mobile"),
		Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size()),
		DisplayServer.get_display_safe_area(), vp.get_visible_rect().size)
	_root.offset_left = insets.x
	_root.offset_top = insets.y
	_root.offset_right = -insets.z
	_root.offset_bottom = -insets.w


## How far the HUD must inset each edge, as `Vector4(left, top, right, bottom)` in CANVAS units.
##
## DESKTOP IS ALWAYS ZERO, and that is a fix, not a shortcut (D-057). On a desktop OS
## `get_display_safe_area()` is the WORK AREA — the screen minus docks, panels and taskbars, in
## screen coordinates — not a notch. Applying it as an inset shifted the whole HUD by the size
## of the OS chrome wherever the window actually was: measured on the dev machine, a window at
## (353, 196) wholly inside a work area starting at (66, 32) still had its HUD pushed 66px right
## and 32px down, so the left plaques sat 85px from the edge and the right ones 18px. On Windows
## the same arithmetic lifts the prompt strip by the taskbar height. A desktop window manager
## never draws over the game's own content, so there is nothing to inset for.
##
## On MOBILE the safe area is the real hazard, and only the part of it that overlaps the WINDOW
## matters — a split-screen window below a notch is not covered by it. The overlap is in screen
## pixels and the HUD lives in the stretched canvas, so it is converted through the
## canvas/window ratio; without that the inset is wrong by exactly the stretch factor.
static func safe_area_insets(is_mobile: bool, window_rect: Rect2i, safe_rect: Rect2i,
		canvas_size: Vector2) -> Vector4:
	if not is_mobile:
		return Vector4.ZERO
	if window_rect.size.x <= 0 or window_rect.size.y <= 0 \
			or safe_rect.size.x <= 0 or safe_rect.size.y <= 0:
		return Vector4.ZERO
	var covered_left := clampi(safe_rect.position.x - window_rect.position.x, 0,
		window_rect.size.x)
	var covered_top := clampi(safe_rect.position.y - window_rect.position.y, 0,
		window_rect.size.y)
	var covered_right := clampi(window_rect.end.x - safe_rect.end.x, 0, window_rect.size.x)
	var covered_bottom := clampi(window_rect.end.y - safe_rect.end.y, 0, window_rect.size.y)
	var sx := canvas_size.x / float(window_rect.size.x)
	var sy := canvas_size.y / float(window_rect.size.y)
	return Vector4(covered_left * sx, covered_top * sy, covered_right * sx,
		covered_bottom * sy)


func _on_viewport_resized() -> void:
	_apply_safe_area()


# --- Builders ----------------------------------------------------------------

## A framed HUD panel wearing the shared 9-slice panel style — the top rung of the weight
## ladder, for what the player tracks.
func _panel() -> PanelContainer:
	return _surface(UITheme.panel_stylebox())


## An unframed container on the quiet hint band (D-057 — the bottom rung of the weight ladder).
func _hint_band() -> PanelContainer:
	return _surface(UITheme.hint_band_stylebox())


## A HUD container wearing `style`. Mouse-transparent: the HUD never eats a click meant for
## the world.
func _surface(style: StyleBox) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A thin ornamental rule, used to separate tiers inside a plaque (D-041).
##
## `STRETCH_SCALE` + `size_flags_horizontal = EXPAND_FILL` makes the strip span whatever width
## its parent plaque settles at, so it keeps working when a longer localized name widens the
## panel (+40% string budget) instead of being authored for one screenshot width. It is a
## plain `TextureRect`, not a NinePatchRect: the divider is DECOR with no interior to protect,
## and scaling a 136x21 strip along one axis is exactly what the art is for. If the texture is
## missing the node simply draws nothing — the layout gap stays, so nothing jumps.
## Delegates to the ONE divider factory (D-050). It used to build its own `TextureRect` with
## its own filter/stretch/size, and so did the main menu — duplicated styling that had already
## produced a visible bug (the stretched jade divider read as a progress bar in every panel
## header). The HUD now asks the theme, like it asks for every other style.
func _divider_strip() -> TextureRect:
	return UITheme.ornament_divider()


# --- Owner-pushed view state -------------------------------------------------

## Set the character identity to display (name + optional title localization keys). Pass the
## authoritative CharacterState's keys; the HUD resolves them through Localization. A null
## state clears the plate (e.g. before the player exists).
func set_character(state: CharacterState) -> void:
	if state == null:
		_name_key = &""
		_title_key = &""
	else:
		_name_key = state.name_key
		_title_key = state.title_key
	_refresh()


## Push the player's health into the gauge (Phase 09). Called by whoever connects the player's
## `health_changed` signal — the HUD never reads a HealthComponent itself, so it stays a view.
##
## A non-positive maximum HIDES the gauge instead of showing an empty one: "no health has been
## reported" and "this character is at 0 HP" are different states, and rendering them the same
## way would make a wiring failure look like a death.
func set_health(current: int, maximum: int) -> void:
	if _health_gauge == null:
		return
	if maximum <= 0:
		_health_gauge.visible = false
		return
	_health_gauge.visible = true
	UITheme.set_gauge_value(_health_gauge, current, maximum)


## Is the health gauge currently shown? (for tests — the gauge's visibility IS its contract.)
func is_health_gauge_visible() -> bool:
	return _health_gauge != null and _health_gauge.visible


## Push the player's read-only level/XP view (Phase 11). Pushed by the owner (MapBase, fed by
## WorldRuntime → ProgressionRuntime) on map arrival and on every XP change — never polled.
##
## An unavailable view HIDES the badge and the meter rather than blanking them: "no
## progression session" and "a fresh character at level 1 with no XP" are different states,
## and rendering them the same way would make a wiring failure look like a new game.
func set_progression_view(view: ProgressionView) -> void:
	_progression_view = view
	if _level_label == null or _xp_meter == null:
		return
	var available := view != null and view.available
	_level_label.visible = available
	_xp_meter.visible = available
	if not available:
		return
	_refresh_progression()


## Play the one-shot level-up celebration. Called by the owner when `level_changed` fires.
##
## The HUD does not decide WHEN a level-up happened — it is told. It only decides what one
## looks like, which is the division `03-architecture.md` requires: the gameplay layer reports
## the event and owns no presentation decision.
func celebrate_level_up(level: int) -> void:
	if _level_up_banner != null:
		_level_up_banner.text = _text_args("UI_HUD_LEVEL_UP", {"level": level})
	if _level_up != null and is_instance_valid(_level_up):
		_level_up.celebrate(level)


## Is the progression row shown? (for tests — its visibility IS the contract.)
func is_progression_visible() -> bool:
	return _level_label != null and _level_label.visible


## The level-up effect, so a test can drive its clock deterministically.
func level_up_feedback() -> LevelUpFeedback:
	return _level_up


## Render the level badge + XP meter from the cached view.
##
## Separate from `set_progression_view` so a LANGUAGE CHANGE re-renders the existing numbers
## without the progression session needing to push again — the same reason the target plaque
## and the world-sim lines each have their own refresh.
func _refresh_progression() -> void:
	if _level_label == null or _xp_meter == null:
		return
	if _progression_view == null or not _progression_view.available:
		return
	_level_label.text = _text_args("UI_HUD_LEVEL", {"level": _progression_view.level})
	var text := ""
	if _progression_view.at_ceiling:
		text = _text("UI_HUD_XP_COMPLETE")
	else:
		text = _text_args("UI_HUD_XP_PROGRESS", {
			"into": _progression_view.xp_into_level,
			"cost": _progression_view.xp_for_next,
		})
	UITheme.set_xp_meter_value(_xp_meter, _progression_view.xp_into_level,
		_progression_view.xp_for_next, _progression_view.at_ceiling, text)


## Show what the player is fighting (Phase 10). A null or empty view HIDES the plaque.
##
## Pushed by the combat session when a target's health changes or it dies — never polled, so
## the HUD does no per-frame work (`05-performance-testing.md`). The view is cached so a
## language change can re-resolve its keys without the session pushing again.
func set_target_view(view: CombatTargetView) -> void:
	var engaging := view != null and view.has_target and not view.is_dead
	# COMBAT TAKES THE SCREEN (D-057B, `UI_UX_BIBLE.md` §3c). The side panels are reading
	# surfaces that cover a third of the playfield each; a fight that starts behind one is a
	# fight the player cannot see. So the moment a LIVE target is engaged — the transition, not
	# every health update — any open side panel closes. A panel the player re-opens mid-fight
	# stays open: that is a choice, and the HUD does not fight the player for it.
	if engaging and not _engaged:
		_close_side_panels()
	_engaged = engaging
	_target_view = view
	if _target_panel == null:
		return
	if view == null or not view.has_target:
		_target_panel.visible = false
		_target_linger.stop()
		return
	_target_panel.visible = true
	UITheme.set_gauge_value(_target_gauge, view.current_health, view.max_health)
	_refresh_target_text()
	# A DEAD target lingers, then goes. Long enough to read what you killed, short enough that
	# the plaque is not still advertising a corpse minutes later. A live target cancels the
	# timer, so taking a second creature's attention keeps the panel up.
	if view.is_dead:
		_target_linger.start(UIPalette.TARGET_PLAQUE_LINGER)
	else:
		_target_linger.stop()


## The dead target has been on screen long enough: retire the plaque.
func _on_target_linger_timeout() -> void:
	if _target_panel != null:
		_target_panel.visible = false


## Is the target plaque shown? (for tests — its visibility IS the contract.)
func is_target_panel_visible() -> bool:
	return _target_panel != null and _target_panel.visible


## Resolve the target's localization keys. Separate from `set_target_view` so a language change
## re-renders the existing target instead of needing the combat session to re-push it.
func _refresh_target_text() -> void:
	if _target_view == null or not _target_view.has_target or _loc == null:
		return
	_target_name_label.text = _resolve(_target_view.name_key)
	# The second row states the target's CONDITION. Alive, that is its threat rating. Dead, it
	# says so (D-057): the rating describes a live danger, so leaving it over a corpse reads as
	# the UI not having noticed — and blanking it, as this used to, left an empty row between
	# the name and the gauge for the whole linger, a gap that read as a broken layout in every
	# kill capture. "Defeated" is the consequence the player just caused, in the one place they
	# are already looking. A live target with no authored rating has no row at all.
	if _target_view.is_dead:
		_target_threat_label.text = _text("UI_HUD_TARGET_DEFEATED")
		_target_threat_label.visible = true
	elif _target_view.threat_key == &"":
		_target_threat_label.visible = false
	else:
		_target_threat_label.text = _resolve(_target_view.threat_key)
		_target_threat_label.visible = true


## Set the current map's name localization key.
func set_map_name(name_key: StringName) -> void:
	_map_name_key = name_key
	_refresh()


## Whether the player can currently interact with an exit (drives the interact prompt).
func set_interact_available(available: bool,
		label_key: StringName = &"UI_HUD_INTERACT_ACTION", label_args: Dictionary = {}) -> void:
	if _interact_available == available and _interact_label_key == label_key \
			and _interact_label_args == label_args:
		return
	_interact_available = available
	_interact_label_key = label_key
	_interact_label_args = label_args.duplicate()
	_refresh()


## Push the player's cảnh giới view (Phase 12). Event-driven: the cultivation runtime announces
## a change and `WorldRuntime` rebuilds and pushes — the HUD never polls.
func set_cultivation_view(view: CultivationView) -> void:
	_cultivation_view = view
	_refresh()


func is_cultivation_visible() -> bool:
	return _cultivation_meter != null and _cultivation_meter.visible


## PASSIVE: what happened around the player. Waits its turn behind whatever holds the band, in
## arrival order, and is never dropped. Stored as a KEY + args, so a language change re-renders
## it instead of leaving the old language on screen.
func announce(text_key: StringName, args: Dictionary = {}) -> void:
	_enqueue_notice(NOTICE_PASSIVE, text_key, args)


## RESULT: what the player's own action achieved. Visible on the frame it is announced.
func announce_result(text_key: StringName, args: Dictionary = {}) -> void:
	_enqueue_notice(NOTICE_RESULT, text_key, args)


## ANSWER: why the player's action did not happen. Visible on the frame it is announced.
func announce_answer(text_key: StringName, args: Dictionary = {}) -> void:
	_enqueue_notice(NOTICE_ANSWER, text_key, args)


func notice_text() -> String:
	return _notice_label.text if _notice_label != null and _notice_label.visible else ""


## The kind of the notice on screen (`NOTICE_*`), or &"" when the slot shows none.
func notice_kind() -> StringName:
	return StringName(_shown.get("kind", &""))


## The stable identity of the notice on screen (its enqueue sequence number), or 0 when
## the slot shows none. Two notice instances with identical kind and text have different
## seq values — the playtest uses this to record each shown instance exactly once.
func notice_seq() -> int:
	return int(_shown.get("seq", 0))


## What waits for the slot, in the order it will be shown: the immediate lane, the paused
## breakthrough banner (`&"<breakthrough>"`), then the passive lane. For tests and the playtest.
func pending_notice_keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in _immediate_lane:
		out.append(StringName(entry["key"]))
	if _banner_pending:
		out.append(&"<breakthrough>")
	for entry in _passive_lane:
		out.append(StringName(entry["key"]))
	return out


## True once the backlog passed `UIPalette.HUD_NOTICE_BACKLOG_GUARD` (a producer bug, reported).
func notice_backlog_overflowed() -> bool:
	return _backlog_overflowed


func _enqueue_notice(kind: StringName, text_key: StringName, args: Dictionary) -> void:
	if _notice_label == null:
		return
	_notice_seq += 1
	var entry := {"seq": _notice_seq, "kind": kind, "key": text_key, "args": args,
		"hold": UIPalette.HUD_NOTICE_SECONDS, "frame": Engine.get_process_frames()}
	if kind == NOTICE_PASSIVE:
		if _band_is_free():
			_present_notice(entry)
		else:
			_insert_in_order(_passive_lane, entry)
			_check_backlog()
		return
	if _is_immediate(_shown) and _same_notice(_shown, entry):
		# The same answer to the same press again: refresh it, never print it twice.
		_shown["hold"] = UIPalette.HUD_NOTICE_SECONDS
		_notice_timer.start(UIPalette.HUD_NOTICE_SECONDS)
		return
	for waiting in _immediate_lane:
		if _same_notice(waiting, entry):
			if kind == NOTICE_ANSWER and int(waiting["frame"]) != int(entry["frame"]):
				# A new action's ANSWER, not a duplicate of the waiting one: the stale
				# copy must not suppress it. Fall through to supersede it below.
				break
			return  # already waiting its turn
	if _is_immediate(_shown) and int(_shown["frame"]) == int(entry["frame"]):
		# Another result of the SAME action (a stele that teaches two things): in order, after it.
		_insert_in_order(_immediate_lane, entry)
		_check_backlog()
		return
	# A new action's answer takes the slot NOW. An answer still waiting from an older action is
	# stale (the player has acted since); everything else that gives way is kept.
	var kept: Array[Dictionary] = []
	for waiting in _immediate_lane:
		if waiting["kind"] != NOTICE_ANSWER:
			kept.append(waiting)
	_immediate_lane = kept
	_pause_banner()
	_interrupt_shown()
	_present_notice(entry)


## The MACRO announcement of a breakthrough: the event, and the realm reached. It outranks a
## passive notice (which steps aside and resumes) and waits for an answer already on screen.
func celebrate_breakthrough(realm_name_key: StringName, layer: int, changed_realm: bool) -> void:
	if _breakthrough_banner == null:
		return
	_breakthrough_realm_key = realm_name_key
	_breakthrough_layer = layer
	_breakthrough_changed_realm = changed_realm
	_refresh_breakthrough_text()
	if _is_immediate(_shown):
		_banner_pending = true
		_banner_hold = UIPalette.BREAKTHROUGH_BANNER_SECONDS
		return
	_interrupt_shown()
	_show_banner(UIPalette.BREAKTHROUGH_BANNER_SECONDS)


func is_breakthrough_banner_visible() -> bool:
	return _breakthrough_banner != null and _breakthrough_banner.visible


## The banner gave way to an answer and will resume (for tests and the playtest).
func is_breakthrough_pending() -> bool:
	return _banner_pending


func _on_breakthrough_timeout() -> void:
	if _breakthrough_banner == null:
		return
	_breakthrough_banner.visible = false
	_advance_band()


func _on_notice_timeout() -> void:
	if _notice_label == null:
		return
	_shown = {}
	_notice_label.visible = false
	_advance_band()


## The slot is free: the next thing in priority order takes it.
func _advance_band() -> void:
	if not _shown.is_empty() or _breakthrough_banner.visible:
		return
	if not _immediate_lane.is_empty():
		_present_notice(_immediate_lane.pop_front())
	elif _banner_pending:
		_show_banner(_banner_hold)
	elif not _passive_lane.is_empty():
		_present_notice(_passive_lane.pop_front())


func _band_is_free() -> bool:
	return _shown.is_empty() and not _breakthrough_banner.visible and not _banner_pending \
		and _immediate_lane.is_empty() and _passive_lane.is_empty()


func _present_notice(entry: Dictionary) -> void:
	_shown = entry
	_refresh_notice()
	_notice_label.visible = true
	_notice_timer.start(float(entry["hold"]))


func _show_banner(hold: float) -> void:
	_banner_pending = false
	_breakthrough_banner.visible = true
	_breakthrough_timer.start(hold)


## The banner steps aside for an answer: PAUSED with the time it had left, never dropped.
func _pause_banner() -> void:
	if not _breakthrough_banner.visible:
		return
	_banner_hold = maxf(_breakthrough_timer.time_left, UIPalette.HUD_NOTICE_RESUME_MIN_SECONDS)
	_breakthrough_timer.stop()
	_breakthrough_banner.visible = false
	_banner_pending = true


## The notice on screen steps aside. A RESULT or PASSIVE goes back to its lane, in its original
## order, for the time it had left; an ANSWER is superseded (the player has acted again).
func _interrupt_shown() -> void:
	if _shown.is_empty():
		return
	var interrupted := _shown
	_shown = {}
	var left := _notice_timer.time_left
	_notice_timer.stop()
	_notice_label.visible = false
	if interrupted["kind"] == NOTICE_ANSWER:
		return
	interrupted["hold"] = maxf(left, UIPalette.HUD_NOTICE_RESUME_MIN_SECONDS)
	_insert_in_order(_immediate_lane if interrupted["kind"] == NOTICE_RESULT else _passive_lane,
		interrupted)


static func _insert_in_order(lane: Array[Dictionary], entry: Dictionary) -> void:
	var at := lane.size()
	while at > 0 and int(lane[at - 1]["seq"]) > int(entry["seq"]):
		at -= 1
	lane.insert(at, entry)


static func _is_immediate(entry: Dictionary) -> bool:
	var kind: StringName = entry.get("kind", &"")
	return kind == NOTICE_RESULT or kind == NOTICE_ANSWER


static func _same_notice(a: Dictionary, b: Dictionary) -> bool:
	return a["kind"] == b["kind"] and a["key"] == b["key"] and a["args"] == b["args"]


## Fail LOUDLY, drop nothing: a backlog past the guard is a producer announcing in a loop.
func _check_backlog() -> void:
	var waiting := _immediate_lane.size() + _passive_lane.size()
	if waiting <= UIPalette.HUD_NOTICE_BACKLOG_GUARD:
		return
	if not _backlog_overflowed:
		push_error(("[hud] %d notices wait for the bottom band, past the guard of %d: a "
			+ "producer is announcing in a loop. Nothing was dropped; find the producer.")
			% [waiting, UIPalette.HUD_NOTICE_BACKLOG_GUARD])
	_backlog_overflowed = true


func _refresh_notice() -> void:
	if _notice_label == null or _shown.is_empty():
		return
	var notice_key := StringName(_shown["key"])
	var args := (_shown["args"] as Dictionary).duplicate()
	# The satchel key is named where items are gained, so the bag is discoverable without a
	# seventh permanent prompt in the strip.
	if not args.is_empty() and not args.has("key"):
		args["key"] = _display_label(INVENTORY_ACTION)
	elif typeof(args.get("key")) == TYPE_STRING_NAME:
		args["key"] = _display_label(args["key"])  # an ACTION named by the notice (a skill key)
	# A knowledge or realm name arrives as a KEY; resolve it in the current language.
	for k: Variant in args:
		if typeof(args[k]) == TYPE_STRING_NAME:
			args[k] = _resolve(args[k])
	_notice_label.text = _text_args(String(notice_key), args) if not args.is_empty() \
		else _text(String(notice_key))


func _refresh_breakthrough_text() -> void:
	if _breakthrough_title == null or _breakthrough_realm_key == &"":
		return
	_breakthrough_title.text = _text("UI_HUD_BREAKTHROUGH_REALM" if _breakthrough_changed_realm
		else "UI_HUD_BREAKTHROUGH_LAYER")
	_breakthrough_realm.text = _realm_text(_breakthrough_realm_key, _breakthrough_layer)


## "Phàm Nhân", "Hậu Thiên tầng 3": a realm and, when it has layers, the layer.
func _realm_text(realm_name_key: StringName, layer: int) -> String:
	var realm := _resolve(realm_name_key)
	if layer <= 0:
		return realm
	return _text_args("UI_HUD_REALM_LAYER", {"realm": realm, "layer": layer})


func _refresh_cultivation() -> void:
	if _cultivation_meter == null:
		return
	var view := _cultivation_view
	if view == null or not view.available:
		_cultivation_meter.visible = false
		return
	_cultivation_meter.visible = true
	var realm := _realm_text(view.realm_name_key, view.layer)
	var text := ""
	if view.at_ceiling:
		text = _text_args("UI_HUD_CULTIVATION_COMPLETE", {"realm": realm})
	elif view.can_breakthrough:
		text = _text_args("UI_HUD_CULTIVATION_READY", {"realm": realm})
	elif view.blocked_by_knowledge:
		text = _text_args("UI_HUD_CULTIVATION_BLOCKED", {"realm": realm})
	else:
		text = _text_args("UI_HUD_CULTIVATION_PROGRESS", {
			"realm": realm, "into": view.progress, "cost": view.step_cost})
	UITheme.set_cultivation_meter_value(_cultivation_meter, view.progress, view.step_cost,
		view.can_breakthrough, text)


## Push the player's read-only sect membership view (Phase 06). The owner (MapBase, fed by
## WorldRuntime→SectRuntime) rebuilds + pushes this on map arrival / membership change — NOT
## per frame. Refreshes the compact chip + the (possibly open) detail panel.
func set_sect_view(view: SectMembershipView) -> void:
	_sect_view = view
	if _sect_panel != null:
		_sect_panel.set_view(view)
	_refresh()


## Push the read-only sect politics view (Phase 07). The owner (MapBase, fed by
## WorldRuntime→FactionRuntime) rebuilds + pushes this on map arrival / politics change — NOT
## per frame.
func set_politics_view(view: SectPoliticsView) -> void:
	_politics_view = view
	if _faction_panel != null:
		_faction_panel.set_view(view)


## Push the read-only world-simulation view (Phase 08). The owner (MapBase, fed by
## WorldRuntime→WorldSimulationRuntime) rebuilds + pushes this on map arrival and after the
## world has ticked — NOT per frame.
func set_world_sim_view(view: WorldSimView) -> void:
	_world_sim_view = view
	_refresh_world_sim()


## Semantic `sect_panel` / `faction_panel` intent toggles the matching panel. Driven through
## InputService (gated to GAMEPLAY context) — never a raw keycode (L-003). Read + handle
## locally, then mark the input handled; no scene teardown happens here so this is a safe
## place to touch the viewport.
func _unhandled_input(_event: InputEvent) -> void:
	if _input == null:
		return
	var handled := false
	# A conversation owns the keys while it is open: Esc ASKS to leave it (never the game).
	if _dialogue_modal:
		if _input.call("is_system_action_just_pressed", &"open_menu"):
			dialogue_close_requested.emit()
			var talk_vp := get_viewport()
			if talk_vp != null:
				talk_vp.set_input_as_handled()
		return
	# The shop owns the keys while it is open: Esc ASKS to close it (never leaves the game),
	# and nothing else here reacts until the shop's owner has closed it.
	if _shop_modal:
		if _input.call("is_system_action_just_pressed", &"open_menu"):
			shop_close_requested.emit()
			var shop_vp := get_viewport()
			if shop_vp != null:
				shop_vp.set_input_as_handled()
		return
	# The bag toggles in BOTH contexts: opened from the world (gameplay), closed from itself
	# (modal) — or with Esc, which must close the panel rather than leave the game.
	if _inventory_modal and (_input.call("is_modal_action_just_pressed", INVENTORY_ACTION)
			or _input.call("is_system_action_just_pressed", &"open_menu")):
		close_inventory()
		handled = true
	elif _inventory_panel != null \
			and _input.call("is_gameplay_action_just_pressed", INVENTORY_ACTION):
		open_inventory()
		handled = true
	if _sect_panel != null \
			and _input.call("is_gameplay_action_just_pressed", SECT_PANEL_ACTION):
		_sect_panel.visible = not _sect_panel.visible
		handled = true
	if _faction_panel != null \
			and _input.call("is_gameplay_action_just_pressed", FACTION_PANEL_ACTION):
		_faction_panel.visible = not _faction_panel.visible
		handled = true
	if handled:
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


## Close both side panels (combat engaged). Safe when either is absent or already closed.
func _close_side_panels() -> void:
	if _sect_panel != null:
		_sect_panel.visible = false
	if _faction_panel != null:
		_faction_panel.visible = false
	close_inventory()
	# A fight ends a conversation: ask the shop's owner to close it.
	if _shop_modal:
		shop_close_requested.emit()
	if _dialogue_modal:
		dialogue_close_requested.emit()


## Open the bag: one reading surface at a time (the other side panels close), and the input
## context becomes UI_MODAL so the move keys navigate rows instead of walking.
func open_inventory() -> void:
	if _inventory_panel == null or _inventory_panel.visible:
		return
	if _sect_panel != null:
		_sect_panel.visible = false
	if _faction_panel != null:
		_faction_panel.visible = false
	_inventory_panel.visible = true
	_inventory_panel.set_process(true)
	if _input != null and not _inventory_modal:
		_input.call("push_modal_context")
		_inventory_modal = true


## Close the bag and give input back to the world. Safe when closed.
func close_inventory() -> void:
	if _inventory_panel != null:
		_inventory_panel.visible = false
		_inventory_panel.set_process(false)
	if _input != null and _inventory_modal:
		_input.call("pop_context")
		_inventory_modal = false


func is_inventory_open() -> bool:
	return _inventory_panel != null and _inventory_panel.visible


func inventory_panel() -> InventoryPanel:
	return _inventory_panel


## Push the learned techniques and the linh khí pool (Phase 15).
func set_skill_view(view: SkillView) -> void:
	if _skill_dock != null:
		_skill_dock.set_view(view)


## Push the shop view (Phase 17). The view is the authority on whether a shop is open: an open
## view shows the panel and takes a UI_MODAL context (the move keys choose rows instead of
## walking); a closed one hides it and gives the context back. Idempotent both ways.
func set_shop_view(view: ShopView) -> void:
	if _shop_panel == null:
		return
	_shop_panel.set_view(view)
	if view != null and view.open:
		_show_shop()
	else:
		_hide_shop()


func _show_shop() -> void:
	if _shop_panel.visible:
		return
	_close_side_panels()
	_shop_panel.visible = true
	_shop_panel.set_process(true)
	if _input != null and not _shop_modal:
		_input.call("push_modal_context")
		_shop_modal = true
	_refresh_prompts()


func _hide_shop() -> void:
	if _shop_panel != null:
		_shop_panel.visible = false
		_shop_panel.set_process(false)
	if _input != null and _shop_modal:
		_input.call("pop_context")
		_shop_modal = false
		_refresh_prompts()


func is_shop_open() -> bool:
	return _shop_panel != null and _shop_panel.visible


## Push the conversation view (Phase 18). The view is the authority on whether a conversation
## is open: an open view shows the box and takes a UI_MODAL context; a closed one hides it and
## gives the context back. Idempotent both ways.
func set_dialogue_view(view: DialogueView) -> void:
	if _dialogue_panel == null:
		return
	_dialogue_panel.set_view(view)
	if view != null and view.open:
		_show_dialogue()
	else:
		_hide_dialogue()


func _show_dialogue() -> void:
	if _dialogue_panel.visible:
		return
	_close_side_panels()
	_dialogue_panel.visible = true
	_dialogue_panel.set_process(true)
	if _input != null and not _dialogue_modal:
		_input.call("push_modal_context")
		_dialogue_modal = true
	_refresh_dialogue_focus()


func _hide_dialogue() -> void:
	if _dialogue_panel != null:
		_dialogue_panel.visible = false
		_dialogue_panel.set_process(false)
	if _input != null and _dialogue_modal:
		_input.call("pop_context")
		_dialogue_modal = false
		_refresh_dialogue_focus()


## DIALOGUE FOCUS: while two people talk, the controls that cannot act stand down (the prompt
## strip, the technique dock) and come back, untouched, when the talk ends.
func _refresh_dialogue_focus() -> void:
	if _prompt_strip != null:
		_prompt_strip.visible = not _dialogue_modal
	# The dock decides its own `visible` (it hides with no techniques), so it is faded, not
	# hidden: its own rule is untouched when the talk ends.
	if _skill_dock != null:
		_skill_dock.modulate.a = 0.0 if _dialogue_modal else 1.0
	_place_notice_band()


## The announcement band rides just above the dialogue box while one is open (a result of what
## was just said must not be printed across the line that said it), and rests where it always
## does otherwise.
func _place_notice_band() -> void:
	if _notice_label == null:
		return
	var lift := 0.0
	if _dialogue_modal and _dialogue_panel != null:
		var box_top := UIPalette.HUD_MARGIN + _dialogue_panel.size.y \
			+ UIPalette.DIALOGUE_NOTICE_GAP
		lift = maxf(0.0, box_top + _notice_rest_bottom)
	_notice_label.offset_top = _notice_rest_top - lift
	_notice_label.offset_bottom = _notice_rest_bottom - lift


func is_dialogue_open() -> bool:
	return _dialogue_panel != null and _dialogue_panel.visible


func dialogue_panel() -> DialoguePanel:
	return _dialogue_panel


func shop_panel() -> ShopPanel:
	return _shop_panel


## Push the linh thú view (Phase 16), event-driven from the pet runtime.
func set_pet_view(view: PetView) -> void:
	_pet_view = view
	_refresh_pet_prompt()


func is_pet_prompt_visible() -> bool:
	return _pet_row != null and _pet_row.visible


func pet_prompt_text() -> String:
	return _pet_row.action_text() if is_pet_prompt_visible() else ""


func _refresh_pet_prompt() -> void:
	if _pet_row == null:
		return
	var view := _pet_view
	# ONE contextual verb at a time (the cultivate row's rule): beside something to interact
	# with, or at a vein, that verb is what the player is here for and the strip has room for
	# one. The summon key itself is never disabled — only its advertisement gives way.
	_pet_row.visible = view != null and view.available and not _interact_available \
		and not (_cultivate_row != null and _cultivate_row.visible)
	if not _pet_row.visible:
		return
	var verb := "UI_HUD_PET_SUMMON"
	if view.out:
		verb = "UI_HUD_PET_DISMISS"
	elif view.recovering:
		verb = "UI_HUD_PET_RECOVERING"
	# A VERB only, like every other row: the strip must stay inside the left half of the screen
	# (the banner is bottom-centre), and the pet's name and level are said by its notices.
	_pet_row.set_prompt(_display_label(PET_SUMMON_ACTION), _text(verb))


func skill_dock() -> SkillDock:
	return _skill_dock


## Push the bag's contents (Phase 13), event-driven from the inventory runtime.
func set_inventory_view(view: InventoryView) -> void:
	if _inventory_panel != null:
		_inventory_panel.set_view(view)


## Is the Sect detail panel currently shown? (for tests)
func is_sect_panel_open() -> bool:
	return _sect_panel != null and _sect_panel.visible


## Is the Sect Politics panel currently shown? (for tests)
func is_faction_panel_open() -> bool:
	return _faction_panel != null and _faction_panel.visible


# --- Rendering ---------------------------------------------------------------

func _refresh() -> void:
	if _name_label == null:
		return  # not built yet
	_name_label.text = _resolve(_name_key)
	_refresh_cultivation()
	_title_label.text = _resolve(_title_key)
	# Once the realm is shown, the title row yields to it (Phase 12): the starting title
	# ("Mortal Seeker") restates the realm the tu vi meter now NAMES, and the plaque must stay
	# inside the permanent-HUD budget (§3c) — one row out, one row in.
	_title_label.visible = _title_key != &"" and not is_cultivation_visible()
	_map_label.text = _resolve(_map_name_key)
	# Re-resolve the combat target too, so a language change relabels what the player is
	# fighting without the combat session having to push the view again.
	_refresh_target_text()
	_refresh_sect_chip()
	_refresh_progression()
	_refresh_cultivation()
	_refresh_notice()
	_refresh_breakthrough_text()
	_refresh_world_sim()
	_refresh_prompts()


## Render world time + the last world event from the read-only view (Phase 08).
##
## With no simulation the two lines are HIDDEN rather than blanked: an empty label still
## occupies its row in the plaque, so blanking would leave a gap that reads as a broken layout.
##
## The event line names WHAT KIND of thing moved and WHICH WAY, never the subject and never a
## raw id (see `WorldSimView`'s note on why the subject has to wait for a phase that can name
## things). The magnitude's SIGN picks the verb, so vi and en each read as a sentence instead
## of as "influence +3", which would need no translation and convey less.
func _refresh_world_sim() -> void:
	if _world_date_label == null or _world_event_label == null:
		return
	if _world_sim_view == null or not _world_sim_view.available:
		_world_date_label.visible = false
		_world_event_label.visible = false
		return
	_world_date_label.visible = true
	_world_date_label.text = _text_args("UI_HUD_WORLD_DATE", {
		"year": _world_sim_view.year,
		"season": _world_sim_view.season,
		"day": _world_sim_view.day,
	})
	_world_event_label.visible = true
	if not _world_sim_view.has_last_event():
		_world_event_label.text = _text("UI_HUD_WORLD_QUIET")
		return
	var subject := _resolve(_world_sim_view.last_event_kind_key)
	var template := "UI_HUD_WORLD_EVENT_ROSE" if _world_sim_view.last_event_magnitude >= 0 \
		else "UI_HUD_WORLD_EVENT_FELL"
	_world_event_label.text = _text_args(template, {"subject": subject})


## Render the compact sect chip from the read-only view (localized; never a raw id). A null
## view or a "not a member" view shows a localized "No Sect" line + no emblem.
func _refresh_sect_chip() -> void:
	if _sect_name_label == null:
		return
	if _sect_view != null and _sect_view.is_member:
		_sect_name_label.text = _resolve(_sect_view.sect_name_key)
		_sect_rank_label.text = "%s · %s %d" % [
			_resolve(_sect_view.rank_name_key),
			_text("UI_SECT_PANEL_REPUTATION"), _sect_view.reputation]
		_sect_rank_label.visible = true
		if _sect_view.emblem_ref != "" and ResourceLoader.exists(_sect_view.emblem_ref):
			_sect_emblem.texture = load(_sect_view.emblem_ref)
		else:
			_sect_emblem.texture = null
		_sect_emblem.visible = _sect_emblem.texture != null
	else:
		_sect_name_label.text = _text("UI_HUD_SECT_NONE")
		_sect_rank_label.visible = false
		_sect_emblem.texture = null
		_sect_emblem.visible = false


## Resolve a localization key to text (empty key -> empty string, no warning spam).
func _resolve(key: StringName) -> String:
	if key == &"" or _loc == null:
		return ""
	return String(_loc.call("t", key))


## Fill the prompt rows from InputService display labels (never raw keycodes).
##
## VISIBILITY CONTRACT (D-055-G), deliberate and per-row rather than one rule for all:
##   * ATTACK   — always visible. The player is armed with the basic attack for the whole
##                session (`WorldRuntime` arms them on every map arrival from
##                `attack_player_basic.tres`), so there is no state in which the prompt would
##                be a lie. Showing it only "when an enemy is near" was rejected: a player who
##                has never attacked does not know the verb exists, so the cue would appear
##                exactly when they are already under pressure and are least able to read it.
##   * INTERACT — contextual. It names a target ("interact with WHAT"), so off an exit it has
##                no referent and would be noise.
##   * SECT / POLITICS / MENU — always visible; they open a panel, which is always legal.
func _refresh_prompts() -> void:
	if _menu_row == null:
		return
	var menu_key := _display_label(OPEN_MENU_ACTION)
	_menu_row.set_prompt(menu_key, _text("UI_HUD_MENU_ACTION"))
	if _attack_row != null:
		var attack_key := _display_label(ATTACK_ACTION)
		_attack_row.set_prompt(attack_key, _text("UI_HUD_ATTACK_ACTION"))
	# Not while the shop holds the keys: `interact` trades there, and the panel says so itself.
	_interact_row.visible = _interact_available and not _shop_modal and not _dialogue_modal
	if _interact_row.visible:
		var interact_key := _display_label(INTERACT_ACTION)
		_interact_row.set_prompt(interact_key, _interact_text())
	_refresh_cultivate_prompt()
	_refresh_pet_prompt()
	# Sect panel prompt: always available (the player can always inspect their sect, §19).
	if _sect_row != null:
		var sect_key := _display_label(SECT_PANEL_ACTION)
		_sect_row.set_prompt(sect_key, _text("UI_SECT_PANEL_TOGGLE"))
	# Politics prompt: also always available. The player can read a sect's internal argument
	# without belonging to a faction — that is how they decide whether to take a side at all.
	if _faction_row != null:
		var faction_key := _display_label(FACTION_PANEL_ACTION)
		_faction_row.set_prompt(faction_key, _text("UI_FACTION_PANEL_TOGGLE"))


## The interact prompt's text: the verb, naming its target when the interactable gives one
## ("Talk to Kha Thản"). A `StringName` argument is a localization key, resolved here.
func _interact_text() -> String:
	if _interact_label_args.is_empty():
		return _text(String(_interact_label_key))
	var args := _interact_label_args.duplicate()
	for k: Variant in args:
		if typeof(args[k]) == TYPE_STRING_NAME:
			args[k] = _resolve(args[k])
	return _text_args(String(_interact_label_key), args)


func interact_prompt_text() -> String:
	return _interact_text() if _interact_available else ""


## The cultivate prompt's verb is what the key will do NOW: sit down at a vein, break through on
## a full step, otherwise rise. Hidden away from any vein and during a breakthrough (the press
## is absorbed then, so advertising it would promise nothing).
func _refresh_cultivate_prompt() -> void:
	if _cultivate_row == null:
		return
	var view := _cultivation_view
	var verb := ""
	if view != null and view.available:
		match view.activity:
			CultivationView.Activity.IDLE:
				if view.site_in_reach:
					verb = "UI_HUD_CULTIVATE_ACTION"
			CultivationView.Activity.MEDITATING:
				verb = "UI_HUD_BREAKTHROUGH_ACTION" if view.can_breakthrough \
					else "UI_HUD_CULTIVATE_STOP"
	# ONE contextual verb at a time: where a key both reads a stele and cultivates, the strip
	# would promise two things at once — and the vein and the stele are never placed together.
	# While seated the cultivate verb wins (interact cannot be what the player is doing then).
	if _interact_available and (view == null
			or view.activity == CultivationView.Activity.IDLE):
		verb = ""
	_cultivate_row.visible = verb != ""
	if verb != "":
		_cultivate_row.set_prompt(_display_label(CULTIVATE_ACTION), _text(verb))


func _display_label(action: StringName) -> String:
	if _input == null:
		return "?"
	return String(_input.call("get_action_display_label", action))


func _text(key: String) -> String:
	if _loc == null:
		return key
	return String(_loc.call("t", key))


## Localized text with `{placeholder}` substitution (`Localization.t_args`). Used for the
## world date + event lines, which are SENTENCES with numbers in them — building them by
## concatenation would break grammar across languages (`07-localization.md`).
func _text_args(key: String, args: Dictionary) -> String:
	if _loc == null:
		return key
	return String(_loc.call("t_args", key, args))


func _on_language_changed(_language_code: String) -> void:
	_refresh()
