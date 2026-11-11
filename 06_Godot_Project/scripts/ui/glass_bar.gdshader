// Sleek slanted resource bar with glass track, glowing fill, white damage chip
// and 10% ticks. Original Project Twilight design.
shader_type canvas_item;

uniform vec2 size = vec2(240.0, 12.0);
uniform float value : hint_range(0.0, 1.0) = 1.0;
uniform float trail : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.32, 0.95, 0.66, 1.0);
uniform vec4 chip_color : source_color = vec4(1.0, 1.0, 1.0, 0.85);
uniform float slant = 0.6;        // horizontal shift per pixel of height
uniform float glow_px = 3.0;      // halo around the fill
uniform float ticks = 10.0;       // 0 disables
uniform float flash = 0.0;
uniform float pulse = 0.0;        // 1 = low-resource pulse

float sd_slanted(vec2 px, float x0, float x1, float h) {
	// Parallelogram from x0..x1, slanted so the top edge is shifted right.
	float shift = (h - px.y) * slant;
	float x = px.x - shift;
	float dx = max(x0 - x, x - x1);
	float dy = max(-px.y, px.y - h);
	return max(dx, dy);
}

void fragment() {
	vec2 px = UV * size;
	float h = size.y - glow_px * 2.0;
	vec2 p = px - vec2(glow_px, glow_px);
	float x0 = 0.0;
	float x1 = size.x - glow_px * 2.0 - h * slant;
	float track = sd_slanted(p, x0, x1, h);
	float fill_x = mix(x0, x1, value);
	float trail_x = mix(x0, x1, trail);
	float d_fill = sd_slanted(p, x0, fill_x, h);
	float d_chip = sd_slanted(p, x0, trail_x, h);

	vec4 col = vec4(0.0);
	// Outer glow of the fill.
	float halo = exp(-max(d_fill, 0.0) / max(glow_px * 0.6, 0.5)) * step(0.001, value);
	col = vec4(fill_color.rgb, 0.45 * halo * (1.0 - step(d_fill, 0.0)));
	if (track <= 0.8) {
		float m = 1.0 - smoothstep(-0.6, 0.6, track);
		float y = clamp(p.y / max(h, 1.0), 0.0, 1.0);
		vec3 t = mix(vec3(0.02, 0.04, 0.07), vec3(0.06, 0.09, 0.14), 1.0 - y);
		vec4 c = vec4(t, 0.78);
		if (d_chip <= 0.0) {
			c = vec4(chip_color.rgb, chip_color.a);
		}
		if (d_fill <= 0.0) {
			vec3 f = fill_color.rgb;
			f = mix(f * 0.7, f * 1.15, 1.0 - y);                       // vertical shading
			f += vec3(1.0) * 0.35 * smoothstep(0.45, 0.0, y);           // glossy top
			f += vec3(1.0) * 0.5 * exp(-(fill_x - (p.x - (h - p.y) * slant)) * 0.6);  // hot edge
			if (pulse > 0.0) f *= 0.8 + 0.3 * (0.5 + 0.5 * sin(TIME * 8.0));
			c = vec4(f, 1.0);
		}
		c.rgb = mix(c.rgb, vec3(1.0), flash * 0.35);
		if (ticks > 0.0) {
			float u = (p.x - (h - p.y) * slant - x0) / (x1 - x0);
			float tk = abs(fract(u * ticks + 0.5) - 0.5) * (x1 - x0) / ticks;
			c.rgb *= mix(0.72, 1.0, smoothstep(0.4, 1.1, tk));
		}
		// Hairline track border.
		float edge = 1.0 - smoothstep(0.0, 1.0, abs(track + 0.5));
		c.rgb = mix(c.rgb, vec3(0.7, 0.92, 1.0), edge * 0.35);
		col = mix(col, c, m);
	}
	COLOR = col;
}
