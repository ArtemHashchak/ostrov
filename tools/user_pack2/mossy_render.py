"""Мшистая земля пользователя (Грунт/Procedural Mossy Dirt Material.blend) → текстуры для слоя
подлеска в рельефе. Запекание Cycles давало нулевой цвет: мох — Principled с Subsurface Weight = 1,
у него нет диффузной составляющей (bake DIFFUSE = 0). Поэтому без запекания: материал перестраивается
в эмиссию (цвет = смесь базовых цветов двух BSDF по маске смешивания шейдеров; данные = маска мха,
высота грязи, высота мха) и плоскость снимается ортокамерой сверху (Standard, без света — точные значения).
blender -b --disable-autoexec "Procedural Mossy Dirt Material.blend" --python tools/user_pack2/mossy_render.py -- OUT_DIR
Выход: mossy_color.png (sRGB), mossy_data.exr (R — маска мха, G — высота грязи, B — высота мха).
Плоскость 2.4×2.4 м в координатах объекта (масштаб узлов автора — как на его сфере радиуса ~1 м)."""
import bpy, sys, os
out = sys.argv[sys.argv.index("--") + 1]
os.makedirs(out, exist_ok=True)
RES = 1280
SIZE = 2.4

sc = bpy.context.scene
src_mat = bpy.data.materials["Material.001"]
ng = bpy.data.node_groups["NodeGroup"]
N = ng.nodes
# какой BSDF на каком входе смешивателя
mix = N["Mix Shader"]
first = mix.inputs[1].links[0].from_node
second = mix.inputs[2].links[0].from_node
print("[moss] mix A =", first.name, "B =", second.name)

def col_src(bsdf):
    s = bsdf.inputs["Base Color"]
    return s.links[0].from_socket if s.is_linked else tuple(s.default_value)

L = ng.links
# цвет: Mix(A, B, fac)
cm = N.new("ShaderNodeMix")
cm.data_type = "RGBA"
cm.blend_type = "MIX"
L.new(N["ColorRamp.002"].outputs["Color"], cm.inputs["Factor"])
for slot, b in ((6, first), (7, second)):
    s = col_src(b)
    if isinstance(s, tuple):
        cm.inputs[slot].default_value = s
    else:
        L.new(s, cm.inputs[slot])
em_c = N.new("ShaderNodeEmission")
L.new(cm.outputs[2], em_c.inputs["Color"])
# данные: маска мха, высота грязи (Noise.001), высота мха (ColorRamp от Noise)
comb = N.new("ShaderNodeCombineColor")
L.new(N["ColorRamp.002"].outputs["Color"], comb.inputs[0])
L.new(N["Noise Texture.001"].outputs["Fac"], comb.inputs[1])
L.new(N["ColorRamp"].outputs["Color"], comb.inputs[2])
em_d = N.new("ShaderNodeEmission")
L.new(comb.outputs[0], em_d.inputs["Color"])
gout = N["Group Output"]

# сцена: только плоскость и ортокамера
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.mesh.primitive_plane_add(size=SIZE)
pl = bpy.context.active_object
pl.data.materials.append(src_mat)
cam_d = bpy.data.cameras.new("cam")
cam_d.type = "ORTHO"
cam_d.ortho_scale = SIZE
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
cam.location = (0, 0, 5)
sc.camera = cam
sc.render.engine = "CYCLES"
sc.cycles.samples = 16
sc.cycles.use_denoising = False
sc.cycles.pixel_filter_width = 0.8
sc.render.resolution_x = RES
sc.render.resolution_y = RES
sc.render.resolution_percentage = 100
sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "None"
sc.view_settings.exposure = 0.0
sc.view_settings.gamma = 1.0
if sc.world is None:
    sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
bg = sc.world.node_tree.nodes.get("Background")
if bg:
    bg.inputs["Strength"].default_value = 0.0

def render(shader_out, path, fmt):
    for l in list(gout.inputs["Shader"].links):
        L.remove(l)
    L.new(shader_out, gout.inputs["Shader"])
    sc.render.image_settings.file_format = fmt
    if fmt == "OPEN_EXR":
        sc.render.image_settings.color_depth = "32"
        sc.render.image_settings.color_mode = "RGB"
    else:
        sc.render.image_settings.color_depth = "8"
        sc.render.image_settings.color_mode = "RGB"
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)

render(em_c.outputs[0], os.path.join(out, "mossy_color.png"), "PNG")
# данные — линейные (EXR не проходит через view transform)
render(em_d.outputs[0], os.path.join(out, "mossy_data.exr"), "OPEN_EXR")
print("[moss] done")
