// Opaque kingdom-forest geometry: logs, stumps, stones, mounds, rot growths (ForestFloor).
// Unshaded: the moonlight model is evaluated per vertex. See forest.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_back;

#include "res://assets/shaders/forest.gdshaderinc"
