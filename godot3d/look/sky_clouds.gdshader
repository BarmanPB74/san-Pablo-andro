shader_type sky;
// Cielo nublado plateado (estilo "después de la lluvia"). Sin TIME: el
// radiance cubemap se recalcula solo cuando cambian los uniforms (preset),
// así no cuesta nada por frame en móvil.

uniform vec3 zenith_color : source_color = vec3(0.32, 0.38, 0.44);
uniform vec3 horizon_color : source_color = vec3(0.68, 0.72, 0.74);
uniform vec3 ground_color : source_color = vec3(0.12, 0.13, 0.13);
uniform vec3 cloud_light : source_color = vec3(0.82, 0.84, 0.86);
uniform vec3 cloud_dark : source_color = vec3(0.36, 0.4, 0.43);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.75;
uniform float cloud_scale = 1.4;
uniform float cloud_sharpness : hint_range(0.01, 1.0) = 0.35;
uniform vec2 cloud_offset = vec2(0.0, 0.0);
uniform float sun_glow : hint_range(0.0, 4.0) = 0.6;     // halo alrededor del sol
uniform float sun_disk : hint_range(0.0, 20.0) = 0.0;    // disco (0 = tapado)
uniform float silver_lining : hint_range(0.0, 4.0) = 0.8; // bordes iluminados de nube
uniform float energy = 1.0;

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

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec2(13.7, 7.1);
		a *= 0.5;
	}
	return s / 0.96875;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, zenith_color, pow(clamp(h, 0.0, 1.0), 0.6));
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-h * 5.0, 0.0, 1.0));
	}

	float sun_amt = 0.0;
	vec3 sun_col = vec3(0.0);
	if (LIGHT0_ENABLED) {
		sun_amt = max(dot(d, LIGHT0_DIRECTION), 0.0);
		sun_col = LIGHT0_COLOR * min(LIGHT0_ENERGY, 2.0);
	}

	float cov = 0.0;
	if (h > -0.02) {
		float hh = max(h, 0.0);
		vec2 uv = d.xz / (hh + 0.12) * cloud_scale + cloud_offset;
		float n = fbm(uv);
		float t = 1.0 - cloud_cover;
		cov = smoothstep(t - cloud_sharpness * 0.5, t + cloud_sharpness * 0.5, n);
		// densidad interna: más oscuro donde la nube es gruesa
		float dens = smoothstep(t, t + 0.45, fbm(uv * 1.7 + 4.3));
		vec3 cc = mix(cloud_light, cloud_dark, dens);
		// borde plateado: zonas delgadas cerca del sol se aclaran
		float thin = cov * (1.0 - dens);
		cc += sun_col * thin * pow(sun_amt, 6.0) * silver_lining;
		// las nubes se funden con el horizonte (aire húmedo)
		cov *= smoothstep(-0.02, 0.18, h);
		col = mix(col, cc, cov);
	}

	// halo y disco del sol (atenuados por nube)
	col += sun_col * pow(sun_amt, 12.0) * sun_glow * (1.0 - 0.6 * cov);
	col += sun_col * smoothstep(0.9993, 0.9997, sun_amt) * sun_disk * (1.0 - cov);

	COLOR = col * energy;
}
