shader_type canvas_item;

uniform float contrast = 1.25;
uniform float grain = 0.08;

float rnd(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	l = (l - 0.5) * contrast + 0.5;
	// slight blur/blockiness to imitate compressed aerial imagery
	float n = rnd(floor(UV * vec2(420.0, 280.0)));
	l += (n - 0.5) * grain;
	vec2 d = UV - 0.5;
	l *= 1.0 - dot(d, d) * 0.9;
	vec3 tint = vec3(l * 0.92, l * 1.0, l * 0.88);
	COLOR = vec4(tint, 1.0);
}
