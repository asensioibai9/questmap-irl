#!/usr/bin/env python3
"""Valida un estilo contra el esquema real del proveedor (TileJSON vector_layers).

Comprueba: JSON válido, version 8, ids de capa únicos, fuentes definidas, source-layers que
existen en el proveedor, campos usados en expresiones `get` que existen en cada capa,
tipografías permitidas y que no quedan placeholders sin sustituir salvo los conocidos.

Uso:  python tools/validate_style.py QuestMapIRL/Resources/style-ciudad-nocturna.json ...
"""
import json
import re
import sys
import urllib.request

TILEJSON = "https://tiles.openfreemap.org/planet/latest"
ALLOWED_FONTS = {"Noto Sans Regular", "Noto Sans Bold", "Noto Sans Italic"}  # los que sirve el proveedor
KNOWN_PLACEHOLDERS = {"{{TILES_URL}}", "{{GLYPHS_URL}}"}
# Campos que no vienen del tile sino de la propia expresión (geometría, zoom, etc.)
SKIP_FIELDS = set()


def load_schema():
    req = urllib.request.Request(TILEJSON, headers={"User-Agent": "QuestMapIRL-tooling/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        tj = json.load(r)
    return {l["id"]: set(l.get("fields", {})) for l in tj["vector_layers"]}


def walk_gets(expr, out):
    if isinstance(expr, list):
        if len(expr) == 2 and expr[0] == "get" and isinstance(expr[1], str):
            out.add(expr[1])
        for item in expr:
            walk_gets(item, out)
    elif isinstance(expr, dict):
        for v in expr.values():
            walk_gets(v, out)


def validate(path, schema):
    errors = []
    raw = open(path, encoding="utf-8").read()
    style = json.loads(raw)
    if style.get("version") != 8:
        errors.append("version != 8")
    for ph in set(re.findall(r"\{\{[A-Z_]+\}\}", raw)) - KNOWN_PLACEHOLDERS:
        errors.append(f"placeholder desconocido {ph}")
    ids = [l["id"] for l in style["layers"]]
    if len(ids) != len(set(ids)):
        errors.append("ids de capa duplicados")
    sources = style["sources"]
    for layer in style["layers"]:
        lid = layer["id"]
        src = layer.get("source")
        if layer["type"] != "background" and src not in sources:
            errors.append(f"{lid}: fuente '{src}' no definida")
        sl = layer.get("source-layer")
        if sl:
            if sl not in schema:
                errors.append(f"{lid}: source-layer '{sl}' no existe en el proveedor")
            else:
                used = set()
                for key in ("filter", "paint", "layout"):
                    walk_gets(layer.get(key), used)
                missing = {f for f in used if f not in schema[sl] and f not in SKIP_FIELDS}
                if missing:
                    errors.append(f"{lid}: campos inexistentes en '{sl}': {sorted(missing)}")
        for font in layer.get("layout", {}).get("text-font", []):
            if font not in ALLOWED_FONTS:
                errors.append(f"{lid}: fuente '{font}' no servida por el proveedor")
    return errors, len(style["layers"])


def main():
    schema = load_schema()
    ok = True
    for path in sys.argv[1:]:
        errors, count = validate(path, schema)
        if errors:
            ok = False
            print(f"FALLA {path}")
            for e in errors:
                print("  -", e)
        else:
            print(f"OK    {path} ({count} capas)")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
