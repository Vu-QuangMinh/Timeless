shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 cone_color : source_color = vec4(1.0, 0.18, 0.18, 1.0);
uniform float intensity : hint_range(0.0, 5.0) = 1.0;
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float border_alpha : hint_range(0.0, 4.0) = 3.0;
uniform float border_width : hint_range(0.0, 0.3) = 0.05;
uniform float far_edge_alpha : hint_range(0.0, 4.0) = 2.5;
uniform float far_edge_width : hint_range(0.0, 0.3) = 0.04;
uniform float length_attenuation : hint_range(0.0, 1.0) = 0.0;
uniform float scan_speed : hint_range(0.0, 8.0) = 0.0;
uniform float scan_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float scan_frequency : hint_range(2.0, 32.0) = 12.0;

void fragment() {
	float modulate_alpha = COLOR.a;

	float lateral = abs(UV.x - 0.5) * 2.0;
	float along = clamp(UV.y, 0.0, 1.0);

	if (lateral > 1.0) discard;

	float side_border = smoothstep(1.0 - border_width, 1.0, lateral);
	float far_border = smoothstep(1.0 - far_edge_width, 1.0, along);
	float length_falloff = max(0.0, 1.0 - along * length_attenuation);
	float scan = 0.5 + 0.5 * sin(along * scan_frequency - TIME * scan_speed * 6.28318);
	float scan_mult = mix(1.0 - scan_intensity, 1.0, scan);

	float fill = fill_alpha * length_falloff * scan_mult;
	float border = max(side_border * border_alpha, far_border * far_edge_alpha);

	float alpha = (fill + border) * intensity;
	alpha = clamp(alpha, 0.0, 1.0);

	COLOR = vec4(cone_color.rgb, alpha * cone_color.a * modulate_alpha);
}
