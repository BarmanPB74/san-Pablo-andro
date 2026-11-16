shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
// Cascada fina que cae de la boca (ref. 83530): vetas verticales que bajan, más densas al centro.
uniform vec3 col : source_color = vec3(0.72, 0.86, 0.94);
uniform float speed = 1.5;
uniform float strength = 0.85;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float edge = smoothstep(0.0, 0.22, uv.x) * smoothstep(1.0, 0.78, uv.x);
	float s1 = vnoise(vec2(uv.x * 12.0, uv.y * 2.4 - TIME * speed * 2.0));
	float s2 = vnoise(vec2(uv.x * 28.0, uv.y * 6.0 - TIME * speed * 3.6));
	float s3 = vnoise(vec2(uv.x * 55.0, uv.y * 11.0 - TIME * speed * 5.0));
	float a = (0.25 + 0.75 * (s1 * 0.45 + s2 * 0.35 + s3 * 0.2)) * edge;
	a *= smoothstep(0.0, 0.04, uv.y);
	ALBEDO = col * (0.65 + 0.7 * s2);
	ALPHA = clamp(a * strength, 0.0, 1.0);
}
