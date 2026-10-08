#!/usr/bin/env python3
"""Validate merged martyr.glb: animation names, timings, and reference integrity."""
import json
import os
import struct
import sys

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def read_glb(path):
    with open(path, "rb") as fh:
        data = fh.read()
    magic, version, total = struct.unpack_from("<III", data, 0)
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
    return json.loads(json_bytes.decode("utf-8")), bin_bytes, total, len(bin_bytes)


def main():
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "martyr.glb")
    gltf, bin_bytes, total, bin_len = read_glb(path)
    n_nodes = len(gltf.get("nodes", []))
    n_acc = len(gltf.get("accessors", []))
    n_views = len(gltf.get("bufferViews", []))
    buf_len = gltf["buffers"][0]["byteLength"]
    print("nodes=%d accessors=%d bufferViews=%d bufferBytes=%d (bin chunk %d, header total %d)"
          % (n_nodes, n_acc, n_views, buf_len, bin_len, total))
    ok = True
    names_wanted = ["idle", "run", "slap", "sillyrun"]
    names_got = [a.get("name") for a in gltf.get("animations", [])]
    print("animations:", names_got)
    if names_got != names_wanted:
        ok = False
        print("  FAIL: animation names/order mismatch")
    for anim in gltf.get("animations", []):
        rng = [None, None]
        for s in anim.get("samplers", []):
            iacc = gltf["accessors"][s["input"]]
            mn = iacc.get("min")
            mx = iacc.get("max")
            if isinstance(mn, list) and mn:
                rng[0] = mn[0] if rng[0] is None else min(rng[0], mn[0])
            if isinstance(mx, list) and mx:
                rng[1] = mx[0] if rng[1] is None else max(rng[1], mx[0])
            if s["input"] >= n_acc or s["output"] >= n_acc:
                ok = False
                print("  FAIL: sampler accessor out of range in", anim["name"])
        for c in anim.get("channels", []):
            if c["target"]["node"] >= n_nodes:
                ok = False
                print("  FAIL: channel target node out of range in", anim["name"])
        dur = (rng[1] - rng[0]) if (rng[0] is not None and rng[1] is not None) else None
        print("  %-10s %d channels, time %.3f..%.3f (dur %.3f s)"
              % (anim["name"], len(anim.get("channels", [])),
                 rng[0] or 0.0, rng[1] or 0.0, dur or 0.0))
    for i, v in enumerate(gltf.get("bufferViews", [])):
        if v.get("byteOffset", 0) + v["byteLength"] > buf_len:
            ok = False
            print("  FAIL: bufferView %d overruns buffer" % i)
    for i, a in enumerate(gltf.get("accessors", [])):
        if a.get("bufferView", -1) >= n_views:
            ok = False
            print("  FAIL: accessor %d bufferView out of range" % i)
    print("RESULT:", "OK" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())