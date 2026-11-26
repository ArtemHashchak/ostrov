"""Конвертер моделей пользователя для версии 5 (агент A · Флора). Запуск в Blender:
  blender -b --factory-startup --python tools/import_v5/flora_blender.py -- <job.json>
job.json: {"jobs": [ {
   "src": "путь к .gltf/.glb/.fbx/.obj/.blend",
   "out": "assets/…/<id>.glb",            # LOD0
   "out_lod1": "assets/…/<id>_lod1.glb",  # опционально: упрощённая копия (decimate)
   "lod1_ratio": 0.3,
   "keep": ["regex по имени объекта"], "drop": ["regex"],
   "split": false,  # true → каждый корневой объект в свой файл: out — шаблон с {name}
   "height": 0,     # >0: масштаб под эту высоту (м)
   "max_height": 80, "min_height": 0.05,  # иначе — подозрение на сантиметры/дюймы: выравнивается на "height_guess"
   "height_guess": 1.0,
   "tex": 1024,     # максимальная сторона текстур
   "center": true,  # центр XY по рамке, низ на 0
   "leaf_regex": "leaf|leaves|frond|grass|fern|blade|foliage|petal|flower",  # материалы с прозрачностью → Alpha Clip
   "img_dir": ""    # доп. папка для поиска потерянных текстур (по имени файла)
}]}
Пишет рядом с job.json файл <job>.result.json: размеры (м), треугольники, итоговые файлы.
"""
import bpy, bmesh, sys, os, re, json, math
from mathutils import Vector

def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def import_src(src):
    ext = os.path.splitext(src)[1].lower()
    if ext in (".gltf", ".glb"):
        bpy.ops.import_scene.gltf(filepath=src)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=src, use_image_search=True)
    elif ext == ".obj":
        if hasattr(bpy.ops.wm, "obj_import"):
            bpy.ops.wm.obj_import(filepath=src)
        else:
            bpy.ops.import_scene.obj(filepath=src)
    elif ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=src)
        cur = bpy.context.scene
        for sc in bpy.data.scenes:   # объекты из остальных сцен файла — тоже в текущую
            if sc == cur:
                continue
            for o in sc.objects:
                if o.name not in cur.objects:
                    try:
                        cur.collection.objects.link(o)
                    except Exception:
                        pass
        for o in bpy.data.objects:      # объекты вне сцен (лежат только в файле)
            if o.type == "MESH" and not o.users_scene:
                try:
                    cur.collection.objects.link(o)
                except Exception:
                    pass
        # в сцене — только видимое для рендера (прочие сцены файла не трогаем)
    elif ext == ".ply":
        bpy.ops.wm.ply_import(filepath=src)
    else:
        raise RuntimeError("неизвестный формат " + src)

def fix_images(img_dir):
    if not img_dir:
        return
    index = {}
    for root, _, files in os.walk(img_dir):
        for f in files:
            index.setdefault(f.lower(), os.path.join(root, f))
    for img in bpy.data.images:
        if img.source != "FILE":
            continue
        p = bpy.path.abspath(img.filepath)
        if img.packed_file or os.path.exists(p):
            continue
        cand = index.get(os.path.basename(p).lower())
        if cand:
            img.filepath = cand
            try:
                img.reload()
            except Exception:
                pass

def roots():
    return [o for o in bpy.context.scene.objects if o.parent is None]

def select_tree(objs):
    bpy.ops.object.select_all(action="DESELECT")
    out = []
    def rec(o):
        out.append(o)
        for c in o.children:
            rec(c)
    for o in objs:
        rec(o)
    for o in out:
        o.select_set(True)
    return out

def bbox(objs):
    bpy.context.view_layer.update()
    mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
    return mn, mx

def tris(objs):
    t = 0
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        if o.type == "MESH":
            me = o.evaluated_get(dg).to_mesh()
            t += sum(len(p.vertices) - 2 for p in me.polygons)
            o.evaluated_get(dg).to_mesh_clear()
    return t

def prep_materials(leaf_re):
    rx = re.compile(leaf_re, re.I) if leaf_re else None
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        alpha_linked = bsdf.inputs["Alpha"].is_linked
        leafy = bool(rx and rx.search(m.name))
        if alpha_linked or (leafy and alpha_linked):
            m.blend_method = "CLIP"
            m.alpha_threshold = 0.5
            m.use_backface_culling = False
        elif leafy:
            m.use_backface_culling = False

def shrink_images(maxs):
    for img in bpy.data.images:
        if img.size[0] == 0 or img.source not in ("FILE", "GENERATED"):
            continue
        w, h = img.size
        s = max(w, h)
        if s > maxs:
            k = maxs / s
            try:
                img.scale(max(1, int(w * k)), max(1, int(h * k)))
            except Exception as e:
                print("scale fail", img.name, e)

def apply_all(objs):
    """Перенести мировые трансформации в меши (без оператора — он падает на общих мешах)."""
    from mathutils import Matrix
    bpy.context.view_layer.update()
    sel = select_tree(objs)
    mats = {o.name: o.matrix_world.copy() for o in sel}
    for o in sel:
        o.parent = None
    for o in sel:
        mw = mats[o.name]
        if o.type == "MESH":
            me = o.data.copy()
            me.transform(mw)
            if mw.determinant() < 0:
                me.flip_normals()
            o.data = me
        o.matrix_world = Matrix.Identity(4)

def normalize(objs, job):
    mn, mx = bbox(objs)
    h = mx.z - mn.z
    k = 1.0
    if job.get("scale", 0) > 0:
        k = job["scale"]
    elif job.get("height", 0) > 0 and h > 1e-6:
        k = job["height"] / h
    elif h > job.get("max_height", 80) or h < job.get("min_height", 0.05):
        k = job.get("height_guess", 1.0) / max(h, 1e-6)
    holder = bpy.data.objects.new("_holder", None)
    bpy.context.scene.collection.objects.link(holder)
    c = (mn + mx) / 2
    off = Vector((-c.x if job.get("center", True) else 0, -c.y if job.get("center", True) else 0, -mn.z))
    for o in objs:
        o.parent = holder
        o.matrix_parent_inverse = holder.matrix_world.inverted()
    holder.location = off * k
    holder.scale = (k, k, k)
    bpy.context.view_layer.update()
    for o in objs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    bpy.data.objects.remove(holder)
    return k

def export(objs, path, fmt):
    select_tree(objs)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sep = path.endswith(".gltf")
    kw = dict(filepath=path, use_selection=True, export_format="GLTF_SEPARATE" if sep else "GLB", export_apply=True,
              export_yup=True, export_texcoords=True, export_normals=True, export_colors=False, export_materials="EXPORT",
              export_animations=False, export_skins=False, export_morph=False, export_cameras=False, export_lights=False)
    if sep:
        kw["export_texture_dir"] = "tex"
    try:
        bpy.ops.export_scene.gltf(export_image_format=fmt, **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)

def apply_mod(o, name):
    """Применить модификатор без оператора (работает и для общих данных)."""
    dg = bpy.context.evaluated_depsgraph_get()
    for m in list(o.modifiers):
        m.show_viewport = (m.name == name)
    dg.update()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    for m in list(o.modifiers):
        if m.name == name:
            o.modifiers.remove(m)
        else:
            m.show_viewport = True
    o.data = me

def run_op(op, objs):
    """op: {"op": "thin", material, keep} | {"op": "dec", material, ratio} — dec: грани материала
    отделяются в свой объект и упрощаются (collapse) отдельно от остального."""
    if op["op"] == "thin":
        thin(objs, op)
        return
    rxm = re.compile(op["material"], re.I)
    for o in objs:
        idx = {i for i, m in enumerate(o.data.materials) if m and rxm.search(m.name)}
        if not idx:
            continue
        bm = bmesh.new(); bm.from_mesh(o.data)
        part = [f for f in bm.faces if f.material_index in idx]
        if not part:
            bm.free(); continue
        # копия объекта: в ней оставить только эти грани, в исходном — удалить их
        n = o.copy(); n.data = o.data.copy(); n.name = o.name + "_" + op.get("tag", "dec")
        bpy.context.scene.collection.objects.link(n)
        bmesh.ops.delete(bm, geom=part, context="FACES")
        bm.to_mesh(o.data); bm.free()
        bm2 = bmesh.new(); bm2.from_mesh(n.data)
        rest = [f for f in bm2.faces if f.material_index not in idx]
        bmesh.ops.delete(bm2, geom=rest, context="FACES")
        bm2.to_mesh(n.data); bm2.free()
        before = len(n.data.polygons)
        md = n.modifiers.new("dec", "DECIMATE"); md.ratio = op["ratio"]
        apply_mod(n, "dec")
        print("OPDEC", n.name, before, "->", len(n.data.polygons))
        # вернуть упрощённые грани в исходный объект
        bpy.ops.object.select_all(action="DESELECT")
        n.select_set(True); o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.join()

def assign_textures(spec):
    """spec: {regex материала: {base, alpha, normal, rough}} — пути к картинкам; собирает Principled."""
    for m in bpy.data.materials:
        for rx, t in spec.items():
            if not re.search(rx, m.name, re.I):
                continue
            m.use_nodes = True
            nt = m.node_tree
            for n in list(nt.nodes):
                nt.nodes.remove(n)
            out = nt.nodes.new("ShaderNodeOutputMaterial")
            b = nt.nodes.new("ShaderNodeBsdfPrincipled")
            nt.links.new(b.outputs[0], out.inputs[0])
            def img(path, non_color=False):
                n = nt.nodes.new("ShaderNodeTexImage")
                n.image = bpy.data.images.load(path, check_existing=True)
                if non_color:
                    n.image.colorspace_settings.name = "Non-Color"
                return n
            if t.get("base"):
                nb = img(t["base"])
                nt.links.new(nb.outputs["Color"], b.inputs["Base Color"])
                if t.get("alpha") == "base":
                    nt.links.new(nb.outputs["Alpha"], b.inputs["Alpha"])
            if t.get("alpha") and t["alpha"] != "base":
                na = img(t["alpha"], True)
                nt.links.new(na.outputs["Color"], b.inputs["Alpha"])
            if t.get("normal"):
                nn = img(t["normal"], True)
                nm = nt.nodes.new("ShaderNodeNormalMap")
                nt.links.new(nn.outputs["Color"], nm.inputs["Color"])
                nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
            if t.get("rough"):
                nr = img(t["rough"], True)
                nt.links.new(nr.outputs["Color"], b.inputs["Roughness"])
            else:
                b.inputs["Roughness"].default_value = 0.75
            b.inputs["Metallic"].default_value = 0.0
            break

def thin(objs, spec):
    print("THIN", spec, [o.name for o in objs if o.type == "MESH"])
    """Прореживание: у материала spec["material"] оставить долю spec["keep"] отдельных кусков (листьев)."""
    import random
    rnd = random.Random(7)
    rx = re.compile(spec["material"], re.I)
    for o in objs:
        if o.type != "MESH":
            continue
        idx = [i for i, m in enumerate(o.data.materials) if m and rx.search(m.name)]
        if not idx:
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.faces.ensure_lookup_table()
        seen = set()
        kill = []
        for f in bm.faces:
            if f.index in seen or f.material_index not in idx:
                continue
            # остров связных граней того же материала
            stack = [f]; isl = []
            seen.add(f.index)
            while stack:
                g = stack.pop(); isl.append(g)
                for e in g.edges:
                    for h in e.link_faces:
                        if h.index not in seen and h.material_index in idx:
                            seen.add(h.index); stack.append(h)
            if spec.get("min_island") and len(isl) < spec["min_island"]:
                kill.extend(isl)
            elif not spec.get("min_island") and rnd.random() > spec.get("keep", 0.2):
                kill.extend(isl)
            elif spec.get("grow"):
                # оставшиеся листья крупнее — компенсировать прореживание
                vs = {v for g in isl for v in g.verts}
                c = sum((v.co for v in vs), Vector()) / max(len(vs), 1)
                for v in vs:
                    v.co = c + (v.co - c) * spec["grow"]
        print("THIN kill", o.name, len(kill), "of", len(bm.faces))
        bmesh.ops.delete(bm, geom=kill, context="FACES")
        bm.to_mesh(o.data)
        bm.free()

def decimate(objs, ratio, skip_rx=None):
    for o in objs:
        if o.type != "MESH":
            continue
        md = o.modifiers.new("dec", "DECIMATE")
        md.ratio = ratio
        md.use_collapse_triangulate = True

def run_job(job, base):
    clear()
    import_src(job["src"])
    bpy.context.view_layer.update()
    fix_images(job.get("img_dir", ""))
    # убрать камеры/свет/пустые без мешей
    for o in list(bpy.context.scene.objects):
        if o.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(o)
    keep = [re.compile(k, re.I) for k in job.get("keep", [])]
    drop = [re.compile(k, re.I) for k in job.get("drop", [])]
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            continue
        if (keep and not any(k.search(o.name) for k in keep)) or any(d.search(o.name) for d in drop):
            bpy.data.objects.remove(o)
    # скрытые в исходнике (viewport/render off) — не берём
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH" and (o.hide_render or o.hide_get() or o.hide_viewport):
            if not job.get("keep_hidden"):
                bpy.data.objects.remove(o)
            else:
                o.hide_set(False); o.hide_viewport = False; o.hide_render = False; o.hide_select = False
    for o in bpy.context.scene.objects:
        o.animation_data_clear()   # анимация объекта сбрасывала бы перенос в начало координат
        if o.type == "MESH" and o.data.users > 1:
            o.data = o.data.copy()
    if job.get("assign"):
        assign_textures(job["assign"])
    if job.get("thin"):
        for t in (job["thin"] if isinstance(job["thin"], list) else [job["thin"]]):
            thin([o for o in bpy.context.scene.objects], t)
    for op in job.get("ops", []):
        run_op(op, [o for o in bpy.context.scene.objects if o.type == "MESH"])
    if job.get("separate_dec"):
        # отделить грани материала и упростить их отдельным объектом (ветки), листья не трогать
        sd = job["separate_dec"]
        rxm = re.compile(sd["material"], re.I)
        for o in list(bpy.context.scene.objects):
            if o.type != "MESH":
                continue
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True); bpy.context.view_layer.objects.active = o
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="DESELECT")
            bpy.ops.object.mode_set(mode="OBJECT")
            for p in o.data.polygons:
                m = o.data.materials[p.material_index]
                p.select = bool(m and rxm.search(m.name))
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.separate(type="SELECTED")
            bpy.ops.object.mode_set(mode="OBJECT")
            for n in bpy.context.selected_objects:
                if n is not o:
                    n.name = o.name + "_dec"
                    bpy.ops.object.select_all(action="DESELECT"); n.select_set(True)
                    bpy.context.view_layer.objects.active = n
                    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
                    bpy.ops.mesh.remove_doubles(threshold=0.001)
                    bpy.ops.object.mode_set(mode="OBJECT")
                    print("SEPDEC merged", len(n.data.polygons), len(n.data.vertices))
                    md = n.modifiers.new("sd", "DECIMATE"); md.ratio = sd["ratio"]
                    apply_mod(n, "sd")
                    print("SEPDEC", n.name, len(n.data.polygons))
    if job.get("pre_decimate"):
        pd = job["pre_decimate"]
        rxm = re.compile(pd.get("material", "."), re.I)
        for o in list(bpy.context.scene.objects):
            if o.type != "MESH":
                continue
            idx = {i for i, m in enumerate(o.data.materials) if m and rxm.search(m.name)}
            vg = o.vertex_groups.new(name="pre")
            vs = set()
            for p in o.data.polygons:
                if p.material_index in idx:
                    vs.update(p.vertices)
            vg.add(list(vs), 1.0, "REPLACE")
            md = o.modifiers.new("pre", "DECIMATE"); md.ratio = pd["ratio"]; md.vertex_group = "pre"
            apply_mod(o, "pre")
    prep_materials(job.get("leaf_regex", "leaf|leaves|frond|grass|fern|blade|foliage|petal|flower|plant"))
    shrink_images(job.get("tex", 1024))
    fmt = job.get("img_format", "AUTO")
    results = []
    groups = []
    if job.get("split"):
        for r in roots():
            objs = [r] + list(r.children_recursive)
            if any(o.type == "MESH" for o in objs):
                groups.append((re.sub(r"[^a-z0-9]+", "_", r.name.lower()).strip("_"), objs))
    else:
        groups.append(("", [o for o in bpy.context.scene.objects]))
    for name, objs in groups:
        # спрятать остальные
        apply_all(objs)
        meshes = [o for o in objs if o.type == "MESH"]
        k = normalize(meshes, job)
        if job.get("target_tris"):
            t0 = tris(meshes)
            if t0 > job["target_tris"] and job.get("target_mode") == "thin":
                thin(meshes, {"material": ".", "keep": job["target_tris"] / t0})
            elif t0 > job["target_tris"]:
                ex = re.compile(job["target_exclude"], re.I) if job.get("target_exclude") else None
                for o in meshes:
                    md = o.modifiers.new("t0", "DECIMATE"); md.ratio = job["target_tris"] / t0
                    if ex:
                        idx = {i for i, m in enumerate(o.data.materials) if m and not ex.search(m.name)}
                        vg = o.vertex_groups.new(name="t0")
                        vs = set()
                        for p in o.data.polygons:
                            if p.material_index in idx:
                                vs.update(p.vertices)
                        vg.add(list(vs), 1.0, "REPLACE")
                        md.vertex_group = "t0"
                        md.ratio = max(0.02, (job["target_tris"] - (t0 - sum(1 for p in o.data.polygons if p.material_index in idx))) / max(1, sum(1 for p in o.data.polygons if p.material_index in idx)))
                    apply_mod(o, "t0")
        if job.get("target_tris_lod1") and job.get("target_mode") != "thin":
            job["lod1_ratio"] = min(1.0, job["target_tris_lod1"] / max(tris(meshes), 1))
        mn, mx = bbox(meshes)
        out = job["out"].replace("{name}", name)
        export(meshes, os.path.join(base, out), fmt)
        res = {"name": name, "out": out, "size": [round(mx.x - mn.x, 3), round(mx.z - mn.z, 3), round(mx.y - mn.y, 3)],
               "scale": round(k, 5), "tris": tris(meshes)}
        if job.get("out_lod1"):
            for t in job.get("lod1_thin", []):
                thin(meshes, t)
            if job.get("target_mode") == "thin" and job.get("target_tris_lod1"):
                thin(meshes, {"material": ".", "keep": min(1.0, job["target_tris_lod1"] / max(tris(meshes), 1))})
                job["lod1_ratio"] = 1.0
            decimate(meshes, job.get("lod1_ratio", 0.3))
            o1 = job["out_lod1"].replace("{name}", name)
            export(meshes, os.path.join(base, o1), fmt)
            res["out_lod1"] = o1
            res["tris_lod1"] = tris(meshes)
            for o in meshes:
                for md in list(o.modifiers):
                    if md.name == "dec":
                        o.modifiers.remove(md)
        results.append(res)
        print("RESULT", json.dumps(res, ensure_ascii=False))
    return results

def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    jp = argv[0]
    base = os.getcwd()
    jobs = json.load(open(jp))["jobs"]
    allres = {}
    for j in jobs:
        try:
            allres[j.get("id", j["out"])] = run_job(j, base)
        except Exception as e:
            import traceback; traceback.print_exc()
            allres[j.get("id", j["out"])] = {"error": str(e)}
    json.dump(allres, open(jp.replace(".json", ".result.json"), "w"), ensure_ascii=False, indent=1)

main()
