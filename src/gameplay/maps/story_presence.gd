extends Node
class_name StoryPresence
## StoryPresence — Aetheria gameplay (a thing in a map that is there because of the story).
##
## A child of a map node that exists only once something has happened (a wreck after the
## Night) or only until it has (a survey stake somebody removed). It holds no state: whether
## its parent is there is asked of the story, through `WorldRuntime`, every time the map is
## entered and every time the story moves. Absent = hidden and bodiless; nothing is freed, so
## the map is the same scene before and after.

## The story flag that decides it.
@export var flag_id: StringName = &""
## True: the parent is there once the flag is set. False: it is there until the flag is set.
@export var present_when_set: bool = true


const GROUP := &"story_presence"


func _ready() -> void:
	add_to_group(GROUP)
	if flag_id == &"":
		push_error("[story-presence] '%s' names no flag" % get_parent().name)


## Show or remove the parent. `flag_is_set(flag_id) -> bool` is the story's answer.
func apply(flag_is_set: Callable) -> void:
	var host := get_parent() as CanvasItem
	if host == null:
		return
	var present := (flag_is_set.is_valid() and bool(flag_is_set.call(flag_id))) \
		== present_when_set
	host.visible = present
	_set_bodies(host, present)


func _set_bodies(node: Node, present: bool) -> void:
	if node is CollisionObject2D:
		for owner_id in (node as CollisionObject2D).get_shape_owners():
			(node as CollisionObject2D).shape_owner_set_disabled(owner_id, not present)
	for child in node.get_children():
		_set_bodies(child, present)
