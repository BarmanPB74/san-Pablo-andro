shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;
// Interior del portal: galaxia espiral con estrellas y nebulosa (ref. 83528).
// `reveal` abre el portal desde el centro (0 = cerrado, 1 = abierto).

uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float aspect = 0.5;                       // ancho / alto del portal
uniform vec3 deep_col : source_color = vec3(0.02, 0.04, 0.13);
uniform vec3 arm_col : source_color = vec3(0.42, 0.52, 0.95);
uniform vec3 dust_col : source_color = vec3(0.62, 0.40, 0.80);
uniform vec3 core_col : source_color = vec3(1.0, 0.95, 0.86);
uniform float spin = 0.22;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
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

void fragment() {
	vec2 uv = UV;
	// máscara de apertura (iris elíptico)
	float dist = length((uv - 0.5) * vec2(1.25, 0.72)) * 2.0;
	float mask = 1.0 - smoothstep(reveal * 1.6 - 0.3, reveal * 1.6, dist);
	// bordes suaves hacia el marco
	vec2 e = min(uv, 1.0 - uv);
	float edge = smoothstep(0.0, 0.03, min(e.x * aspect * 2.0, e.y));

	vec2 c = vec2(0.5, 0.60);
	vec2 q = (uv - c) * vec2(aspect, 1.0) * 2.6;
	float r = length(q);
	float a = atan(q.y, q.x);
	float s = a * 2.0 + log(r + 0.03) * 5.5 - TIME * spin;
	float arms = pow(0.5 + 0.5 * cos(s), 2.2) * exp(-r * 1.9);
	float dust = fbm(q * 4.0 + vec2(TIME * 0.01, 0.0));
	float core = exp(-r * 9.0);
	float halo = exp(-r * 3.0);

	vec2 sp = uv * vec2(aspect, 1.0) * 70.0;
	float st = hash21(floor(sp));
	vec2 f = fract(sp) - 0.5;
	float star = step(0.965, st) * smoothstep(0.35, 0.0, length(f)) * (0.5 + 0.5 * hash21(floor(sp) + 3.1));

	vec3 col = deep_col + dust * dust_col * 0.22;
	col += arm_col * arms * (0.7 + dust * 0.9);
	col += dust_col * halo * 0.25;
	col += core_col * core * 1.6;
	col += vec3(star);

	ALBEDO = col;
	ALPHA = mask * edge;
}
