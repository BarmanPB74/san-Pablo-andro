shader_type spatial;
// Plastilina stop-motion (modo "plastilina"). ClayStyle crea variantes cambiando esta línea:
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Variante con recorte alfa: ClayStyle reemplaza la marca #ALPHA al final de fragment().

// ---- color base (copiado del material original) ----
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_tex = false;
uniform int uv_mode = 0;              // 0 = UV de la malla, 1 = triplanar de mundo, 2 = triplanar de objeto
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float tex_blur = 0.35;         // sesgo de mip: borra el detalle fotográfico fino, deja la forma
uniform float tex_keep = 1.0;        // cuánto patrón de la textura se conserva (0 = color plano)
uniform bool use_vcolor = false;
uniform bool vcolor_srgb = true;
uniform float alpha_cut = 0.5;

// ---- arcilla ----
uniform sampler2D clay_tex : filter_linear_mipmap, repeat_enable;   // RG = normal, B = altura
uniform float clay_scale = 1.4;       // repeticiones por metro
uniform float clay_bump = 0.75;
uniform float clay_cavity = 0.35;     // oscurece los surcos (huellas, presiones)
uniform bool clay_local = false;      // true: el detalle viaja con el objeto (personaje, autos)
uniform float rough = 0.6;
uniform float spec = 0.35;
uniform float sheen = 0.35;           // borde aterciopelado de la plastilina
uniform float metal = 0.0;

// ---- gradación de color "pueblo de plastilina" ----
uniform float saturation = 0.95;
uniform float brick_shift = 0.02;    // naranjas → rojo ladrillo/frambuesa
uniform vec3 grey_tint : source_color = vec3(0.82, 0.76, 0.86);   // grises → piedra malva fría
uniform float grey_amount = 0.55;
uniform vec3 moss_tint : source_color = vec3(0.34, 0.62, 0.22);
uniform float moss_amount = 0.6;
uniform float value_lift = 0.04;      // la plastilina nunca es negro puro

// ---- emisión ----
uniform bool has_emission = false;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 1.0;
uniform sampler2D emission_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_emission_tex = false;
uniform bool emission_add = true;

varying vec3 v_pos;
varying vec3 v_nrm;

void vertex() {
	if (clay_local || uv_mode == 2) {
		v_pos = VERTEX;
		v_nrm = NORMAL;
	} else {
		v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		v_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	}
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

vec3 clay_grade(vec3 c) {
	vec3 hsv = rgb2hsv(c);
	float orange = smoothstep(0.015, 0.04, hsv.x) * (1.0 - smoothstep(0.12, 0.17, hsv.x)) * smoothstep(0.12, 0.3, hsv.y);
	hsv.x = fract(hsv.x - brick_shift * orange + 1.0);
	float green = smoothstep(0.14, 0.2, hsv.x) * (1.0 - smoothstep(0.48, 0.54, hsv.x)) * smoothstep(0.05, 0.16, hsv.y);
	hsv.y = clamp(hsv.y * saturation * (1.0 + 0.25 * green), 0.0, 1.0);
	// ladrillo granate apagado (no rojo chillón)
	float warm = (1.0 - smoothstep(0.1, 0.16, hsv.x)) + smoothstep(0.9, 0.96, hsv.x);
	hsv.y *= mix(1.0, 0.68, warm * smoothstep(0.25, 0.5, hsv.y));
	vec3 o = hsv2rgb(hsv);
	o = mix(o, moss_tint * clamp(hsv.z / 0.4, 0.0, 1.3), green * moss_amount);   // verdes oscuros (postes) siguen oscuros
	float grey = (1.0 - smoothstep(0.06, 0.24, hsv.y)) * (1.0 - green);
	o = mix(o, hsv.z * grey_tint * 1.08, grey * grey_amount);
	return o * (1.0 - value_lift) + value_lift * vec3(0.16, 0.12, 0.17);
}

vec3 tri_w(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z + 1e-5);
}

vec4 sample_albedo(vec2 uv) {
	if (uv_mode == 0) {
		return texture(albedo_tex, uv * uv_scale.xy + uv_offset.xy, tex_blur);
	}
	vec3 w = tri_w(v_nrm);
	vec3 p = v_pos * uv_scale + uv_offset;
	return texture(albedo_tex, p.zy, tex_blur) * w.x
		+ texture(albedo_tex, p.xz, tex_blur) * w.y
		+ texture(albedo_tex, p.xy, tex_blur) * w.z;
}

void fragment() {
	vec4 col = base_color;
	if (has_tex) {
		vec4 t = sample_albedo(UV);
		col.rgb = mix(base_color.rgb * 0.8, base_color.rgb * t.rgb, tex_keep);
		col.a *= t.a;
	}
	if (use_vcolor) {
		vec4 vc = COLOR;
		if (vcolor_srgb) {
			vc.rgb = pow(max(vc.rgb, vec3(0.0)), vec3(2.2));
		}
		col *= vc;
	}

	// detalle de arcilla triplanar (sin tangentes: se perturba la normal en el espacio de v_nrm)
	vec3 w = tri_w(v_nrm);
	vec3 p = v_pos * clay_scale;
	vec3 sx = texture(clay_tex, p.zy).rgb;
	vec3 sy = texture(clay_tex, p.xz + vec2(0.37, 0.71)).rgb;
	vec3 sz = texture(clay_tex, p.xy + vec2(0.53, 0.19)).rgb;
	vec2 dx = (sx.rg * 2.0 - 1.0) * clay_bump;
	vec2 dy = (sy.rg * 2.0 - 1.0) * clay_bump;
	vec2 dz = (sz.rg * 2.0 - 1.0) * clay_bump;
	vec3 n0 = normalize(v_nrm);
	vec3 pn = normalize(n0
		+ w.x * vec3(0.0, dx.y, dx.x)
		+ w.y * vec3(dy.x, 0.0, dy.y)
		+ w.z * vec3(dz.x, dz.y, 0.0));
	float h = sx.b * w.x + sy.b * w.y + sz.b * w.z;
	mat4 to_view = VIEW_MATRIX * ((clay_local || uv_mode == 2) ? MODEL_MATRIX : mat4(1.0));
	vec3 nv = normalize((to_view * vec4(pn, 0.0)).xyz);
	NORMAL = FRONT_FACING ? nv : -nv;

	vec3 graded = clay_grade(col.rgb);
	float cav = mix(1.0, smoothstep(0.0, 0.62, h), clay_cavity);
	ALBEDO = graded * cav;
	ROUGHNESS = clamp(rough + (0.5 - h) * 0.25, 0.25, 1.0);
	SPECULAR = spec;
	METALLIC = metal;
	RIM = sheen;
	RIM_TINT = 0.6;
	AO = mix(0.75, 1.0, smoothstep(0.1, 0.55, h));
	if (has_emission) {
		vec3 e = emission_color.rgb * emission_energy;
		if (has_emission_tex) {
			vec3 et = texture(emission_tex, UV * uv_scale.xy + uv_offset.xy).rgb;
			e = emission_add ? (emission_color.rgb + et) * emission_energy : e * et;
		}
		EMISSION = e;
	}
	// #ALPHA
}
