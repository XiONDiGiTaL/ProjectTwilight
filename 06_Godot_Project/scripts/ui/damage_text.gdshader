// Sleek combat text: vertical gradient fill, crisp white outline and a soft
// coloured glow, drawn from one Label. The Label uses marker colours so the
// passes can be told apart: fill = white, outline = green, shadow = red.
shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(0.92, 0.98, 1.0, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.45, 0.75, 1.0, 1.0);
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.3, 0.65, 1.0, 1.0);
uniform float height = 40.0;      // label height in px (gradient span)
uniform float shine = 0.0;        // 1 = animated sheen sweep + pulse (big hits)

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 c = COLOR;
	float a = c.a;
	if (c.g > 0.5 && c.r < 0.5) {
		// Outline pass.
		COLOR = vec4(outline_color.rgb, outline_color.a * a);
	} else if (c.r > 0.5 && c.g < 0.5) {
		// Glow (shadow) pass.
		float pulse = 1.0 + shine * 0.35 * sin(TIME * 9.0);
		COLOR = vec4(glow_color.rgb, glow_color.a * a * pulse);
	} else {
		float k = clamp(local_pos.y / max(height, 1.0), 0.0, 1.0);
		vec3 fill = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.15, 0.95, k));
		// Glassy highlight band across the upper third.
		fill += vec3(0.18) * smoothstep(0.42, 0.3, k) * smoothstep(0.12, 0.26, k);
		if (shine > 0.0) {
			float sweep = fract(TIME * 0.9) * 3.0 - 1.0;
			float band = exp(-pow((local_pos.x / max(height, 1.0) * 0.5 - k * 0.4 - sweep) * 5.0, 2.0));
			fill += vec3(0.55, 0.8, 1.0) * band * 0.6 * shine;
		}
		COLOR = vec4(fill, a);
	}
}
