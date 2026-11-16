shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
// Haz de luz que entra por el óculo (ref. 83531): translúcido, más denso al centro y arriba.
uniform vec3 col : source_color = vec3(0.75, 0.88, 1.0);
uniform float intensity = 0.55;
uniform float height = 26.0;
varying float vh;

void vertex() {
	vh = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = pow(facing, 1.6) * mix(0.15, 1.0, vh * vh) * intensity;
	ALBEDO = col * a;
	ALPHA = 1.0;
}
