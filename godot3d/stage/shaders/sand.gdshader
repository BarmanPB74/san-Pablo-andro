shader_type spatial;
// Arena blanca de luna: ruido suave + ondulaciones de viento + destellos finos. Sin texturas; todo en espacio mundo.
uniform vec3 col_a : source_color = vec3(0.60, 0.63, 0.73);
uniform vec3 col_b : source_color = vec3(0.93, 0.94, 0.98);
uniform float ripple_scale = 1.3;

varying vec3 wp;

float hash21(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = vnoise2(wp.xz * 0.07) * 0.6 + vnoise2(wp.xz * 0.45) * 0.4;
	float rip = 0.5 + 0.5 * sin(dot(wp.xz, vec2(0.92, 0.39)) * ripple_scale * 3.0 + n * 6.0 + wp.y * 2.2);
	rip = smoothstep(0.25, 0.95, rip);
	float t = clamp(0.38 + n * 0.38 + rip * 0.2, 0.0, 1.0);
	ALBEDO = mix(col_a, col_b, t);
	float spark = step(0.987, hash21(floor(wp.xz * 11.0)));
	ROUGHNESS = 0.9;
	SPECULAR = 0.2 + spark * 0.9;
}
