shader_type spatial;
render_mode unshaded, cull_back;
// Núcleo de la bola de fuego: centro blanco-amarillo, borde naranja que parpadea. Sin luz (el halo y la luz aportan el brillo).
uniform vec3 core_col : source_color = vec3(1.0, 0.93, 0.66);
uniform vec3 edge_col : source_color = vec3(1.0, 0.32, 0.04);

void fragment() {
	vec3 n = normalize(NORMAL);
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 1.6);
	float flick = 0.5 + 0.5 * sin(TIME * 23.0 + n.y * 7.0 + n.x * 5.0 + n.z * 3.0);
	flick = 0.75 + 0.25 * flick * (0.5 + 0.5 * sin(TIME * 13.0 + n.x * 9.0));
	ALBEDO = mix(core_col, edge_col, fres) * (1.0 + 0.5 * flick);
}
