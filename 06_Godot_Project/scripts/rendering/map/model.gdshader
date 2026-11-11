// Classic RO model shading: texture * clamp(ambient + diffuse * N.L), computed on
// raw sRGB values like the original client, then converted to linear.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 light_dir = vec3(0.5, 0.7, -0.5);
uniform vec3 light_diffuse = vec3(1.0);
uniform vec3 light_ambient = vec3(0.3);
uniform bool use_lighting = true;
uniform float alpha = 1.0;
uniform bool flip_normals = false;

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
	vec3 c = t.rgb;
	if (use_lighting) {
		vec3 n = normalize(world_normal) * (flip_normals ? -1.0 : 1.0);
		float ndl = max(dot(n, normalize(light_dir)), 0.0);
		c *= clamp(light_ambient + light_diffuse * ndl, 0.0, 1.0);
	}
	// Model-wide translucency (RSM alpha) is not applied yet: writing ALPHA would
	// move every model into the sorted transparent pass.
	ALBEDO = srgb_to_linear(clamp(c, 0.0, 1.0));
}
