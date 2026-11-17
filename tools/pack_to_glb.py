"""Конвертер упакованных мешей (Poly Haven CC0, из wild-fields-1648 scan_pack) в GLB.
Читает JSON-данные (не выполняет JS). Запуск: python3 -I pack_to_glb.py scan.txt texdir outdir
"""
import base64, json, os, struct, sys

SKIP = {'spinning_wheel_01'}
GROUPS = {'cannon_01': 'cannon_01'}  # части пушки — в один файл


def b64(s):
    return base64.b64decode(s)


def pad4(b, fill=b'\x00'):
    return b + fill * ((4 - len(b) % 4) % 4)


def build_glb(parts, texdir, out):
    # parts: list of (name, meshdict)
    bin_chunks = []
    offset = 0
    buffer_views, accessors, meshes, nodes, images, textures, materials = [], [], [], [], [], [], []
    mat_index = {}

    def add_view(data, target=None):
        nonlocal offset
        data = pad4(data)
        bv = {'buffer': 0, 'byteOffset': offset, 'byteLength': len(data)}
        if target:
            bv['target'] = target
        buffer_views.append(bv)
        bin_chunks.append(data)
        offset += len(data)
        return len(buffer_views) - 1

    def add_image(fname):
        data = open(os.path.join(texdir, fname), 'rb').read()
        v = add_view(data)
        images.append({'bufferView': v, 'mimeType': 'image/jpeg', 'name': fname})
        textures.append({'source': len(images) - 1, 'sampler': 0})
        return len(textures) - 1

    for name, m in parts:
        mm = m['m']
        if mm['base'] not in mat_index:
            mat = {'name': mm['key'], 'pbrMetallicRoughness': {
                'baseColorTexture': {'index': add_image(mm['base'])},
                'metallicRoughnessTexture': {'index': add_image(mm['mr'])},
                'metallicFactor': 1.0 if mm.get('metal') else 0.0, 'roughnessFactor': 1.0},
                'normalTexture': {'index': add_image(mm['nor'])},
                'occlusionTexture': {'index': len(textures) - 2},  # ARM: R = AO
                'doubleSided': bool(mm.get('ds'))}
            if mm.get('ds'):
                mat['alphaMode'] = 'MASK'
                mat['alphaCutoff'] = 0.5
            materials.append(mat)
            mat_index[mm['base']] = len(materials) - 1
        p, n, uv = b64(m['p']), b64(m['n']), b64(m['uv'])
        idx = b64(m['i'])
        cnt = len(p) // 12
        pf = struct.unpack('<%df' % (cnt * 3), p)
        mn = [min(pf[i::3]) for i in range(3)]
        mx = [max(pf[i::3]) for i in range(3)]
        ap = len(accessors); accessors.append({'bufferView': add_view(p, 34962), 'componentType': 5126, 'count': cnt, 'type': 'VEC3', 'min': mn, 'max': mx})
        an = len(accessors); accessors.append({'bufferView': add_view(n, 34962), 'componentType': 5126, 'count': cnt, 'type': 'VEC3'})
        au = len(accessors); accessors.append({'bufferView': add_view(uv, 34962), 'componentType': 5126, 'count': len(uv) // 8, 'type': 'VEC2'})
        ctype, isz = (5125, 4) if m.get('i32') else (5123, 2)
        ai = len(accessors); accessors.append({'bufferView': add_view(idx, 34963), 'componentType': ctype, 'count': len(idx) // isz, 'type': 'SCALAR'})
        meshes.append({'name': name, 'primitives': [{'attributes': {'POSITION': ap, 'NORMAL': an, 'TEXCOORD_0': au}, 'indices': ai, 'material': mat_index[mm['base']]}]})
        nodes.append({'name': name, 'mesh': len(meshes) - 1})

    gltf = {'asset': {'version': '2.0', 'generator': 'ostrova pack_to_glb'},
            'scene': 0, 'scenes': [{'nodes': list(range(len(nodes)))}], 'nodes': nodes, 'meshes': meshes,
            'materials': materials, 'textures': textures, 'images': images,
            'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}],
            'accessors': accessors, 'bufferViews': buffer_views, 'buffers': [{'byteLength': offset}]}
    js = pad4(json.dumps(gltf, separators=(',', ':')).encode(), b' ')
    binb = b''.join(bin_chunks)
    total = 12 + 8 + len(js) + 8 + len(binb)
    with open(out, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack('<II', len(binb), 0x004E4942)); f.write(binb)


def main(scan, texdir, outdir):
    t = open(scan).read()
    d = json.loads(t[t.index('{'):].rstrip().rstrip(';'))
    os.makedirs(outdir, exist_ok=True)
    grouped = {}
    for name, m in d['meshes'].items():
        g = next((v for k, v in GROUPS.items() if name.startswith(k)), name)
        if g in SKIP:
            continue
        grouped.setdefault(g, []).append((name, m))
    for g, parts in grouped.items():
        build_glb(parts, texdir, os.path.join(outdir, g + '.glb'))
        print('ok', g, len(parts))


if __name__ == '__main__':
    main(*sys.argv[1:4])
