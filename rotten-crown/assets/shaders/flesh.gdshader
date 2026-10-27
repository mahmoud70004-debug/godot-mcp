// Diseased skin for the transformed citizens of Valdron.
// - PS1-style vertex snapping (affine jitter) for the retro wobble.
// - Slow "breathing" displacement so bodies never sit still.
// - Pixelated procedural blotches, rot and pulsing green veins.
// - Per-instance hit flash.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform vec4 skin_color : source_color = vec4(0.58, 0.55, 0.48, 1.0);
uniform vec4 rot_color : source_color = vec4(0.22, 0.3, 0.12, 1.0);
uniform vec4 vein_color : source_color = vec4(0.3, 0.55, 0.08, 1.0);
uniform vec4 bruise_color : source_color = vec4(0.25, 0.12, 0.14, 1.0);
uniform float pulse_speed = 1.3;
uniform float wobble_amount = 0.018;
uniform float pixel_density = 22.0;
uniform float snap_resolution = 140.0;
uniform float vein_glow = 0.6;

instance uniform float hit_flash = 0.0;
instance uniform float time_offset = 0.0;

varying vec3 object_pos;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i + vec3(0.0, 0.0, 0.0)), hash3(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

void vertex() {
	object_pos = VERTEX;
	float t = TIME * pulse_speed + time_offset;
	float n = noise3(VERTEX * 6.0 + vec3(0.0, t, 0.0));
	VERTEX += NORMAL * (n - 0.5) * wobble_amount * (1.0 + sin(t * 2.0) * 0.5);

	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip.xy = floor(clip.xy / clip.w * snap_resolution) / snap_resolution * clip.w;
	POSITION = clip;
}

void fragment() {
	vec3 q = floor(object_pos * pixel_density) / pixel_density;
	float t = TIME * pulse_speed + time_offset;
	float blotch = noise3(q * 3.0);
	float bruise = noise3(q * 5.0 + vec3(7.1));
	float vein = 1.0 - smoothstep(0.0, 0.07, abs(noise3(q * 4.0 + vec3(3.3)) - 0.5));

	vec3 col = skin_color.rgb;
	col = mix(col, bruise_color.rgb, smoothstep(0.62, 0.8, bruise) * 0.7);
	col = mix(col, rot_color.rgb, smoothstep(0.55, 0.78, blotch));
	float pulse = 0.55 + 0.45 * sin(t * 3.0 + blotch * 6.2831);
	col = mix(col, vein_color.rgb, vein * pulse * 0.8);
	col = mix(col, vec3(0.85, 0.08, 0.04), clamp(hit_flash, 0.0, 1.0));

	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.35;
	EMISSION = vein_color.rgb * vein * pulse * vein_glow * 0.25;
}
