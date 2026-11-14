// Kingdom ground: four small scanned textures (nearest-filtered) blended by
// vertex paint (R road/mud, G pale dry field, B forest floor, remainder grass)
// with a dithered, pixel-quantized transition so edges stay crisp and retro.
// Inside the kingdom forest the paint alpha also carries the floor (ForestBuilder):
// alpha 1 = untouched; 1 -> 0.5 = more moss in blotches over dark loam; below 0.5 =
// the amber leaf litter of the Cellar Hollow.
shader_type spatial;
// The renderer's flat Environment ambient is off: the sky ambient comes from the moon model
// (moon_ambient(), added in light() with the moon), the same as every other family.
render_mode diffuse_lambert, specular_disabled, ambient_light_disabled;

#include "res://assets/shaders/moonlight.gdshaderinc"

uniform sampler2D grass_tex : filter_nearest_mipmap, repeat_enable;
uniform sampler2D dry_tex : filter_nearest_mipmap, repeat_enable;
uniform sampler2D road_tex : filter_nearest_mipmap, repeat_enable;
uniform sampler2D forest_tex : filter_nearest_mipmap, repeat_enable;
// Texture repeats per metre for each layer.
uniform float grass_scale = 0.16;
uniform float dry_scale = 0.2;
uniform float forest_scale = 0.2;
uniform float road_scale = 0.28;
// V7: renamed from *_tint. The bake stores every uniform's value in the baked materials, so a
// change to these defaults only shows after a re-bake (tools/bake_world.sh overworld).
uniform vec3 grass_albedo : source_color = vec3(0.64, 0.74, 0.82);
uniform vec3 dry_albedo : source_color = vec3(0.66, 0.68, 0.75);
uniform vec3 forest_albedo : source_color = vec3(0.64, 0.7, 0.78);
uniform vec3 road_albedo : source_color = vec3(1.0, 1.0, 1.08);
uniform vec3 loam_albedo : source_color = vec3(0.5, 0.52, 0.57);
uniform vec3 moss_albedo : source_color = vec3(0.56, 0.84, 0.74);
uniform vec3 amber_albedo : source_color = vec3(1.0, 0.74, 0.52);

// Linear gain on the lit ground layers (the scans x tints alone give ~0.1 albedo, near black
// under a 30 degree moon); the road keeps its own, lower, level so paths read paler but textured.
const float GROUND_GAIN = 2.2;

varying vec3 world_pos;
varying vec3 paint;
varying float floor_mix;
// The cloud shadow, per vertex: the clouds are ~80 m features, the ground grid is 2 m.
varying float v_cloud;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	paint = COLOR.rgb;
	floor_mix = 1.0 - COLOR.a;
	v_cloud = moon_cloud(world_pos);
}

float blotch(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec4 h = fract(sin(vec4(dot(i, vec2(127.1, 311.7)), dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7)),
		dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7)), dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7)))) * 43758.5453);
	return mix(mix(h.x, h.y, u.x), mix(h.z, h.w, u.x), u.y);
}

float bayer4(vec2 p) {
	ivec2 c = ivec2(mod(p, 4.0));
	int i = c.y * 4 + c.x;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return m[i] / 16.0;
}

void fragment() {
	vec2 uv = world_pos.xz;
	// Dither threshold on an 8 px/m world grid so blends read as chunky pixel art (V6:
	// 16 px/m went below one screen pixel a few metres out and read as grain).
	float d = bayer4(floor(world_pos.xz * 8.0)) - 0.5;
	vec3 grass = texture(grass_tex, uv * grass_scale).rgb * grass_albedo;
	// Keep the night mood: pull the scan's green toward blue-grey.
	grass = mix(vec3(dot(grass, vec3(0.3, 0.59, 0.11))) * vec3(0.92, 1.0, 1.08), grass, 0.55);
	vec3 col = grass;
	if (paint.b + d * 0.3 > 0.5) {
		col = texture(forest_tex, uv * forest_scale).rgb * forest_albedo;
		if (floor_mix > 0.004) {
			vec3 base = texture(forest_tex, uv * forest_scale).rgb;
			float moss_amt = min(floor_mix * 2.0, 1.0);
			float amber = clamp(floor_mix * 2.0 - 1.0, 0.0, 1.0);
			float n = blotch(world_pos.xz * 0.11) * 0.7 + blotch(world_pos.xz * 0.43) * 0.3;
			col = base * loam_albedo;
			if (n + d * 0.2 < moss_amt * 0.6) {
				col = texture(grass_tex, uv * 0.23).rgb * moss_albedo;
			}
			if (amber + d * 0.3 > 0.5 + n * 0.3) {
				col = base * amber_albedo;
			}
		}
	}
	if (paint.g + d * 0.3 > 0.5) {
		col = texture(dry_tex, uv * dry_scale).rgb * dry_albedo;
	}
	col *= GROUND_GAIN;
	if (paint.r + d * 0.3 > 0.5) {
		vec3 road = texture(road_tex, uv * road_scale).rgb * road_albedo;
		float luma = dot(road, vec3(0.3, 0.59, 0.11));
		// The same road changes with the land it crosses: a pale, moonlit dirt
		// path under the trees, a worn grey track through the dry fields.
		road = mix(road, vec3(luma) * vec3(1.6, 1.66, 1.8), smoothstep(0.2, 0.6, paint.b));
		road = mix(road, mix(vec3(luma) * vec3(1.12, 1.16, 1.26), col, 0.35), smoothstep(0.2, 0.6, paint.g));
		col = road;
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}

// The moon (the directional light) goes through the shared model: lambert as Godot's
// diffuse_lambert (light colour / PI), times the baked canopy shade (per pixel: its dapples are
// finer than the ground grid) x the cloud shadow, combined with the real-time shadow as min()
// so the two never double-darken; with it comes the hemispheric sky ambient (moon_ambient(),
// linear, multiplied by the linear albedo like the renderer's own ambient), once per pixel.
// Lantern omnis stay plain lambert. Needs the scene's moon (a directional light): without one
// the ground gets no ambient either.
void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float att = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		att = min(att, moon_canopy(world_pos) * v_cloud);
		DIFFUSE_LIGHT += moon_ambient((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * ndl * att / PI;
}
