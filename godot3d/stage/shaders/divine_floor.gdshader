shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Piso del Umbral: el suelo de un dios en el universo. Mármol negro azulado, pulido (refleja el cielo), con incrustaciones
// de oro: anillos dobles, rosa de los vientos, estrella de 12 puntas, rosetón, arcos, una franja de signos y un borde triple
// con marcas. Todo procedural en coordenadas de mundo (centro en el origen). Más allá del borde el piso sigue liso, con
// anillos y rayos dorados muy tenues que se pierden en el horizonte: da la sensación de un suelo sin fin.
// El ancho de cada línea se compensa con el tamaño del pixel en el piso (`a`) para que no parpadee a distancia.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 base_col : source_color = vec3(0.012, 0.018, 0.046);
uniform vec3 vein_col : source_color = vec3(0.07, 0.11, 0.26);
uniform vec3 gold_col : source_color = vec3(1.0, 0.76, 0.33);
// Color del horizonte del cielo (mismos valores que umbral_sky): el piso lejano se funde con él para que no haya una línea dura.
uniform vec3 horizon_col : source_color = vec3(0.70, 0.78, 0.94);
uniform vec3 glow_col : source_color = vec3(1.0, 0.72, 0.60);
uniform vec3 glow_dir = vec3(-0.55, 0.21, -0.80);

varying vec3 wpos;

const float PI_ = 3.14159265359;
const float TAU_ = 6.28318530718;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Línea: d = distancia al eje (m), w = ancho (m), a = tamaño del pixel sobre el piso (m).
float ln(float d, float w, float a) {
	float aa = max(a, 0.0004);
	float t = 1.0 - smoothstep(w * 0.5 - aa, w * 0.5 + aa, d);
	return t * clamp(w / (aa * 2.5), 0.0, 1.0);
}

// Disco: d = distancia al centro (m), rad = radio (m).
float dot_(float d, float rad, float a) {
	float aa = max(a, 0.0004);
	return (1.0 - smoothstep(rad - aa, rad + aa, d)) * clamp(rad * 2.0 / (aa * 2.5), 0.0, 1.0);
}

// Tramo radial: 1 entre lo y hi.
float rng(float r, float lo, float hi, float a) {
	return smoothstep(lo - a, lo + a, r) * (1.0 - smoothstep(hi - a, hi + a, r));
}

// Distancia (m) al rayo más cercano de n rayos equiespaciados (uno en ángulo 0).
float spoke(float th, float r, float n) {
	return r * (2.0 / n) * asin(clamp(abs(sin(n * 0.5 * th)), 0.0, 1.0));
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Distancia aproximada a la curva r = r0 + amp * f(n·θ) con pendiente slope = dr/(r dθ).
float curve_d(float r, float rc, float slope) {
	return abs(r - rc) / sqrt(1.0 + slope * slope);
}

float gold_mask(vec2 p, float a) {
	float r = length(p);
	float th = atan(p.y, p.x);
	float m = 0.0;

	// ---- anillos dobles que separan las franjas
	m = max(m, ln(abs(r - 4.6), 0.24, a));
	m = max(m, ln(abs(r - 4.95), 0.08, a));
	m = max(m, ln(abs(r - 9.0), 0.22, a));
	m = max(m, ln(abs(r - 9.35), 0.08, a));
	m = max(m, ln(abs(r - 16.5), 0.22, a));
	m = max(m, ln(abs(r - 16.85), 0.08, a));
	m = max(m, ln(abs(r - 26.0), 0.24, a));
	m = max(m, ln(abs(r - 26.35), 0.08, a));

	// ---- centro: rosa de los vientos (8 rayos largos, 8 cortos) y anillos pequeños
	if (r < 4.7) {
		float lg = ln(spoke(th, r, 8.0), 0.13, a) * rng(r, 0.55, 4.3, a);
		float sh = ln(spoke(th + PI_ / 8.0, r, 8.0), 0.09, a) * rng(r, 0.55, 2.7, a);
		m = max(m, max(lg, sh));
		m = max(m, ln(abs(r - 0.5), 0.1, a));
		m = max(m, ln(abs(r - 1.05), 0.06, a));
		m = max(m, ln(abs(r - 3.0), 0.05, a));
		m = max(m, dot_(r, 0.26, a));
	}

	// ---- franja 1: 12 rayos finos y rombos entre los anillos
	if (r > 4.9 && r < 9.1) {
		m = max(m, ln(spoke(th, r, 12.0), 0.07, a) * rng(r, 5.0, 8.95, a));
		float dl = (2.0 / 12.0) * asin(clamp(abs(sin(6.0 * (th + PI_ / 12.0))), 0.0, 1.0));   // rombo entre rayos
		vec2 q = vec2(r * dl, r - 6.95);
		float dm = abs(q.x) / 0.75 + abs(q.y) / 1.35;
		m = max(m, ln(abs(dm - 1.0) * 0.55, 0.07, a));
		m = max(m, dot_(length(q), 0.17, a));
	}

	// ---- franja 2: estrella de 12 puntas {12/5} dentro de un círculo, con un punto en cada vértice
	if (r > 9.4 && r < 16.5) {
		float R = 15.9;
		float rho = R * cos(5.0 * PI_ / 12.0);
		float best = 100.0;
		for (int j = 0; j < 12; j++) {
			float psi = TAU_ * float(j) / 12.0 + 5.0 * PI_ / 12.0;
			best = min(best, abs(r * cos(th - psi) - rho));
		}
		m = max(m, ln(best, 0.13, a) * (1.0 - smoothstep(R - a, R + a, r)));
		m = max(m, ln(abs(r - R), 0.1, a));
		float dv = (2.0 / 12.0) * asin(clamp(abs(sin(6.0 * th)), 0.0, 1.0));
		m = max(m, dot_(length(vec2(r * dv, r - R)), 0.36, a));
		m = max(m, ln(abs(r - 12.4), 0.05, a));
	}

	// ---- franja 3: rosetón de dos ondas entrelazadas con un punto en cada cresta
	if (r > 17.0 && r < 26.0) {
		float s1 = -3.0 * 24.0 * sin(24.0 * th) / r;
		float c1 = curve_d(r, 21.5 + 3.0 * cos(24.0 * th), s1);
		float c2 = curve_d(r, 21.5 - 3.0 * cos(24.0 * th), -s1);
		m = max(m, max(ln(c1, 0.16, a), ln(c2, 0.16, a)));
		m = max(m, ln(abs(r - 17.7), 0.07, a));
		m = max(m, ln(abs(r - 25.3), 0.07, a));
		float d24 = (2.0 / 24.0) * asin(clamp(abs(sin(12.0 * th)), 0.0, 1.0));
		float d24b = (2.0 / 24.0) * asin(clamp(abs(cos(12.0 * th)), 0.0, 1.0));
		m = max(m, dot_(length(vec2(r * d24, r - 24.5)), 0.3, a));
		m = max(m, dot_(length(vec2(r * d24b, r - 18.5)), 0.3, a));
	}

	// ---- franja 4: dos hileras de arcos y una franja de signos
	if (r > 26.4 && r < 34.5) {
		float sa = 2.2 * 18.0 * cos(18.0 * th) * sign(sin(18.0 * th)) / r;
		float arc1 = curve_d(r, 28.0 + 2.2 * abs(sin(18.0 * th)), sa);
		float sb = -2.2 * 18.0 * sin(18.0 * th) * sign(cos(18.0 * th)) / r;
		float arc2 = curve_d(r, 28.6 + 2.2 * abs(cos(18.0 * th)), sb);
		m = max(m, max(ln(arc1, 0.12, a), ln(arc2, 0.1, a)) * rng(r, 26.5, 31.2, a));
		m = max(m, ln(abs(r - 31.6), 0.07, a));
		m = max(m, ln(abs(r - 34.0), 0.07, a));
		// signos: 180 celdas, cada una con 1 a 3 trazos según su azar
		if (r > 31.9 && r < 33.7) {
			float cellf = (th / TAU_ + 0.5) * 180.0;
			float cid = floor(cellf);
			vec2 lp = vec2((fract(cellf) - 0.5) * r * TAU_ / 180.0, r - 32.8);
			float h1 = hash21(vec2(cid, 1.7));
			float h2 = hash21(vec2(cid, 5.3));
			float h3 = hash21(vec2(cid, 9.1));
			float gl = 100.0;
			if (h1 > 0.25) { gl = min(gl, seg(lp, vec2(0.0, -0.6), vec2(0.0, 0.6))); }
			if (h2 > 0.45) { gl = min(gl, seg(lp, vec2(-0.32, -0.25 + 0.5 * h2), vec2(0.32, -0.25 + 0.5 * h2))); }
			if (h3 > 0.55) { gl = min(gl, seg(lp, vec2(-0.3, -0.45), vec2(0.3, 0.45))); }
			if (h1 <= 0.25) { gl = min(gl, length(lp - vec2(0.0, 0.0)) - 0.2); }
			m = max(m, ln(gl, 0.075, a));
		}
	}

	// ---- borde triple y marcas
	m = max(m, ln(abs(r - 34.7), 0.3, a));
	m = max(m, ln(abs(r - 35.1), 0.1, a));
	m = max(m, ln(abs(r - 35.9), 0.5, a));
	m = max(m, ln(abs(r - 36.6), 0.1, a));
	m = max(m, ln(spoke(th, r, 180.0), 0.07, a) * rng(r, 37.0, 37.6, a));
	return m;
}

void fragment() {
	vec2 p = wpos.xz;
	float a = length(fwidth(p));
	float r = length(p);

	// mármol: negro azulado con vetas tenues
	float n1 = texture(noise_tex, p * 0.012).r;
	float n2 = texture(noise_tex, p * 0.045 + vec2(0.31, 0.77)).r;
	float veins = pow(1.0 - abs(n2 * 2.0 - 1.0), 7.0);
	vec3 marble = mix(base_col, vein_col, clamp(veins * 0.7 + n1 * 0.2, 0.0, 1.0));

	float gold = 0.0;
	if (r < 38.0) {
		gold = gold_mask(p, a);
	} else {
		// más allá del borde: anillos (separación creciente) y rayos dorados muy tenues hacia el horizonte
		float lr = log(r / 38.0) / log(1.5);
		float dring = abs(fract(lr + 0.5) - 0.5) * log(1.5) * r;
		float far_m = max(ln(dring, 0.007 * r, a), ln(spoke(atan(p.y, p.x), r, 24.0), 0.0045 * r, a));
		gold = far_m * 0.4;
	}

	float pulse = 0.5 + 0.5 * sin(TIME * 0.7 - r * 0.13);     // una onda lenta de brillo que sale del centro
	// a lo lejos el piso se vuelve el color del horizonte (con el resplandor del amanecer de su lado), sin línea dura
	vec3 vd = wpos - CAMERA_POSITION_WORLD;
	float dist = length(vd);
	float haze = smoothstep(150.0, 1800.0, dist);
	vec2 hd = normalize(vd.xz + vec2(0.0001));
	float g = max(dot(hd, normalize(glow_dir.xz)), 0.0);
	vec3 haze_c = mix(horizon_col, glow_col, pow(g, 3.0) * 0.6);

	ALBEDO = mix(marble, gold_col, gold) * (1.0 - haze);
	METALLIC = gold;
	ROUGHNESS = mix(0.17, 0.3, gold);
	SPECULAR = 0.85 * (1.0 - haze);
	EMISSION = gold_col * gold * (0.42 + 0.2 * pulse) * (1.0 - haze) + haze_c * haze;
}
