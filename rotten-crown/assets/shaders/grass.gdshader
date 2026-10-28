// Pixel grass tufts for MultiMesh quads. Blades are generated from UV
// columns (no texture), sway in the wind, and shade from base to tip.
shader_type spatial;
// Unshaded on purpose: the web renderer re-draws lit objects once per light,
// and grass covers the whole meadow. Moonlight is baked into the colours.
render_mode cull_disabled, unshaded;

uniform vec4 base_color : source_color = vec4(0.035, 0.05, 0.025, 1.0);
uniform vec4 tip_color : source_color = vec4(0.16, 0.22, 0.1, 1.0);
uniform vec4 dry_color : source_color = vec4(0.22, 0.2, 0.1, 1.0);
uniform float wind_strength = 0.07;
uniform float wind_speed = 1.4;
uniform float pixel_size = 22.0;
uniform float blades = 11.0;
uniform float lean = 0.0;
uniform float gust_strength = 1.0;
uniform float sheen = 0.0;

varying vec3 world_pos;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = 1.0 - UV.y;
	float gust = sin(TIME * wind_speed + world_pos.x * 0.35 + world_pos.z * 0.25) * 0.6 + sin(TIME * wind_speed * 2.3 + world_pos.z) * 0.4;
	VERTEX.x += (gust * gust_strength * wind_strength + lean) * h * h;
}

void fragment() {
	vec2 uv = floor(UV * pixel_size) / pixel_size;
	float column = floor(uv.x * blades);
	float seed = hash(column + floor(world_pos.x * 3.0) * 17.0 + floor(world_pos.z * 3.0) * 31.0);
	float height = 0.35 + 0.65 * seed;
	float in_blade = step(fract(uv.x * blades), 0.4);
	float y = 1.0 - uv.y;
	if (y > height || in_blade < 0.5) {
		discard;
	}
	vec3 tip = mix(tip_color.rgb, dry_color.rgb, step(0.8, seed));
	float t = y / height;
	ALBEDO = mix(base_color.rgb, tip, t);
	ALBEDO += vec3(sheen * 0.5) * smoothstep(0.7, 1.0, t);
	ROUGHNESS = 1.0;
}
