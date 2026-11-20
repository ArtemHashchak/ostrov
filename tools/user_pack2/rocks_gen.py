"""Набор валунов под материалы камня пользователя (Rocks/Stone0XX — только поверхности, без сеток).
blender -b --disable-autoexec --python tools/user_pack2/rocks_gen.py -- OUT_DIR
Каждая форма: икосфера → срезы плоскостями (сколы/грани) → воксельный ремеш (ровная сетка) →
смещение шумами (бугры + ячейки Вороного = трещины/сколы) → плоское основание (сидит в грунте) →
Decimate до 3600 треуг. (LOD0; LOD1/LOD2 строит импорт Godot — generate_lods). UV не нужны:
текстура кладётся трипланарно в мире (user_rock.gdshader), плотность одна на любом размере.
Масштаб: 1 единица = 1 м (габарит ~1 м по длинной оси; в игре масштабируется по месту)."""
import bpy, bmesh, sys, os, json, math, random
from mathutils import Vector, Matrix
out = sys.argv[sys.argv.index("--") + 1]
os.makedirs(out, exist_ok=True)
TRIS = 3600

# имя, масштаб (x, y, z), срезов, сила бугров, сила трещин, высота основания (доля), seed
SHAPES = [
    ("boulder_round", (1.0, 0.85, 0.7), 2, 0.16, 0.05, 0.62, 11),   # окатанный валун
    ("boulder_split", (1.0, 0.8, 0.75), 4, 0.12, 0.07, 0.6, 23),    # валун с отколотым боком
    ("rock_angular", (1.0, 0.75, 0.8), 7, 0.08, 0.09, 0.58, 37),    # угловатый обломок
    ("rock_slab", (1.0, 0.9, 0.36), 5, 0.07, 0.06, 0.5, 41),         # плоская плита (песчаник у воды)
    ("rock_karst", (0.75, 0.65, 1.0), 6, 0.1, 0.12, 0.66, 53),       # вертикальный известняк, источенный
    ("rock_low", (1.0, 0.95, 0.42), 3, 0.14, 0.05, 0.55, 67),        # низкий окатыш, полу в песке
]

def clean():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)

def cut(bm, co, no):
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_outer=True)
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if edges:
        bmesh.ops.edgeloop_fill(bm, edges=edges)

report = {}
for name, sc, ncut, bump, crack, base, seed in SHAPES:
    clean()
    rnd = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=5, radius=1.0)
    o = bpy.context.active_object
    o.name = name
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.scale(bm, vec=Vector(sc), verts=bm.verts)
    # сколы: плоскости на расстоянии 0.55..0.85 радиуса в случайных направлениях (не снизу)
    for i in range(ncut):
        d = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.2, 1.0))).normalized()
        r = rnd.uniform(0.55, 0.85) * (abs(d.x) * sc[0] + abs(d.y) * sc[1] + abs(d.z) * sc[2]) / (abs(d.x) + abs(d.y) + abs(d.z))
        cut(bm, d * r, d)
    bm.to_mesh(o.data)
    bm.free()
    # ровная сетка под смещение
    rm = o.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = 0.025
    bpy.ops.object.modifier_apply(modifier="remesh")
    # крупные бугры
    t1 = bpy.data.textures.new(name + "_clouds", "CLOUDS")
    t1.noise_scale = 0.55
    t1.noise_depth = 3
    t1.noise_basis = "BLENDER_ORIGINAL"
    m1 = o.modifiers.new("bump", "DISPLACE")
    m1.texture = t1
    m1.strength = bump
    m1.mid_level = 0.5
    m1.texture_coords = "LOCAL"
    # трещины/сколы: Вороной F2−F1 даёт узкие борозды по границам ячеек
    t2 = bpy.data.textures.new(name + "_vor", "VORONOI")
    t2.distance_metric = "DISTANCE"
    t2.color_mode = "INTENSITY"
    t2.noise_scale = 0.32
    t2.weight_1 = -1.0
    t2.weight_2 = 1.0
    t2.noise_intensity = 1.0
    m2 = o.modifiers.new("crack", "DISPLACE")
    m2.texture = t2
    m2.strength = crack
    m2.mid_level = 0.25
    m2.texture_coords = "LOCAL"
    # мелкие выщерблины
    t3 = bpy.data.textures.new(name + "_fine", "CLOUDS")
    t3.noise_scale = 0.12
    t3.noise_depth = 2
    m3 = o.modifiers.new("fine", "DISPLACE")
    m3.texture = t3
    m3.strength = bump * 0.18
    m3.mid_level = 0.5
    m3.texture_coords = "LOCAL"
    for m in ("bump", "crack", "fine"):
        bpy.ops.object.modifier_apply(modifier=m)
    # основание: срез снизу (камень «сидит» в грунте), потом опустить на z = 0
    bm = bmesh.new()
    bm.from_mesh(o.data)
    zs = [v.co.z for v in bm.verts]
    zmin, zmax = min(zs), max(zs)
    zc = zmin + (zmax - zmin) * (1.0 - base) * 0.5
    cut(bm, Vector((0, 0, zc)), Vector((0, 0, -1)))
    bmesh.ops.translate(bm, vec=Vector((0, 0, -zc)), verts=bm.verts)
    # центр по XY
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    bmesh.ops.translate(bm, vec=Vector((-(min(xs) + max(xs)) / 2, -(min(ys) + max(ys)) / 2, 0)), verts=bm.verts)
    bm.to_mesh(o.data)
    bm.free()
    # упростить до бюджета
    tris0 = sum(len(p.vertices) - 2 for p in o.data.polygons)
    dm = o.modifiers.new("dec", "DECIMATE")
    dm.decimate_type = "COLLAPSE"
    dm.ratio = min(1.0, TRIS / max(1, tris0))
    dm.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="dec")
    # нормализация: длинная ось = 1 м
    dims = o.dimensions
    k = 1.0 / max(dims.x, dims.y)
    o.scale = (k, k, k)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    # гладкие нормали со сколами: сглаживание по углу 40°
    for p in o.data.polygons:
        p.use_smooth = True
    if hasattr(o.data, "use_auto_smooth"):
        o.data.use_auto_smooth = True
        o.data.auto_smooth_angle = math.radians(40)
    # UV на всякий случай (кубическая проекция) — шейдер их не использует
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=1.0)
    bpy.ops.object.mode_set(mode="OBJECT")
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    path = os.path.join(out, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_materials="NONE",
        export_normals=True, export_texcoords=True, export_apply=True)
    report[name] = {"tris_hi": tris0, "tris": tris, "size": [round(v, 3) for v in o.dimensions]}
    print("[rocks]", name, tris0, "->", tris, [round(v, 2) for v in o.dimensions])
json.dump(report, open(os.path.join(out, "rocks_report.json"), "w"), ensure_ascii=False, indent=1)
