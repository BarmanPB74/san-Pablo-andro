shader_type sky;
// Cielo del Umbral: degradado suave (índigo arriba, malva al medio, gris de niebla en el horizonte) con nubes de humo
// teñidas de colores agradables (cian, rosa, ámbar). Sin TIME a propósito: el cielo es estático → se renderiza una vez.

uniform vec3 zenith_col : source_color = vec3(0.13, 0.13, 0.28);
uniform vec3 mid_col : source_color = vec3(0.36, 0.33, 0.50);
uniform vec3 horizon_col : source_color = vec3(0.50, 0.50, 0.56);
uniform vec3 tint_a : source_color = vec3(0.35, 0.75, 0.82);
uniform vec3 tint_b : source_color = vec3(0.82, 0.52, 0.74);
uniform vec3 tint_c : source_color = vec3(0.96, 0.78, 0.56);
uniform float cloud_amount = 0.6;

float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x), mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x), mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise3(p);
		p = p * 2.07 + vec3(3.3, 1.7, 5.1);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_col, mid_col, smoothstep(0.0, 0.34, h));
	col = mix(col, zenith_col, smoothstep(0.3, 0.95, h));
	float n1 = fbm3(d * vec3(2.2, 3.4, 2.2) + vec3(1.7, 0.3, 4.1));
	float n2 = fbm3(d * vec3(3.6, 5.2, 3.6) + vec3(8.1, 2.2, 0.7));
	// las nubes viven a media altura y se apagan hacia el horizonte (para no romper la unión con la niebla) y el cenit
	float band = smoothstep(0.03, 0.2, h) * (1.0 - smoothstep(0.6, 0.97, h));
	vec3 t = mix(tint_a, tint_b, smoothstep(0.32, 0.68, n1));
	t = mix(t, tint_c, smoothstep(0.5, 0.8, n2) * 0.75);
	float cloud = smoothstep(0.36, 0.74, n1 * 0.5 + n2 * 0.5);
	col = mix(col, t, cloud * band * cloud_amount);
	col = mix(col, vec3(0.64, 0.64, 0.7), smoothstep(0.45, 0.8, n2) * band * 0.22);   // humo gris entre los colores
	if (h < 0.0) {
		col = horizon_col;
	}
	COLOR = col;
}
