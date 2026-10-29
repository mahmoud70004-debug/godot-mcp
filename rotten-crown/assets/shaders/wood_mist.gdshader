// Whispering Wood mist: soft additive cards with slowly drifting value noise.
// billboard 0 = fixed card, 1 = faces the camera, 2 = turns around Y only
// (low banks that stay upright). Fades near the camera (you walk through it,
// it does not wall the view) and far away (no overdraw beyond the fog).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.32, 0.46, 0.95, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 0.3;
uniform int billboard = 2;
uniform float near_start = 3.0;
uniform float near_end = 14.0;
uniform float far_start = 70.0;
uniform float far_end = 110.0;
// Noise cells per card; 0 = smooth radial glow.
uniform float wisps = 2.5;
uniform float speed = 0.03;
// Extra fade towards the card's bottom edge (hides where it cuts the ground).
uniform float bottom_soft = 0.45;
uniform float seed = 0.0;
// Long ground strips: soft across (UV.x) only; UV.y runs along in metres / 4.
uniform bool strip = false;

varying float view_dist;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	if (billboard == 1) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	} else if (billboard == 2) {
		vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
		vec3 back = vec3(-right.z, 0.0, right.x);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(back, 0.0), MODEL_MATRIX[3]);
	}
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec2 q = (UV - vec2(0.5)) * 2.0;
	float edge = clamp(1.0 - (strip ? q.x * q.x : dot(q, q)), 0.0, 1.0);
	edge *= edge;
	float shape = edge;
	if (wisps > 0.0) {
		vec2 w = UV * wisps + vec2(seed * 3.7, seed * 1.3);
		float t = TIME * speed;
		float n = vnoise(w + vec2(t, t * 0.4)) * 0.6 + vnoise(w * 2.3 - vec2(t * 0.5, t)) * 0.4;
		shape *= smoothstep(0.2, 0.8, n) * 1.6;
	}
	shape *= mix(1.0, smoothstep(1.0, 1.0 - bottom_soft, UV.y), step(0.001, bottom_soft));
	float fade = smoothstep(near_start, near_end, view_dist) * (1.0 - smoothstep(far_start, far_end, view_dist));
	ALBEDO = tint.rgb;
	ALPHA = clamp(shape * fade * intensity, 0.0, 1.0);
}
