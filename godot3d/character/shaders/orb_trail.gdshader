shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Estela de vidrio de una esfera de Andro: tubo fino que se desvanece hacia atrás (COLOR.a = desvanecido).

uniform vec3 col : source_color = vec3(0.86, 0.89, 0.95);
uniform float glow = 0.0;

void fragment() {
	ALBEDO = col + vec3(glow * 0.4);
	ALPHA = COLOR.a * (0.5 + glow * 0.5);
}
