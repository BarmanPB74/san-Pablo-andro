shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Lámina de humo: un plano horizontal con ruido en coordenadas de mundo (se mueve con el viento, no con el jugador).
// Varias láminas a distintas alturas hacen niebla espesa y en capas. Se desvanece con la distancia a la cámara.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 smoke_col : source_color = vec3(0.64, 0.65, 0.70);
uniform float opacity = 0.4;
uniform float tex_scale = 0.045;
uniform vec2 wind = vec2(0.5, 0.2);
uniform float coverage = 0.42;
uniform float tint_amt = 0.35;
uniform float far_fade = 48.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * tex_scale + wind * TIME * 0.03;
	float n1 = texture(noise_tex, uv).r;
	float n2 = texture(noise_tex, uv * 2.7 + vec2(0.37, 0.71) - wind * TIME * 0.02).r;
	float n = n1 * 0.62 + n2 * 0.38;
	float d = smoothstep(coverage, coverage + 0.28, n);
	float dist = length(wpos.xz - CAMERA_POSITION_WORLD.xz);
	float fade = smoothstep(far_fade, far_fade * 0.3, dist);
	// si la cámara casi toca la lámina no se ve el borde del plano
	float above = smoothstep(0.15, 1.2, abs(CAMERA_POSITION_WORLD.y - wpos.y));
	float pt = clamp(n1 * 1.2 + wpos.x * 0.004 - wpos.z * 0.003, 0.0, 1.0);
	vec3 pal = mix(vec3(0.25, 0.70, 0.80), vec3(0.60, 0.45, 0.90), smoothstep(0.2, 0.55, pt));
	pal = mix(pal, vec3(0.90, 0.55, 0.70), smoothstep(0.55, 0.9, pt));
	vec3 col = mix(smoke_col, mix(pal, vec3(1.0), 0.35), tint_amt * d);
	ALBEDO = col;
	ALPHA = d * opacity * fade * above;
}
