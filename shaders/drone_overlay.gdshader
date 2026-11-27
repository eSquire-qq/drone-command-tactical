shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.045;
uniform float vignette = 0.55;
uniform float desat = 0.16;
uniform float tint_strength = 0.05;
uniform float jam = 0.0;   // 0 clean link .. 1 nearly lost (enemy EW)

float rnd(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	// EW interference: horizontal tearing bands and line jitter
	float band = step(1.0 - jam * 0.35, rnd(vec2(floor(uv.y * 40.0), floor(t * 12.0))));
	uv.x += band * (rnd(vec2(floor(uv.y * 90.0), t)) - 0.5) * 0.08 * jam;
	uv.x += (rnd(vec2(floor(uv.y * 300.0), floor(t * 30.0))) - 0.5) * 0.006 * jam;
	// blocky macroblock corruption
	vec2 blk = floor(uv * vec2(48.0, 27.0));
	float corrupt = step(1.0 - jam * jam * 0.25, rnd(blk + floor(t * 8.0)));
	vec2 d = uv - 0.5;
	float e = dot(d, d);
	vec3 c;
	c.r = texture(screen_tex, uv + d * e * 0.006 + vec2(jam * 0.004, 0.0)).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - d * e * 0.006 - vec2(jam * 0.004, 0.0)).b;
	c = mix(c, texture(screen_tex, (blk + 0.5) / vec2(48.0, 27.0)).rgb, corrupt);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desat + jam * 0.6);
	c = mix(c, c * vec3(0.95, 1.03, 0.97), tint_strength * 4.0);
	float n = rnd(uv * vec2(1731.0, 977.0) + fract(t * 7.13));
	c += (n - 0.5) * (grain + jam * 0.35);
	// signal dropouts
	float drop = step(0.93, rnd(vec2(floor(t * 6.0), 1.0))) * smoothstep(0.6, 1.0, jam);
	c = mix(c, vec3(n * 0.4), drop);
	c *= 1.0 - e * vignette * 1.6;
	c *= 0.985 + 0.015 * sin(uv.y * 1100.0 + t * 30.0);
	COLOR = vec4(c, 1.0);
}
