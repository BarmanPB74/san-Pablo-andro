shader_type canvas_item;
// Viaje entre escenas: la pantalla se enrosca hacia un vórtice de galaxia y se cubre de luz.
// amount: 0 = nada, 1 = cubierto por completo (se cambia la escena en ese momento).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 deep_col : source_color = vec3(0.02, 0.03, 0.10);
uniform vec3 arm_col : source_color = vec3(0.55, 0.62, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float ar = res.x / res.y;
	vec2 c = (SCREEN_UV - 0.5) * vec2(ar, 1.0);
	float r = length(c);
	float twist = amount * amount * 7.0 * (1.2 - r);
	float cs = cos(twist);
	float sn = sin(twist);
	vec2 q = vec2(cs * c.x - sn * c.y, sn * c.x + cs * c.y);
	q *= mix(1.0, 0.25, amount * amount);
	vec3 scene = texture(screen_tex, q / vec2(ar, 1.0) + 0.5).rgb;
	scene *= 1.0 - smoothstep(0.35, 0.95, amount) * 0.85;

	// vórtice espiral que crece desde el centro
	float a = atan(c.y, c.x);
	float s = a * 2.0 + log(r + 0.04) * 5.0 - amount * 6.0;
	float arms = pow(0.5 + 0.5 * cos(s), 2.0) * exp(-r * 2.2);
	float core = exp(-r * 6.0);
	float spark = step(0.985, hash21(floor(SCREEN_UV * res * 0.25))) * 0.8;
	vec3 gal = deep_col + arm_col * arms * 0.9 + vec3(1.0, 0.95, 0.85) * core * 1.2 + vec3(spark);
	float cover = smoothstep(0.25, 0.95, amount);
	vec3 col = mix(scene, gal, cover);
	col = mix(col, vec3(1.0, 0.97, 0.9), smoothstep(0.9, 1.0, amount) * 0.35);
	COLOR = vec4(col, 1.0);
}
