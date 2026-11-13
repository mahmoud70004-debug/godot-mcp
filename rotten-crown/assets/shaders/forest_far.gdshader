// Kingdom-forest impostors (ForestBuilder "Far"): tiled cards, unshaded, lit per pixel by
// the moonlight model from the baked impostor normals (ForestAtlas.normal_texture), so they
// match their trees at the swap. See forest.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled;

#define CUTOUT
#define TILED
#define IMPOSTOR
#include "res://assets/shaders/forest.gdshaderinc"
