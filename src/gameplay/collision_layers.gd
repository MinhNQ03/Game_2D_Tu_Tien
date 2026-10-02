extends RefCounted
class_name CollisionLayers
## CollisionLayers — Aetheria gameplay (shared 2D physics layer/mask vocabulary).
##
## One documented place for 2D collision layer bits, so scenes/components don't scatter
## magic numbers (`.kiro/steering/04-coding-standards.md`: no magic numbers;
## `05-performance-testing.md`: control physics via layers/masks). Values are bit MASKS
## (1 << n), matching Godot's `collision_layer` / `collision_mask` properties.
##
## Phase 02 bodies:
##   WORLD   — static environment (sandbox walls/boundaries).
##   PLAYER  — the player body.
##   DUMMY   — the training dummy body.
## The player collides with WORLD (and the dummy's solid body) so it cannot walk through
## boundaries; the dummy and walls are static. No hitbox/hurtbox framework yet (Phase 09).

const WORLD: int = 1 << 0   # bit 1
const PLAYER: int = 1 << 1  # bit 2
const DUMMY: int = 1 << 2   # bit 3
