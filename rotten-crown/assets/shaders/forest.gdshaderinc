// Kingdom forest (ForestTrees / ForestFloor): one look for trunks, leaves, impostors
// and the forest floor, drawn as MultiMesh instances. Included by forest_card.gdshader
// (trees: alpha-cut, back faces culled; TREE), forest_solid.gdshader (floor kits: opaque),
// forest_floor_card.gdshader (tiled floor cards: alpha-cut, both sides; TILED, CARD_SWAY)
// and forest_far.gdshader (impostors: TILED, IMPOSTOR).
//
// - Lighting (V7): every family is UNSHADED and evaluates the one moonlight model itself
//   (assets/shaders/moonlight.gdshaderinc): the moon key (lambert, wrapped for leaves and
//   cards) x the baked canopy shade x the cloud shadow, plus the hemispheric sky ambient.
//   The key and ambient are evaluated per pixel (the shade per vertex) on trees and on
//   impostors (the floor cards and kits per vertex, VERTEX_LIT), which take their normals from a baked normal atlas (ForestAtlas) laid on the
//   card's own bake axes (turned half way to the camera, IMPOSTOR_VIEW_TURN), so a tree and its
//   impostor are lit by the same function and the lit side mostly stays put in the world. The light is applied with moon_lit() (one pow per pixel).
//   No light pass ever touches the forest; the player's carried lantern (the only lamp that
//   reaches the trees: < 0.1 % of the forest is within a fixed lantern's range) is evaluated
//   per vertex from the lantern globals (pushed by its FlickerLight, flicker included; off
//   when none) with Godot's omni attenuation curve.
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
// The floor (cards, kits) is lit per vertex like V6 (small, many, never compared with an
// impostor); trees and impostors per pixel.
#ifndef TREE
#ifndef IMPOSTOR
#define VERTEX_LIT
#endif
#endif

// Display-space gain on every forest albedo (mesh and impostor alike; V7-8 calibration, 1.7 -> 2.0
// in V7-R with the one sky ambient: the forest lost its own brighter ambient).
uniform float albedo_gain = 2.0;
uniform sampler2D atlas : source_color, filter_nearest_mipmap;
// Mipmapped (nearest within a level): chunky up close, no shimmering grain far away.
uniform sampler2D bark_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform float lod_begin = 0.0;
uniform float lod_end = 10000.0;
// Widths in metres: an instance dithers in over fade_in after lod_begin and fades into the
// fog colour over the fade_out before lod_end.
uniform float fade_in = 0.0;
uniform float fade_out = 0.0;
// V10: near trees dissolve OUT over fade_out (complementary to the impostor's dissolve in over the
// same band, same screen pattern: every pixel is drawn by exactly one of the two) instead of
// fading into the fog colour, so the mesh/impostor swap is a soft cross-dissolve, not a pop.
uniform bool dissolve_out = false;
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
#ifdef IMPOSTOR
// Share (0..1) of the way the impostor's normal frame turns from the card's bake side towards
// the camera (see vertex()).
const float IMPOSTOR_VIEW_TURN = 0.5;
// Impostor normals (ForestAtlas.normal_texture): rgb = normal in the bake view (x right,
// y up, z towards the viewer) * 0.5 + 0.5, a = 1 leaf / 0 bark. It covers the atlas'
// impostor band (UV / impostor_band). Nearest within a mip level like the colour atlas (V7-R:
// trilinear filtering of this fetch was the single largest per-pixel cost on software GL).
uniform sampler2D normal_atlas : filter_nearest_mipmap;
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
// Mip level of the colour atlas (x) and the normal atlas (y) for this card at this distance:
// one per vertex instead of screen derivatives per pixel (the card faces the camera).
varying vec2 v_lod;
varying float v_canopy;
varying float v_cloud;
varying float v_height;
#else
varying float v_shade;
varying vec3 v_lantern;
#ifdef VERTEX_LIT
// moon_lit()'s light factor (display space), per vertex.
varying vec3 v_lit;
#endif
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

// The carried lantern on a point (linear), Godot's omni attenuation (lantern_light.a > 0).
vec3 forest_lantern(vec3 pos, vec3 n, float wrap) {
	vec3 to = lantern_pos.xyz - pos;
	float d = length(to);
	float nd = d / lantern_light.a;
	nd *= nd;
	nd *= nd;
	nd = max(1.0 - nd, 0.0);
	float att = nd * nd * pow(max(d, 0.0001), -lantern_pos.w);
	float ndl = max((dot(n, to / max(d, 0.0001)) + wrap) / (1.0 + wrap), 0.0);
	return lantern_light.rgb * att * ndl;
}

// inverse(mat3(m)) * v for a rotation x scale basis (orthogonal columns, no shear): each
// column's share of v over its squared length.
vec3 forest_unbasis(mat4 m, vec3 v) {
	vec3 c0 = m[0].xyz;
	vec3 c1 = m[1].xyz;
	vec3 c2 = m[2].xyz;
	return vec3(dot(c0, v) / max(dot(c0, c0), 1e-8), dot(c1, v) / max(dot(c1, c1), 1e-8), dot(c2, v) / max(dot(c2, c2), 1e-8));
}

void vertex() {
#ifdef IMPOSTOR
	// Which card quad this vertex belongs to, read before the wind moves it (the ZY quad sits at
	// x = 0 exactly; sway would push its top vertices past any small threshold).
	bool quad_x = abs(VERTEX.x) > 0.01;
#endif
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
	v_world = vec3(0.0);
	v_wnormal = vec3(0.0, 1.0, 0.0);
#ifdef IMPOSTOR
	v_right = vec3(1.0, 0.0, 0.0);
	v_toward = vec3(0.0, 0.0, 1.0);
	v_lod = vec2(0.0);
	v_canopy = 1.0;
	v_cloud = 1.0;
	v_height = 0.0;
#else
	v_shade = 1.0;
	v_lantern = vec3(0.0);
#ifdef VERTEX_LIT
	v_lit = vec3(0.0);
#endif
#endif
	if (!drawn) {
		// Collapsed to a point: no pixels, so none of the work below.
		VERTEX = vec3(0.0);
	} else {
		if (v_glow > 0.01) {
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
		VERTEX += forest_unbasis(MODEL_MATRIX, sway);
		world += sway;
		v_world = world;
		v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
#ifdef IMPOSTOR
		// Each card quad shows the tree as baked from the side the camera is on (ForestAtlas: the
		// quad in the XY plane its +Z / -Z views, the one in the ZY plane its +X / -X views):
		// the normal atlas' x runs along the quad's u axis, z towards the side shown. The frame is
		// built from the card's own axes (fixed in the world for that side), not the camera's.
		vec3 axis = normalize(quad_x ? MODEL_MATRIX[0].xyz : MODEL_MATRIX[2].xyz);
		vec3 facing = normalize(quad_x ? MODEL_MATRIX[2].xyz : MODEL_MATRIX[0].xyz);
		if (!quad_x) {
			v_uv.x += impostor_view_offset.x;
		}
		if (dot(cam - origin, facing) < 0.0) {
			v_uv.y += impostor_view_offset.y;
			facing = -facing;
		}
		// Seen from a diagonal the tree's visible surfaces face the camera more than the bake
		// side does: the frame turns half way towards the camera (the lit side follows the view
		// at half rate, the other half stays fixed in the world; a full turn would light the
		// card like a billboard, none matches the mesh worst on diagonals).
		vec3 to_cam = cam - origin;
		to_cam.y = 0.0;
		to_cam = normalize(to_cam + vec3(0.0001, 0.0, 0.0));
		// (to_cam is on the shown side, facing was flipped to it: the mix never cancels.)
		v_toward = normalize(mix(facing, to_cam, IMPOSTOR_VIEW_TURN));
		v_right = normalize(axis - v_toward * dot(axis, v_toward));
		// Atlas texels per screen pixel: texels per metre on the card x metres per pixel at d.
		vec2 tex = vec2(textureSize(atlas, 0));
		float m_per_px = 2.0 * d / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
		float width = length(quad_x ? MODEL_MATRIX[0].xyz : MODEL_MATRIX[2].xyz);
		float tpm = max(tile_size.y * tex.y / length(MODEL_MATRIX[1].xyz), tile_size.x * tex.x / width);
		float lod = max(log2(max(tpm * m_per_px, 1.0)), 0.0);
		vec2 ntex = vec2(textureSize(normal_atlas, 0));
		v_lod = vec2(lod, max(lod + log2(ntex.y / (tex.y * impostor_band.y)), 0.0));
		v_canopy = moon_canopy(origin);
		v_cloud = moon_cloud(origin);
		v_height = height;
#else
		v_shade = forest_shade(moon_canopy(world), moon_cloud(world), height);
		if (lantern_light.a > 0.0) {
			v_lantern = forest_lantern(world, v_wnormal, leaf ? leaf_wrap : bark_wrap);
		}
#ifdef VERTEX_LIT
		vec3 vl = forest_moon(v_wnormal, v_shade, leaf ? leaf_wrap : bark_wrap) + v_lantern;
		if (v_glow > 0.0) {
			vl += vec3(v_glow * glow_strength * (0.8 + 0.2 * sin(TIME * 1.3 + world.x * 0.7 + world.z * 0.9)));
		}
		v_lit = pow(max(vl, vec3(0.0)), vec3(1.0 / 2.2));
#endif
#endif
	}
}

// Interleaved gradient noise (V10): an even, structure-free screen pattern; the old 4x4 Bayer
// grid read as a chessboard ghost on phones.
float dissolve_threshold(vec2 frag) {
	return fract(52.9829189 * fract(dot(floor(frag), vec2(0.06711056, 0.00583715))));
}

void fragment() {
	if (v_fade_in < 1.0 || (dissolve_out && v_fade_out > 0.0)) {
		float thr = dissolve_threshold(FRAGCOORD.xy);
		if (thr >= v_fade_in || (dissolve_out && thr < v_fade_out)) {
			discard;
		}
	}
	float fog_mix = dissolve_out ? 0.0 : v_fade_out;
	vec4 t;
	bool bark = v_uv.x < -0.5 || force_bark;
	if (bark) {
		vec2 buv = abs(v_wnormal.y) > 0.75 ? v_world.xz : vec2(v_world.x + v_world.z, v_world.y);
		// Grain only (grey): the colour (bark, moss, rot) is the vertex colour's.
		float grain = dot(texture(bark_tex, buv * bark_scale).rgb, vec3(0.3, 0.59, 0.11)) * bark_gain;
		t = vec4(vec3(mix(0.7, grain, bark_detail)), 1.0);
	} else {
#ifdef IMPOSTOR
		t = textureLod(atlas, v_uv, v_lod.x);
#else
		t = texture(atlas, v_uv);
#endif
	}
#ifdef CUTOUT
	// Cut before any lighting (the alpha-cut pixels are most of a leaf card).
	if (t.a < 0.5) {
		discard;
	}
#endif
	// V7-8: the painted bark/leaf colours were chosen under the old fill light and read
	// near-black under the plain moon model; one gain (display space) lifts mesh and impostor
	// alike, so their match holds.
	vec3 albedo = min(t.rgb * COLOR.rgb * tint * albedo_gain, vec3(1.0));
#ifdef VERTEX_LIT
	ALBEDO = mix(albedo * v_lit, fog_tint, fog_mix);
#else
#ifdef IMPOSTOR
	vec4 nt = textureLod(normal_atlas, v_uv / impostor_band, v_lod.y);
	vec3 nb = nt.rgb * 2.0 - 1.0;
	vec3 n = normalize(v_right * nb.x + vec3(0.0, nb.y, 0.0) + v_toward * nb.z);
	vec3 light = forest_moon(n, forest_shade(v_canopy, v_cloud, v_height), mix(bark_wrap, leaf_wrap, nt.a));
#else
	vec3 light = forest_moon(normalize(v_wnormal), v_shade, bark ? bark_wrap : leaf_wrap) + v_lantern;
#endif
	if (v_glow > 0.0) {
		float beat = 0.8 + 0.2 * sin(TIME * 1.3 + v_world.x * 0.7 + v_world.z * 0.9);
		light += vec3(v_glow * glow_strength * beat);
	}
	ALBEDO = mix(moon_lit(albedo, light), fog_tint, fog_mix);
#endif
}
