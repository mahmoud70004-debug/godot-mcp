// Long silver-green meadow grass of the Moonlit Meadows and the plains between
// the villages (task U10). Same chunked quad approach as the Thornfield wheat
// (MeadowProps.grass_chunks merges the tufts into one ArrayMesh per 12 m cell,
// identity basis, so vertex offsets are world offsets), with its own look:
// thin long blades combed by the wind, moonlit silver sheen rolling across the
// field in gust waves, dark rush clumps and sparse pale flowering weeds.
// Unshaded on purpose (the web renderer re-draws lit meshes once per light).
// Vertex COLOR: r = tuft seed, g = tuft height in metres / 2, b = brightness,
// a = kind (1 = long grass, ~0.66 = flowering weeds, ~0.33 = dark rushes).
shader_type spatial;
render_mode cull_disabled, unshaded;

uniform vec4 root_color : source_color = vec4(0.025, 0.032, 0.027, 1.0);
uniform vec4 stem_color : source_color = vec4(0.09, 0.125, 0.085, 1.0);
uniform vec4 tip_color : source_color = vec4(0.23, 0.28, 0.21, 1.0);
uniform vec4 dry_color : source_color = vec4(0.33, 0.31, 0.21, 1.0);
uniform vec4 rush_color : source_color = vec4(0.05, 0.075, 0.05, 1.0);
uniform vec4 sheen_color : source_color = vec4(0.62, 0.68, 0.62, 1.0);
// Multiplier in cloud shadow: shadows lean cold (art direction).
uniform vec4 shade_tint : source_color = vec4(0.42, 0.46, 0.55, 1.0);
uniform vec4 flower_a : source_color = vec4(0.62, 0.6, 0.52, 1.0);
uniform vec4 flower_b : source_color = vec4(0.62, 0.55, 0.3, 1.0);
uniform vec4 flower_c : source_color = vec4(0.36, 0.29, 0.42, 1.0);
uniform vec2 wind_dir = vec2(0.35, 0.94);
// Static bend along the wind, as a fraction of the tuft height.
uniform float lean = 0.22;
uniform float gust_strength = 0.34;
uniform float gust_speed = 0.9;
// Gust waves per metre across the field.
uniform float gust_scale = 0.05;
uniform float flutter = 0.05;
uniform float blades = 13.0;
uniform float pixel_size = 30.0;
uniform float cloud_scale = 0.06;
uniform float cloud_speed = 0.4;
uniform float cloud_shadow = 0.4;
uniform float sheen = 0.32;
// Tufts fade into the ground (shrink) towards the end of their visibility range.
uniform float fade_start = 44.0;
uniform float fade_end = 58.0;

varying float v_light;
varying float v_gust;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = 1.0 - UV.y;
	float tuft_h = COLOR.g * 2.0;
	float rush = step(COLOR.a, 0.45);
	vec2 wd = normalize(wind_dir);
	float phase = dot(wp.xz, wd) * gust_scale * 6.2832 - TIME * gust_speed;
	float gust = sin(phase) * 0.5 + 0.5;
	gust *= gust;
	float fl = sin(TIME * 3.1 + COLOR.r * 40.0 + wp.x * 1.1) * flutter;
	float bend = (lean + gust * gust_strength + fl) * h * h * (1.0 - rush * 0.6);
	VERTEX.xz += wd * bend * tuft_h;
	VERTEX.y -= bend * bend * tuft_h * 0.4;
	// Sink far tufts into the ground before their chunk is culled (no pop).
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX.y -= smoothstep(fade_start, fade_end, dist) * h * tuft_h;
	// Drifting cloud shadows: two crossed sine fields, cheap and per vertex.
	float t = TIME * cloud_speed * 0.05;
	float c = sin(wp.x * cloud_scale + t) * sin(wp.z * cloud_scale * 1.3 - t * 0.7);
	c += 0.5 * sin((wp.x + wp.z) * cloud_scale * 2.3 + 1.7 + t * 1.3);
	v_light = mix(1.0 - cloud_shadow, 1.0, smoothstep(-0.45, 0.35, c));
	v_gust = gust;
}

void fragment() {
	vec2 px = vec2(pixel_size, pixel_size * 1.4);
	vec2 uv = floor(UV * px) / px;
	float y = 1.0 - uv.y;
	float kind = COLOR.a;
	float rush = step(kind, 0.45);
	float weed = step(0.45, kind) * step(kind, 0.8);
	// Blades curve sideways with height (per tuft), then split into columns.
	float x = uv.x * blades + (COLOR.r - 0.5) * 3.5 * y * y;
	float col = floor(x);
	float s = hash(col * 1.37 + COLOR.r * 97.0);
	float s2 = hash(col * 2.11 + COLOR.r * 31.0 + 5.0);
	float bh = 0.35 + 0.65 * s;
	float t = y / bh;
	// Weeds: a few tall stalks with a small round head; the rest short grass.
	float stalk = weed * step(0.72, s2);
	float head = stalk * step(0.86, t);
	float width = mix(0.5, 0.12, t) + rush * 0.2 + head * 0.45;
	if (t > 1.0 || abs(fract(x) - 0.5) * 2.0 > width) {
		discard;
	}
	if (weed > 0.5 && stalk < 0.5 && t > 0.55) {
		discard;
	}
	vec3 tip = mix(tip_color.rgb, dry_color.rgb, step(0.82, s2) * (1.0 - rush));
	vec3 c = mix(root_color.rgb, stem_color.rgb, smoothstep(0.0, 0.4, t));
	c = mix(c, tip, smoothstep(0.35, 1.0, t));
	c = mix(c, rush_color.rgb * (0.8 + 0.5 * t), rush);
	float pick = hash(COLOR.r * 53.0 + col);
	vec3 flower = pick < 0.5 ? flower_a.rgb : (pick < 0.8 ? flower_b.rgb : flower_c.rgb);
	c = mix(c, flower, head);
	c *= (0.88 + 0.2 * s2) * (0.6 + 0.6 * COLOR.b);
	// Deep inside the tuft is dark, whatever the blade.
	c *= mix(0.45, 1.0, smoothstep(0.0, 0.5, y));
	c *= mix(shade_tint.rgb, vec3(1.0), v_light);
	c += sheen_color.rgb * sheen * v_gust * t * t * v_light * (1.0 - rush) * (1.0 - head) * 0.5;
	ALBEDO = c;
}
