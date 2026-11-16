shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
// Nicho en arco, oscuro, para decorar el muro circular de la cámara (ref. 83531).
uniform float darkness = 0.88;

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * 2.0, UV.y);          // UV.y = 0 arriba, 1 abajo
	float h = 1.0 - UV.y;                               // 0 abajo, 1 arriba
	float body = step(abs(p.x), 1.0) * step(h, 0.68);
	vec2 c = vec2(p.x, (h - 0.68) / 0.32);
	float top = step(length(c), 1.0) * step(0.68, h);
	float inside = max(body, top);
	float rim = smoothstep(0.0, 0.1, 1.0 - max(abs(p.x), length(c) * step(0.68, h)));
	ALBEDO = vec3(0.005, 0.01, 0.012);
	ALPHA = inside * darkness * mix(0.55, 1.0, rim);
}
