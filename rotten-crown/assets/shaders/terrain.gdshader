// Kingdom ground: four small scanned textures (nearest-filtered) blended by
// vertex paint (R road/mud, G pale dry field, B forest floor, remainder grass)
// with a dithered, pixel-quantized transition so edges stay crisp and retro.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D grass_tex : filter_nearest, repeat_enable;
uniform sampler2D dry_tex : filter_nearest, repeat_enable;
uniform sampler2D road_tex : filter_nearest, repeat_enable;
uniform sampler2D forest_tex : filter_nearest, repeat_enable;
// Texture repeats per metre for each layer.
uniform float grass_scale = 0.16;
uniform float dry_scale = 0.2;
uniform float forest_scale = 0.2;
uniform float road_scale = 0.28;
uniform vec3 grass_tint : source_color = vec3(0.5, 0.55, 0.45);
uniform vec3 dry_tint : source_color = vec3(0.75, 0.68, 0.5);
uniform vec3 forest_tint : source_color = vec3(0.38, 0.4, 0.36);
uniform vec3 road_tint : source_color = vec3(0.62, 0.56, 0.5);

varying vec3 world_pos;
varying vec3 paint;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	paint = COLOR.rgb;
}

float bayer4(vec2 p) {
	ivec2 c = ivec2(mod(p, 4.0));
	int i = c.y * 4 + c.x;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return m[i] / 16.0;
}

void fragment() {
	vec2 uv = world_pos.xz;
	// Dither threshold on the 16 px/m world grid so blends read as pixel art.
	float d = bayer4(floor(world_pos.xz * 16.0)) - 0.5;
	vec3 grass = texture(grass_tex, uv * grass_scale).rgb * grass_tint;
	vec3 col = grass;
	if (paint.b + d * 0.5 > 0.5) {
		col = texture(forest_tex, uv * forest_scale).rgb * forest_tint;
	}
	if (paint.g + d * 0.5 > 0.5) {
		col = texture(dry_tex, uv * dry_scale).rgb * dry_tint;
	}
	if (paint.r + d * 0.5 > 0.5) {
		vec3 road = texture(road_tex, uv * road_scale).rgb * road_tint;
		float luma = dot(road, vec3(0.3, 0.59, 0.11));
		// The same road changes with the land it crosses: a pale, moonlit dirt
		// path under the trees, a worn olive track through the dry fields.
		road = mix(road, vec3(luma) * vec3(1.5, 1.45, 1.35), smoothstep(0.2, 0.6, paint.b));
		road = mix(road, mix(vec3(luma) * vec3(1.3, 1.25, 0.9), col, 0.35), smoothstep(0.2, 0.6, paint.g));
		col = road;
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
