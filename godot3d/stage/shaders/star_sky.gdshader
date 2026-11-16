shader_type sky;
// Cielo del umbral: negro azulado con Vía Láctea inclinada, nebulosa y estrellas (ref. 83528 / 83529).
// Sin TIME a propósito: el cielo es estático → se renderiza una sola vez (barato en Compatibility).

uniform vec3 zenith_col : source_color = vec3(0.004, 0.006, 0.02);
uniform vec3 horizon_col : source_color = vec3(0.05, 0.06, 0.12);
uniform vec3 band_col : source_color = vec3(0.45, 0.5, 0.75);
uniform vec3 nebula_col : source_color = vec3(0.45, 0.3, 0.6);
uniform vec3 band_normal = vec3(0.35, 0.8, 0.45);
uniform float star_amount : hint_range(0.0, 1.0) = 0.55;
uniform float band_strength = 1.0;

float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1, 0, 0));
	float n010 = hash31(i + vec3(0, 1, 0));
	float n110 = hash31(i + vec3(1, 1, 0));
	float n001 = hash31(i + vec3(0, 0, 1));
	float n101 = hash31(i + vec3(1, 0, 1));
	float n011 = hash31(i + vec3(0, 1, 1));
	float n111 = hash31(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise3(p);
		p = p * 2.07 + vec3(3.3, 1.7, 5.1);
		a *= 0.5;
	}
	return v;
}

float stars(vec3 dir, float scale, float thresh) {
	vec3 p = dir * scale;
	vec3 id = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = hash31(id);
	vec3 off = (vec3(hash31(id + 1.7), hash31(id + 5.3), hash31(id + 9.1)) - 0.5) * 0.5;
	float d = length(f - off);
	return step(thresh, h) * smoothstep(0.16, 0.0, d) * (0.4 + 0.6 * hash31(id + 2.2));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	vec3 col = mix(horizon_col, zenith_col, smoothstep(-0.05, 0.75, h));
	col = mix(col * 0.6, col, step(-0.2, h));

	vec3 n = normalize(band_normal);
	float bd = dot(dir, n);
	float band = exp(-bd * bd * 9.0);
	float cloud = fbm3(dir * 3.2);
	float dark_lane = smoothstep(0.55, 0.8, fbm3(dir * 6.0 + 4.0));
	col += band_col * band * (0.25 + cloud * 0.9) * (1.0 - dark_lane * 0.7) * band_strength * 0.55;
	float neb = smoothstep(0.45, 0.85, fbm3(dir * 2.1 + 11.0));
	col += nebula_col * neb * 0.16 * (0.4 + band);

	float st = stars(dir, 70.0, 1.0 - 0.06 * star_amount * 1.4);
	st += stars(dir, 130.0, 1.0 - 0.05 * star_amount * 1.4) * 0.8;
	st += stars(dir, 28.0, 1.0 - 0.02 * star_amount * 1.4) * 1.6;
	st *= mix(0.5, 1.4, band);
	col += vec3(0.85, 0.9, 1.0) * st * smoothstep(-0.12, 0.1, h);

	COLOR = col;
}
