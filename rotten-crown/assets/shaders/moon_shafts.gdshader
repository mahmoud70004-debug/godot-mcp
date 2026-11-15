// V19 moonlight shafts: screen-space crepuscular rays towards the moon, in the Compatibility
// renderer (no volumetric fog there). A full-screen additive quad reads the DEPTH buffer: a pixel
// is "open sky" where the depth is 0 (reversed Z in Godot 4.7 Compatibility: nothing drawn there; leaf cut-outs included, they are discarded
// before depth), and every pixel marches towards the moon on screen, adding the share of open
// sky it passes. Gaps between trunks and leaves therefore throw real shafts into the dark
// air behind them, strongest towards the moon, instead of any lifting of the whole frame.
// Nothing is drawn when the moon is behind the camera. Cost: `steps` depth reads per pixel of the
// 640x360 viewport (8 / 12 / 16 by quality), no colour read-back.
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform vec3 moon_dir;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec3 shaft_color : source_color = vec3(0.42, 0.6, 1.0);
// Overall strength (the script scales it by the moon's brightness under clouds).
uniform float strength : hint_range(0.0, 2.0) = 0.6;
uniform int steps : hint_range(4, 16) = 12;
// 1 marches all the way to the moon, less stops short (softer, shorter shafts).
uniform float reach : hint_range(0.2, 1.0) = 0.9;
// Weight left after each step: lower = the shafts concentrate near their source.
uniform float decay : hint_range(0.7, 1.0) = 0.94;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Smooth 1D value noise round the moon: the thin beams, drifting very slowly (dust in the air).
float beams(float a, float time) {
	float x = a * 9.0 + time * 0.04;
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n = mix(hash(vec2(i, 3.1)), hash(vec2(i + 1.0, 3.1)), f);
	float y = a * 31.0 - time * 0.07;
	float j = floor(y);
	float g = fract(y);
	g = g * g * (3.0 - 2.0 * g);
	float m = mix(hash(vec2(j, 7.7)), hash(vec2(j + 1.0, 7.7)), g);
	return 0.45 + 0.55 * (n * 0.65 + m * 0.35);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

float shafts(vec2 uv, vec2 fragcoord, mat4 view, mat4 proj, float time) {
	vec3 mv = normalize((view * vec4(moon_dir, 0.0)).xyz);
	float front = -mv.z;
	if (front < 0.02) {
		return 0.0;
	}
	vec4 clip = proj * vec4(mv * 100.0, 1.0);
	vec2 ndc = clip.xy / clip.w;
	vec2 moon_uv = vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
	// Fades: the moon turning out of view, and far off to the side.
	float off = length((moon_uv - 0.5) * vec2(1.0, 0.5625));
	float vis = smoothstep(0.02, 0.35, front) * (1.0 - smoothstep(0.7, 1.5, off));
	if (vis <= 0.0) {
		return 0.0;
	}
	vec2 delta = (moon_uv - uv) * reach;
	vec2 stp = delta / float(steps);
	vec2 p = uv + stp * hash(fragcoord + fract(time) * 7.0);
	float acc = 0.0;
	float norm = 0.0;
	float w = 1.0;
	for (int i = 0; i < 16; i++) {
		if (i >= steps) {
			break;
		}
		float d = textureLod(depth_texture, clamp(p, vec2(0.002), vec2(0.998)), 0.0).r;
		acc += step(d, 0.00001) * w;
		norm += w;
		w *= decay;
		p += stp;
	}
	acc /= max(norm, 0.001);
	float here_d = textureLod(depth_texture, uv, 0.0).r;
	float here_sky = step(here_d, 0.00001);
	// Reversed Z: depth = near / distance. Air in front of the surface carries the light: nothing
	// on a trunk right in front of the eye, most in the middle distance, less again on far fogged
	// silhouettes (they must not glow like cut-outs).
	float z = 0.05 / max(here_d, 0.000001);
	float air = smoothstep(1.5, 14.0, z) * (1.0 - 0.75 * smoothstep(45.0, 130.0, z));
	// Brightest near the moon, thin far from it; the open sky itself is left alone.
	float dist = length(delta * vec2(1.0, 0.5625)) / max(reach, 0.01);
	float falloff = exp(-dist * 0.85);
	float shape = smoothstep(0.12, 0.85, acc);
	float ang = atan(delta.y * 0.5625, delta.x);
	return shape * falloff * beams(ang, time) * mix(air, 0.08, here_sky) * vis * strength;
}

void fragment() {
	ALBEDO = shaft_color * shafts(SCREEN_UV, FRAGCOORD.xy, VIEW_MATRIX, PROJECTION_MATRIX, TIME);
	ALPHA = 1.0;
}
