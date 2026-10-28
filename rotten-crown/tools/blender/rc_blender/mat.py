"""Procedural Cycles materials for sprite renders (worn steel, cloth, leather...).

Detail that survives a 150 px sprite: value variation (grime in crevices via AO,
scratched bright edges via Pointiness... Cycles only), roughness noise, dents as bump.
"""
import bpy

_cache = {}


def _principled(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    return mat, nt, bsdf


def _noise(nt, scale, detail=6.0, roughness=0.6):
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    n.inputs["Roughness"].default_value = roughness
    return n


def _ramp(nt, src, a, b, lo=0.35, hi=0.65):
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.elements[0].position = lo
    r.color_ramp.elements[0].color = a
    r.color_ramp.elements[1].position = hi
    r.color_ramp.elements[1].color = b
    nt.links.new(src, r.inputs["Fac"])
    return r


def steel(name="steel", base=(0.2, 0.21, 0.22), rough=(0.28, 0.55), grime=0.55, edge=0.35):
    """Dark worn plate: grime darkens cavities (AO), bright scratched edges (pointiness),
    blotchy roughness and fine dents."""
    if name in _cache:
        return _cache[name]
    mat, nt, bsdf = _principled(name)
    bsdf.inputs["Metallic"].default_value = 1.0
    noise = _noise(nt, 18.0)
    rough_ramp = _ramp(nt, noise.outputs["Fac"], (rough[0],) * 3 + (1,), (rough[1],) * 3 + (1,))
    nt.links.new(rough_ramp.outputs["Color"], bsdf.inputs["Roughness"])
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.05
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    edge_ramp = _ramp(nt, geo.outputs["Pointiness"], (0, 0, 0, 1), (1, 1, 1, 1), 0.52, 0.6)
    blotch = _noise(nt, 6.0, 4.0, 0.5)
    base_ramp = _ramp(nt, blotch.outputs["Fac"], tuple(c * 0.7 for c in base) + (1,), tuple(base) + (1,), 0.4, 0.6)
    dark = nt.nodes.new("ShaderNodeMix")
    dark.data_type = "RGBA"
    dark.blend_type = "MULTIPLY"
    dark.inputs["Factor"].default_value = grime
    nt.links.new(base_ramp.outputs["Color"], dark.inputs[6])
    nt.links.new(ao.outputs["Color"], dark.inputs[7])
    bright = nt.nodes.new("ShaderNodeMix")
    bright.data_type = "RGBA"
    bright.blend_type = "SCREEN"
    nt.links.new(dark.outputs[2], bright.inputs[6])
    bright.inputs[7].default_value = (edge, edge, edge * 1.02, 1)
    nt.links.new(edge_ramp.outputs["Color"], bright.inputs["Factor"])
    nt.links.new(bright.outputs[2], bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.12
    dents = _noise(nt, 40.0, 3.0, 0.5)
    nt.links.new(dents.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    _cache[name] = mat
    return mat


def cloth(name, color, rough=0.92, sheen=0.3, weave=60.0, fray=0.15):
    """Matte cloth with a faint weave and dirt blotches."""
    if name in _cache:
        return _cache[name]
    mat, nt, bsdf = _principled(name)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Sheen Weight"].default_value = sheen
    blotch = _noise(nt, 4.0, 5.0, 0.6)
    ramp = _ramp(nt, blotch.outputs["Fac"], tuple(c * (1.0 - fray * 2) for c in color) + (1,), tuple(color) + (1,))
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = weave
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.08
    nt.links.new(wave.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    mat.use_backface_culling = False
    _cache[name] = mat
    return mat


def flat(name, color, rough=0.7, metallic=0.0, emission=0.0):
    if name in _cache:
        return _cache[name]
    mat, nt, bsdf = _principled(name)
    bsdf.inputs["Base Color"].default_value = tuple(color) + (1,)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    if emission > 0.0:
        bsdf.inputs["Emission Color"].default_value = tuple(color) + (1,)
        bsdf.inputs["Emission Strength"].default_value = emission
    _cache[name] = mat
    return mat


def mail(name="mail", base=(0.16, 0.16, 0.17)):
    """Chainmail: metallic with a tight ring pattern as bump and dark gaps."""
    if name in _cache:
        return _cache[name]
    mat, nt, bsdf = _principled(name)
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.45
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 220.0
    vor.feature = "DISTANCE_TO_EDGE"
    ramp = _ramp(nt, vor.outputs["Distance"], (0.02, 0.02, 0.02, 1), tuple(base) + (1,), 0.02, 0.12)
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.4
    nt.links.new(vor.outputs["Distance"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    _cache[name] = mat
    return mat
