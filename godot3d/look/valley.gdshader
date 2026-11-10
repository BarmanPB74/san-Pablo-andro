shader_type spatial;
// Montañas lejanas del valle de Aburrá. Malla low-poly con color por vértice.
// fog_disabled: hacemos nuestra propia neblina (haze) para controlar la
// perspectiva aérea sin que la niebla global se trague las montañas; y de
// noche dibujamos las luces de las laderas (comunas) como puntos emisivos.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled, fog_disabled, shadows_disabled;

uniform vec3 haze_color : source_color = vec3(0.55, 0.6, 0.62);
uniform float haze_amount : hint_range(0.0, 1.0) = 0.55;   // neblina en la base
uniform float haze_top : hint_range(0.0, 1.0) = 0.25;      // neblina en la cresta
uniform float max_height = 500.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;          // luces de barrios
uniform vec3 city_light_a : source_color = vec3(1.0, 0.62, 0.28);
uniform vec3 city_light_b : source_color = vec3(0.85, 0.92, 1.0);
uniform float light_energy = 2.0;
uniform float light_cell = 7.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float hn = clamp(wpos.y / max_height, 0.0, 1.0);
	float haze = mix(haze_amount, haze_top, sqrt(hn));
	vec3 col = COLOR.rgb;
	ALBEDO = col * (1.0 - haze);
	ROUGHNESS = 1.0;
	// la neblina se suma como emisión: así se ve plana/atmosférica
	vec3 em = haze_color * haze;

	if (night > 0.001) {
		vec3 c = wpos / light_cell;
		vec3 cell = floor(c);
		float h = hash13(cell);
		// más luces abajo (barrios en laderas), casi ninguna en la cresta
		float density = mix(0.22, 0.0, smoothstep(0.05, 0.6, hn));
		float on = step(1.0 - density, h);
		float d = length(fract(c) - 0.5);
		float dot_ = 1.0 - smoothstep(0.08, 0.22, d);
		vec3 lc = mix(city_light_a, city_light_b, step(0.8, hash13(cell + 5.3)));
		em += lc * on * dot_ * light_energy * night;
	}
	EMISSION = em;
}
