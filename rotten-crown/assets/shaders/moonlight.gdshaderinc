// The one night lighting model of the overworld (V7): one moon, one hemispheric sky ambient,
// one baked canopy shade, drifting cloud shadows and wind. Every material family includes
// this file so ground, trees (mesh and impostor), floor kits, props and grass agree.
// The values are global shader parameters (project.godot [shader_globals]); the defaults are
// the "no model" look (no shade, no clouds, no wind) and src/rendering/moonlight.gd
// [Moonlight] drives them in the overworld. Pure functions only: usable from vertex(),
// fragment() and light() (TIME is a global built-in). Light colours (moon_color, sky ambient) are
// linear; albedos passed in and colours returned are display (sRGB) values, see below.
#ifndef MOONLIGHT_INC
#define MOONLIGHT_INC

// Unit vector pointing TOWARDS the moon (the moon light's +Z axis in world space).
global uniform vec3 moon_dir;
// Moon light colour x energy, linear (rgb; a unused).
global uniform vec4 moon_color;
// Night sky ambient from above / bounce from the ground (linear, multiplied by albedo).
global uniform vec4 sky_ambient_top;
global uniform vec4 sky_ambient_bottom;
// Baked canopy shade (r: 1 = full moonlight, 0 = full shade) over shade_rect (x0, z0, x1, z1).
global uniform sampler2D shade_map : filter_linear, repeat_disable;
global uniform vec4 shade_rect;
// Tileable cloud noise, its drift (metres / second), repeats per metre and darkening 0..1.
global uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
global uniform vec2 cloud_scroll;
global uniform float cloud_scale;
global uniform float cloud_strength;
// Wind: (dir.x, dir.z, strength in metres, speed).
global uniform vec4 wind;

// Cloud shadow on the moonlight at a world position: 1 clear, 1 - cloud_strength under a thick cloud.
float moon_cloud(vec3 world_pos) {
	vec2 uv = (world_pos.xz + cloud_scroll * TIME) * cloud_scale;
	float n = textureLod(cloud_tex, uv, 0.0).r;
	return 1.0 - cloud_strength * smoothstep(0.45, 0.75, n);
}

// Baked canopy shade at a world position: 1 in the open (and outside shade_rect), 0 in deep shade.
float moon_canopy(vec3 world_pos) {
	vec2 uv = (world_pos.xz - shade_rect.xy) / max(shade_rect.zw - shade_rect.xy, vec2(0.0001));
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	return mix(1.0, textureLod(shade_map, uv, 0.0).r, inside);
}

// How much moonlight reaches a world position (canopy shade x cloud shadow), 0..1.
float moon_shade(vec3 world_pos) {
	return moon_canopy(world_pos) * moon_cloud(world_pos);
}

// Hemispheric sky ambient for a world-space normal (bright from above, dark bounce from below).
vec3 moon_ambient(vec3 n_world) {
	return mix(sky_ambient_bottom.rgb, sky_ambient_top.rgb, n_world.y * 0.5 + 0.5);
}

// Colour space (measured on the Compatibility renderer, V7-1): an unshaded shader writes ALBEDO
// straight to the screen (display / sRGB values), while a lit shader linearises ALBEDO, lights it
// in linear and re-encodes. So the unshaded helpers below light in linear and return display
// values: their output matches a lit material with the same albedo under the same moon.
vec3 moon_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 moon_to_display(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

// Linear light (moon key x shade + sky ambient) reaching a surface with this normal, for a given
// lambert term; lit shaders can use it in light() / for EMISSION as well.
vec3 moon_irradiance(float ndl, vec3 n_world, vec3 world_pos) {
	return moon_color.rgb * ndl * moon_shade(world_pos) + moon_ambient(n_world);
}

// Moon key (lambert x shade) + sky ambient on a display-space albedo, returned in display space:
// for UNSHADED shaders that must match lit ones.
vec3 moon_light(vec3 albedo, vec3 n_world, vec3 world_pos) {
	float ndl = max(dot(n_world, moon_dir), 0.0);
	return moon_to_display(moon_to_linear(albedo) * moon_irradiance(ndl, n_world, world_pos));
}

// moon_light() with a wrapped lambert ((N.L + wrap) / (1 + wrap)) for foliage and cards.
vec3 moon_light_wrap(vec3 albedo, vec3 n_world, vec3 world_pos, float wrap) {
	float ndl = max((dot(n_world, moon_dir) + wrap) / (1.0 + wrap), 0.0);
	return moon_to_display(moon_to_linear(albedo) * moon_irradiance(ndl, n_world, world_pos));
}

// Horizontal sway offset (y = 0) for a point height01 (0 root .. 1 tip) up a plant; pass the
// plant's origin as world_pos for a rigid sway, the vertex position for a travelling gust.
vec3 wind_offset(vec3 world_pos, float height01) {
	vec2 dir = wind.xy / max(length(wind.xy), 0.0001);
	float phase = dot(world_pos.xz, vec2(0.23, 0.31)) + sin(world_pos.x * 0.071 + world_pos.z * 0.053) * 2.0;
	float t = TIME * wind.w;
	float sway = sin(t * 1.3 + phase) * 0.7 + sin(t * 2.9 + phase * 1.7) * 0.3;
	float flutter = sin(t * 4.7 + phase * 2.3) * 0.15;
	vec2 off = (dir * sway + vec2(-dir.y, dir.x) * flutter) * wind.z * height01 * height01;
	return vec3(off.x, 0.0, off.y);
}

#endif
