shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Zarcillos NEGROS que se mezclan con el aura morada (etapa "morado y negro" del ki). No es aditivo: el negro tapa la luz.
uniform float power : hint_range(0.0, 1.5) = 0.0;
uniform float height = 2.5;
varying float h;
varying float ang;

void vertex() {
	h = clamp((VERTEX.y + height * 0.5) / height, 0.0, 1.0);
	ang = atan(VERTEX.z, VERTEX.x);
	float wob = 1.0 + 0.12 * sin(TIME * 7.0 + h * 9.0 + ang * 4.0) * h;
	VERTEX.xz *= wob * (1.0 - 0.3 * h * h) * (0.9 + 0.2 * power);
}

void fragment() {
	float s = 0.5 + 0.5 * sin(ang * 7.0 - h * 6.0 - TIME * 4.5);
	float s2 = 0.5 + 0.5 * sin(ang * 13.0 + h * 9.0 + TIME * 3.0);
	float streak = smoothstep(0.62, 0.95, s * 0.7 + s2 * 0.3);
	float fade = pow(1.0 - h, 1.1) * smoothstep(0.0, 0.1, h);
	ALBEDO = vec3(0.015, 0.0, 0.03);
	ALPHA = clamp(streak * fade * power * 1.2, 0.0, 0.9);
}
