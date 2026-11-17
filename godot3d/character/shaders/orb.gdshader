shader_type spatial;
// Esferas de Andro: cromo brillante plateado en tonos grises. Malla de radio 1 escalada por nodo.
// Además del reflejo real del cielo, se suma un "estudio" procedural (cielo claro, horizonte brillante,
// suelo oscuro, dos cajas de luz) para que el cromo se lea igual en cualquier escena, también en niebla gris.
uniform vec3 tint : source_color = vec3(0.80, 0.82, 0.85);
uniform float glow = 0.0;
uniform vec3 glow_col : source_color = vec3(1.0);

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 r = reflect(-VIEW, n);
	vec3 rw = normalize((INV_VIEW_MATRIX * vec4(r, 0.0)).xyz);
	float h = rw.y;
	vec3 sky = mix(vec3(0.56, 0.58, 0.61), vec3(0.92, 0.93, 0.95), smoothstep(0.0, 0.9, h));
	vec3 ground = mix(vec3(0.07, 0.075, 0.085), vec3(0.30, 0.31, 0.33), smoothstep(-1.0, -0.05, h));
	vec3 env = mix(ground, sky, smoothstep(-0.07, 0.07, h));
	env += vec3(0.55) * exp(-pow(h * 8.0, 2.0)) * 0.55;                       // línea brillante del horizonte
	float k1 = pow(max(dot(rw, normalize(vec3(0.5, 0.75, 0.45))), 0.0), 22.0);
	float k2 = pow(max(dot(rw, normalize(vec3(-0.7, 0.3, -0.5))), 0.0), 16.0) * 0.55;
	env += vec3(1.0) * (k1 + k2) * 0.9;
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
	env *= 1.0 + fres * 0.25;
	ALBEDO = tint * 0.4;
	METALLIC = 1.0;
	ROUGHNESS = 0.06;
	SPECULAR = 0.9;
	EMISSION = env * tint * 0.72 + glow_col * glow;
}
