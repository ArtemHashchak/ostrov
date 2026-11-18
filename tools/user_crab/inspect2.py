import bpy
bpy.ops.wm.open_mainfile(filepath="/tmp/models_in/crab/crab.blend", load_ui=False, use_scripts=False)
arm=bpy.data.objects["CAngrejo"]; me=bpy.data.objects["crab"]
for b in arm.data.bones:
    print("BONE", b.name, "parent=",b.parent.name if b.parent else "-", "head=",tuple(round(v,2) for v in b.head_local),"tail=",tuple(round(v,2) for v in b.tail_local), "deform",b.use_deform)
for m in me.modifiers:
    print("MOD", m.name, m.type, {k:getattr(m,k) for k in ("levels","render_levels","sculpt_levels","strength","show_viewport") if hasattr(m,k)})
mesh=me.data
mesh.calc_loop_triangles()
print("BASE tris", len(mesh.loop_triangles), "verts", len(mesh.vertices), "uvs", [u.name for u in mesh.uv_layers])
uv=mesh.uv_layers.active.data
import math
tiles=set()
for l in uv:
    tiles.add((math.floor(l.uv.x), math.floor(l.uv.y)))
print("UDIM tiles", sorted(tiles))
mat=bpy.data.materials["pbr_bridge_crab_0"]
for n in mat.node_tree.nodes:
    s=n.type
    if n.type=='TEX_IMAGE': s+=" "+(n.image.name if n.image else "-")+" src="+(n.image.source if n.image else "")
    print("NODE", n.name, s)
for img in bpy.data.images:
    if img.source=='TILED': print("TILED", img.name, [t.number for t in img.tiles])
