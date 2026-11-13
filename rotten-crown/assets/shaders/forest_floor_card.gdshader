// Forest floor cards (ForestFloor): one MultiMesh of crossed / flat / hanging cards per
// chunk, the atlas tile and mode per instance. Unshaded: the moonlight model is evaluated
// per vertex; upright and hanging cards sway a little. See forest.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled;

#define CUTOUT
#define TILED
#define CARD_SWAY
#include "res://assets/shaders/forest.gdshaderinc"
