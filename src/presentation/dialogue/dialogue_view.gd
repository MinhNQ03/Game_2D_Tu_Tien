extends RefCounted
class_name DialogueView
## DialogueView — Aetheria presentation DTO (what the dialogue panel shows, Phase 18).
##
## A read-only snapshot built by `DialogueRuntime.build_view()` and pushed through
## `WorldRuntime` → `MapBase` → `GameplayHUD` → `DialoguePanel`. Localization KEYS, a portrait
## path and plain ids — never a `DialogueData`, a `CharacterState` or a relationship edge. The
## panel decides nothing from it: the choices listed are the ones `DialogueService` offered.

## A conversation is open (false = the panel should be closed).
var open: bool = false
var dialogue_id: StringName = &""
## The line being said. A choice is submitted WITH this id, so an answer to a line that is no
## longer the current one is refused by the runtime.
var node_id: StringName = &""
## Counts every line shown this session: two views of the same node are still two lines (the
## panel replays its reaction and re-arms its key guard when this changes).
var line_serial: int = 0

var speaker_id: StringName = &""
var speaker_name_key: StringName = &""
var speaker_title_key: StringName = &""
## `CharacterTemplateData.portrait_ref` of the speaker ("" = no portrait authored).
var portrait_path: String = ""

## How the line is delivered: a `DialogueNodeData.Mood`.
var mood: int = 0
## The speaker's body gestures on this line (the portrait reacts with it).
var gestures: bool = false
var text_key: StringName = &""

## The answers offered now, in authored order: { id, text_key }.
var choices: Array[Dictionary] = []
## A line with no choices: acknowledging it continues (false = it ends the conversation).
var continues: bool = false


static func make_closed() -> DialogueView:
	return DialogueView.new()
