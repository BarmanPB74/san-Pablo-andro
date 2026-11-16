shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Telón de cascadas de niebla (ref. 83532): masas grises que caen en vertical. Se repite sin costuras.
uniform vec3 light_col : source_color = vec3(0.86, 0.89, 0.92);
uniform vec3 mid_col : source_color = vec3(0.55, 0.60, 0.65);
uniform vec3 dark_col : source_color = vec3(0.22, 0.26, 0.31);
uniform float cells_x = 22.0;           // entero: nº de celdas alrededor (repetición sin costura)
uniform float flow = 0.012;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, period);
	float x1 = mod(i.x + 1.0, period);
	return mix(mix(hash21(vec2(x0, i.y)), hash21(vec2(x1, i.y)), f.x),
			mix(hash21(vec2(x0, i.y + 1.0)), hash21(vec2(x1, i.y + 1.0)), f.x), f.y);
}

float fbm(vec2 p, float period) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p, period);
		p *= 2.0;
		period *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = vec2(UV.x * cells_x, UV.y * 5.0);
	float t = TIME * flow * 40.0;
	// masas verticales: estiradas en y y desplazadas hacia abajo
	float n1 = fbm(vec2(uv.x, uv.y * 0.55 + t * 0.35), cells_x);
	float n2 = fbm(vec2(uv.x * 2.0, uv.y * 0.9 + t * 0.6), cells_x * 2.0);
	float v = n1 * 0.65 + n2 * 0.35;
	float g = smoothstep(0.25, 0.8, v);
	vec3 col = mix(dark_col, mid_col, smoothstep(0.0, 0.5, g));
	col = mix(col, light_col, smoothstep(0.45, 1.0, g));
	// más claro hacia abajo (bruma al pie) y más oscuro arriba
	col *= mix(1.05, 0.78, smoothstep(0.55, 1.0, UV.y)) ;
	col = mix(col, light_col, smoothstep(0.1, 0.0, UV.y) * 0.8);
	ALBEDO = col;
}
