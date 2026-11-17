shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Ondas de energía que se expanden por el piso alrededor de Andro mientras carga.
uniform float power : hint_range(0.0, 1.5) = 0.0;
uniform vec3 col : source_color = vec3(1.0, 0.55, 0.15);

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float w1 = fract(TIME * 0.9 - r * 1.2);
	float w2 = fract(TIME * 0.9 + 0.5 - r * 1.2);
	float ring = (1.0 - smoothstep(0.0, 0.22, w1)) + (1.0 - smoothstep(0.0, 0.22, w2)) * 0.6;
	float body = (1.0 - smoothstep(0.0, 1.0, r));
	float a = (ring * 0.55 * body + body * body * 0.35) * (1.0 - smoothstep(0.85, 1.0, r)) * power;
	ALBEDO = col * 1.6;
	ALPHA = clamp(a * 1.5, 0.0, 1.0);
}
