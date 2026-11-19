"""Процедурный материал пользователя «Procedural Mossy Dirt Material.blend» (Грунт) → бесшовные PBR-текстуры.
blender -b --disable-autoexec "Procedural Mossy Dirt Material.blend" --python tools/user_pack2/mossy_bake.py -- OUT_DIR RES EXTENT
Запекается на плоскости EXTENT×EXTENT единиц (объектные координаты), Cycles: цвет, шероховатость,
нормаль (с бампом/смещением материала). Бесшовность — потом (tools/user_pack2/make_seamless.py)."""
import bpy, sys, os
a = sys.argv[sys.argv.index("--") + 1:]
out, res, ext = a[0], int(a[1]), float(a[2])
os.makedirs(out, exist_ok=True)
mat = bpy.data.materials["Material.001"]
mat.cycles.displacement_method = "BUMP"
# мох в исходнике — с подповерхностным рассеянием (Subsurface Weight 1): цвет уходит в SSS-проход,
# а запекание DIFFUSE/COLOR даёт 0. Для запекания SSS выключаем (цвет тот же).
for g in [n.node_tree for n in mat.node_tree.nodes if n.type == "GROUP"]:
    for n in g.nodes:
        if n.type == "BSDF_PRINCIPLED":
            n.inputs["Subsurface Weight"].default_value = 0.0
for n in mat.node_tree.nodes:
    if n.type == "OUTPUT_MATERIAL":
        print("OUT", n.name, n.target, n.is_active_output)
        n.target = "ALL"
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.mesh.primitive_plane_add(size=ext)
pl = bpy.context.active_object
for c in pl.users_collection: c.objects.unlink(pl)
bpy.context.scene.collection.objects.link(pl)
pl.data.materials.append(mat)
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 4
sc.render.bake.margin = 0
sc.render.bake.target = "IMAGE_TEXTURES"; sc.render.bake.use_selected_to_active = False; sc.render.bake.use_clear = True
print("BAKECFG", sc.render.bake.target)
def bake(kind, name, colorspace):
    img = bpy.data.images.new(name, res, res, float_buffer=False)
    img.colorspace_settings.name = colorspace
    nt = mat.node_tree
    n = nt.nodes.new("ShaderNodeTexImage"); n.image = img; n.select = True
    nt.nodes.active = n
    for o in bpy.data.objects: o.select_set(o == pl)
    bpy.context.view_layer.objects.active = pl
    if kind == "DIFFUSE":
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    else:
        bpy.ops.object.bake(type=kind)
    px = img.pixels[:]; print("PX", name, sum(px)/len(px))
    img.filepath_raw = os.path.join(out, name + ".png"); img.file_format = "PNG"; img.save()
    nt.nodes.remove(n)
    print("BAKED", name)
# цвет: эмиссия = mix(мох, грунт) с тем же коэффициентом, что у Mix Shader исходника
g = [n.node_tree for n in mat.node_tree.nodes if n.type == "GROUP"][0]
gout = [n for n in g.nodes if n.type == "GROUP_OUTPUT"][0]
mixs = [n for n in g.nodes if n.type == "MIX_SHADER"][0]
b_moss = mixs.inputs[1].links[0].from_node
b_dirt = mixs.inputs[2].links[0].from_node
mixc = g.nodes.new("ShaderNodeMix"); mixc.data_type = "RGBA"
g.links.new(mixs.inputs["Fac"].links[0].from_socket, mixc.inputs["Factor"])
def feed(bsdf, sock):
    bc = bsdf.inputs["Base Color"]
    if bc.links: g.links.new(bc.links[0].from_socket, sock)
    else: sock.default_value = bc.default_value
feed(b_moss, mixc.inputs[6]); feed(b_dirt, mixc.inputs[7])
em = g.nodes.new("ShaderNodeEmission")
g.links.new(mixc.outputs[2], em.inputs["Color"])
old = gout.inputs["Shader"].links[0].from_socket
g.links.new(em.outputs[0], gout.inputs["Shader"])
bake("EMIT", "mossy_albedo", "sRGB")
g.links.new(old, gout.inputs["Shader"])
bake("NORMAL", "mossy_normal", "Non-Color")
