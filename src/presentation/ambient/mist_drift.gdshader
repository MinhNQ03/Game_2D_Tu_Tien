// mist_drift.gdshader — Aetheria presentation (D-057B).
//
// Low mist obeys the FLUID law (`MOTION_DESIGN_CONTRACT.md` M-2.1: flow, ripple, dispersion):
// the bank drifts slowly side to side, each band of rows a little out of step with the next so
// it RIPPLES instead of sliding as one sticker, and it thins and thickens over many seconds. It
// is micro-scale (M-4.7): slower and fainter than anything that matters, never drawing the eye.
//
// Whole-pixel shifts, like `pixel_sway`, so the 2x-zoomed pixel art never smears. The phase is
// taken from the world position, so two banks never breathe together, and nothing here is
// random: the same time and place give the same picture.
shader_type canvas_item;

uniform float drift_px = 4.0;
uniform float drift_hz = 0.045;
// Phase lag per texture row: how much the lower rows trail the upper ones.
uniform float ripple = 0.22;
// How deep the slow thinning goes (0 = constant density), and how slowly.
uniform float breathe = 0.35;
uniform float breathe_hz = 0.06;

varying vec2 world_pos;
varying vec4 tint;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	tint = COLOR;
}

void fragment() {
	float rows = 1.0 / TEXTURE_PIXEL_SIZE.y;
	float row = floor(UV.y * rows);
	float phase = world_pos.x * 0.011 + world_pos.y * 0.007;
	float shift = floor(sin(TIME * drift_hz * 6.2831853 + phase - row * ripple) * drift_px + 0.5);
	vec2 uv = UV - vec2(shift * TEXTURE_PIXEL_SIZE.x, 0.0);
	vec4 c = texture(TEXTURE, uv);
	c.a *= step(0.0, uv.x) * step(uv.x, 1.0);
	c.a *= 1.0 - breathe * 0.5 * (1.0 + sin(TIME * breathe_hz * 6.2831853 + phase * 1.7));
	COLOR = c * tint;
}
