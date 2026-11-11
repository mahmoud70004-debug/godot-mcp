// Kingdom-forest impostors (ForestBuilder "Far"): tiled cards, unshaded (the shading is
// painted into the atlas; no lantern ever adds a light pass to the whole forest).
// See forest.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled;

#define CUTOUT
#define TILED
#define UNSHADED
#include "res://assets/shaders/forest.gdshaderinc"
