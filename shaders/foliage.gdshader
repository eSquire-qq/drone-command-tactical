shader_type spatial;
render_mode cull_back, diffuse_lambert;

uniform float sway = 0.035;
uniform float roughness_v = 0.95;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(VERTEX.y + 0.6, 0.0);
	float t = TIME;
	VERTEX.x += sin(t * 1.3 + wp.x * 0.35 + wp.z * 0.21) * sway * h;
	VERTEX.z += cos(t * 1.07 + wp.z * 0.31 + wp.x * 0.12) * sway * 0.6 * h;
}

void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
	ROUGHNESS = roughness_v;
	SPECULAR = 0.2;
}
