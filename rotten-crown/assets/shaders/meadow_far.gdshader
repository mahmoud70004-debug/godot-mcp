// Far village silhouettes seen across the plains from the Moonlit Meadows
// (task U10): flat painted cards (roofs, a church spire, the lone farmhouse, a
// tree line) standing in front of the horizon backdrop. Like silhouette.gdshader
// they ignore fog and fade from a dark foot to a hazier top, but they are fixed
// in the world, so they dissolve (dithered) as the player walks up to them and
// the real, fogged region geometry takes over. Vertex COLOR.r = 1 marks a lit
// window (the pale yellow accent of the plains palette).
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled;

uniform vec3 base_color : source_color = vec3(0.045, 0.055, 0.045);
uniform vec3 top_color : source_color = vec3(0.1, 0.115, 0.095);
uniform vec3 window_color : source_color = vec3(0.79, 0.7, 0.35);
// Card-local heights of the gradient.
uniform float base_height = 0.0;
uniform float top_height = 14.0;
// Fully gone closer than near_end, fully drawn beyond near_start (metres).
uniform float near_end = 52.0;
uniform float near_start = 70.0;

varying float local_y;
varying float view_dist;
varying float front;

void vertex() {
	local_y = VERTEX.y;
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	// Seen from behind (local -Z side) the card is a lie: hide it.
	front = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).z;
}

float bayer4(vec2 p) {
	ivec2 c = ivec2(mod(p, 4.0));
	int i = c.y * 4 + c.x;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	float fade = smoothstep(near_end, near_start, view_dist) * step(0.0, front);
	if (fade < bayer4(floor(FRAGCOORD.xy))) {
		discard;
	}
	float t = clamp((local_y - base_height) / max(top_height - base_height, 0.001), 0.0, 1.0);
	vec3 col = mix(base_color, top_color, t * t);
	float d = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	col += (d - 0.5) * 0.012;
	ALBEDO = mix(col, window_color, step(0.5, COLOR.r));
}
