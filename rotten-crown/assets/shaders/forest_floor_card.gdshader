// Forest floor cards (ForestFloor): one MultiMesh of crossed / flat / hanging cards per
// chunk, the atlas tile and mode per instance. See forest.gdshaderinc.
shader_type spatial;
render_mode cull_disabled, vertex_lighting, diffuse_lambert, specular_disabled;

#define CUTOUT
#define TILED
#include "res://assets/shaders/forest.gdshaderinc"
