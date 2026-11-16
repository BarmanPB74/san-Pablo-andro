shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, fog_disabled, shadows_disabled;
// Esfera de energía del cielo, dibujada como "impostor": un cuadro que mira a la cámara y se sombrea como esfera.
// Así es un círculo perfecto en cualquier parte de la pantalla (una malla esférica se estira en los bordes con
// el campo de visión ancho) y cuesta 2 triángulos. El plasma usa la normal en coordenadas de mundo, así que
// el dibujo queda fijo en la esfera aunque la cámara gire. El tamaño va en la malla (QuadMesh = diámetro).

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 col_a : source_color = vec3(0.30, 0.85, 0.90);
uniform vec3 col_b : source_color = vec3(0.55, 0.35, 0.95);
uniform float speed = 0.02;
uniform float energy = 1.0;
uniform vec2 seed = vec2(0.0);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r2 = dot(q, q);
	if (r2 > 1.0) {
		discard;
	}
	vec3 nv = vec3(q.x, -q.y, sqrt(1.0 - r2));                  // normal en el espacio de la cámara
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz);   // en el espacio del mundo: el dibujo no gira con la cámara
	float w = n.z * n.z;
	float t = TIME * speed;
	vec2 ua = n.xy * 0.6 + seed + vec2(t, -t * 0.7);
	vec2 ub = n.zy * 0.6 + seed + vec2(-t * 0.8, t);
	float f1 = mix(texture(noise_tex, ub).r, texture(noise_tex, ua).r, w);
	float f2 = mix(texture(noise_tex, ub * 2.3 + 0.17 - t).r, texture(noise_tex, ua * 2.3 + 0.17 + t).r, w);
	float swirl = f1 * 0.6 + f2 * 0.4;
	vec3 col = mix(col_a, col_b, smoothstep(0.25, 0.78, swirl));
	float veins = pow(1.0 - abs(f2 * 2.0 - 1.0), 6.0);
	float fres = pow(1.0 - nv.z, 2.2);
	vec3 c = col * (0.6 + 0.7 * swirl) + vec3(1.0) * veins * 0.4 + mix(col_b, vec3(1.0), 0.4) * fres * 1.1;
	ALBEDO = c * energy;
	ALPHA = 1.0 - smoothstep(0.94, 1.0, sqrt(r2));
}
