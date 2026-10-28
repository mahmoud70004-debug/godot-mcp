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
// Raises the blacks towards a smoky tone, like aged oil paint.
uniform vec3 lift : source_color = vec3(0.0, 0.0, 0.0);
// 0..1, driven by gameplay (curse / low health) in later phases.
uniform float corruption : hint_range(0.0, 1.0) = 0.0;
// 0..1, driven by WeatherController: slanted screen-space rain streaks + cool haze.
uniform float rain_amount : hint_range(0.0, 1.0) = 0.0;
// 0..1, lightning pulse: brightens and cools the whole frame.
uniform float flash : hint_range(0.0, 1.0) = 0.0;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

float rand(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float luma_of(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// One layer of 1 px slanted streaks on the FRAGCOORD grid (~13 degrees).
// Returns streak coverage 0..1. No texture reads.
float rain_layer(vec2 p, float cell_w, float speed, float length_px, float density, float seed) {
	float xs = p.x + p.y * 0.23;
	float column = floor(xs / cell_w);
	float h = rand(vec2(column, seed));
	if (h > density || mod(floor(xs), cell_w) > 0.5) {
		return 0.0;
	}
	float h2 = rand(vec2(column * 1.7, seed + 3.1));
	float period = 70.0 + h2 * 90.0;
	float y = p.y + TIME * speed * (0.85 + h2 * 0.3) + h2 * 500.0;
	float t = mod(y, period);
	// Bright head, fading tail.
	return t < length_px ? (1.0 - t / length_px) * (0.5 + 0.5 * h2) : 0.0;
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
	col = lift + col * (1.0 - lift);
	col = mix(col, col * vec3(0.75, 1.1, 0.7), corruption * 0.6);

	if (rain_amount > 0.0) {
		float rl = luma_of(col);
		col = mix(col, vec3(rl) * vec3(0.9, 1.0, 1.05), rain_amount * 0.25);
		col = mix(col, vec3(0.2, 0.26, 0.28), rain_amount * 0.07);
		vec2 fp = floor(FRAGCOORD.xy);
		float streak = rain_layer(fp, 2.0, 520.0, 16.0, 0.5 * rain_amount, 1.0)
			+ rain_layer(fp, 3.0, 420.0, 12.0, 0.45 * rain_amount, 7.0) * 0.8
			+ rain_layer(fp, 5.0, 330.0, 8.0, 0.4 * rain_amount, 13.0) * 0.6
			+ rain_layer(fp, 3.0, 640.0, 22.0, 0.3 * rain_amount, 29.0) * 0.9;
		col += vec3(0.46, 0.55, 0.58) * clamp(streak, 0.0, 1.0) * (0.25 + 0.35 * rain_amount);
	}
	if (flash > 0.0) {
		col *= 1.0 + flash * 0.9;
		col = mix(col, vec3(0.78, 0.88, 1.0), flash * 0.45);
	}

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
