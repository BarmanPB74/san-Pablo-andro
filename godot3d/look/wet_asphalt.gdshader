shader_type spatial;
// Asfalto / andén mojado (dirección de color "ciudad tras la lluvia").
// Todo procedural en espacio de mundo (sin texturas): charcos por ruido fbm,
// roughness bajo en charcos, grano con normal sutil, fresnel que añade
// reflejo de cielo y ondas de lluvia animadas en los charcos.
// Compatible con renderer Mobile y Compatibility (sin SSR: el reflejo viene
// del cielo/radiance + especular de luces + término fresnel falso).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.11, 0.115, 0.125);
uniform vec3 puddle_color : source_color = vec3(0.025, 0.03, 0.035);
uniform float color_variation : hint_range(0.0, 1.0) = 0.35;
uniform float dry_roughness : hint_range(0.0, 1.0) = 0.78;
uniform float damp_roughness : hint_range(0.0, 1.0) = 0.38;
uniform float puddle_roughness : hint_range(0.0, 1.0) = 0.04;
// Controlados globalmente desde Palette.set_weather()
uniform float wetness : hint_range(0.0, 1.0) = 0.7;
uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sky_reflection : source_color = vec3(0.45, 0.5, 0.55);
// Forma de los charcos
uniform float puddle_coverage : hint_range(0.0, 1.0) = 0.55;
uniform float puddle_scale = 0.11;      // frecuencia por metro (manchas grandes)
uniform float grain_scale = 2.5;        // frecuencia del grano fino
uniform float normal_strength = 0.18;
uniform float reflect_boost : hint_range(0.0, 2.0) = 0.4;
// Losas (andén / baldosa). tile_size = 0 → sin juntas.
uniform float tile_size = 0.0;
uniform float groove_width = 0.025;
uniform vec3 groove_color : source_color = vec3(0.08, 0.08, 0.085);
uniform float tile_variation : hint_range(0.0, 1.0) = 0.12;
// Texturas PBR opcionales (Fase 1, art/tex/*). Proyección por coordenadas de mundo:
// XZ en caras horizontales (XY / ZY en caras verticales). use_tex = false → look procedural
// original sin ningún cambio. Con texturas, la humedad, los charcos y las ondas de lluvia se
// aplican ENCIMA: lo mojado y los charcos oscurecen el albedo y bajan la rugosidad del ORM.
uniform bool use_tex = false;
uniform sampler2D tex_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;   // OpenGL (Y+)
uniform sampler2D tex_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable; // R=AO G=rugosidad B=metal
uniform float tex_tile_m = 4.0;                                  // metros por repetición
uniform vec3 tex_tint : source_color = vec3(1.0);                // multiplica el albedo de la textura
uniform float tex_normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float tex_ao_strength : hint_range(0.0, 1.0) = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm3(vec2 p) {
	float s = 0.5 * vnoise(p);
	p = p * 2.03 + vec2(17.1, 9.3);
	s += 0.25 * vnoise(p);
	p = p * 2.01 + vec2(3.7, 41.2);
	s += 0.125 * vnoise(p);
	return s / 0.875;
}

void fragment() {
	vec2 p = wpos.xz;
	float up = smoothstep(0.6, 0.95, wnrm.y);   // charcos solo en caras horizontales

	// --- ruido base ---
	float big = fbm3(p * puddle_scale);
	vec2 gp = p * grain_scale;
	float g1 = vnoise(gp * 4.0);
	float g2 = vnoise(gp * 13.0 + 7.0);
	float grain = g1 * 0.55 + g2 * 0.45;

	// --- texturas opcionales (proyección mundo) ---
	vec3 t_alb = vec3(1.0);
	vec3 t_orm = vec3(1.0, dry_roughness, 0.0);
	vec2 t_n = vec2(0.0);
	if (use_tex) {
		vec3 an = abs(wnrm);
		vec2 tp = (an.y >= max(an.x, an.z)) ? wpos.xz : (an.x > an.z ? wpos.zy : wpos.xy);
		vec2 tuv = tp / max(tex_tile_m, 0.001);
		t_alb = texture(tex_albedo, tuv).rgb * tex_tint;
		t_orm = texture(tex_orm, tuv).rgb;
		t_n = texture(tex_normal, tuv).rg * 2.0 - 1.0;
	}

	// --- losas opcionales ---
	float groove = 0.0;
	float tile_tint = 1.0;
	if (tile_size > 0.0) {
		vec2 tc = p / tile_size;
		vec2 e = (0.5 - abs(fract(tc) - 0.5)) * tile_size;   // distancia al borde (m)
		float d = min(e.x, e.y);
		float aa = max(fwidth(d), 0.001);
		groove = 1.0 - smoothstep(groove_width - aa, groove_width + aa, d);
		tile_tint = 1.0 + (hash12(floor(tc)) - 0.5) * 2.0 * tile_variation;
	}

	// --- humedad y charcos ---
	float w = clamp(wetness, 0.0, 1.0);
	float thr = 0.78 - 0.36 * puddle_coverage * w;
	float puddle = smoothstep(thr, thr + 0.06, big + (grain - 0.5) * 0.04) * up * step(0.02, w);
	float damp = clamp(w * (0.55 + 0.6 * big) + groove * w, 0.0, 1.0);

	// --- color ---
	vec3 alb = use_tex ? t_alb * tile_tint
		: base_color * tile_tint * (1.0 + (grain - 0.5) * color_variation);
	alb = mix(alb, groove_color, groove);
	alb *= mix(1.0, 0.55, damp);                       // lo mojado oscurece
	alb = mix(alb, use_tex ? alb * 0.42 : puddle_color, puddle);   // con textura: el agua oscurece lo de abajo

	// --- normal: grano (seco) + ondas de lluvia (charcos) ---
	float eps = 0.02;
	float gx = vnoise((gp + vec2(eps, 0.0)) * 4.0) - g1;
	float gz = vnoise((gp + vec2(0.0, eps)) * 4.0) - g1;
	vec3 n = use_tex
		? wnrm + vec3(t_n.x, 0.0, -t_n.y) * tex_normal_strength * (1.0 - puddle) * up
		: wnrm + vec3(-gx, 0.0, -gz) * (normal_strength * 6.0) * (1.0 - puddle) * up;
	if (rain > 0.01) {
		vec2 rp = p * 1.6;
		vec2 cell = floor(rp);
		vec2 f = fract(rp) - 0.5;
		float h = hash12(cell);
		float t = fract(TIME * 1.1 + h);
		vec2 c = (vec2(hash12(cell + 3.1), hash12(cell + 7.7)) - 0.5) * 0.5;
		vec2 dv = f - c;
		float d = length(dv);
		float rad = t * 0.45;
		float ring = sin((d - rad) * 55.0) * (1.0 - t) * (1.0 - smoothstep(0.0, 0.07, abs(d - rad)));
		vec2 dir = dv / max(d, 1e-3);
		n += vec3(dir.x, 0.0, dir.y) * ring * 0.2 * rain * (0.3 + 0.7 * puddle) * up;
	}
	n = normalize(n);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// --- respuesta especular ---
	float rough = use_tex
		? mix(t_orm.g, min(t_orm.g, damp_roughness * (0.7 + 0.6 * t_orm.g)), damp)
		: mix(dry_roughness, damp_roughness, damp) * (0.85 + 0.3 * grain);
	rough = mix(rough, puddle_roughness, puddle);
	rough = mix(rough, 0.9, groove * (1.0 - w));
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 5.0);

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	AO = use_tex ? mix(1.0, t_orm.r, tex_ao_strength) : 1.0;   // 1.0 = sin oclusión (look original intacto)
	SPECULAR = mix(0.5, 1.0, max(puddle, damp * 0.5));
	// reflejo de cielo falso (fresnel): da el brillo plateado del asfalto mojado
	// incluso donde el radiance del cielo es pobre (Mobile, cubemap pequeño).
	// color según la elevación del rayo reflejado: horizonte claro → cénit más oscuro
	vec3 vw = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
	vec3 rw = reflect(-vw, n);
	vec3 refl = mix(sky_reflection, sky_reflection * 0.45, sqrt(clamp(rw.y, 0.0, 1.0)));
	EMISSION = refl * fres * reflect_boost * (puddle * 0.9 + damp * 0.2);
}
