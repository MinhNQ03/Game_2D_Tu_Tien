extends RefCounted
class_name StoryOwners
## StoryOwners — Aetheria domain (how the story reaches what it does not own, Phase 20).
##
## The story records beats, choices and flags. Everything else a decision or an Origin touches
## belongs to someone else, and is changed by ASKING them — the same shape as `RewardPayers`.
## Each seam is a Callable so the domain never names a runtime, a node or a scene.
##
## A seam left invalid is not a silent skip: content that needs it is refused before anything
## is recorded.

## `knows.call(knowledge_id) -> bool` — the Knowledge Core's answer, asked each time.
var knows: Callable = Callable()
## `teach.call(knowledge_id, source_id) -> bool` — true if the player now holds it.
var teach: Callable = Callable()
## `move_regard.call(character_id, dimension, delta) -> bool`.
var move_regard: Callable = Callable()
## `give_all.call({item_id: count}) -> bool` — put ALL of these in the bag, or none of them.
## The bag's own all-or-nothing exchange; false means nothing was given.
var give_all: Callable = Callable()
