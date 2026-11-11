// SAO-style class badge: rounded square tile in the class-family colour with a
// crisp white glyph (from the emblem mask), soft drop shadow, glossy top and a
// tier frame (white / silver double / icy blue / gold). Original design.
shader_type canvas_item;

uniform sampler2D emblem_tex : filter_linear_mipmap;
uniform vec4 base_color : source_color = vec4(0.75, 0.15, 0.18, 1.0);
uniform vec4 frame_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool double_frame = false;
uniform bool star = false;            // small star pip for transcendent tiers
uniform vec2 glyph_offset = vec2(0.0, -0.043);
uniform float glyph_scale = 1.0;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float glyph(vec2 uv) {
	vec4 t = textureLod(emblem_tex, uv, 0.0);
	float lum = max(t.r, max(t.g, t.b));
	return lum < 0.08 ? 0.0 : t.a;   // engraved ink lines become cut-outs
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float px = 2.0 / 512.0;
	float d = sd_round_box(p, vec2(0.9), 0.2);
	float mask = 1.0 - smoothstep(-px, px, d);
	if (mask <= 0.0) discard;
	// Tile: vertical gradient, glossy upper half, darker rim.
	vec3 top = base_color.rgb * 1.25 + vec3(0.06);
	vec3 bottom = base_color.rgb * 0.55;
	vec3 col = mix(top, bottom, smoothstep(-0.9, 0.9, p.y));
	col += vec3(1.0) * 0.12 * smoothstep(0.0, -0.9, p.y) * smoothstep(0.95, 0.3, abs(p.x));
	col *= 0.82 + 0.18 * smoothstep(0.0, -0.25, d);
	// Glyph: emblem space -> centred, scaled into the tile.
	vec2 guv = (UV - vec2(0.5)) / glyph_scale + vec2(0.5) - glyph_offset;
	float g = glyph(guv);
	float sh = glyph(guv - vec2(0.012, 0.016));
	col = mix(col, col * 0.45, sh * 0.6);
	col = mix(col, vec3(1.0), g);
	// Tier frame.
	float f1 = 1.0 - smoothstep(0.0, px * 1.5, abs(d + 0.035) - 0.022);
	col = mix(col, frame_color.rgb, f1 * frame_color.a);
	if (double_frame) {
		float f2 = 1.0 - smoothstep(0.0, px * 1.5, abs(d + 0.11) - 0.008);
		col = mix(col, frame_color.rgb, f2 * 0.8);
	}
	if (star) {
		vec2 sp = p - vec2(0.62, -0.62);
		float a = atan(sp.y, sp.x);
		float r = length(sp);
		float st = 0.11 * (0.55 + 0.45 * cos(a * 5.0));
		float s = 1.0 - smoothstep(st - px, st + px, r);
		col = mix(col, frame_color.rgb, s);
	}
	// Outer dark edge for contrast on any background.
	col = mix(col * 0.35, col, smoothstep(0.0, px * 3.0, -d));
	COLOR = vec4(col, mask);
}
