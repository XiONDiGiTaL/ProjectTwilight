// Shared additive glow for spell effects, sparkles and light pillars.
// shape: 0 soft disc, 1 ring, 2 streak (bolt), 3 four-point sparkle,
//        4 light pillar (cylinder UV: x around, y along height).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform vec4 core : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform int shape = 0;
uniform float intensity = 1.0;
uniform float ring_radius = 0.7;   // ring: radius 0..1
uniform float ring_width = 0.08;
uniform bool billboard = false;
uniform float streak_speed = 0.6;  // pillar streak scroll speed

varying vec4 v_color;

float hash(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void vertex() {
	v_color = COLOR;
	if (billboard) {
		mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		bb = bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float v = 0.0;
	float c = 0.0;
	if (shape == 0) {
		v = exp(-r * r * 4.0);
		c = exp(-r * r * 30.0);
	} else if (shape == 1) {
		float d = abs(r - ring_radius);
		v = exp(-pow(d / ring_width, 2.0));
		c = exp(-pow(d / (ring_width * 0.3), 2.0));
	} else if (shape == 2) {
		float across = exp(-pow(p.x * 3.2, 2.0));
		float along = smoothstep(1.0, 0.6, abs(p.y)) * (0.35 + 0.65 * smoothstep(-1.0, 0.8, -p.y));
		v = across * along;
		c = exp(-pow(p.x * 9.0, 2.0)) * along;
	} else if (shape == 3) {
		vec2 a = abs(p);
		float star = exp(-a.x * 14.0) * exp(-a.y * 2.2) + exp(-a.y * 14.0) * exp(-a.x * 2.2);
		v = star + exp(-r * r * 12.0) * 0.6;
		c = exp(-r * r * 60.0);
	} else {
		float h = UV.y;   // 0 top .. 1 bottom on CylinderMesh
		float base = smoothstep(0.0, 0.85, h) * smoothstep(1.0, 0.94, h);
		float cols = 34.0;
		float id = floor(UV.x * cols);
		float s = hash(id);
		float scroll = fract(h * (1.0 + s) + TIME * streak_speed * (0.5 + s));
		float streak = smoothstep(0.0, 0.08, fract(UV.x * cols)) * smoothstep(1.0, 0.7, fract(UV.x * cols));
		streak *= smoothstep(0.4, 1.0, scroll) * step(0.35, s);
		v = base * (0.25 + streak * 1.2);
		c = base * streak * 0.5;
	}
	float a = v_color.a > 0.0 ? v_color.a : 1.0;
	vec3 tint = v_color.rgb == vec3(0.0) ? vec3(1.0) : v_color.rgb;
	ALBEDO = (color.rgb * v + core.rgb * c) * intensity * a * tint;
}
