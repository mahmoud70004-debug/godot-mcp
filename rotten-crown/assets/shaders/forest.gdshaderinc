// Kingdom forest (ForestTrees / ForestFloor): one look for trunks, leaves, impostors
// and the forest floor, drawn as MultiMesh instances. Included by forest_card.gdshader
// (trees: alpha-cut, back faces culled; TREE), forest_solid.gdshader (floor kits: opaque),
// forest_floor_card.gdshader (tiled floor cards: alpha-cut, both sides; TILED, CARD_SWAY)
// and forest_far.gdshader (impostors: TILED, IMPOSTOR).
//
// - Lighting (V7): every family is UNSHADED and evaluates the one moonlight model itself
//   (assets/shaders/moonlight.gdshaderinc): the moon key (lambert, wrapped for leaves and
//   cards) x the baked canopy shade x the cloud shadow, plus the hemispheric sky ambient.
//   The key and ambient are evaluated per pixel (the shade per vertex) on meshes and on
//   impostors, which take their normals from a baked normal atlas (ForestAtlas), so a tree
//   and its impostor are lit by the same function. No light pass
//   ever touches the forest; the player's carried lantern (the only lamp that reaches the
//   trees: < 0.1 % of the forest is within a fixed lantern's range) is evaluated here as a
//   small omni light at the camera with Godot's attenuation curve.
//   The canopy shade fades out up the tree (crown_shade metres above the instance origin):
//   trunk feet under a canopy are shaded, crown tops stay moonlit.
// - No fills or rims: the only emission is the green rot glow (v_glow), by design.
// - Wind (moonlight.gdshaderinc wind_offset): a tree sways rigidly by its origin with the
//   height above it (trunk foot 0), leaves flutter a little on top, baked moss strands
//   swing from their limb; the impostor card sways with the same function of its origin and
//   height, so the swap does not jump. Floor cards and hanging cards sway slightly.
// - LOD per INSTANCE: an instance whose origin is nearer than lod_begin or as far as
//   lod_end from the camera collapses to a point (no pixels), so detailed, simple and
//   impostor copies on different chunk grids never overlap or leave gaps.
// - Albedo = vertex colour x instance colour x texture: the shared atlas (ForestAtlas,
//   mipmapped, nearest within a level), or, where UV.x < -0.5 (solid bark, stone, rot),
//   the world-mapped bark scan.
// - The green rot glows: vertex alpha < 1 marks rot (or glowing caps), INSTANCE_CUSTOM.z
//   says how strongly this instance glows; emission = albedo x glow, slow pulse.
// - Kit meshes (ForestFloor): several small meshes in one, UV2.x = kit, the instance
//   keeps the kit INSTANCE_CUSTOM.x names and collapses the rest.
// - TILED cards (floor kit): UV is tile-local, INSTANCE_CUSTOM = (tile corner u, v,
//   glow, mode) with mode 0 upright crossed quads, 1 flat quad, 2 upright hanging down
//   (UV2.x of the card mesh marks its flat quad).
// - Hanging moss baked into the tree meshes (V6): UV2.y > 0 is a strand's rank; the tree
//   instance keeps the strands whose shifted rank fract(rank + INSTANCE_CUSTOM.w) is below
//   its moss amount INSTANCE_CUSTOM.y. Moss therefore draws only with its own tree.
// - Range ends (V7): nothing grows, shrinks or dithers at its range. Every family fades
//   into the fog colour (fog_tint) over fade_out before lod_end, where ViewDistance puts
//   it inside thick fog. fade_in (a dither) is only used if the near/far swap is given a
//   band again (ViewDistance.SWAP_FADE, 0 today: the swap is one frame at one distance).

#include "res://assets/shaders/moonlight.gdshaderinc"

// Trees and their impostors sway alike.
#ifdef TREE
#define TREE_SWAY
#endif
#ifdef IMPOSTOR
#define TREE_SWAY
#endif

uniform sampler2D atlas : source_color, filter_nearest_mipmap;
// Mipmapped (nearest within a level): chunky up close, no shimmering grain far away.
uniform sampler2D bark_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform float lod_begin = 0.0;
uniform float lod_end = 10000.0;
// Widths in metres: an instance dithers in over fade_in after lod_begin and fades into the
// fog colour over the fade_out before lod_end.
uniform float fade_in = 0.0;
uniform float fade_out = 0.0;
// Atlas tile size (UV units) for TILED cards.
uniform vec2 tile_size = vec2(0.25, 0.25);
uniform float bark_scale = 0.9;
uniform float bark_gain = 2.0;
// How much of the bark scan shows (the rest is flat vertex colour). Low: flat-shaded forms.
uniform float bark_detail = 0.35;
uniform float glow_strength = 1.25;
// Rot swelling in metres (vertex shader only).
uniform float pulse = 0.025;
// Glow used when there is no instance data (single MeshInstance3D growths).
uniform float glow_base = 0.0;
// Meshes without vertex colours or UVs (the bark faces): bark grain in this colour.
uniform vec3 tint : source_color = vec3(1.0);
uniform bool force_bark = false;
// The fog colour (ViewDistance keeps it in step with the environment).
uniform vec3 fog_tint : source_color = vec3(0.18, 0.195, 0.245);
// Wrapped lambert ((N.L + wrap) / (1 + wrap)): leaves and cards take light round the side.
uniform float leaf_wrap = 0.5;
uniform float bark_wrap = 0.1;
// The canopy shade fades to full moonlight between these heights (m) above the origin.
uniform vec2 crown_shade = vec2(3.0, 10.0);
// Wind: heights (m) above the origin where the sway starts (the trunk foot stays put) and
// is full; leaf flutter and moss swing on top of it.
uniform vec2 sway_height = vec2(2.0, 12.0);
uniform float leaf_flutter = 0.35;
uniform float moss_sway = 2.5;
uniform float card_sway = 1.5;
// The hanging moss strip in the atlas (v0, v size): a strand's top is anchored.
uniform vec2 hang_uv_y = vec2(0.0, 0.25);
// The carried lantern (player.tscn Head/Lantern): sRGB colour, energy, range, attenuation,
// offset from the camera (view space). Energy 0 switches it off.
uniform vec3 lantern_color = vec3(1.0, 0.72, 0.42);
uniform float lantern_energy = 0.55;
uniform float lantern_range = 5.5;
uniform float lantern_attenuation = 1.6;
uniform vec3 lantern_offset = vec3(-0.25, -0.45, -0.2);
#ifdef IMPOSTOR
// Impostor normals (ForestAtlas.normal_texture): rgb = normal in the bake view (x right,
// y up, z towards the viewer) * 0.5 + 0.5, a = 1 leaf / 0 bark. It covers the atlas'
// impostor band (UV / impostor_band).
uniform sampler2D normal_atlas : filter_linear_mipmap;
uniform vec2 impostor_band = vec2(1.0, 0.8);
// Atlas offsets from a style's +Z view to its +X view (u) and to the far-side views (v).
uniform vec2 impostor_view_offset = vec2(0.4375, 0.4);
#endif

varying vec3 v_world;
varying vec3 v_wnormal;
varying float v_glow;
varying vec2 v_uv;
varying float v_fade_in;
varying float v_fade_out;
#ifdef IMPOSTOR
varying vec3 v_right;
varying vec3 v_toward;
varying float v_canopy;
varying float v_cloud;
varying float v_height;
#else
varying float v_shade;
varying vec3 v_lantern;
#endif

// How much moonlight reaches a point: the canopy shade fading out up the crown x cloud.
float forest_shade(float canopy, float cloud, float height) {
	return mix(canopy, 1.0, smoothstep(crown_shade.x, crown_shade.y, height)) * cloud;
}

// Moonlight on a surface (linear): moon key (wrapped lambert) x shade + sky ambient. Mesh and
// impostor both evaluate it per pixel (the leaf cards' normals splay across each card, so
// lighting per vertex would not be what the impostor can reproduce).
vec3 forest_moon(vec3 n, float shade, float wrap) {
	float ndl = max((dot(n, moon_dir) + wrap) / (1.0 + wrap), 0.0);
	return moon_color.rgb * ndl * shade + moon_ambient(n);
}

// The carried lantern on a point (linear), Godot's omni attenuation.
vec3 forest_lantern(vec3 pos, vec3 n, float wrap, mat4 inv_view) {
	vec3 to = (inv_view * vec4(lantern_offset, 1.0)).xyz - pos;
	float d = length(to);
	float nd = d / lantern_range;
	nd *= nd;
	nd *= nd;
	nd = max(1.0 - nd, 0.0);
	float att = nd * nd * pow(max(d, 0.0001), -lantern_attenuation);
	float ndl = max((dot(n, to / max(d, 0.0001)) + wrap) / (1.0 + wrap), 0.0);
	return moon_to_linear(lantern_color) * lantern_energy * att * ndl;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float d = distance(origin, cam);
	v_uv = UV;
	// Sway weight (0 root .. 1 tip) of this vertex for the floor cards.
	float card_h = 0.0;
	bool leaf = UV.x > -0.5 && !force_bark;
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
	card_h = mode < 0.5 ? VERTEX.y : 0.0;
	if (mode > 1.5) {
		VERTEX.y -= 1.0;
		card_h = -VERTEX.y;
	}
#else
	v_glow = (1.0 - COLOR.a) * max(INSTANCE_CUSTOM.z, glow_base);
	// Kit meshes (ForestFloor): UV2.x is the kit of the vertex, INSTANCE_CUSTOM.x the
	// instance's kit (both 0 on trees).
	if (abs(UV2.x - INSTANCE_CUSTOM.x) > 0.5) {
		d = -1.0;
	}
	// Baked moss strand: kept by the instance's moss amount (y), ranks shifted by w.
	if (UV2.y > 0.0 && fract(UV2.y + INSTANCE_CUSTOM.w) >= INSTANCE_CUSTOM.y) {
		d = -1.0;
	}
#endif
	v_fade_in = fade_in > 0.0 ? clamp((d - lod_begin) / fade_in, 0.0, 1.0) : 1.0;
	v_fade_out = fade_out > 0.0 ? clamp((d - (lod_end - fade_out)) / fade_out, 0.0, 1.0) : 0.0;
	bool drawn = d >= lod_begin && d < lod_end;
	if (!drawn) {
		VERTEX = vec3(0.0);
	} else if (v_glow > 0.01) {
		VERTEX += NORMAL * v_glow * pulse * sin(TIME * 1.3 + origin.x * 0.7 + origin.z * 0.9 + VERTEX.y * 2.5);
	}
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float height = world.y - origin.y;
	// Wind, in world metres, brought back into the instance's space.
	vec3 sway = vec3(0.0);
#ifdef TREE_SWAY
	float h01 = clamp((height - sway_height.x) / (sway_height.y - sway_height.x), 0.0, 1.25);
	sway = wind_offset(origin, h01);
#endif
#ifdef TREE
	if (UV2.y > 0.0) {
		// Moss strand: swings from its anchored top.
		float s = clamp((UV.y - hang_uv_y.x) / hang_uv_y.y, 0.0, 1.0);
		sway += wind_offset(origin + vec3(UV2.y * 9.0, 0.0, 0.0), 1.0) * moss_sway * s;
	} else if (leaf) {
		sway += wind_offset(world, h01) * leaf_flutter;
	}
#endif
#ifdef CARD_SWAY
	sway = wind_offset(origin, clamp(card_h, 0.0, 1.0)) * card_sway;
#endif
	if (drawn) {
		VERTEX += inverse(mat3(MODEL_MATRIX)) * sway;
		world += sway;
	}
	v_world = world;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
#ifdef IMPOSTOR
	// Each card quad shows the tree as baked from the side the camera is on (ForestAtlas: the
	// quad in the XY plane its +Z / -Z views, the one in the ZY plane its +X / -X views):
	// the normal atlas' x runs along the quad's u axis, z towards the viewer. Rebuild those
	// axes in world space for this camera.
	bool quad_x = abs(VERTEX.x) > 0.01;
	vec3 axis = quad_x ? MODEL_MATRIX[0].xyz : MODEL_MATRIX[2].xyz;
	vec3 facing = quad_x ? MODEL_MATRIX[2].xyz : MODEL_MATRIX[0].xyz;
	if (!quad_x) {
		v_uv.x += impostor_view_offset.x;
	}
	if (dot(cam - origin, facing) < 0.0) {
		v_uv.y += impostor_view_offset.y;
	}
	vec3 toward = cam - origin;
	toward.y = 0.0;
	toward = normalize(toward + vec3(0.0001, 0.0, 0.0));
	vec3 across = vec3(-toward.z, 0.0, toward.x);
	v_right = dot(axis, across) < 0.0 ? -across : across;
	v_toward = toward;
	v_canopy = moon_canopy(origin);
	v_cloud = moon_cloud(origin);
	v_height = height;
#else
	v_shade = forest_shade(moon_canopy(world), moon_cloud(world), height);
	v_lantern = lantern_energy > 0.0 ? forest_lantern(world, v_wnormal, leaf ? leaf_wrap : bark_wrap, INV_VIEW_MATRIX) : vec3(0.0);
#endif
}

float dissolve_threshold(vec2 frag) {
	ivec2 c = ivec2(mod(floor(frag), 4.0));
	int i = c.y * 4 + c.x;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	if (v_fade_in < 1.0) {
		if (dissolve_threshold(FRAGCOORD.xy) >= v_fade_in) {
			discard;
		}
	}
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
#ifdef IMPOSTOR
	vec4 nt = texture(normal_atlas, v_uv / impostor_band);
	vec3 nb = nt.rgb * 2.0 - 1.0;
	vec3 n = normalize(v_right * nb.x + vec3(0.0, nb.y, 0.0) + v_toward * nb.z);
	vec3 light = forest_moon(n, forest_shade(v_canopy, v_cloud, v_height), mix(bark_wrap, leaf_wrap, nt.a));
#else
	bool bark = v_uv.x < -0.5 || force_bark;
	vec3 light = forest_moon(normalize(v_wnormal), v_shade, bark ? bark_wrap : leaf_wrap) + v_lantern;
#endif
	float beat = 0.8 + 0.2 * sin(TIME * 1.3 + v_world.x * 0.7 + v_world.z * 0.9);
	vec3 lit = moon_to_display(moon_to_linear(albedo) * (light + vec3(v_glow * glow_strength * beat)));
	ALBEDO = mix(lit, fog_tint, v_fade_out);
#ifdef CUTOUT
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
}
