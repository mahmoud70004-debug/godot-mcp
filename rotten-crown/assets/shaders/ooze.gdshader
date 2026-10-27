// Flat procedural splat used for the green curse-ooze and for blood.
// The blob silhouette is generated from noise, pixelated, and alpha-cut,
// so one PlaneMesh gives an endless variety of irregular puddles.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 surface_color : source_color = vec4(0.36, 0.66, 0.08, 1.0);
uniform vec4 deep_color : source_color = vec4(0.06, 0.17, 0.02, 1.0);
uniform float emission_strength = 1.4;
uniform float bubble_amount : hint_range(0.0, 1.0) = 1.0;
uniform float bubble_speed = 0.5;
uniform float pixel_size = 24.0;
uniform float roughness_value = 0.15;

instance uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = floor(UV * pixel_size) / pixel_size;
	float d = length(uv - 0.5) * 2.0;
	vec2 s = vec2(seed * 13.7, seed * 7.3);
	float n = noise(uv * 5.0 + s) * 0.65 + noise(uv * 11.0 - s) * 0.35;
	float mask = (1.0 - d) + (n - 0.5) * 1.1;
	if (mask < 0.12) {
		discard;
	}
	float depth = smoothstep(0.12, 0.65, mask);
	float bubbles = step(0.94, noise(uv * 18.0 + vec2(TIME * bubble_speed, seed))) * bubble_amount;
	vec3 col = mix(surface_color.rgb, deep_color.rgb, depth);
	col += bubbles * 0.25;
	ALBEDO = col;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.7;
	float shimmer = 0.8 + 0.2 * sin(TIME * 2.0 + n * 6.2831);
	EMISSION = surface_color.rgb * emission_strength * (0.3 + 0.7 * (1.0 - depth)) * shimmer;
}
