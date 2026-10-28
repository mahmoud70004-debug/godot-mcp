// Faint additive moonlight shafts and blue mist cards for the Whispering Wood.
// Unshaded, additive, no depth writes; fades out with distance (and very close
// to the camera) so it blends into the fog instead of popping.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.62, 0.74, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.1;
// 0 = shaft (soft vertical edges and ends), 1 = mist (radial falloff).
uniform float radial : hint_range(0.0, 1.0) = 0.0;
uniform bool billboard = false;
uniform float near_start = 0.5;
uniform float near_end = 5.0;
uniform float far_start = 60.0;
uniform float far_end = 120.0;
uniform float shimmer = 0.15;

varying float view_dist;
varying vec3 world_pos;

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float edge = sin(clamp(UV.x, 0.0, 1.0) * 3.14159);
	float ends = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.45, UV.y);
	float shaft = edge * edge * ends;
	float r = clamp(length((UV - vec2(0.5)) * 2.0), 0.0, 1.0);
	float mist = pow(1.0 - r, 2.0);
	float shape = mix(shaft, mist, radial);
	float fade = smoothstep(near_start, near_end, view_dist) * (1.0 - smoothstep(far_start, far_end, view_dist));
	float flick = 1.0 + shimmer * sin(TIME * 0.6 + world_pos.x * 0.7 + world_pos.z * 0.5);
	ALBEDO = tint.rgb;
	ALPHA = clamp(shape * fade * intensity * flick, 0.0, 1.0);
}
