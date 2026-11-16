shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;
// Tela de Andro (ref. 84070): cúpula lisa sobre la esfera invisible, capa interior y manto exterior abierto al frente
// con ribetes ornamentados (borde de la abertura y dobladillo). Todo procedural.
// Datos de vértice: COLOR.r = capa (0 interior, 1 manto), COLOR.g = distancia al borde de la abertura (m × 2),
// COLOR.b = distancia al dobladillo (m × 2), COLOR.a = abertura (0 cerrada .. 1 abierta). UV = (arco m, altura m).
// La parte baja se mueve sola: `drift` es el arrastre (resorte-amortiguador calculado en GDScript) y `flutter` el aleteo.

uniform vec3 albedo_col : source_color = vec3(0.016, 0.016, 0.021);
uniform vec3 trim_col : source_color = vec3(0.2, 0.2, 0.23);
uniform vec3 rim_col : source_color = vec3(0.50, 0.54, 0.62);
uniform vec3 drift = vec3(0.0);
uniform float flutter = 0.03;
uniform float cloth_top = 1.45;     // sobre esta altura la tela está "pegada" a la esfera
uniform float cloth_bottom = 0.05;
uniform float flare = 0.0;          // abre la falda (al golpear / saltar)
uniform float trim_edge_w = 0.10;  // ancho del ribete de la abertura (m)
uniform float trim_hem_w = 0.088;   // ancho del ribete del dobladillo (m)

varying float w_cloth;
varying float layer;
varying float edge_d;
varying float hem_d;
varying float gap_open;
varying vec2 vuv;

void vertex() {
	layer = COLOR.r;
	edge_d = COLOR.g * 0.5;
	hem_d = COLOR.b * 0.5;
	gap_open = COLOR.a;
	vuv = UV;
	float t = clamp((cloth_top - VERTEX.y) / (cloth_top - cloth_bottom), 0.0, 1.0);
	float w = t * t * (1.45 - 0.45 * t);
	w_cloth = w;
	vec2 rad = VERTEX.xz;
	float rl = length(rad);
	vec2 dir = rl > 0.0001 ? rad / rl : vec2(0.0, 1.0);
	float ang = atan(VERTEX.z, VERTEX.x);
	float rip = sin(ang * 5.0 + TIME * 2.1 + VERTEX.y * 3.0 + layer * 2.4) * 0.6
			+ sin(ang * 9.0 - TIME * 3.3 + VERTEX.y * 5.0 - layer * 1.7) * 0.4;
	float lag = 0.85 + 0.35 * layer;                // el manto exterior se arrastra más que la capa interior
	vec3 off = vec3(drift.x, 0.0, drift.z) * w * lag;
	off.xz += dir * (rip * flutter + flare) * w * (0.85 + 0.3 * layer);
	off.y += (drift.y - length(drift.xz) * 0.22) * w * lag;
	VERTEX += off;
}

// Ribete: p.x = distancia al borde de la tela (m), p.y = coordenada a lo largo (m), w = ancho de la banda.
// Dibuja una enredadera ondulada con hojas entre dos filetes.
float ornament(vec2 p, float w) {
	float u = clamp(p.x / w, 0.0, 1.0);
	float s = p.y / 0.12;
	float wave = sin(s * 6.2832);
	float vine = abs(u - 0.5 - 0.2 * wave);
	float line = 1.0 - smoothstep(0.03, 0.08, vine);
	vec2 c = vec2(fract(s) - 0.5, (u - 0.5 - 0.2 * sign(wave)) * 0.9);
	float leaf = 1.0 - smoothstep(0.1, 0.22, length(c * vec2(1.4, 1.0)));
	float rails = (1.0 - smoothstep(0.03, 0.07, abs(u - 0.08))) + (1.0 - smoothstep(0.03, 0.07, abs(u - 0.92)));
	float aa = 1.0 - smoothstep(0.25, 0.6, fwidth(s));       // lejos, sin detalle (evita parpadeo)
	return clamp((line + leaf * 0.75) * aa + rails, 0.0, 1.0);
}

void fragment() {
	float outer = step(0.5, layer);
	float open_k = smoothstep(0.08, 0.5, gap_open);
	float ae = max(fwidth(edge_d), 0.0004) * 1.2;
	float ah = max(fwidth(hem_d), 0.0004) * 1.2;
	float in_edge = (1.0 - smoothstep(trim_edge_w - ae, trim_edge_w + ae, edge_d)) * open_k * outer;
	float in_hem = (1.0 - smoothstep(trim_hem_w - ah, trim_hem_w + ah, hem_d)) * outer;
	float trim = max(in_edge, in_hem);
	float orn;
	if (in_edge >= in_hem) {
		orn = ornament(vec2(edge_d, vuv.y), trim_edge_w);
	} else {
		orn = ornament(vec2(hem_d, vuv.x), trim_hem_w);
	}

	// tela: la cúpula es un poco más clara y satinada (reflejo suave); la falda interior es la más oscura
	float dome = smoothstep(cloth_top - 0.25, cloth_top + 0.12, vuv.y);
	float skirt = 1.0 - dome;
	float pleat = 0.5 + 0.5 * sin(vuv.x * 38.0 + layer * 1.7);
	// brocado suave sobre el manto (casi imperceptible de cerca, desaparece de lejos)
	vec2 bp = vec2(vuv.x * 21.0, vuv.y * 17.0);
	float damask = 0.5 + 0.5 * sin(bp.x + 1.6 * sin(bp.y)) * sin(bp.y * 0.9 + 1.3 * sin(bp.x * 0.8));
	damask *= 1.0 - smoothstep(0.35, 0.9, fwidth(bp.x));
	float cloth_k = mix(0.7, 1.0, layer) * mix(1.0 + 0.45 * pleat, 1.7, dome) * (1.0 + 0.5 * outer * skirt * damask);
	vec3 cloth = albedo_col * cloth_k;
	vec3 trim_c = trim_col * (0.45 + 0.95 * orn);
	ALBEDO = mix(cloth, trim_c, trim);
	ROUGHNESS = mix(mix(0.88, 0.62, dome), 0.42, trim);
	METALLIC = trim * 0.3;
	SPECULAR = mix(mix(0.25, 0.32, dome), 0.5, trim);
	RIM = 0.55;
	RIM_TINT = 0.65;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_col * fres * 0.2 + trim_c * trim * 0.12;
}
