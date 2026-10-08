#!/usr/bin/env python3
"""Merge the four separate martyr animation .glb files into one martyr.glb.

Each source file is a self-contained glTF binary carrying the same mesh,
skeleton and node list, plus exactly one animation named
``Reconstructed_Action`` (idle / run / slap / sillyrun).  Because the node
lists are identical across the files, only the animation accessors and their
buffer views need to be carried over -- no node remapping is required.

Output clips are named ``idle``, ``run``, ``slap`` and ``sillyrun``.
"""
import json
import os
import struct
import sys

GLB_MAGIC = 0x46546C67      # "glTF"
CHUNK_JSON = 0x4E4F534A    # "JSON"
CHUNK_BIN = 0x004E4942     # "BIN\0"


def read_glb(path):
    with open(path, "rb") as fh:
        data = fh.read()
    magic, version, total = struct.unpack_from("<III", data, 0)
    assert magic == GLB_MAGIC, "bad glb magic in %s" % path
    assert version == 2, "unexpected glTF version %d in %s" % (version, path)
    assert total == len(data), "header length mismatch in %s" % path
    off = 12
    json_bytes = None
    bin_bytes = b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == CHUNK_JSON:
            json_bytes = chunk
        elif ctype == CHUNK_BIN:
            bin_bytes = chunk
    assert json_bytes is not None, "no JSON chunk in %s" % path
    return json.loads(json_bytes.decode("utf-8")), bin_bytes


def _pad(raw, n=4):
    r = len(raw) % n
    return raw if r == 0 else raw + b"\x00" * (n - r)


def write_glb(path, gltf, bin_bytes):
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js_p = _pad(js)
    bin_p = _pad(bytes(bin_bytes))
    total = 12 + 8 + len(js_p) + 8 + len(bin_p)
    out = bytearray()
    out += struct.pack("<III", GLB_MAGIC, 2, total)
    out += struct.pack("<II", len(js_p), CHUNK_JSON)
    out += js_p
    out += struct.pack("<II", len(bin_p), CHUNK_BIN)
    out += bin_p
    with open(path, "wb") as fh:
        fh.write(out)


def names(gltf):
    return [n.get("name") for n in gltf.get("nodes", [])]


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    unit_dir = os.path.dirname(here)

    # Base carries the mesh/skeleton and becomes the "idle" clip.
    base_gltf, base_bin = read_glb(os.path.join(unit_dir, "idle.glb"))
    base_bin = bytearray(base_bin)
    base_names = names(base_gltf)

    assert len(base_gltf.get("animations", [])) == 1, "expected exactly one animation in base"
    base_gltf["animations"][0]["name"] = "idle"

    # Sanity: every file shares the base node list, so animation node targets
    # stay valid in the merged file unchanged.
    for extra in ("run", "slap", "sillyrun"):
        g, _ = read_glb(os.path.join(unit_dir, extra + ".glb"))
        assert names(g) == base_names, "node list differs in %s.glb" % extra
        assert len(g.get("animations", [])) == 1, "expected one animation in %s.glb" % extra

    accs = base_gltf.setdefault("accessors", [])
    views = base_gltf.setdefault("bufferViews", [])

    for clip in ("run", "slap", "sillyrun"):
        src_gltf, src_bin = read_glb(os.path.join(unit_dir, clip + ".glb"))
        src_anim = src_gltf["animations"][0]

        # Collect every accessor the animation references (input timestamps plus
        # the per-bone output tracks).
        needed = set()
        for s in src_anim["samplers"]:
            needed.add(s["input"])
            needed.add(s["output"])

        accessor_map = {}
        view_map = {}
        for ai in sorted(needed):
            acc = src_gltf["accessors"][ai]
            view = src_gltf["bufferViews"][acc.get("bufferView")]
            new_view = view_map.get(acc["bufferView"])
            if new_view is None:
                start = view.get("byteOffset", 0)
                length = view["byteLength"]
                while len(base_bin) % 4:  # keep float data 4-byte aligned
                    base_bin.append(0)
                new_offset = len(base_bin)
                base_bin += src_bin[start:start + length]
                added = dict(view)
                added["byteOffset"] = new_offset
                views.append(added)
                new_view = len(views) - 1
                view_map[acc["bufferView"]] = new_view

            new_acc = dict(acc)
            new_acc["bufferView"] = new_view
            accs.append(new_acc)
            accessor_map[ai] = len(accs) - 1

        # Deep-copy the animation, rename it, remap sampler references.
        new_anim = json.loads(json.dumps(src_anim))
        new_anim["name"] = clip
        for s in new_anim["samplers"]:
            s["input"] = accessor_map[s["input"]]
            s["output"] = accessor_map[s["output"]]
        base_gltf["animations"].append(new_anim)

    base_gltf["buffers"][0]["byteLength"] = len(base_bin)
    out_path = os.path.join(unit_dir, "martyr.glb")
    write_glb(out_path, base_gltf, bytes(base_bin))

    # Report what was produced so the caller can validate.
    merged, _ = read_glb(out_path)
    print("wrote %s (%d bytes)" % (out_path, os.path.getsize(out_path)))
    for anim in merged["animations"]:
        times = []
        for s in anim["samplers"]:
            tacc = merged["accessors"][s["input"]]
            times.append((tacc.get("min", [tacc.get("min")])[0] if isinstance(tacc.get("min"), list)
                          else tacc.get("min")))
        low = min((t for t in times if t is not None), default=None)
        high = max((t for t in times if t is not None), default=None)
        print("  %-10s channels=%d duration=%s..%s" % (
            anim["name"], len(anim["channels"]),
            "%.3f" % low if low is not None else "?",
            "%.3f" % high if high is not None else "?"))
    print("accessors=%d bufferViews=%d bufferBytes=%d" % (
        len(merged["accessors"]), len(merged["bufferViews"]),
        merged["buffers"][0]["byteLength"]))


if __name__ == "__main__":
    sys.exit(main())