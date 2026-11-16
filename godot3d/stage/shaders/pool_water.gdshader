shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Agua quieta y negra con ondas que nacen donde cae la cascada (ref. 83530).
uniform vec3 deep_col : source_color = vec3(0.006, 0.02, 0.028);
uniform vec3 foam_col : source_color = vec3(0.45, 0.62, 0.7);
uniform vec2 center = vec2(0.0, -17.0);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = length(wp.xz - center);
	float rip = sin(d * 5.0 - TIME * 2.6) * exp(-d * 0.22);
	float rx = (wp.x - center.x) / max(d, 0.01);
	float rz = (wp.z - center.y) / max(d, 0.01);
	float wob = sin(wp.x * 1.7 + TIME * 0.6) * sin(wp.z * 1.3 - TIME * 0.5);
	vec3 nw = normalize(vec3(rx * rip * 0.16 + wob * 0.03, 1.0, rz * rip * 0.16 + wob * 0.03));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float foam = exp(-d * 1.8) * (0.55 + 0.45 * sin(d * 9.0 - TIME * 4.0));
	ALBEDO = deep_col;
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	EMISSION = foam_col * foam * 0.22;
}
