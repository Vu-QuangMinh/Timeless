shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float intensity : hint_range(0.0, 5.0) = 1.5;
uniform float core_width : hint_range(0.0, 0.5) = 0.2;
uniform float glow_width : hint_range(0.0, 1.0) = 0.7;
uniform float glitch_amount : hint_range(0.0, 0.5) = 0.15;
uniform float glitch_rate : hint_range(0.5, 30.0) = 12.0;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.3;
uniform float length_fade : hint_range(0.0, 0.3) = 0.04;

float hash(float x) {
	return fract(sin(x * 12.9898) * 43758.5453);
}

void fragment() {
	float time_step = floor(TIME * glitch_rate);
	float jitter = (hash(time_step) - 0.5) * 2.0 * glitch_amount;

	float lateral = abs(UV.y - 0.5 - jitter) * 2.0;
	if (lateral > 1.0) discard;

	float core = 1.0 - smoothstep(0.0, core_width, lateral);
	float glow = (1.0 - smoothstep(0.0, glow_width, lateral)) * 0.5;

	float flicker = 1.0 - flicker_amount * hash(time_step + UV.x * 7.0);

	float fade_start = smoothstep(0.0, length_fade, UV.x);
	float fade_end = 1.0 - smoothstep(1.0 - length_fade, 1.0, UV.x);
	float length_mask = fade_start * fade_end;

	float shape = (core + glow) * intensity * flicker * length_mask;
	shape = clamp(shape, 0.0, 1.0);

	COLOR.a *= shape;
}
