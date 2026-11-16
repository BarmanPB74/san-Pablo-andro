shader_type spatial;
// Roca / arena procedural: ruido 3D en espacio mundo + estratos horizontales. Sin texturas.
uniform vec3 col_a : source_color = vec3(0.20, 0.085, 0.05);
uniform vec3 col_b : source_color = vec3(0.64, 0.33, 0.17);
uniform float noise_scale = 0.35;
uniform float strata = 0.8;
uniform float rough = 0.95;

varying vec3 wp;

float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x),
			mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x),
			mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float f = vnoise3(wp * noise_scale) * 0.55 + vnoise3(wp * noise_scale * 2.7) * 0.3 + vnoise3(wp * noise_scale * 7.0) * 0.15;
	float st = 0.5 + 0.5 * sin(wp.y * 2.3 + f * 5.5);
	float t = clamp(f * 1.1 + (st - 0.5) * 0.45 * strata, 0.0, 1.0);
	ALBEDO = mix(col_a, col_b, t);
	ROUGHNESS = rough;
	SPECULAR = 0.2;
}
