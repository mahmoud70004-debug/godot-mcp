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
	ALBEDO = col + top_color * rim * smoothstep(0.85, 1.0, t);
}
