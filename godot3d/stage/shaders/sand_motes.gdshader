shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Motas de luz que flotan sobre la arena (MultiMesh de quads). Cada una sube y se desvía según su INSTANCE_ID; sin texturas.
uniform vec3 tint : source_color = vec3(0.7, 0.85, 1.0);
uniform float rise = 6.0;
uniform float speed = 0.35;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

varying float life;

void vertex() {
	float id = float(INSTANCE_ID);
	float ph = hash11(id * 1.7);
	float t = fract(TIME * speed * (0.5 + hash11(id * 3.1)) + ph);
	life = sin(t * 3.14159);
	vec3 pos = MODEL_MATRIX[3].xyz;
	pos.y += t * rise;
	pos.x += sin(TIME * 0.6 + id) * 0.6;
	pos.z += cos(TIME * 0.5 + id * 1.3) * 0.6;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(pos, 1.0));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = smoothstep(1.0, 0.0, d);
	ALBEDO = tint * 2.0;
	ALPHA = a * a * life;
}
