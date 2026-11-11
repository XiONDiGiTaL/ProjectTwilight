// Ornate resource bar (HP / SP / EXP), original Project Twilight design.
// Drawn entirely from signed-distance shapes so it stays crisp at any size:
//   * bevelled gold frame with flared end horns and an optional top diamond
//   * molten animated fill with flowing veins
//   * a pale "damage chip" (trail) that lingers then drains, showing the decline
shader_type canvas_item;

uniform vec2 size = vec2(240.0, 32.0);   // control size in pixels
uniform float value : hint_range(0.0, 1.0) = 1.0;
uniform float trail : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_dark : source_color = vec4(0.22, 0.0, 0.0, 1.0);
uniform vec4 fill_mid : source_color = vec4(0.68, 0.05, 0.02, 1.0);
uniform vec4 fill_hot : source_color = vec4(1.0, 0.42, 0.1, 1.0);
uniform vec4 gem_color : source_color = vec4(0.75, 0.05, 0.08, 1.0);
uniform vec4 trail_color : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform vec4 gold_dark : source_color = vec4(0.26, 0.17, 0.05, 1.0);
uniform vec4 gold_light : source_color = vec4(0.9, 0.72, 0.38, 1.0);
uniform bool show_diamond = true;
uniform bool show_horns = true;
uniform bool sleek = false;              // slim frame with pointed diamond tips
uniform float flow_speed = 1.0;
uniform float low_pulse = 0.25;          // pulse the fill below this fraction
uniform float flash = 0.0;               // 0..1 white flash on hit

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sd_round_box(vec2 p, vec2 b, float r) {
	return sd_box(p, b - vec2(r)) - r;
}

float sd_rhombus(vec2 p, vec2 b) {
	p = abs(p);
	float h = clamp((-2.0 * dot(p, b) + dot(b, b)) / dot(b, b), -1.0, 1.0);
	float d = length(p - 0.5 * b * vec2(1.0 - h, 1.0 + h));
	return d * sign(p.x * b.y + p.y * b.x - b.x * b.y);
}

float sd_triangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
	vec2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
	vec2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
					 vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
					 vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 px = UV * size;
	float h = size.y;
	float aa = 1.0;
	// Layout (pixels). The trough holds the fill; the frame surrounds it.
	float horn_w = show_horns ? h * 0.6 : h * 0.15;
	float border = max(2.0, h * 0.15);
	vec2 trough_c = vec2(size.x * 0.5, h * 0.58);
	vec2 trough_b = vec2(size.x * 0.5 - horn_w - border, h * 0.22);
	float d_trough = sd_box(px - trough_c, trough_b);
	float d_frame = sd_round_box(px - trough_c, trough_b + vec2(border), border * 0.5);
	if (show_horns) {
		// Flared blade-like horns at both ends, sweeping up and outward.
		for (int s = 0; s < 2; s++) {
			vec2 q = vec2(s == 0 ? px.x : size.x - px.x, px.y);
			float inner = horn_w + border * 1.6;
			float blade = sd_triangle(q, vec2(inner, h * 0.3), vec2(1.0, h * 0.04), vec2(inner * 0.7, h * 0.97));
			float cap = sd_round_box(q - vec2(inner * 0.78, h * 0.6), vec2(inner * 0.3, h * 0.36), border * 0.5);
			d_frame = min(d_frame, min(blade, cap));
		}
	}
	vec2 gem_c = vec2(size.x * 0.5, trough_c.y - trough_b.y - border * 0.6);
	vec2 gem_b = vec2(h * 0.22, h * 0.27);
	if (sleek) {
		// Slim bar between two spear tips; replaces the ornate layout above.
		float tip = h * 1.15;
		border = max(1.5, h * 0.11);
		trough_c = vec2(size.x * 0.5, h * 0.5);
		trough_b = vec2(size.x * 0.5 - tip - border, h * 0.24);
		d_trough = sd_box(px - trough_c, trough_b);
		d_frame = sd_round_box(px - trough_c, trough_b + vec2(border), border * 0.8);
		for (int s = 0; s < 2; s++) {
			vec2 q = vec2(s == 0 ? px.x : size.x - px.x, px.y);
			float spear = sd_rhombus(q - vec2(tip * 0.62, h * 0.5), vec2(tip * 0.62, h * 0.46));
			float collar = sd_round_box(q - vec2(tip + border * 0.5, h * 0.5), vec2(border * 1.2, h * 0.36), border * 0.5);
			d_frame = min(d_frame, min(spear, collar));
		}
		gem_c = vec2(size.x * 0.5, trough_c.y - trough_b.y - border * 0.4);
		gem_b = vec2(h * 0.2, h * 0.24);
	}
	float d_gem_frame = sd_rhombus(px - gem_c, gem_b);
	if (show_diamond) {
		d_frame = min(d_frame, d_gem_frame);
	}
	float frame_mask = 1.0 - smoothstep(-aa, aa, d_frame);
	if (frame_mask <= 0.0) {
		discard;
	}
	// Gold bevel: SDF gradient gives an edge normal; light from the top-left.
	vec2 g = vec2(dFdx(d_frame), dFdy(d_frame));
	vec2 nrm = g / max(length(g), 1e-4);
	float lit = dot(nrm, normalize(vec2(-0.35, -1.0)));
	float bevel = 1.0 - clamp(-d_frame / (border * 0.55), 0.0, 1.0);  // 1 at the edge
	float vgrad = 1.0 - clamp(px.y / h, 0.0, 1.0);
	vec3 gold = mix(gold_dark.rgb, gold_light.rgb, 0.35 + 0.55 * vgrad);
	gold *= 1.0 + 0.55 * lit * bevel;
	// Dark outer outline and a darker rim hugging the trough.
	gold = mix(vec3(0.06, 0.035, 0.01), gold, smoothstep(0.0, 1.6, -d_frame));
	float rim = 1.0 - smoothstep(0.0, max(1.5, border * 0.35), d_trough);
	gold = mix(gold, vec3(0.1, 0.06, 0.02), rim * 0.85);
	float glint = pow(max(0.0, 1.0 - abs(px.x / size.x - fract(TIME * 0.08)) * 9.0), 3.0) * vgrad;
	gold += vec3(1.0, 0.9, 0.6) * glint * 0.3;
	vec4 col = vec4(gold, 1.0);
	if (show_diamond) {
		// Inset gem inside the diamond mount.
		float d_gem = sd_rhombus(px - gem_c, gem_b * 0.55);
		float gem_mask = 1.0 - smoothstep(-aa, aa, d_gem);
		vec2 gp = (px - gem_c) / gem_b;
		vec3 gem = mix(gem_color.rgb * 0.35, gem_color.rgb * 1.3, clamp(0.6 - gp.y - gp.x * 0.4, 0.0, 1.0));
		gem += vec3(1.0, 0.85, 0.85) * smoothstep(0.22, 0.0, length(gp - vec2(-0.12, -0.18))) * 0.8;
		gem = mix(vec3(0.05, 0.0, 0.0), gem, smoothstep(0.0, 1.2, -d_gem));
		col.rgb = mix(col.rgb, gem, gem_mask);
	}

	// Trough contents.
	float trough_mask = 1.0 - smoothstep(-aa, aa, d_trough);
	if (trough_mask > 0.0) {
		float x = clamp((px.x - (trough_c.x - trough_b.x)) / (2.0 * trough_b.x), 0.0, 1.0);
		float y = clamp((px.y - (trough_c.y - trough_b.y)) / (2.0 * trough_b.y), 0.0, 1.0);
		vec3 empty = mix(vec3(0.015, 0.01, 0.01), vec3(0.06, 0.04, 0.035), y);
		empty *= 0.6 + 0.4 * smoothstep(0.0, 0.35, y);  // inner shadow under the rim
		vec3 c = empty;
		if (x < trail) {
			// Lingering damage chip: bright, slightly warm.
			c = trail_color.rgb * (0.75 + 0.25 * (1.0 - y));
		}
		if (x < value) {
			vec2 fp = vec2(px.x / h * 1.1 - TIME * 0.5 * flow_speed, y * 1.2);
			float n = fbm(fp * 1.6 + vec2(0.0, TIME * 0.12));
			float veins = smoothstep(0.62, 0.9, fbm(fp * 3.0 - vec2(TIME * 0.35 * flow_speed, 0.0)));
			float core = 1.0 - abs(y - 0.38) * 2.2;  // bright molten core line
			vec3 lava = mix(fill_dark.rgb, fill_mid.rgb, smoothstep(0.2, 0.75, n * 0.8 + core * 0.45));
			lava = mix(lava, fill_hot.rgb, veins * 0.55 + pow(max(core, 0.0), 8.0) * 0.45);
			lava *= 0.7 + 0.3 * smoothstep(1.0, 0.55, y);  // darker toward the bottom
			float tip = smoothstep(0.03, 0.0, value - x);  // hot leading edge
			lava = mix(lava, fill_hot.rgb, tip * 0.6);
			if (value < low_pulse) {
				lava *= 0.8 + 0.35 * (0.5 + 0.5 * sin(TIME * 9.0));
			}
			c = lava;
		}
		c = mix(c, vec3(1.0), flash * 0.3);
		// Glassy highlight across the top of the trough.
		c += vec3(0.25) * smoothstep(0.35, 0.0, y) * 0.35;
		col.rgb = mix(col.rgb, c, trough_mask);
	}
	COLOR = vec4(col.rgb, col.a * frame_mask);
}
