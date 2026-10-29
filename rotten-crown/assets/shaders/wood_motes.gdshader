// Whispering Wood motes and fireflies: one MultiMesh of tiny camera-facing
// quads, animated entirely in the vertex shader (no lights, no CPU work).
// INSTANCE_CUSTOM: x = phase 0..1, y = kind (0 drifting moon mote, 1 firefly),
// z = speed 0..1, w = wander radius 0..1.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 mote_color : source_color = vec4(0.6, 0.74, 1.0, 1.0);
uniform vec4 fly_color : source_color = vec4(0.74, 0.95, 0.6, 1.0);
uniform float energy = 2.0;
uniform float size = 0.05;
uniform float wander = 0.9;
uniform float fade_start = 24.0;
uniform float fade_end = 40.0;

varying float v_alpha;
varying vec3 v_color;

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float t = TIME * (0.12 + c.z * 0.35) + c.x * 6.2831;
	vec3 off = vec3(sin(t * 1.3 + c.x * 11.0), sin(t * 0.7 + c.x * 5.0) * 0.5 - mod(TIME * 0.02 * (1.0 - c.y) + c.x, 1.0) * 0.6, cos(t * 1.1 + c.x * 7.0));
	off *= wander * (0.4 + c.w);
	vec4 centre = MODEL_MATRIX * vec4(off, 1.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], centre);
	float pulse = mix(0.45 + 0.25 * sin(TIME * 0.9 + c.x * 40.0), pow(max(sin(TIME * (1.1 + c.z) + c.x * 31.0), 0.0), 5.0), c.y);
	float dist = length((VIEW_MATRIX * centre).xyz);
	v_alpha = pulse * (1.0 - smoothstep(fade_start, fade_end, dist)) * smoothstep(0.6, 2.0, dist);
	v_color = mix(mote_color.rgb, fly_color.rgb, c.y);
	VERTEX *= size * (1.0 + c.y * 0.6);
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float dot_shape = clamp(1.0 - r, 0.0, 1.0);
	ALBEDO = v_color * energy;
	ALPHA = clamp(dot_shape * dot_shape * v_alpha, 0.0, 1.0);
}
