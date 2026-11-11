// Procedural magic circle on the ground (original design).
// Outer double ring with a rotating band of rune glyphs, a ring of dots /
// crescents, an element motif in the centre and a soft core glow. The rune
// band lights up clockwise as the cast progresses. Additive, unshaded.
shader_type spatial;
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(0.85, 0.92, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.45, 0.7, 1.0, 1.0);
uniform int motif = 0;            // see ElementPalette
uniform float intensity = 1.0;    // overall brightness / fade
uniform float progress = 0.0;     // cast progress 0..1 (lights the rune band)
uniform float spin = 1.0;         // rotation speed multiplier
uniform float rune_seed = 3.0;
uniform float flash = 0.0;        // release burst
uniform bool aura_mode = false;   // simplified ring set used by player auras


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float line(float x, float w) {
	float aa = fwidth(x) * 1.2 + 1e-4;
	return 1.0 - smoothstep(w, w + aa, abs(x));
}

float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return line(length(pa - ba * h), w);
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Distance-based line along a regular polygon / star polygon outline.
float star_poly(vec2 p, float r, float n, float step_k, float w) {
	float acc = 0.0;
	for (int i = 0; i < 8; i++) {
		if (float(i) >= n) break;
		float a0 = TAU * float(i) / n - PI * 0.5;
		float a1 = TAU * (float(i) + step_k) / n - PI * 0.5;
		acc = max(acc, seg(p, vec2(cos(a0), sin(a0)) * r, vec2(cos(a1), sin(a1)) * r, w));
	}
	return acc;
}

// One procedural rune in a cell: u across (0..1), v radial (0..1).
float rune(vec2 uv, float id) {
	vec2 q = uv * 2.0 - 1.0;
	float h = hash(vec2(id, rune_seed));
	float h2 = hash(vec2(id * 1.7, rune_seed + 9.0));
	float w = 0.13;
	float g = 0.0;
	g = max(g, seg(q, vec2(-0.25 + h * 0.5, -0.7), vec2(-0.25 + h * 0.5, 0.7), w));
	if (h2 > 0.3) g = max(g, seg(q, vec2(-0.5, 0.7), vec2(0.5, 0.2 * h), w));
	if (h2 < 0.6) g = max(g, seg(q, vec2(-0.5, -0.1), vec2(0.45, -0.6), w));
	if (h > 0.55) g = max(g, line(length(q - vec2(0.35, 0.45)) - 0.18, w * 0.8));
	if (h < 0.25) g = max(g, seg(q, vec2(-0.5, 0.0), vec2(0.5, 0.0), w));
	return g;
}

float motif_shape(vec2 p, float t) {
	float r = length(p);
	float a = atan(p.y, p.x);
	float g = 0.0;
	if (motif == 0) {          // hexagram + inner ring
		vec2 q = rot(p, t * 0.2);
		g = max(star_poly(q, 0.5, 6.0, 2.0, 0.008), line(r - 0.25, 0.006));
	} else if (motif == 1) {   // crescents in a cross with a curved four-point star
		vec2 q = rot(p, -t * 0.15);
		for (int i = 0; i < 4; i++) {
			float ang = float(i) * PI * 0.5;
			vec2 c = vec2(cos(ang), sin(ang)) * 0.33;
			float outer = length(q - c) - 0.11;
			float inner = length(q - c * 1.12) - 0.09;
			g = max(g, line(outer, 0.007) * step(0.0, inner));
			g = max(g, line(max(outer, -inner), 0.006));
		}
		vec2 s = abs(q);
		float astroid = pow(s.x, 0.6) + pow(s.y, 0.6) - pow(0.48, 0.6);
		g = max(g, line(astroid, 0.012));
	} else if (motif == 2) {   // six flame petals
		vec2 q = rot(p, t * 0.3);
		float qa = atan(q.y, q.x);
		float petal = 0.5 * (0.35 + 0.65 * pow(abs(cos(qa * 3.0)), 0.5));
		g = max(line(r - petal, 0.008), line(r - petal * 0.6, 0.006));
		g = max(g, star_poly(q, 0.26, 3.0, 1.0, 0.007));
	} else if (motif == 3) {   // lightning star with flickering arcs
		vec2 q = rot(p, t * 0.25);
		vec2 s = abs(q);
		float astroid = pow(s.x, 0.5) + pow(s.y, 0.5) - pow(0.52, 0.5);
		g = line(astroid, 0.01);
		g = max(g, star_poly(rot(q, PI * 0.25), 0.3, 4.0, 1.0, 0.006));
		float flick = step(0.6, hash(vec2(floor(t * 9.0), 1.0)));
		float jag = sin(a * 23.0 + floor(t * 12.0) * 3.1) * 0.025 + sin(a * 57.0 - t * 20.0) * 0.012;
		g = max(g, line(r - 0.42 - jag, 0.006) * flick);
	} else if (motif == 4) {   // two rotated squares (octagram) and a centre square
		vec2 q = rot(p, t * 0.12);
		g = max(star_poly(q, 0.5, 4.0, 1.0, 0.008), star_poly(rot(q, PI * 0.25), 0.5, 4.0, 1.0, 0.008));
		g = max(g, star_poly(q, 0.2, 4.0, 1.0, 0.006));
	} else {                   // wave rings
		float wv = sin(a * 8.0 + t * 1.5) * 0.02;
		g = max(line(r - 0.45 - wv, 0.007), line(r - 0.33 + wv, 0.006));
		g = max(g, star_poly(rot(p, -t * 0.2), 0.24, 6.0, 2.0, 0.006));
	}
	return g;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.02) discard;
	float t = TIME * spin;
	float a = atan(p.y, p.x);

	float lines = 0.0;
	// Outer double ring.
	lines = max(lines, line(r - 0.97, 0.006));
	lines = max(lines, line(r - 0.86, 0.004));
	float rune_v = 0.0;
	if (!aura_mode) {
		// Rotating rune band between the outer rings.
		float ra = a + t * 0.18;
		float n = 40.0;
		float cell = (ra / TAU + 0.5) * n;
		float id = floor(cell);
		vec2 ruv = vec2(fract(cell), (r - 0.875) / 0.085);
		if (ruv.y > 0.0 && ruv.y < 1.0) {
			rune_v = rune(vec2((ruv.x - 0.5) * 1.6 + 0.5, ruv.y), mod(id, n));
		}
		// Progress: the band brightens clockwise from the top.
		float prog_a = fract(0.25 - a / TAU);
		float lit = step(prog_a, progress);
		rune_v *= mix(0.45, 1.25, lit);
		lines = max(lines, rune_v);
		// Dots / crescents ring.
		float da = a - t * 0.3;
		float dn = 24.0;
		float dc = fract((da / TAU + 0.5) * dn) - 0.5;
		vec2 dp = vec2(dc * TAU * 0.76 / dn, r - 0.76);
		float dot_d = length(dp) - 0.022;
		float dots = line(dot_d, 0.005);
		if (motif == 1) dots = max(dots, line(length(dp - vec2(0.008, 0.0)) - 0.018, 0.004));
		lines = max(lines, dots);
		lines = max(lines, line(r - 0.69, 0.004));
		lines = max(lines, line(r - 0.58, 0.006));
		lines = max(lines, motif_shape(p, t));
	} else {
		// Aura: a slow dashed ring and a thin inner ring.
		float dash = step(0.35, fract((a + t * 0.25) / TAU * 18.0));
		lines = max(lines, line(r - 0.78, 0.004) * dash);
		lines = max(lines, line(r - 0.6, 0.003) * 0.6);
	}

	// Soft glow: core haze, edge halo, release flash.
	float haze = exp(-r * r * 6.0) * 0.35 + exp(-pow((r - 0.92) * 9.0, 2.0)) * 0.3;
	haze += flash * exp(-r * r * 2.5) * 1.5;
	float pulse = 0.85 + 0.15 * sin(TIME * 3.0);
	// Premultiplied: lines darken what is behind them a little so the hue
	// survives on bright ground, while the glow still adds light.
	vec3 col = mix(glow_color.rgb, core_color.rgb, 0.55) * lines * 1.15 + glow_color.rgb * (haze * pulse + lines * 0.5);
	float edge_fade = smoothstep(1.02, 0.96, r) * clamp(intensity, 0.0, 1.5);
	ALBEDO = col * edge_fade;
	ALPHA = clamp((lines * 0.55 + haze * 0.18) * edge_fade, 0.0, 0.85);
}
