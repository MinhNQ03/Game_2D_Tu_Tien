extends RefCounted
class_name CollisionLayers
## CollisionLayers — Aetheria gameplay (shared 2D physics layer/mask vocabulary).
##
## One documented place for 2D collision layer bits, so scenes/components don't scatter
## magic numbers (`.kiro/steering/04-coding-standards.md`: no magic numbers;
## `05-performance-testing.md`: control physics via layers/masks). Values are bit MASKS
## (1 << n), matching Godot's `collision_layer` / `collision_mask` properties.
##
## BODIES (solid — they block movement):
##   WORLD   — static environment (walls/boundaries).
##   PLAYER  — the player body.
##   DUMMY   — the training dummy body.
## The player collides with WORLD (and the dummy's solid body) so it cannot walk through
## boundaries; the dummy and walls are static.

const WORLD: int = 1 << 0   # bit 1
const PLAYER: int = 1 << 1  # bit 2
const DUMMY: int = 1 << 2   # bit 3

# NO HITBOX/HURTBOX LAYER BITS — and that is a decision, not an omission (Phase 09, D-007).
#
# Combat resolves hits ANALYTICALLY: `CombatService` compares reach and arc against a session
# registry of hurtboxes, so an attack never needs a physics sensor and these bits would have
# no consumer (L-005 forbids a constant without one). Two reasons drove it, and the first is
# the expensive one:
#
#   * In the headless `-s` runner an Area2D overlap does not fire reliably — that is L-016 and
#     L-017, the two costliest lessons in this repository. A combat system whose hit detection
#     depended on it could not be tested end to end at all, so "does my attack damage the
#     target" would be a question only a human with a window could answer.
#   * It is also cheaper and more precise about what it means: no Area2D per attack, no physics
#     query per swing, and a hit window that opens and closes with the state machine instead of
#     with the physics tick.
#
# The trade is real and documented: a target is a POINT plus a radius rather than an arbitrary
# polygon. On a 16px grid with 32x48 characters that is not a distinction a player can see.
# Add these bits the day something genuinely needs shape-accurate overlap (a swept projectile,
# a terrain-shaped AoE) — together with its consumer.
