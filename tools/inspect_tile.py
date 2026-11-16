#!/usr/bin/env python3
"""Inspecciona un tile vectorial (MVT) real y lista capas, geometrías y valores de las
propiedades que usan los estilos. Sin dependencias externas: decodificador mínimo de protobuf.

Uso:  python tools/inspect_tile.py <z> <x> <y> [url_base]
Por defecto usa el TileJSON público de OpenFreeMap para resolver la versión actual.
"""
import gzip
import json
import math
import sys
import urllib.request
from collections import defaultdict

TILEJSON = "https://tiles.openfreemap.org/planet/latest"
UA = {"User-Agent": "QuestMapIRL-tooling/1.0"}


def fetch(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    return data


def varint(buf, i):
    shift = result = 0
    while True:
        b = buf[i]
        i += 1
        result |= (b & 0x7F) << shift
        if not b & 0x80:
            return result, i
        shift += 7


def fields(buf):
    """Itera (número_de_campo, wire_type, valor) de un mensaje protobuf."""
    i = 0
    while i < len(buf):
        key, i = varint(buf, i)
        fn, wt = key >> 3, key & 7
        if wt == 0:
            v, i = varint(buf, i)
        elif wt == 2:
            ln, i = varint(buf, i)
            v = buf[i:i + ln]
            i += ln
        elif wt == 5:
            v = buf[i:i + 4]
            i += 4
        elif wt == 1:
            v = buf[i:i + 8]
            i += 8
        else:
            raise ValueError(f"wire type {wt}")
        yield fn, wt, v


def zigzag(n):
    return (n >> 1) ^ -(n & 1)


def decode_value(buf):
    for fn, wt, v in fields(buf):
        if fn == 1:
            return v.decode("utf-8")
        if fn in (2, 3):  # float, double
            return "<float>"
        if fn == 4:
            return v
        if fn == 5:
            return v
        if fn == 6:
            return zigzag(v)
        if fn == 7:
            return bool(v)
    return None


GEOM = {1: "Point", 2: "LineString", 3: "Polygon"}


def decode_tile(buf):
    layers = {}
    for fn, wt, v in fields(buf):
        if fn != 3:
            continue
        name, keys, values, feats, extent = None, [], [], [], 4096
        for lf, lw, lv in fields(v):
            if lf == 1:
                name = lv.decode()
            elif lf == 2:
                feats.append(lv)
            elif lf == 3:
                keys.append(lv.decode())
            elif lf == 4:
                values.append(decode_value(lv))
            elif lf == 5:
                extent = lv
        parsed = []
        for fb in feats:
            gtype, tags = 0, []
            for ff, fw, fv in fields(fb):
                if ff == 3:
                    gtype = fv
                elif ff == 2:
                    # tags empaquetados
                    j = 0
                    while j < len(fv):
                        t, j = varint(fv, j)
                        tags.append(t)
            props = {}
            for a in range(0, len(tags) - 1, 2):
                props[keys[tags[a]]] = values[tags[a + 1]]
            parsed.append((GEOM.get(gtype, "?"), props))
        layers[name] = parsed
    return layers


def main():
    z, x, y = (int(a) for a in sys.argv[1:4])
    if len(sys.argv) > 4:
        base = sys.argv[4]
    else:
        base = json.loads(fetch(TILEJSON))["tiles"][0]
    url = base.replace("{z}", str(z)).replace("{x}", str(x)).replace("{y}", str(y))
    print("tile:", url)
    layers = decode_tile(fetch(url))
    wanted = ["transportation", "poi", "landuse", "landcover", "park", "water", "waterway",
              "building", "place", "transportation_name", "aeroway"]
    for name in wanted:
        feats = layers.get(name, [])
        print(f"\n== {name}: {len(feats)} features")
        geoms = defaultdict(int)
        by_key = defaultdict(lambda: defaultdict(int))
        for g, props in feats:
            geoms[g] += 1
            for k in ("class", "subclass", "brunnel", "ramp", "expressway", "oneway", "layer", "network"):
                if k in props:
                    by_key[k][str(props[k])] += 1
        print("   geometrías:", dict(geoms))
        for k, vals in by_key.items():
            top = sorted(vals.items(), key=lambda kv: -kv[1])[:25]
            print(f"   {k}:", ", ".join(f"{a}({b})" for a, b in top))
        if name == "building" and feats:
            hs = [p.get("render_height") for _, p in feats if "render_height" in p]
            print("   render_height ejemplo:", hs[:8])


if __name__ == "__main__":
    main()
