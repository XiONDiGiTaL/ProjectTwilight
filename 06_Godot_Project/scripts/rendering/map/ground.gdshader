// Classic RO ground shading. All math runs on raw (sRGB-encoded) values like the
// original client, and the result is converted to linear for Godot's pipeline.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_tex : filter_linear, repeat_disable;
uniform vec3 light_dir = vec3(0.5, 0.7, -0.5);
uniform vec3 light_diffuse = vec3(1.0);
uniform vec3 light_ambient = vec3(0.3);
uniform float light_opacity = 1.0;
uniform bool use_lightmap = true;
uniform bool use_tile_color = true;

varying vec3 world_normal;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	if (t.a < 0.5) {
		discard;
	}
	// Normals are oriented at build time (top faces up, walls toward the lower
	// side), so no FRONT_FACING flip: GND winding is not Godot's front-face order.
	vec3 n = normalize(world_normal);
	float ndl = max(dot(n, normalize(light_dir)), 0.0);
	vec3 light = clamp(light_ambient * light_opacity + light_diffuse * ndl, 0.0, 1.0);
	vec3 c = t.rgb * light;
	if (use_tile_color) {
		c *= COLOR.rgb;
	}
	if (use_lightmap) {
		vec4 lm = texture(lightmap_tex, UV2);
		c = c * lm.a + lm.rgb;
	}
	ALBEDO = srgb_to_linear(clamp(c, 0.0, 1.0));
}
