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
##
## PREPARE, THEN COMMIT (D-073 §2). For each thing the story asks an owner to DO there is a
## seam that asks whether it CAN. The story asks every "can" before it changes anything, so an
## owner's "no" refuses a decision whole. An owner answers "can" with the SAME rule its commit
## uses to decide: a "yes" is a promise that the commit will not refuse.

## `knows.call(knowledge_id) -> bool` — the Knowledge Core's answer, asked each time.
var knows: Callable = Callable()
## `can_teach.call(knowledge_id) -> bool` — would `teach` leave the player holding it?
var can_teach: Callable = Callable()
## `teach.call(knowledge_id, source_id) -> bool` — true if the player now holds it.
var teach: Callable = Callable()
## `can_move_regard.call(character_id, dimension, delta) -> bool` — would `move_regard` be
## carried out (a move that is already at its bound counts: it changes nothing and is done)?
var can_move_regard: Callable = Callable()
## `move_regard.call(character_id, dimension, delta) -> Dictionary` — the relationship owner's
## own answer, `{ ok, old_value, new_value }` (`RegardRules.move`). What it WAS is what lets
## the story put a regard back exactly if a later owner breaks its word.
var move_regard: Callable = Callable()
## `give_all.call({item_id: count}) -> bool` — put ALL of these in the bag, or none of them.
## The bag's own all-or-nothing exchange; false means nothing was given.
var give_all: Callable = Callable()
