shader_type spatial;
// Piso del Umbral: superficie lisa y pulida, azul grisáceo oscuro, con manchas de color muy suaves bajo la superficie
// (como humo atrapado en vidrio). Sin líneas ni elementos; las manchas dan referencia de movimiento. Refleja el cielo.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 base_col : source_color = vec3(0.105, 0.11, 0.14);
uniform float fade_dist = 40.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Tres colores suaves (cian, violeta, rosa) mezclados: nada de arcoíris.
vec3 pastel(float t) {
	vec3 c = mix(vec3(0.25, 0.70, 0.80), vec3(0.60, 0.45, 0.90), smoothstep(0.2, 0.55, t));
	return mix(c, vec3(0.90, 0.55, 0.70), smoothstep(0.55, 0.9, t));
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = texture(noise_tex, p * 0.011).r;
	float n2 = texture(noise_tex, p * 0.043 + vec2(0.31, 0.77)).r;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float fade = exp(-dist / fade_dist);
	vec3 pal = pastel(n1);
	ALBEDO = base_col * (0.8 + 0.5 * n2);
	ROUGHNESS = 0.42 + 0.2 * n2;
	METALLIC = 0.0;
	SPECULAR = 0.45;
	EMISSION = pal * smoothstep(0.3, 0.8, n2) * 0.05 * fade;
}
