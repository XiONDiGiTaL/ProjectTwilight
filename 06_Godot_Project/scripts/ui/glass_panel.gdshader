// Translucent anime-MMO system window (SAO / PSO2 inspired, original design):
// blurred backdrop under a navy glass tint, chamfered corners, bright hairline
// border plus a faint inset frame, an optional gradient title band, corner
// brackets, liquid top sheen and a slow light sweep.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 size = vec2(320.0, 120.0);
uniform vec4 tint : source_color = vec4(0.07, 0.2, 0.4, 0.62);
uniform vec4 border : source_color = vec4(0.62, 0.88, 1.0, 0.6);
uniform vec4 accent : source_color = vec4(0.36, 0.78, 1.0, 1.0);
uniform vec4 header_color : source_color = vec4(0.2, 0.55, 0.95, 1.0);
uniform float header_h = 0.0;      // title band height in pixels (0 = none)
uniform float chamfer = 12.0;      // cut on top-left and bottom-right corners
uniform float blur = 2.6;          // backdrop blur (mip level)
uniform float sweep = 1.0;         // 0 disables the light sweep
uniform float glow = 0.0;          // 0..1 extra border glow (focus / alert)

float sd_chamfer_box(vec2 p, vec2 half_size, float c) {
	vec2 q = abs(p) - half_size;
	float box = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
	float cut_tl = (-p.x - p.y) - (half_size.x + half_size.y - c);
	float cut_br = (p.x + p.y) - (half_size.x + half_size.y - c);
	return max(box, max(cut_tl, cut_br) * 0.7071);
}

void fragment() {
	vec2 px = UV * size;
	vec2 c = size * 0.5;
	float d = sd_chamfer_box(px - c, c - vec2(1.0), chamfer);
	float mask = 1.0 - smoothstep(-0.8, 0.8, d);
	if (mask <= 0.0) discard;
	vec3 back = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	float vg = UV.y;
	// Navy glass body with a gentle top-to-bottom gradient.
	vec3 col = mix(back * 0.55, tint.rgb, tint.a);
	col = mix(col, col * 0.78, vg * 0.55);
	// Title band: bright system-blue gradient fading to the right, bright underline.
	if (header_h > 0.0 && px.y < header_h) {
		float hx = clamp(px.x / size.x, 0.0, 1.0);
		vec3 band = mix(header_color.rgb, header_color.rgb * 0.35, smoothstep(0.0, 1.0, hx));
		band += vec3(0.18) * smoothstep(header_h, 0.0, px.y) * 0.6;
		col = mix(col, band, 0.9);
	}
	if (header_h > 0.0) {
		col = mix(col, accent.rgb * 1.2, (1.0 - smoothstep(0.0, 1.2, abs(px.y - header_h))) * 0.9);
	}
	// Liquid top sheen.
	col += vec3(0.75, 0.9, 1.0) * 0.06 * smoothstep(0.45, 0.0, vg);
	// Slow diagonal light sweep.
	if (sweep > 0.0) {
		float s = fract(TIME * 0.06) * 2.6 - 0.8;
		float band = exp(-pow((UV.x + UV.y * 0.35 - s) * 9.0, 2.0));
		col += vec3(0.6, 0.85, 1.0) * band * 0.05 * sweep;
	}
	// Faint scanlines for the holographic feel.
	col *= 0.975 + 0.025 * sin(px.y * 2.1);
	// Outer hairline (brighter toward the top-left) and a faint inset frame.
	float edge = 1.0 - smoothstep(0.0, 1.3, abs(d + 0.6));
	float bright = mix(0.5, 1.0, clamp(1.1 - UV.x * 0.5 - UV.y * 0.7, 0.0, 1.0));
	col = mix(col, border.rgb, edge * border.a * bright + edge * glow * 0.6);
	float inset = 1.0 - smoothstep(0.0, 1.0, abs(d + 4.5));
	col = mix(col, border.rgb, inset * 0.16);
	// Corner brackets at the chamfered corners.
	float br = 0.0;
	vec2 tl = px;
	vec2 rb = size - px;
	br += step(tl.y, 2.0) * step(chamfer, tl.x) * step(tl.x, chamfer + 26.0);
	br += step(tl.x, 2.0) * step(chamfer, tl.y) * step(tl.y, chamfer + 18.0);
	br += step(rb.y, 2.0) * step(chamfer, rb.x) * step(rb.x, chamfer + 26.0);
	br += step(rb.x, 2.0) * step(chamfer, rb.y) * step(rb.y, chamfer + 18.0);
	col = mix(col, accent.rgb, clamp(br, 0.0, 1.0) * 0.9);
	COLOR = vec4(col, mix(0.9, 0.97, glow) * mask);
}
