// Full-screen retro grade: desaturation, sickly tint, ordered (Bayer) dither,
// colour quantisation, vignette and film grain. Runs on the 640x360 viewport,
// so every dither cell is one chunky screen pixel.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float color_levels : hint_range(2.0, 64.0) = 14.0;
uniform float dither_strength : hint_range(0.0, 2.0) = 0.7;
uniform float desaturation : hint_range(0.0, 1.0) = 0.35;
uniform vec4 tint : source_color = vec4(0.84, 0.92, 0.8, 1.0);
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.6;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.045;
uniform float contrast : hint_range(0.5, 2.0) = 1.12;
// 0..1, driven by gameplay (curse / low health) in later phases.
uniform float corruption : hint_range(0.0, 1.0) = 0.0;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

float rand(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// Corruption: faint horizontal smear.
	uv.x += (rand(vec2(floor(FRAGCOORD.y * 0.5), floor(TIME * 12.0))) - 0.5) * 0.004 * corruption;
	vec3 col = textureLod(screen_texture, uv, 0.0).rgb;

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma), desaturation);
	col = (col - 0.5) * contrast + 0.5;
	col *= tint.rgb;
	col = mix(col, col * vec3(0.75, 1.1, 0.7), corruption * 0.6);

	ivec2 cell = ivec2(mod(FRAGCOORD.xy, 4.0));
	float threshold = BAYER[cell.y * 4 + cell.x] / 16.0 - 0.5;
	col += threshold * dither_strength / color_levels;
	col = floor(clamp(col, 0.0, 1.0) * color_levels + 0.5) / color_levels;

	vec2 v = SCREEN_UV - 0.5;
	float vignette = 1.0 - dot(v, v) * vignette_strength * 2.2;
	col *= clamp(vignette, 0.0, 1.0);

	float grain = rand(FRAGCOORD.xy + fract(TIME) * vec2(91.7, 37.3)) - 0.5;
	col += grain * grain_strength;

	COLOR = vec4(col, 1.0);
}
