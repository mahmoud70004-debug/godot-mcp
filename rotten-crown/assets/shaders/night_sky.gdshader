// Painterly pixel night sky, used for both moods of the game:
//  - "Gloom"  (cursed Valdron): grey-green haze, moon behind torn clouds.
//  - "Festive" (the night of the feast): deep blue, dense stars, a bright
//    star with long rays.
// The moon follows the scene's first DirectionalLight (LIGHT0).
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.015, 0.02, 0.02);
uniform vec3 horizon_color : source_color = vec3(0.3, 0.32, 0.25);
uniform vec3 ground_color : source_color = vec3(0.02, 0.025, 0.02);
uniform float horizon_sharpness = 3.5;

uniform vec3 moon_color : source_color = vec3(0.95, 0.92, 0.74);
uniform float moon_size = 0.035;
uniform vec3 halo_color : source_color = vec3(0.45, 0.47, 0.37);
uniform float halo_size = 0.5;
uniform float halo_strength = 0.9;

uniform float star_density = 0.012;
uniform float star_brightness = 1.2;
uniform vec3 star_tint : source_color = vec3(0.85, 0.9, 0.8);

uniform vec3 cloud_color : source_color = vec3(0.05, 0.06, 0.06);
uniform vec3 cloud_lit_color : source_color = vec3(0.5, 0.53, 0.44);
uniform float cloud_coverage = 0.55;
uniform float cloud_speed = 0.006;
uniform float cloud_scale = 1.6;

// Optional radiant star (festive sky). flare_strength 0 disables it.
uniform vec3 flare_direction = vec3(0.0, 0.75, -0.66);
uniform vec3 flare_color : source_color = vec3(0.6, 0.75, 1.0);
uniform float flare_strength = 0.0;
uniform float flare_rays = 10.0;

float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise2(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = dir.y;

	// Base gradient with a glowing horizon band.
	float h = clamp(up, 0.0, 1.0);
	vec3 col = mix(horizon_color, zenith_color, pow(h, 1.0 / horizon_sharpness));
	col = mix(col, ground_color, smoothstep(0.0, -0.08, up));

	vec3 moon_dir = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : vec3(0.0, 0.5, -0.86);
	float moon_dot = dot(dir, moon_dir);
	float moon_dist = acos(clamp(moon_dot, -1.0, 1.0));

	// Halo: soft wide glow plus a tighter bright ring.
	float halo = exp(-moon_dist / max(halo_size, 0.001) * 3.0) * halo_strength;
	halo += exp(-moon_dist / max(moon_size * 4.0, 0.001)) * 0.6 * halo_strength;
	col += halo_color * halo;

	if (!AT_CUBEMAP_PASS && up > 0.0) {
		// Stars on a fixed grid of directions, twinkling, fading near the horizon.
		vec3 cell = floor(dir * 220.0);
		float r = hash(cell);
		if (r > 1.0 - star_density) {
			float twinkle = 0.6 + 0.4 * sin(TIME * (1.5 + r * 4.0) + r * 60.0);
			float big = step(0.9985, r);
			col += star_tint * star_brightness * twinkle * (0.5 + big * 1.5) * smoothstep(0.02, 0.25, up);
		}
		// Radiant star with rays (festive sky).
		if (flare_strength > 0.0) {
			vec3 fd = normalize(flare_direction);
			float fdist = acos(clamp(dot(dir, fd), -1.0, 1.0));
			vec3 side = normalize(cross(fd, vec3(0.0, 1.0, 0.0)));
			vec3 upv = cross(side, fd);
			vec3 rel = dir - fd * dot(dir, fd);
			float ang = atan(dot(rel, upv), dot(rel, side));
			float rays = pow(abs(cos(ang * flare_rays * 0.5)), 24.0) * exp(-fdist * 6.0);
			rays += pow(abs(cos(ang * 2.0)), 80.0) * exp(-fdist * 2.2) * 0.8;
			float core = exp(-fdist * 160.0) * 6.0 + exp(-fdist * 18.0) * 0.8;
			col += flare_color * flare_strength * (core + rays);
		}
	}

	// Clouds on a virtual plane above the world.
	float cloud = 0.0;
	if (up > -0.02) {
		vec2 cuv = dir.xz / (up + 0.18) * cloud_scale;
		cuv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		float n = fbm(cuv);
		cloud = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.25, n);
		cloud *= smoothstep(-0.02, 0.12, up);
		// Silver lining: clouds near the moon catch its light at their edges.
		float edge = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.08, n) - smoothstep(1.0 - cloud_coverage + 0.08, 1.0 - cloud_coverage + 0.3, n);
		vec3 lit = mix(cloud_color, cloud_lit_color, clamp(halo * 1.4 + edge * halo * 2.5, 0.0, 1.0));
		col = mix(col, lit, cloud * 0.92);
	}

	// Moon disc, dimmed where clouds pass in front of it.
	float disc = smoothstep(moon_size, moon_size * 0.85, moon_dist);
	float maria = noise2(vec2(atan(dir.x, dir.z), dir.y) * 90.0) * 0.18;
	col = mix(col, moon_color * (1.15 - maria), disc * (1.0 - cloud * 0.75));

	COLOR = col;
}
