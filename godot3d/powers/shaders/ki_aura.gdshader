shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Aura de ki (estilo Dragon Ball): llamas verticales que suben por un cilindro abierto alrededor de Andro.
// `power` 0..1 es la intensidad; `phase` desfasa las dos capas; `height` es la altura del cilindro.
uniform float power : hint_range(0.0, 1.5) = 0.0;
uniform float phase = 0.0;
uniform float height = 2.5;
uniform vec3 core_col : source_color = vec3(1.0, 0.92, 0.62);
uniform vec3 edge_col : source_color = vec3(1.0, 0.42, 0.08);

varying float h;
varying float ang;

void vertex() {
	h = clamp((VERTEX.y + height * 0.5) / height, 0.0, 1.0);
	ang = atan(VERTEX.z, VERTEX.x);
	float wob = 1.0 + 0.10 * sin(TIME * 9.0 + h * 7.0 + ang * 3.0 + phase) * h
			+ 0.07 * sin(TIME * 14.0 - h * 11.0 + ang * 5.0 + phase * 2.0) * h;
	float tip = 1.0 - 0.35 * h * h;                       // se cierra hacia arriba como una llama
	VERTEX.xz *= wob * tip * (0.85 + 0.25 * power);
	VERTEX.y += sin(TIME * 12.0 + ang * 4.0 + phase) * 0.06 * h;
}

void fragment() {
	float s1 = 0.5 + 0.5 * sin(ang * 9.0 + h * 5.0 - TIME * 8.0 + phase);
	float s2 = 0.5 + 0.5 * sin(ang * 5.0 - h * 8.0 - TIME * 5.0 + phase * 1.7);
	float streak = pow(s1 * 0.6 + s2 * 0.4, 2.2);
	float fade = pow(1.0 - h, 1.3) * smoothstep(0.0, 0.07, h);
	float fres = pow(1.0 - clamp(abs(dot(normalize(NORMAL), VIEW)), 0.0, 1.0), 1.2);
	float a = streak * fade * (0.45 + 1.0 * fres) * power * 1.6;
	ALBEDO = mix(edge_col, core_col, clamp(streak * 0.8 + (1.0 - h) * 0.3, 0.0, 1.0)) * 1.5;
	ALPHA = clamp(a, 0.0, 1.0);
}
