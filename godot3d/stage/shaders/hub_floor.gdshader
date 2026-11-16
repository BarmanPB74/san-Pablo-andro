shader_type spatial;
// Piso del umbral: losa oscura y pulida con vetas doradas (ref. 83528). Plano y sin geometría.

uniform vec3 base_col : source_color = vec3(0.08, 0.10, 0.15);
uniform vec3 line_col : source_color = vec3(0.80, 0.62, 0.30);
uniform float cell = 3.2;
uniform float line_w = 0.035;
uniform float fade_dist = 70.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid(vec2 p, float c, float w) {
	vec2 g = abs(fract(p / c - 0.5) - 0.5) * c;
	float d = min(g.x, g.y);
	float aa = max(fwidth(d), 0.0001);
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + aa * 1.5, d);
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 w = p + vec2(sin(p.y * 0.21) * 0.35, cos(p.x * 0.17) * 0.35);
	float l1 = grid(w, cell, line_w);
	// segunda familia de vetas, rotada, más fina y espaciada
	float ca = 0.8, sa = 0.6;
	vec2 r = vec2(ca * w.x - sa * w.y, sa * w.x + ca * w.y);
	float l2 = grid(r, cell * 2.7, line_w * 0.6) * 0.7;
	float lines = max(l1, l2);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float fade = exp(-dist / fade_dist);
	float fw = length(fwidth(p)) / cell;
	lines *= fade * (1.0 - smoothstep(0.04, 0.22, fw));
	// manchas suaves en la losa para que no sea un color plano
	float tile = fract(sin(dot(floor(w / cell), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 base = base_col * (0.8 + 0.5 * tile);
	ALBEDO = mix(base, line_col, lines);
	ROUGHNESS = mix(0.24 + 0.1 * tile, 0.4, lines);
	METALLIC = mix(0.35, 0.9, lines);
	SPECULAR = 0.9;
	EMISSION = line_col * lines * 0.28;
}
