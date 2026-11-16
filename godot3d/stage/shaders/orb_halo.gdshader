shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Resplandor de una esfera de energía: un cuadro que siempre mira a la cámara con degradado radial.
// El tamaño va en la malla (QuadMesh), no en la escala del nodo.

uniform vec3 col : source_color = vec3(0.5, 0.8, 1.0);
uniform float intensity = 0.8;
uniform float power = 2.4;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float a = pow(clamp(1.0 - r, 0.0, 1.0), power);
	ALBEDO = col * intensity;
	ALPHA = a;
}
