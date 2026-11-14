// Kingdom-forest trees (ForestTrees): bark and leaf cards in one alpha-cut surface,
// back faces culled (the trunks are closed tubes, the leaf cards carry both sides).
// Unshaded: the moonlight model is evaluated per pixel (the canopy shade per vertex). See
// forest.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_back;

#define CUTOUT
#define TREE
#include "res://assets/shaders/forest.gdshaderinc"
