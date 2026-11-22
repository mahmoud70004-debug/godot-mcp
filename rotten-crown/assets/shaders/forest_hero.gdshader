// Close-up trunks (ForestTrees.hero): the sculpted redwood mesh with its moss and roots, drawn
// only near the camera over the coarse trunk of the same tree (which stays for the middle distance).
// The mesh dissolves out (dither) while the coarse trunk beneath stays whole. Unshaded: the
// moonlight model is evaluated per pixel. See forest.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_back;

#define TREE
#define BARK_DISSOLVE
#include "res://assets/shaders/forest.gdshaderinc"
