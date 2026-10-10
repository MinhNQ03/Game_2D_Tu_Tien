extends RefCounted
class_name RewardPayers
## RewardPayers — Aetheria domain (the owners a reward is paid THROUGH, Phase 19).
##
## Three seams, one per part of a `RewardData`. Each is the owner's own mutation path, handed
## in by whoever knows the session (so this layer never sees a node):
##
##   trade(take: Dictionary, give: Dictionary) -> bool
##       the bag: `{item_id -> count}` out and in as ONE all-or-nothing change
##       (`InventoryRuntime.exchange`). False = refused, nothing changed.
##   pay_xp(amount: int, source_id: StringName) -> bool
##       progression. True = the owner HANDLED it (XP wasted at the level ceiling is handled).
##   move_regard(character_id, dimension, delta: int, source_id: StringName) -> bool
##       the relationship graph: that character's regard for the player.
##
## An invalid Callable means "this session cannot pay that part": a reward that needs it is
## refused rather than silently short-paid.

var trade: Callable = Callable()
var pay_xp: Callable = Callable()
var move_regard: Callable = Callable()
