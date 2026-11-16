#!/usr/bin/env python3
"""Genera las miniaturas de la galería de estilos de la Fase 4.

Son ESQUEMAS procedurales (manzanas, vías por rango, agua y ruta) dibujados con la paleta real de cada
estilo: no son capturas de la app ni de ningún juego. Salida: Assets.xcassets/StylePreview<Nombre>.imageset
Uso: python tools/make_style_previews.py   (requiere Pillow)
"""
import importlib.util
import json
import random
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "QuestMapIRL" / "Resources" / "Assets.xcassets"
spec = importlib.util.spec_from_file_location("build_styles", ROOT / "tools" / "build_styles.py")
bs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bs)

W, H = 1200, 560
TARGETS = [("StylePreviewOeste", bs.OESTE), ("StylePreviewCiber", bs.CIBER), ("StylePreviewFantasia", bs.NORDICO),
           ("StylePreviewRed", bs.RED), ("StylePreviewRally", bs.RALLY)]


def draw(cfg, seed):
    p = cfg["palette"]
    r = random.Random(seed)
    img = Image.new("RGB", (W, H), p["land"])
    d = ImageDraw.Draw(img)
    # Agua: una curva ancha en diagonal
    d.polygon([(0, 380), (380, 300), (760, 470), (1200, 400), (1200, 560), (0, 560)], fill=p["water"])
    d.line([(0, 380), (380, 300), (760, 470), (1200, 400)], fill=p["water_edge"], width=4)
    # Manzanas
    xs = [60 + i * 150 for i in range(8)]
    for x in xs:
        for y in (40, 150, 260):
            if r.random() < 0.85:
                d.rectangle([x, y, x + 110 + r.randint(-14, 8), y + 80 + r.randint(-12, 8)], fill=p["building"])
    # Vías: cuadrícula con una avenida
    cas = p["casing"]
    for y in (130, 240):
        if not cfg.get("no_casing"):
            d.line([(0, y), (W, y)], fill=cas, width=22)
        d.line([(0, y), (W, y)], fill=p["road"]["secondary"], width=16 if not cfg.get("no_casing") else 4)
    for x in (20, 215, 520, 815, 1100):
        if not cfg.get("no_casing"):
            d.line([(x, 0), (x, 330)], fill=cas, width=18)
        d.line([(x, 0), (x, 330)], fill=p["road"]["tertiary"], width=12 if not cfg.get("no_casing") else 3)
    if not cfg.get("no_casing"):
        d.line([(0, 330), (W, 120)], fill=cas, width=34)
    d.line([(0, 330), (W, 120)], fill=p["road"]["motorway"], width=26 if not cfg.get("no_casing") else 7)
    # Ruta
    rt = cfg["route"]
    pts = [(120, 500), (120, 240), (520, 240), (520, 130), (1000, 130)]
    d.line(pts, fill=rt["casing"], width=22, joint="curve")
    d.line(pts, fill=rt["core"], width=13, joint="curve")
    d.ellipse([1000 - 20, 130 - 20, 1000 + 20, 130 + 20], fill=cfg["destination"]["color"], outline=cfg["destination"]["stroke"], width=5)
    return img


def save(name, img):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    img.save(folder / f"{name}.png", "PNG", optimize=True)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1}}, indent=2), encoding="utf-8")


if __name__ == "__main__":
    for i, (name, cfg) in enumerate(TARGETS):
        save(name, draw(cfg, 40 + i))
        print(name)
