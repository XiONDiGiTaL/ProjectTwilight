// Fallback class insignia: the shared heater-shield silhouette in the rank's
// material (wood / bronze / silver / gold, optional icy-blue trim), with a
// blank centre and a small rivet. Shown only until the painted emblem exists.
shader_type canvas_item;

uniform vec4 body_dark : source_color = vec4(0.32, 0.19, 0.09, 1.0);
uniform vec4 body_light : source_color = vec4(0.62, 0.42, 0.24, 1.0);
uniform vec4 rim_dark : source_color = vec4(0.25, 0.16, 0.08, 1.0);
uniform vec4 rim_light : source_color = vec4(0.55, 0.4, 0.25, 1.0);
uniform bool wood_grain = true;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// Heater shield in [-1,1]^2 (y down): flat-ish top, sides curving to a point.
float sd_shield(vec2 p) {
	p.x = abs(p.x);
	float top = -0.82 + 0.06 * p.x * p.x;       // slightly arched top edge
	float side;
	if (p.y < 0.05) {
		side = p.x - 0.78;
	} else {
		float t = (p.y - 0.05) / 0.9;           // 0 at shoulder, 1 at tip
		side = p.x - 0.78 * sqrt(max(0.0, 1.0 - t * t));
	}
	return max(max(top - p.y, side), p.y - 0.95);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = sd_shield(p);
	float px = 2.0 / max(1.0, 1.0 / fwidth(UV.x));  // ~1 pixel in shield space
	float a = 1.0 - smoothstep(-px, px, d);
	if (a <= 0.0) discard;
	float rim_w = 0.13;
	float rim = 1.0 - smoothstep(rim_w - px, rim_w + px, -d);
	float vgrad = clamp(0.5 - p.y * 0.5, 0.0, 1.0);
	vec3 body = mix(body_dark.rgb, body_light.rgb, vgrad);
	if (wood_grain) {
		float g = noise(vec2(p.x * 9.0, p.y * 1.4)) * 0.6 + noise(vec2(p.x * 22.0, p.y * 3.0)) * 0.4;
		body *= 0.82 + 0.3 * g;
		body *= 0.92 + 0.08 * step(0.5, fract(p.x * 3.0 + 0.5));  // plank seams
	} else {
		body *= 0.9 + 0.15 * noise(p * 14.0);
		body += vec3(0.25) * pow(max(0.0, 1.0 - length(p - vec2(-0.3, -0.45)) * 1.4), 3.0);  // sheen
	}
	vec3 rim_col = mix(rim_dark.rgb, rim_light.rgb, clamp(0.6 - p.y * 0.6 - p.x * 0.2, 0.0, 1.0));
	vec3 col = mix(body, rim_col, rim);
	col = mix(col * 0.35, col, smoothstep(0.0, 0.04, -d));   // dark outline
	// Central rivet.
	float r = length(p - vec2(0.0, 0.05));
	float rivet = 1.0 - smoothstep(0.07, 0.09, r);
	col = mix(col, mix(rim_light.rgb, rim_dark.rgb, clamp((p.y - 0.0) * 6.0 + 0.5, 0.0, 1.0)), rivet);
	COLOR = vec4(col, a);
}
