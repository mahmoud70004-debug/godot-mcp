// Distant landscape layers (hills, crags, ruined spires) drawn as flat
// painted silhouettes. They ignore fog and instead fade from a dark base to
// a hazier top colour, giving the layered depth of the concept paintings.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled;

uniform vec3 base_color : source_color = vec3(0.03, 0.04, 0.03);
uniform vec3 top_color : source_color = vec3(0.1, 0.12, 0.09);
uniform float base_height = 0.0;
uniform float top_height = 30.0;
uniform float rim = 0.25;
// Veil (ViewDistance): mix towards the fog colour. Parts standing inside veil_rect (x0, z0,
// x1, z1: the walled kingdom, whose fogged forest stands in front of them) are fully veiled,
// so no painted hill ever shows between fogged trees.
uniform vec3 haze_color : source_color = vec3(0.13, 0.14, 0.18);
uniform float haze = 0.0;
uniform vec4 veil_rect = vec4(0.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = clamp((world_pos.y - base_height) / max(top_height - base_height, 0.001), 0.0, 1.0);
	vec3 col = mix(base_color, top_color, t * t);
	// Pixel dither between the two tones keeps the retro look.
	float d = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	col += (d - 0.5) * 0.015;
	col += top_color * rim * smoothstep(0.85, 1.0, t);
	vec2 p = world_pos.xz;
	float inside = step(veil_rect.x, p.x) * step(p.x, veil_rect.z) * step(veil_rect.y, p.y) * step(p.y, veil_rect.w);
	ALBEDO = mix(col, haze_color, max(haze, inside));
}
