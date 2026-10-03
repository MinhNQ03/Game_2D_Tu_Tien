extends HBoxContainer
class_name UIPromptRow
## UIPromptRow — Aetheria presentation (reusable control-prompt row).
##
## One control hint rendered as a graphic key badge (`UIKeyBadge`) + an action label, e.g.
## [E] Interact or [Esc] Menu. The HUD builds TWO of these (interact + menu), so the
## badge+label layout lives here once instead of being duplicated
## (`08-ai-review-protocol.md` no-duplication).
##
## Pure presentation. The owner passes an already-resolved key glyph (from
## `InputService.get_action_display_label`) and an already-localized action text (from
## `Localization`); this row never touches InputMap or raw keycodes (L-003) and owns no state.

const KeyBadgeScript := preload("res://src/presentation/ui/components/ui_key_badge.gd")

var _badge: UIKeyBadge
var _text: Label


func _ready() -> void:
	add_theme_constant_override("separation", UIPalette.SPACE_SM)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _badge == null:
		_build()


func _build() -> void:
	_badge = KeyBadgeScript.new() as UIKeyBadge
	add_child(_badge)
	_text = Label.new()
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_text.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	add_child(_text)


## Set the key glyph (e.g. "E") and the action text (e.g. "Interact"), both pre-resolved.
func set_prompt(key_label: String, action_text: String) -> void:
	if _badge == null:
		_build()
	_badge.set_key_label(key_label)
	_text.text = action_text
