"""Минимальное чтение/запись GLB для стилевой калибровки «Островов».

Умеет: прочитать JSON и BIN, достать/заменить встроенные картинки (bufferView),
прочитать атрибуты примитивов (POSITION, TEXCOORD_0, индексы), мировые матрицы узлов,
и записать GLB заново (BIN пересобирается с выравниванием 4 байта).
"""
import json
import struct

import numpy as np

_CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
_NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class Glb:
    def __init__(self, path: str):
        b = open(path, "rb").read()
        magic, _ver, _length = struct.unpack("<III", b[:12])
        assert magic == 0x46546C67, "не GLB: " + path
        off = 12
        self.json = None
        self.bin = b""
        while off < len(b):
            clen, ctype = struct.unpack("<II", b[off:off + 8])
            data = b[off + 8: off + 8 + clen]
            if ctype == 0x4E4F534A:
                self.json = json.loads(data.decode("utf-8"))
            elif ctype == 0x004E4942:
                self.bin = bytes(data)
            off += 8 + clen
        self.path = path

    # ---------- буферы
    def view_bytes(self, vi: int) -> bytes:
        v = self.json["bufferViews"][vi]
        o = v.get("byteOffset", 0)
        return self.bin[o: o + v["byteLength"]]

    def accessor(self, ai: int) -> np.ndarray:
        a = self.json["accessors"][ai]
        n = a["count"]
        nc = _NC[a["type"]]
        dt = np.dtype(_CT[a["componentType"]])
        if "bufferView" not in a:
            return np.zeros((n, nc), dt)
        v = self.json["bufferViews"][a["bufferView"]]
        base = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = v.get("byteStride", 0) or dt.itemsize * nc
        raw = np.frombuffer(self.bin, np.uint8, count=stride * (n - 1) + dt.itemsize * nc, offset=base)
        if stride == dt.itemsize * nc:
            arr = raw.view(dt).reshape(n, nc)
        else:
            rows = np.lib.stride_tricks.as_strided(raw, (n, dt.itemsize * nc), (stride, 1))
            arr = np.ascontiguousarray(rows).view(dt).reshape(n, nc)
        if a.get("normalized"):
            arr = arr.astype(np.float32) / float(np.iinfo(dt).max)
        return arr.astype(np.float64) if dt == np.float32 else arr

    # ---------- картинки
    def image_bytes(self, ii: int) -> bytes:
        im = self.json["images"][ii]
        if "bufferView" in im:
            return self.view_bytes(im["bufferView"])
        raise ValueError("картинка %d не встроена (uri=%s)" % (ii, im.get("uri")))

    def set_image_bytes(self, ii: int, data: bytes, mime: str = "image/png") -> None:
        im = self.json["images"][ii]
        im["mimeType"] = mime
        self._pending = getattr(self, "_pending", {})
        self._pending[im["bufferView"]] = data

    def texture_image(self, ti: int) -> int:
        return self.json["textures"][ti]["source"]

    # ---------- узлы
    def node_world_matrices(self) -> dict:
        nodes = self.json.get("nodes", [])
        parent = {}
        for i, n in enumerate(nodes):
            for c in n.get("children", []):
                parent[c] = i
        cache = {}

        def local(n):
            if "matrix" in n:
                return np.array(n["matrix"], np.float64).reshape(4, 4).T
            t = np.array(n.get("translation", [0, 0, 0]), np.float64)
            r = n.get("rotation", [0, 0, 0, 1])
            s = np.array(n.get("scale", [1, 1, 1]), np.float64)
            x, y, z, w = r
            R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                          [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                          [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
            M = np.eye(4)
            M[:3, :3] = R * s
            M[:3, 3] = t
            return M

        def world(i):
            if i in cache:
                return cache[i]
            M = local(nodes[i])
            if i in parent:
                M = world(parent[i]) @ M
            cache[i] = M
            return M

        return {i: world(i) for i in range(len(nodes))}

    def primitives(self):
        """(material_index, positions_world Nx3, uv Nx2 | None, indices Mx3) для каждого примитива."""
        W = self.node_world_matrices()
        out = []
        for ni, n in enumerate(self.json.get("nodes", [])):
            if "mesh" not in n:
                continue
            M = W[ni] if "skin" not in n else np.eye(4) * 1.0
            if "skin" in n:   # у скин-мешей трансформ узла игнорируется — берём масштаб корня
                M = np.eye(4)
            mesh = self.json["meshes"][n["mesh"]]
            for p in mesh["primitives"]:
                at = p["attributes"]
                if "POSITION" not in at:
                    continue
                pos = self.accessor(at["POSITION"])[:, :3]
                pos = (np.c_[pos, np.ones(len(pos))] @ M.T)[:, :3]
                uv = self.accessor(at["TEXCOORD_0"])[:, :2] if "TEXCOORD_0" in at else None
                if "indices" in p:
                    idx = self.accessor(p["indices"]).reshape(-1).astype(np.int64)
                else:
                    idx = np.arange(len(pos))
                idx = idx[: len(idx) // 3 * 3].reshape(-1, 3)
                out.append((p.get("material", -1), pos, uv, idx))
        return out

    # ---------- запись
    def save(self, path: str) -> None:
        pend = getattr(self, "_pending", {})
        views = self.json["bufferViews"]
        blobs = []
        cur = 0
        for vi, v in enumerate(views):
            data = pend.get(vi, self.view_bytes(vi))
            pad = (-cur) % 4
            if pad:
                blobs.append(b"\0" * pad)
                cur += pad
            v["byteOffset"] = cur
            v["byteLength"] = len(data)
            blobs.append(data)
            cur += len(data)
        newbin = b"".join(blobs)
        newbin += b"\0" * ((-len(newbin)) % 4)
        self.json["buffers"][0]["byteLength"] = len(newbin)
        js = json.dumps(self.json, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        js += b" " * ((-len(js)) % 4)
        total = 12 + 8 + len(js) + 8 + len(newbin)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A))
            f.write(js)
            f.write(struct.pack("<II", len(newbin), 0x004E4942))
            f.write(newbin)
        self.bin = newbin
        self._pending = {}
