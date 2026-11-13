// Pixel grass tufts for MultiMesh quads. Blades are generated from UV
// columns (no texture), sway in the wind, and shade from base to tip.
shader_type spatial;
// Unshaded on purpose: the web renderer re-draws lit objects once per light,
// and grass covers the whole meadow. The moonlight model is evaluated per vertex (V7).
render_mode cull_disabled, unshaded;

#include "res://assets/shaders/moonlight.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.035, 0.05, 0.025, 1.0);
uniform vec4 tip_color : source_color = vec4(0.12, 0.18, 0.16, 1.0);
uniform vec4 dry_color : source_color = vec4(0.17, 0.19, 0.21, 1.0);
uniform float wind_strength = 0.07;
uniform float wind_speed = 1.4;
uniform float pixel_size = 22.0;
uniform float blades = 11.0;
uniform float lean = 0.0;
uniform float gust_strength = 1.0;
uniform float sheen = 0.0;

// Merged chunks (GrassScatter.merge_chunks): INSTANCE_CUSTOM.xyz is the centre of the
// 12 m chunk a tuft was scattered in; beyond chunk_range from it the tuft is discarded,
// exactly as that chunk's own visibility range used to cull it. 0 = off.
uniform float chunk_range = 0.0;
// Tufts shrink into the ground between these distances (ViewDistance), before their
// chunk is culled.
uniform float fade_start = 1000.0;
uniform float fade_end = 1001.0;


// V7 moonlight model: the shader's painted colours are the CLEAR-moon look; this scales them by
// the model's light (moon key with wrapped lambert x canopy shade x cloud + hemispheric sky
// ambient) relative to the reference light (project defaults, open ground, no cloud), so a
// clear moon leaves the colours as authored and shade / clouds / a dimmed moon follow the globals.
// The factor is a display-space multiplier (linear ratio ^ 1/2.2), computed per vertex.
const vec3 MOON_REF_IRR = vec3(0.387, 0.5431, 1.1067);
uniform float light_gain = 1.0;

vec3 grass_light(vec3 wp, vec3 cam) {
	vec3 to_cam = vec3(cam.x - wp.x, 0.0, cam.z - wp.z);
	vec3 n = normalize(mix(vec3(0.0, 1.0, 0.0), to_cam / max(length(to_cam), 0.001), 0.3));
	float ndl = max((dot(n, moon_dir) + 0.5) / 1.5, 0.0);
	vec3 ratio = moon_irradiance(ndl, n, wp) / MOON_REF_IRR;
	return pow(ratio, vec3(1.0 / 2.2)) * light_gain;
}

varying vec3 world_pos;
varying float v_culled;
varying vec3 v_lit;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = 1.0 - UV.y;
	float gust = sin(TIME * wind_speed + world_pos.x * 0.35 + world_pos.z * 0.25) * 0.6 + sin(TIME * wind_speed * 2.3 + world_pos.z) * 0.4;
	// Own gust character, direction and strength from the global wind (the old fixed look
	// where no Moonlight node drives it: strength 0).
	bool driven = wind.z > 0.0001;
	vec2 wdir = driven ? normalize(wind.xy) : vec2(1.0, 0.0);
	float wk = driven ? wind.z / 0.12 : 1.0;
	vec3 sway = vec3(wdir.x, 0.0, wdir.y) * (gust * gust_strength * wind_strength * wk) * h * h;
	VERTEX.x += lean * h * h;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(sway, 0.0)).xyz;
	v_lit = grass_light(world_pos, CAMERA_POSITION_WORLD);
	VERTEX.y *= 1.0 - smoothstep(fade_start, fade_end, length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
	v_culled = chunk_range > 0.0 && distance(CAMERA_POSITION_WORLD, INSTANCE_CUSTOM.xyz) > chunk_range ? 1.0 : 0.0;
	// A culled tuft collapses to a point: no pixels are rasterised for it at all.
	if (v_culled > 0.5) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (v_culled > 0.5) {
		discard;
	}
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
	ALBEDO = mix(base_color.rgb, tip, t) * v_lit;
	ALBEDO += vec3(sheen * 0.5) * smoothstep(0.7, 1.0, t);
	ROUGHNESS = 1.0;
}
