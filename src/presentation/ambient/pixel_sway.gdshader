// pixel_sway.gdshader — Aetheria presentation (D-057B).
//
// ONE motion law for everything that bends about a fixed point: grass and foliage rooted at the
// bottom, a banner or a hanging lantern rooted at the top, a training post leaning about its
// footing when struck. Rows of the texture shift HORIZONTALLY by WHOLE pixels, weighted by their
// distance from the pivot row. A rotated pixel-art sprite at 2x zoom shows "mixels" (a rotated
// pixel grid); a whole-pixel row shear does not, which is how hand-animated pixel art leans.
//
// What differs per material is DATA (`MOTION_DESIGN_CONTRACT.md` M-2.1, M-10.1):
//   bend      1 = a rigid lever (post, hanging lantern); > 1 = a flexible stem whose tip moves
//             most (grass 2.2, a tree canopy 2.6 — the trunk barely moves, the crown does)
//   wind_px   ambient amplitude at the free end; wind_hz its frequency — light things fast and
//             small, heavy things slow and larger
//   ripple    phase lag per row: 0 for a rigid body, > 0 for cloth, where the wave travels down
//             the material instead of the whole thing swinging as one
//   wind_bias the prevailing lean (cloth hangs downwind and flutters around it)
//   lean_px   a script-driven lean (`HitReaction`), added to the wind
//
// NO SYNCHRONIZED WALLPAPER: the phase comes from the WORLD position, so neighbours never move
// in lockstep, and a gust is a band that TRAVELS across the world — grass ahead of it still,
// grass under it bending, grass behind it settling. Deterministic (TIME + position, no noise
// texture, no RNG), so a capture of the same frame is the same picture.
shader_type canvas_item;

// The texture row the material is fixed at, and how many rows from it reach full deflection.
uniform float pivot_row = 47.0;
uniform float span_rows = 40.0;
// true: fixed at the TOP (banner, hanging lantern); false: rooted at the BOTTOM.
uniform bool hang = false;
uniform float bend : hint_range(0.5, 4.0) = 1.0;
uniform float wind_px = 0.0;
uniform float wind_hz = 0.3;
// The PREVAILING lean at the free end: cloth in a steady breeze hangs to one side and flutters
// around that, rather than swinging symmetrically through vertical.
uniform float wind_bias = 0.0;
uniform float ripple = 0.0;
// A gust: a band `gust_width` px wide crossing the world in +x at `gust_speed` px/s, once every
// `gust_period` px of travel, adding up to `gust_px` at the free end.
uniform float gust_px = 0.0;
uniform float gust_speed = 70.0;
uniform float gust_period = 900.0;
uniform float gust_width = 140.0;
uniform float lean_px = 0.0;

varying vec2 world_pos;
varying vec4 tint;

void vertex() {
	// The ORIGIN of the drawn item in world space: every row of one tuft shares its phase.
	world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	tint = COLOR;
}

void fragment() {
	float rows = 1.0 / TEXTURE_PIXEL_SIZE.y;
	float row = floor(UV.y * rows);
	float from_pivot = hang ? (row - pivot_row) : (pivot_row - row);
	float w = pow(clamp(from_pivot / max(span_rows, 1.0), 0.0, 1.0), bend);

	float phase = world_pos.x * 0.023 + world_pos.y * 0.017;
	float t = TIME * wind_hz * 6.2831853 + phase - row * ripple;
	// Two incommensurate sines: a sway that never visibly repeats within a glance.
	float wind = wind_bias + wind_px * (0.7 * sin(t) + 0.3 * sin(t * 2.37 + 1.3));

	float lane = mod(world_pos.x - TIME * gust_speed, gust_period);
	float gust = gust_px * exp(-pow((lane - gust_period * 0.5) / max(gust_width, 1.0), 2.0) * 4.0);

	float shift = floor((wind + gust + lean_px) * w + 0.5);
	vec2 uv = UV - vec2(shift * TEXTURE_PIXEL_SIZE.x, 0.0);
	vec4 c = texture(TEXTURE, uv);
	// Outside the texture is empty, never a clamped smear of the edge column.
	c.a *= step(0.0, uv.x) * step(uv.x, 1.0);
	COLOR = c * tint;
}
