shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;
// Tela de Andro: tres capas de tela negra mate sobre una esfera invisible (campo de fuerza).
// COLOR.r = capa (0 interior, 0.5 intermedia, 1 manto exterior). La parte baja se mueve sola:
// `drift` es el arrastre (resorte-amortiguador calculado en GDScript) y `flutter` el aleteo.
// Cada capa se mueve un poco distinto, así se separan al correr y se juntan al quedarse quieto.

uniform vec3 albedo_col : source_color = vec3(0.04, 0.04, 0.05);
uniform vec3 rim_col : source_color = vec3(0.50, 0.54, 0.62);
uniform vec3 drift = vec3(0.0);
uniform float flutter = 0.03;
uniform float cloth_top = 1.5;      // sobre esta altura la tela está "pegada" a la esfera
uniform float cloth_bottom = 0.05;
uniform float flare = 0.0;          // abre la falda (al golpear / saltar)

varying float w_cloth;
varying float layer;

void vertex() {
	layer = COLOR.r;
	float t = clamp((cloth_top - VERTEX.y) / (cloth_top - cloth_bottom), 0.0, 1.0);
	float w = t * t * (1.45 - 0.45 * t);
	w_cloth = w;
	vec2 rad = VERTEX.xz;
	float rl = length(rad);
	vec2 dir = rl > 0.0001 ? rad / rl : vec2(0.0, 1.0);
	float ang = atan(VERTEX.z, VERTEX.x);
	float rip = sin(ang * 5.0 + TIME * 2.1 + VERTEX.y * 3.0 + layer * 2.4) * 0.6
			+ sin(ang * 9.0 - TIME * 3.3 + VERTEX.y * 5.0 - layer * 1.7) * 0.4;
	float lag = 0.8 + 0.4 * layer;                 // el manto exterior se arrastra más que la capa interior
	vec3 off = vec3(drift.x, 0.0, drift.z) * w * lag;
	off.xz += dir * (rip * flutter + flare) * w * (0.8 + 0.4 * layer);
	off.y += (drift.y - length(drift.xz) * 0.22) * w * lag;
	VERTEX += off;
}

void fragment() {
	// cada capa un poco más clara hacia afuera: se leen los mantos superpuestos
	ALBEDO = albedo_col * (0.8 + 0.45 * layer + 0.35 * w_cloth);
	ROUGHNESS = 0.88;
	SPECULAR = 0.25;
	RIM = 0.55;
	RIM_TINT = 0.65;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_col * fres * 0.24;
}
