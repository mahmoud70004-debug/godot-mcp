// V20 volumetric moonlight shafts, baked into the air (Compatibility renderer, no volumetric fog).
//
// A full-screen additive quad marches every view ray through the night haze. At each sample it asks
// "does the moon reach this point of air?" from DATA ALREADY BAKED, not from what is on screen:
// the point P at height h above the ground is lit when the ground point G = P - moon_dir * h / moon_dir.y
// (the one whose ray to the moon passes through P) is lit. The canopy shade map (MoonShadeBaker:
// every tree, wall and building projected along the moon, R) tells that for G, its G channel gives the
// ground height under P, and the drifting cloud shadow (moon_cloud) dims it like the ground. So the
// shafts stand in the world: they fill the gaps between trunks and leaves exactly where the light
// really reaches the floor, from every viewing direction, and move with the clouds. They scatter
// forward (brighter looking towards the moon) but never vanish looking away.
// Cost: `steps` samples per pixel of the 640x360 viewport (6 / 10 / 14 by quality); the march ends
// at the opaque surface (the depth buffer) so nothing in front is lit through a trunk.
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform vec3 moon_dir;
global uniform sampler2D shade_map : filter_linear, repeat_disable;
global uniform vec4 shade_rect;
global uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
global uniform vec2 cloud_offset;
global uniform float cloud_scale;
global uniform float cloud_strength;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec3 shaft_color : source_color = vec3(0.42, 0.6, 1.0);
// Overall strength (the script scales it by the moon's brightness under clouds).
uniform float strength : hint_range(0.0, 3.0) = 1.0;
uniform int steps : hint_range(4, 16) = 10;
// Camera near / far (reverse-Z depth to distance) and how far the haze is marched (m).
uniform float cam_near = 0.05;
uniform float cam_far = 170.0;
uniform float max_dist = 46.0;
// Haze density per metre in deep shade / in the open; the shaft is the contrast between lit and
// unlit air, so the open (where everything is lit) stays quiet.
uniform float density_shade = 0.095;
uniform float density_open = 0.018;
// The haze thins out above this height over the ground (m): the canopy roof.
uniform float top = 17.0;
// Ground height encoding of the shade map's G channel (MoonShadeBaker.HEIGHT_MIN / RANGE).
uniform float height_min = -12.0;
uniform float height_range = 48.0;
// 0 = scatters evenly, 1 = only towards the moon.
uniform float forward = 0.45;

vec3 shade_sample(vec2 xz) {
	vec2 uv = (xz - shade_rect.xy) / max(shade_rect.zw - shade_rect.xy, vec2(0.0001));
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec3 s = textureLod(shade_map, uv, 0.0).rgb;
	// Outside the baked rect: open sky, ground at the sample height (G = 0.25 ~ the plains).
	return mix(vec3(1.0, 0.25, 0.0), s, inside);
}

float moon_cloud_at(vec2 xz) {
	float n = textureLod(cloud_tex, (xz + cloud_offset) * cloud_scale, 0.0).r;
	return 1.0 - cloud_strength * smoothstep(0.45, 0.75, n);
}

vec3 volume(vec2 sc_uv, vec2 frag, mat4 inv_proj, mat4 inv_view, float time) {
	vec2 ndc = vec2(sc_uv.x * 2.0 - 1.0, 1.0 - sc_uv.y * 2.0);
	vec4 vp = inv_proj * vec4(ndc, 1.0, 1.0);
	vec3 dv = normalize(vp.xyz / vp.w);
	vec3 dir = normalize((inv_view * vec4(dv, 0.0)).xyz);
	vec3 cam = inv_view[3].xyz;
	float d = textureLod(depth_texture, sc_uv, 0.0).r;
	// Reverse Z with a finite far plane: d = n (f - z) / (z (f - n)).
	float z = cam_near * cam_far / (d * (cam_far - cam_near) + cam_near);
	float t_end = min(z / max(-dv.z, 0.1), max_dist);
	// A ray leaving the haze through its roof stops there.
	float cam_h = cam.y - (height_min + textureLod(shade_map, (cam.xz - shade_rect.xy) / max(shade_rect.zw - shade_rect.xy, vec2(0.0001)), 0.0).g * height_range);
	if (dir.y > 0.02) {
		t_end = min(t_end, max(top - cam_h, 0.5) / dir.y);
	}
	float mdy = max(moon_dir.y, 0.2);
	float cos_t = dot(dir, moon_dir);
	// Henyey-Greenstein (g 0.35), normalised to 1 looking straight at the moon, blended with an even floor.
	float hg = (0.8775 / pow(1.1225 - 0.7 * cos_t, 1.5)) / 3.2;
	float phase = mix(1.0, hg, forward);
	// Interleaved gradient noise: a fine, even pattern the retro dither hides (white noise showed as grain).
	float jitter = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
	float acc = 0.0;
	float dt = t_end / float(steps);
	for (int i = 0; i < 16; i++) {
		if (i >= steps) {
			break;
		}
		// Denser near the eye, where a shaft is big on screen.
		float u = (float(i) + jitter) / float(steps);
		float t = t_end * u * u * (3.0 - 2.0 * u) * 0.35 + t_end * u * 0.65;
		vec3 p = cam + dir * t;
		vec3 here = shade_sample(p.xz);
		float h = p.y - (height_min + here.g * height_range);
		if (h < -0.3 || h > top) {
			continue;
		}
		h = max(h, 0.0);
		vec2 g = p.xz - moon_dir.xz * (h / mdy);
		vec3 lit_s = shade_sample(g);
		// Shade map: 1 open, 0 deep shade. Crisp the dapples so partly lit air stays quiet.
		float lit = smoothstep(0.08, 0.5, lit_s.r) * moon_cloud_at(g);
		// Haze is thicker in the shaded wood (it pools under the canopy) than over open ground, and
		// thins out upwards to the roof.
		float dens = mix(density_shade, density_open, here.r) * (0.35 + 0.65 * exp(-h / 6.0)) * (1.0 - smoothstep(top * 0.6, top, h));
		// A slow breathing, so the air is never still.
		dens *= 0.9 + 0.1 * sin(time * 0.25 + dot(p.xz, vec2(0.11, 0.07)));
		acc += lit * dens * dt * exp(-t * 0.018);
	}
	return shaft_color * acc * phase * strength;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

void fragment() {
	ALBEDO = volume(SCREEN_UV, FRAGCOORD.xy, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, TIME);
	ALPHA = 1.0;
}
