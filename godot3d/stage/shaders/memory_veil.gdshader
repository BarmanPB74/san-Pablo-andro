shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// Velo de bruma que cubre cada puerta de la casa: oculta lo que hay al otro lado (el cuarto vecino aún no está cargado)
// y se siente como cruzar un recuerdo. Opaco y barato: dos capas de ruido que se desplazan despacio.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 col_dark : source_color = vec3(0.020, 0.020, 0.028);
uniform vec3 col_light : source_color = vec3(0.19, 0.20, 0.25);

void fragment() {
	vec2 uv = UV * vec2(1.0, 1.7);
	float n1 = texture(noise_tex, uv * 1.3 + vec2(TIME * 0.030, -TIME * 0.050)).r;
	float n2 = texture(noise_tex, uv * 2.9 + vec2(-TIME * 0.055, TIME * 0.020)).r;
	float m = clamp((n1 * 0.6 + n2 * 0.4 - 0.22) * 1.9, 0.0, 1.0);
	vec2 c = (UV - vec2(0.5, 0.42)) * vec2(1.0, 0.7);
	float vig = smoothstep(0.75, 0.0, length(c));          // la bruma es más clara hacia el centro
	ALBEDO = mix(col_dark, col_light, m * (0.30 + 0.70 * vig));
}
