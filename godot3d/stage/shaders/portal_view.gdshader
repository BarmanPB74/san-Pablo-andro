shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;
// Interior de los portales por etapa de la historia, recortado en forma de arco:
//   0 piedra    → remolino blanco-azulado (ref. 84869)
//   1 celestial → amanecer dorado entre nubes con destellos (ref. 84870)
//   2 dorado    → cosmos negro con polvo y estrellas doradas (ref. 84871)
// `reveal` abre el portal desde el centro (0 = cerrado, 1 = abierto).

uniform int style = 0;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform vec2 size = vec2(2.6, 5.6);              // ancho × alto de la abertura (m)

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(7.1, 3.7);
		a *= 0.5;
	}
	return v;
}

float stars(vec2 uv, float density, float cell) {
	vec2 sp = uv * cell;
	float st = hash21(floor(sp));
	vec2 f = fract(sp) - 0.5;
	float tw = 0.6 + 0.4 * sin(TIME * (1.5 + 3.0 * hash21(floor(sp) + 9.0)) + st * 30.0);
	return step(1.0 - density, st) * smoothstep(0.38, 0.0, length(f)) * tw;
}

void fragment() {
	vec2 uv = UV;
	float m = (uv.x - 0.5) * size.x;
	float ym = (1.0 - uv.y) * size.y;
	float r = size.x * 0.5;
	float y0 = size.y - r;
	float d = ym > y0 ? length(vec2(m, ym - y0)) : abs(m);
	float arch = 1.0 - smoothstep(r - 0.05, r, d);
	float dist = length((uv - 0.5) * vec2(1.25, 0.72)) * 2.0;
	float iris = 1.0 - smoothstep(reveal * 1.6 - 0.3, reveal * 1.6, dist);

	vec2 q = vec2(m / size.x, (ym - size.y * 0.45) / size.y) * vec2(size.x / size.y, 1.0) * 2.6;
	vec3 col = vec3(0.0);
	if (style == 0) {
		float rr = length(q);
		float a = atan(q.y, q.x);
		float s = a * 1.0 + log(rr + 0.06) * 4.2 - TIME * 0.55;
		float band = pow(0.5 + 0.5 * cos(s * 3.0 + fbm(q * 3.0) * 2.5), 1.6);
		float streak = fbm(vec2(a * 3.0 + TIME * 0.1, rr * 6.0 - TIME * 0.4));
		float fall = exp(-rr * 0.9);
		col = mix(vec3(0.03, 0.07, 0.16), vec3(0.78, 0.88, 1.0), band * fall * (0.6 + 0.7 * streak));
		col += vec3(0.7, 0.82, 1.0) * exp(-rr * 5.0) * 1.1;
		// lejos, en el fondo del remolino, las dunas oscuras
		col = mix(col, vec3(0.02, 0.05, 0.11), smoothstep(0.30, 0.0, uv.y - 0.72) * 0.5);
		col += vec3(stars(uv * vec2(size.x / size.y, 1.0), 0.04, 55.0)) * 0.6;
	} else if (style == 1) {
		float h = uv.y;                                      // 0 arriba, 1 abajo
		vec3 sky = mix(vec3(0.30, 0.52, 0.92), vec3(0.98, 0.86, 0.55), smoothstep(0.1, 0.75, h));
		float sun = exp(-length((uv - vec2(0.5, 0.62)) * vec2(1.6, 1.0)) * 5.0);
		float cl = fbm(vec2(uv.x * 4.0 + TIME * 0.02, uv.y * 7.0));
		float cloud = smoothstep(0.42, 0.78, cl) * smoothstep(0.52, 0.95, h);
		col = sky + vec3(1.0, 0.95, 0.7) * sun * 1.3;
		col = mix(col, vec3(1.0, 0.93, 0.92) * (0.82 + 0.3 * sun), cloud * 0.9);
		col += vec3(stars(uv * vec2(size.x / size.y, 1.0), 0.05, 45.0)) * smoothstep(0.55, 0.1, h);
	} else {
		float neb = fbm(q * 2.2 + vec2(TIME * 0.015, 0.0));
		float rr = length(q);
		col = vec3(0.012, 0.012, 0.03) + vec3(0.45, 0.32, 0.1) * neb * neb * 0.8 * exp(-rr * 0.6);
		col += vec3(1.0, 0.8, 0.35) * stars(uv * vec2(size.x / size.y, 1.0), 0.10, 60.0) * 1.4;
		col += vec3(0.9, 0.7, 0.3) * stars(uv * vec2(size.x / size.y, 1.0) + 3.7, 0.04, 28.0) * 1.8;
		col += vec3(1.0, 0.72, 0.28) * smoothstep(0.7, 1.0, uv.y) * 0.8;       // luz de la escalera al pie
	}
	ALBEDO = col;
	ALPHA = arch * iris;
}
