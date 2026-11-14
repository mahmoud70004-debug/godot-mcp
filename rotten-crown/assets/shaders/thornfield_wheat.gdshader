// Tall wind-bent dry grass of Thornfield (reference 1): a pale, wheat-like sea
// leaning with the storm wind, with gust waves rolling across it and drifting
// cloud shadows. Drawn on merged quad chunks (ThornfieldProps.grass_chunks):
// ArrayMesh data survives the headless world bake, MultiMesh buffers do not.
// Unshaded on purpose (the web renderer re-draws lit meshes once per light);
// the moonlight, shade and sheen are computed here.
// Vertex COLOR: r = tuft seed, g = tuft height in metres / 2, b = brightness.
// Chunk meshes keep an identity basis, so vertex offsets are world offsets.
shader_type spatial;
render_mode cull_disabled, unshaded;

#include "res://assets/shaders/moonlight.gdshaderinc"

uniform vec4 root_color : source_color = vec4(0.022, 0.024, 0.03, 1.0);
uniform vec4 stem_color : source_color = vec4(0.11, 0.115, 0.12, 1.0);
uniform vec4 tip_color : source_color = vec4(0.27, 0.28, 0.31, 1.0);
uniform vec4 ear_color : source_color = vec4(0.33, 0.34, 0.37, 1.0);
uniform vec2 wind_dir = vec2(0.55, 0.83);
// Static bend along the wind, as a fraction of the tuft height.
uniform float lean = 0.42;
uniform float gust_strength = 0.3;
uniform float gust_speed = 1.2;
// Gust waves per metre across the field.
uniform float gust_scale = 0.07;
uniform float flutter = 0.04;
uniform float blades = 26.0;
uniform float pixel_size = 52.0;
uniform float sheen = 0.45;

varying vec3 world_pos;
// Merged chunks (MeshMerger.merge_grass_chunks): CUSTOM0.xyz is the centre of the 12 m
// chunk a tuft was built in; beyond chunk_range from it the tuft is hidden, exactly as
// that chunk's own visibility range used to cull it (discarded, not moved: the wind
// math stays untouched). 0 = off.
uniform float chunk_range = 0.0;
// Tufts sink into the ground between these distances (ViewDistance: inside the fog, before
// their chunk is culled, so the field never pops).
uniform float fade_start = 1000.0;
uniform float fade_end = 1001.0;


// V7 moonlight model: the shader's painted colours are the look under the scene's reference
// light (moon_ref_irr: its base moon and ambient, open ground, no cloud); moon_light_ratio()
// scales them by the model's light at the tuft (moon key with wrapped lambert x canopy shade x
// cloud + hemispheric sky ambient), so shade, clouds, a dimmed moon and darker regions follow
// the globals. The factor is a display-space multiplier, computed per vertex.
uniform float light_gain = 0.88;

varying float v_light;
varying vec3 v_lit;
varying float v_culled;
varying float v_gust;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = 1.0 - UV.y;
	float tuft_h = COLOR.g * 2.0;
	// Direction and strength follow the global wind (project default 0 = the authored look).
	vec2 wd = wind_dir_or(wind_dir);
	float wk = wind_scale();
	float phase = dot(wp.xz, wd) * gust_scale * 6.2832 - TIME * gust_speed;
	float gust = sin(phase) * 0.5 + 0.5;
	gust *= gust;
	float fl = sin(TIME * 3.7 + COLOR.r * 40.0 + wp.x * 1.3) * flutter;
	float bend = (lean + (gust * gust_strength + fl) * wk) * h * h;
	VERTEX.xz += wd * bend * tuft_h;
	VERTEX.y -= bend * bend * tuft_h * 0.45;
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX.y -= smoothstep(fade_start, fade_end, dist) * h * tuft_h;
	// Moonlight (shade, clouds, moon) at the tuft, not the bent tip; skipped for culled tufts.
	v_culled = chunk_range > 0.0 && distance(CAMERA_POSITION_WORLD, CUSTOM0.xyz) > chunk_range ? 1.0 : 0.0;
	float shade = v_culled > 0.5 ? 0.0 : moon_shade(wp);
	v_lit = v_culled > 0.5 ? vec3(0.0) : moon_light_ratio(wp, CAMERA_POSITION_WORLD, shade) * light_gain;
	v_light = shade;
	v_gust = gust;
	world_pos = wp;
	// A culled tuft collapses to a point: no pixels are rasterised for it at all.
	if (v_culled > 0.5) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	if (v_culled > 0.5) {
		discard;
	}
	vec2 px = vec2(pixel_size, pixel_size * 1.5);
	vec2 uv = floor(UV * px) / px;
	float y = 1.0 - uv.y;
	// Blades curve sideways with height (per tuft), then split into columns.
	float x = uv.x * blades + (COLOR.r - 0.5) * 3.0 * y * y;
	float col = floor(x);
	float s = hash(col * 1.37 + COLOR.r * 97.0);
	float s2 = hash(col * 2.11 + COLOR.r * 31.0 + 5.0);
	float bh = 0.4 + 0.6 * s;
	float t = y / bh;
	float ear = step(0.55, s2) * step(0.78, t);
	float width = mix(0.46, 0.12, t) + ear * 0.3;
	if (t > 1.0 || abs(fract(x) - 0.5) * 2.0 > width) {
		discard;
	}
	vec3 c = mix(root_color.rgb, stem_color.rgb, smoothstep(0.0, 0.45, t));
	c = mix(c, tip_color.rgb, smoothstep(0.4, 1.0, t));
	c = mix(c, ear_color.rgb, ear);
	c *= (0.78 + 0.4 * s2) * (0.7 + 0.6 * COLOR.b);
	// Deep inside the tuft is dark, whatever the blade.
	c *= mix(0.35, 1.0, smoothstep(0.0, 0.55, y));
	c *= v_lit;
	c += tip_color.rgb * sheen * v_gust * t * t * v_light;
	ALBEDO = c;
}
