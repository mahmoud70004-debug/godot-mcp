// Kingdom forest (ForestTrees / ForestFloor): one look for trunks, leaves, impostors
// and the forest floor, drawn as MultiMesh instances. Included by forest_solid.gdshader
// (floor kits: opaque), forest_card.gdshader (trees: alpha-cut, back faces culled) and
// forest_floor_card.gdshader (tiled floor cards: alpha-cut, both sides) and
// forest_far.gdshader (impostors: the same, unshaded).
//
// - Per-vertex lit (the cheap path on phones), no shadows.
// - LOD per INSTANCE: an instance whose origin is nearer than lod_begin or as far as
//   lod_end from the camera collapses to a point (no pixels), so detailed, simple and
//   impostor copies on different chunk grids never overlap or leave gaps.
// - Albedo = vertex colour x instance colour x texture: the shared 256 px atlas
//   (ForestAtlas), or, where UV.x < -0.5 (solid bark, stone, rot), the world-mapped
//   bark scan.
// - Moonlight catches the forms: a cold rim on silhouette edges and a soft top light
//   (emission, no extra pass), so trunks never read as flat black cut-outs.
// - The green rot glows: vertex alpha < 1 marks rot (or glowing caps), INSTANCE_CUSTOM.z
//   says how strongly this instance glows; emission = albedo x glow, slow pulse.
// - Kit meshes (ForestFloor): several small meshes in one, UV2.x = kit, the instance
//   keeps the kit INSTANCE_CUSTOM.x names and collapses the rest.
// - TILED cards (floor kit): UV is tile-local, INSTANCE_CUSTOM = (tile corner u, v,
//   glow, mode) with mode 0 upright crossed quads, 1 flat quad, 2 upright hanging down
//   (UV2.x of the card mesh marks its flat quad).

uniform sampler2D atlas : source_color, filter_nearest;
uniform sampler2D bark_tex : source_color, filter_nearest, repeat_enable;
uniform float lod_begin = 0.0;
uniform float lod_end = 10000.0;
// Atlas tile size (UV units) for TILED cards.
uniform vec2 tile_size = vec2(0.25, 0.25);
uniform float bark_scale = 0.9;
uniform float bark_gain = 2.0;
// How much of the bark scan shows (the rest is flat vertex colour).
uniform float bark_detail = 0.6;
uniform vec3 rim_color : source_color = vec3(0.42, 0.52, 0.8);
uniform float rim_strength = 0.9;
uniform vec3 top_color : source_color = vec3(0.12, 0.15, 0.24);
// Night fill on the side the moon does not reach (x albedo), so shapes never go black.
uniform vec3 fill = vec3(0.2, 0.24, 0.39);
uniform float glow_strength = 1.6;
// Rot swelling in metres (vertex shader only).
uniform float pulse = 0.025;
// Glow used when there is no instance data (single MeshInstance3D growths).
uniform float glow_base = 0.0;
// Meshes without vertex colours or UVs (the bark faces): bark grain in this colour.
uniform vec3 tint : source_color = vec3(1.0);
uniform bool force_bark = false;
// Unshaded impostors: the moonlight they would get, as a colour.
uniform vec3 far_light = vec3(0.5, 0.58, 0.86);

varying vec3 v_world;
varying vec3 v_wnormal;
varying float v_glow;
varying vec2 v_uv;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float d = distance(origin, cam);
	v_uv = UV;
#ifdef TILED
	vec4 c = INSTANCE_CUSTOM;
	// w: mode (+10 for a half-width tile: the hanging moss strip).
	float mode = mod(c.w, 10.0);
	v_uv = c.xy + UV * (c.w > 9.5 ? tile_size * vec2(0.5, 1.0) : tile_size);
	v_glow = c.z;
	bool flat_quad = UV2.x > 0.5;
	bool keep = mode > 0.5 && mode < 1.5 ? flat_quad : !flat_quad;
	if (!keep) {
		d = -1.0;
	}
	if (mode > 1.5) {
		VERTEX.y -= 1.0;
	}
#else
	v_glow = (1.0 - COLOR.a) * max(INSTANCE_CUSTOM.z, glow_base);
	// Kit meshes (ForestFloor): UV2.x is the kit of the vertex, INSTANCE_CUSTOM.x the
	// instance's kit (both 0 on trees).
	if (abs(UV2.x - INSTANCE_CUSTOM.x) > 0.5) {
		d = -1.0;
	}
#endif
	if (d < lod_begin || d >= lod_end) {
		VERTEX = vec3(0.0);
	} else if (v_glow > 0.01) {
		VERTEX += NORMAL * v_glow * pulse * sin(TIME * 1.3 + origin.x * 0.7 + origin.z * 0.9 + VERTEX.y * 2.5);
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 t;
	if (v_uv.x < -0.5 || force_bark) {
		vec2 buv = abs(v_wnormal.y) > 0.75 ? v_world.xz : vec2(v_world.x + v_world.z, v_world.y);
		// Grain only (grey): the colour (bark, moss, rot) is the vertex colour's.
		float grain = dot(texture(bark_tex, buv * bark_scale).rgb, vec3(0.3, 0.59, 0.11)) * bark_gain;
		t = vec4(vec3(mix(0.7, grain, bark_detail)), 1.0);
	} else {
		t = texture(atlas, v_uv);
	}
	vec3 albedo = t.rgb * COLOR.rgb * tint;
#ifdef UNSHADED
	ALBEDO = albedo * far_light;
#else
	ALBEDO = albedo;
#endif
#ifdef CUTOUT
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
	ROUGHNESS = 1.0;
	// Moonlight on the forms: a cold rim on silhouette edges (strongest on upward faces)
	// and a soft light from above; both follow the surface colour a little, so pale
	// bark catches more than black bark.
#ifndef UNSHADED
	float edge = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float up = clamp(v_wnormal.y, 0.0, 1.0);
	vec3 moon = rim_color * rim_strength * edge * edge * (0.4 + 0.6 * up) * (0.25 + albedo * 1.5)
		+ top_color * up * up * (0.15 + albedo);
	float beat = 0.8 + 0.2 * sin(TIME * 1.3 + v_world.x * 0.7 + v_world.z * 0.9);
	EMISSION = moon + albedo * (fill + vec3(v_glow * glow_strength * beat));
#endif
}
