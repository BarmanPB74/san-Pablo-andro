shader_type sky;
// Cielo del Umbral: azul de amanecer con nubes. NO hay disco solar: solo un resplandor ancho y suave que tiñe de
// durazno y rosa el horizonte y la parte de abajo de las nubes del lado por donde amanece (`glow_dir`).
// Las nubes se proyectan sobre un plano alto (se achican hacia el horizonte) en dos capas: cúmulos y cirros.
// Sin TIME a propósito: el cielo es estático → se renderiza una sola vez (barato en Compatibility).

uniform vec3 zenith_col : source_color = vec3(0.09, 0.21, 0.52);
uniform vec3 blue_col : source_color = vec3(0.32, 0.55, 0.88);
uniform vec3 horizon_col : source_color = vec3(0.70, 0.78, 0.94);
uniform vec3 glow_col : source_color = vec3(1.0, 0.72, 0.60);
uniform vec3 glow_dir = vec3(-0.55, 0.21, -0.80);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.95, 0.90);
uniform vec3 cloud_shade : source_color = vec3(0.40, 0.50, 0.76);
uniform vec3 cloud_pink : source_color = vec3(1.0, 0.62, 0.60);
uniform float cloud_cover = 0.62;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise2(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 gd = normalize(glow_dir);
	float g = max(dot(d, gd), 0.0);

	// degradado: azul profundo arriba, azul claro, lavanda pálido en el horizonte
	vec3 col = mix(horizon_col, blue_col, smoothstep(0.0, 0.36, h));
	col = mix(col, zenith_col, smoothstep(0.25, 1.0, h));
	// resplandor del amanecer, ancho y sin disco (la potencia baja evita que se forme un punto brillante)
	float glow = pow(g, 3.0) * (1.0 - smoothstep(0.0, 0.75, h));
	col = mix(col, glow_col, glow * 0.6);

	if (h > 0.0) {
		float fade = smoothstep(0.0, 0.14, h);      // las nubes se funden con el horizonte
		float warm = pow(g, 2.0) * (1.0 - smoothstep(0.0, 0.7, h));
		vec2 ld = normalize(gd.xz + vec2(0.0001));

		// cúmulos
		vec2 uv = d.xz / (h + 0.22) * 0.9 + vec2(3.1, 1.7);
		float n = fbm2(uv);
		float dens = smoothstep(1.0 - cloud_cover - 0.06, 1.0 - cloud_cover + 0.2, n);
		float n2 = fbm2(uv + ld * 0.14);
		float lit = clamp(0.5 + (n - n2) * 4.5, 0.0, 1.0);       // más claro del lado de la luz
		vec3 ccol = mix(cloud_shade, cloud_lit, lit);
		ccol = mix(ccol, cloud_pink, clamp(warm * (1.1 - lit), 0.0, 1.0));
		col = mix(col, ccol, dens * fade * 0.93);

		// cirros: franjas finas y altas
		vec2 uv2 = d.xz / (h + 0.55) * vec2(0.6, 2.6) + vec2(7.3, 2.1);
		float c = smoothstep(0.52, 0.86, fbm2(uv2 * 1.5));
		vec3 ccol2 = mix(cloud_lit, cloud_pink, warm * 0.8);
		col = mix(col, ccol2, c * 0.5 * fade * (1.0 - dens * 0.6));
	} else {
		col = horizon_col;                          // bajo el horizonte lo cubre el piso
	}
	COLOR = col;
}
