// Renders a Project Twilight class insignia: shared heater-shield silhouette in
// the rank's material, with the class emblem (painted mask) embossed in relief.
// Every icon uses this one shader, so silhouette, lighting and construction
// stay identical across the collection; only the material uniforms and the
// emblem mask change.
shader_type canvas_item;

uniform sampler2D emblem_tex : filter_linear;
uniform vec2 canvas = vec2(512.0);
uniform vec4 body_dark : source_color;
uniform vec4 body_light : source_color;
uniform vec4 rim_dark : source_color;
uniform vec4 rim_light : source_color;
uniform vec4 emblem_dark : source_color;
uniform vec4 emblem_light : source_color;
uniform bool wood = false;
uniform bool patina = false;      // bronze verdigris flecks
uniform bool engraved = false;    // engraved inner border (silver and above)
uniform bool ornate = false;      // double border and filigree dots (gold)
uniform bool blue_trim = false;   // icy-blue upgraded rim + crystal studs
uniform bool rivet = false;       // central rivet (Novice)
uniform bool studs = true;        // rim rivets

const vec2 KEY_LIGHT = vec2(-0.45, -0.89);
const vec2 SHIELD_C = vec2(256.0, 258.0);
const vec2 SHIELD_HALF = vec2(214.0, 232.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.02 + 3.1; a *= 0.5; }
	return v;
}

// Heater shield in normalised space (y down), returns distance in pixels.
float sd_shield_px(vec2 px) {
	vec2 p = (px - SHIELD_C) / SHIELD_HALF;
	p.x = abs(p.x);
	float top = -1.0 + 0.07 * p.x * p.x;
	float side;
	if (p.y < 0.0) {
		side = p.x - 0.98;
	} else {
		float t = clamp(p.y / 1.0, 0.0, 1.0);
		side = p.x - 0.98 * pow(max(0.0, 1.0 - t * t), 0.62);
	}
	float d = max(max(top - p.y, side), p.y - 1.0);
	return d * min(SHIELD_HALF.x, SHIELD_HALF.y);
}

float emblem_height(vec2 uv) {
	vec4 t = texture(emblem_tex, uv);
	float lum = max(t.r, max(t.g, t.b));
	return t.a * (lum < 0.08 ? 0.15 : 1.0);
}

float blurred_height(vec2 uv, float r) {
	vec2 px = r / canvas;
	float h = 0.0;
	h += emblem_height(uv) * 4.0;
	h += emblem_height(uv + vec2(px.x, 0)) * 2.0 + emblem_height(uv - vec2(px.x, 0)) * 2.0;
	h += emblem_height(uv + vec2(0, px.y)) * 2.0 + emblem_height(uv - vec2(0, px.y)) * 2.0;
	h += emblem_height(uv + px) + emblem_height(uv - px) + emblem_height(uv + vec2(px.x, -px.y)) + emblem_height(uv + vec2(-px.x, px.y));
	return h / 16.0;
}

vec3 metal(vec3 dark, vec3 light, float t, float spec) {
	return mix(dark, light, clamp(t, 0.0, 1.0)) + vec3(spec);
}

void fragment() {
	vec2 px = UV * canvas;
	float d = sd_shield_px(px);
	float aa = 1.0;
	float mask = 1.0 - smoothstep(-aa, aa, d);
	if (mask <= 0.0) discard;
	float inside = -d;  // pixels from the outer edge

	// Edge normal of the shield silhouette (for rim bevel lighting).
	vec2 g = vec2(sd_shield_px(px + vec2(1, 0)) - sd_shield_px(px - vec2(1, 0)), sd_shield_px(px + vec2(0, 1)) - sd_shield_px(px - vec2(0, 1)));
	vec2 n_edge = normalize(g + 1e-5);
	vec2 sp = (px - SHIELD_C) / SHIELD_HALF;
	float vgrad = clamp(0.5 - sp.y * 0.5, 0.0, 1.0);

	// --- Body ---
	vec3 body;
	if (wood) {
		float grain = fbm(vec2(px.x * 0.045, px.y * 0.006)) * 0.7 + fbm(vec2(px.x * 0.18, px.y * 0.02)) * 0.3;
		body = mix(body_dark.rgb, body_light.rgb, 0.25 + 0.6 * grain + 0.25 * vgrad);
		float plank = abs(fract(px.x / 86.0 + 0.5) - 0.5);
		body *= 0.78 + 0.22 * smoothstep(0.0, 0.03, plank);
		body *= 0.92 + 0.08 * noise(px * 0.5);
	} else {
		float brushed = fbm(vec2(px.x * 0.01, px.y * 0.25));
		body = metal(body_dark.rgb, body_light.rgb, 0.3 + 0.55 * vgrad + 0.15 * brushed, 0.0);
		float sheen = pow(max(0.0, 1.0 - length(sp - vec2(-0.35, -0.45)) * 0.95), 2.5);
		body += body_light.rgb * sheen * 0.35;
		if (patina) {
			float pt = smoothstep(0.62, 0.8, fbm(px * 0.02 + 7.0));
			body = mix(body, vec3(0.32, 0.5, 0.42) * 0.85, pt * 0.35);
		}
		body *= 0.94 + 0.06 * noise(px * 0.8);
	}

	// --- Emblem relief and drop shadow ---
	vec2 uv = UV;
	float shadow = blurred_height(uv - vec2(6.0, 8.0) / canvas, 5.0);
	body *= 1.0 - 0.45 * shadow;
	float h = blurred_height(uv, 2.5);
	vec4 em = texture(emblem_tex, uv);
	vec3 col = body;
	if (em.a > 0.01 || h > 0.01) {
		float e = 2.0 / canvas.x;
		float hx = blurred_height(uv + vec2(e, 0), 2.5) - blurred_height(uv - vec2(e, 0), 2.5);
		float hy = blurred_height(uv + vec2(0, e), 2.5) - blurred_height(uv - vec2(0, e), 2.5);
		vec3 n = normalize(vec3(-hx * 3.2, -hy * 3.2, 1.0));
		float lit = dot(n, normalize(vec3(KEY_LIGHT, 0.9)));
		float spec = pow(max(0.0, dot(reflect(-normalize(vec3(KEY_LIGHT, 0.9)), n), vec3(0, 0, 1))), 24.0);
		float lum = max(em.r, max(em.g, em.b));
		float sat = lum > 0.0 ? (lum - min(em.r, min(em.g, em.b))) / lum : 0.0;
		vec3 metal_c = metal(emblem_dark.rgb, emblem_light.rgb, 0.35 + 0.55 * vgrad, 0.0);
		vec3 surf;
		if (lum < 0.08) {
			surf = metal_c * 0.32;            // engraved recess
		} else if (sat > 0.25) {
			surf = em.rgb * 0.9 + vec3(0.04);  // enamel inlay
			spec *= 1.6;
		} else {
			surf = metal_c;
		}
		surf *= 0.55 + 0.7 * clamp(lit, 0.0, 1.0);
		surf += vec3(1.0, 0.97, 0.9) * spec * 0.55;
		// Dark contour where the relief meets the shield.
		float contour = smoothstep(0.02, 0.35, h) * (1.0 - smoothstep(0.35, 0.6, h));
		col = mix(col, col * 0.45, contour * (1.0 - em.a) * 0.9);
		col = mix(col, surf, em.a);
	}

	// --- Rim ---
	float rim_w = 22.0;
	float rim_t = 1.0 - smoothstep(rim_w - 1.0, rim_w + 1.0, inside);
	if (rim_t > 0.0) {
		float bevel = dot(-n_edge, KEY_LIGHT);
		float across = clamp(inside / rim_w, 0.0, 1.0);
		float ridge = sin(across * 3.14159);  // rounded rim profile
		vec3 rdark = blue_trim ? vec3(0.28, 0.42, 0.55) : rim_dark.rgb;
		vec3 rlight = blue_trim ? vec3(0.82, 0.94, 1.0) : rim_light.rgb;
		vec3 rc = metal(rdark, rlight, 0.35 + 0.35 * vgrad + 0.3 * bevel * (1.0 - across) - 0.25 * bevel * across, 0.0);
		rc *= 0.75 + 0.35 * ridge;
		rc += rlight * pow(ridge, 8.0) * 0.25;
		col = mix(col, rc, rim_t);
	}
	// Shadow cast by the rim onto the body.
	col *= 1.0 - 0.35 * (1.0 - smoothstep(rim_w, rim_w + 8.0, inside)) * (1.0 - rim_t);

	// --- Engraved borders (silver and above) ---
	if (engraved || ornate) {
		float line1 = 1.0 - smoothstep(0.7, 1.6, abs(inside - (rim_w + 14.0)));
		col = mix(col, col * 0.45, line1 * 0.8);
		col = mix(col, col * 1.35, (1.0 - smoothstep(0.6, 1.4, abs(inside - (rim_w + 15.6)))) * 0.6);
		if (ornate) {
			float line2 = 1.0 - smoothstep(0.7, 1.6, abs(inside - (rim_w + 22.0)));
			col = mix(col, col * 0.5, line2 * 0.7);
			// Filigree dots along the border.
			float along = atan(sp.y, sp.x);
			float dots = smoothstep(0.75, 1.0, cos(along * 28.0)) * (1.0 - smoothstep(1.5, 3.2, abs(inside - (rim_w + 18.0))));
			col = mix(col, emblem_light.rgb, dots * 0.8);
		}
	}

	// --- Rim rivets / crystal studs ---
	if (studs) {
		vec2 pts[6] = {vec2(-0.86, -0.82), vec2(0.86, -0.82), vec2(-0.93, -0.1), vec2(0.93, -0.1), vec2(-0.55, 0.62), vec2(0.55, 0.62)};
		for (int i = 0; i < 6; i++) {
			vec2 c = SHIELD_C + pts[i] * SHIELD_HALF * vec2(0.96, 0.95);
			vec2 q = px - c;
			if (blue_trim && i < 2) {
				float dd = (abs(q.x) + abs(q.y)) - 11.0;
				float cm = 1.0 - smoothstep(-1.0, 1.0, dd);
				vec3 cr = mix(vec3(0.45, 0.75, 1.0), vec3(0.92, 0.98, 1.0), clamp(0.5 - q.y / 12.0 - q.x / 24.0, 0.0, 1.0));
				col = mix(col, cr, cm);
			} else {
				float r = length(q);
				float cm = 1.0 - smoothstep(6.0, 7.5, r);
				float dome = clamp(0.5 - dot(q / 7.0, KEY_LIGHT) * 0.5, 0.0, 1.0);
				vec3 rv = blue_trim ? mix(vec3(0.3, 0.45, 0.6), vec3(0.9, 0.97, 1.0), dome) : mix(rim_dark.rgb * 0.8, rim_light.rgb * 1.2, dome);
				col = mix(col, rv, cm);
			}
		}
	}

	// --- Central rivet (Novice) ---
	if (rivet) {
		vec2 q = px - vec2(256.0, 236.0);
		float r = length(q);
		float cm = 1.0 - smoothstep(15.0, 17.0, r);
		float dome = clamp(0.5 - dot(q / 16.0, KEY_LIGHT) * 0.55, 0.0, 1.0);
		vec3 rdark = blue_trim ? vec3(0.3, 0.45, 0.6) : rim_dark.rgb;
		vec3 rlight = blue_trim ? vec3(0.9, 0.97, 1.0) : rim_light.rgb;
		col *= 1.0 - 0.4 * (1.0 - smoothstep(16.0, 24.0, length(q - vec2(4.0, 6.0)))) * (1.0 - cm);
		col = mix(col, mix(rdark * 0.8, rlight * 1.15, dome), cm);
	}

	// Outer dark outline for readability at small sizes.
	col = mix(col * 0.3, col, smoothstep(0.0, 2.2, inside));
	COLOR = vec4(col, mask);
}
