shader_type canvas_item;
// Post-proceso de pantalla completa: viñeta teal-negra, grano fino de película
// y aberración cromática leve solo en los bordes. 3 lecturas de textura por píxel.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.38;
uniform float vignette_radius : hint_range(0.2, 1.2) = 0.78;
uniform float vignette_softness : hint_range(0.05, 1.0) = 0.55;
uniform vec3 vignette_color : source_color = vec3(0.0, 0.015, 0.02);
uniform float grain_amount : hint_range(0.0, 0.2) = 0.03;
uniform float aberration : hint_range(0.0, 0.02) = 0.0025;
// Estilo "tinta y papel" (ilustración): 0 = apagado (look normal, sin costo extra)
uniform float ink_amount : hint_range(0.0, 1.0) = 0.0;     // contorno de tinta en bordes de luminancia
uniform float paper_amount : hint_range(0.0, 1.0) = 0.0;   // mezcla hacia duotono tinta/papel
uniform vec3 ink_color : source_color = vec3(0.06, 0.055, 0.05);
uniform vec3 paper_color : source_color = vec3(0.82, 0.79, 0.66);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	vec2 off = c * aberration * r2 * 4.0;   // crece hacia los bordes, 0 en el centro
	vec3 col;
	col.r = texture(screen_tex, uv - off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv + off).b;

	if (ink_amount > 0.001 || paper_amount > 0.001) {
		float l0 = dot(col, vec3(0.299, 0.587, 0.114));
		vec2 px = SCREEN_PIXEL_SIZE * 1.3;
		float lx = dot(texture(screen_tex, uv + vec2(px.x, 0.0)).rgb, vec3(0.299, 0.587, 0.114))
			- dot(texture(screen_tex, uv - vec2(px.x, 0.0)).rgb, vec3(0.299, 0.587, 0.114));
		float ly = dot(texture(screen_tex, uv + vec2(0.0, px.y)).rgb, vec3(0.299, 0.587, 0.114))
			- dot(texture(screen_tex, uv - vec2(0.0, px.y)).rgb, vec3(0.299, 0.587, 0.114));
		float edge = smoothstep(0.08, 0.26, length(vec2(lx, ly)));
		// duotono: sombras en tinta, luces en papel; conserva un poco del color original
		float t = smoothstep(0.0, 0.62, l0);
		vec3 duo = mix(ink_color, paper_color, pow(t, 0.7));
		col = mix(col, mix(duo, col, 0.3), paper_amount);
		// textura de papel: variación suave de baja frecuencia
		float pn = hash(floor(FRAGCOORD.xy / 3.0)) - 0.5;
		col *= 1.0 + pn * 0.05 * paper_amount;
		col = mix(col, ink_color, edge * ink_amount);
	}

	// grano: más visible en sombras/medios tonos, como película
	float n = hash(FRAGCOORD.xy + fract(TIME * 7.13) * 917.0) - 0.5;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col += n * grain_amount * (1.0 - 0.7 * lum);

	// viñeta (corrige el aspecto con la relación de la pantalla)
	vec2 cv = c * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	cv.x *= 0.75;
	float d = length(cv) * 1.4;
	float v = smoothstep(vignette_radius, vignette_radius - vignette_softness, d);
	col = mix(vignette_color, col, mix(1.0, v, vignette_strength));

	COLOR = vec4(col, 1.0);
}
