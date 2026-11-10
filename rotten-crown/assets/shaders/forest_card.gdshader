// Kingdom-forest trees (ForestTrees): bark and leaf cards in one alpha-cut surface,
// back faces culled (the trunks are closed tubes, the leaf cards carry both sides).
// See forest.gdshaderinc.
shader_type spatial;
render_mode cull_back, vertex_lighting, diffuse_lambert, specular_disabled;

#define CUTOUT
#include "res://assets/shaders/forest.gdshaderinc"
