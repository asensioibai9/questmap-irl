#!/usr/bin/env python3
"""Genera las texturas procedurales (PNG tileables, con alfa) que superponen los estilos
Isla y Mundo de bloques mediante `fill-pattern`. Son dibujos propios generados por código:
no se ha copiado ninguna textura de ningún juego.

Salida: QuestMapIRL/Resources/Assets.xcassets/<nombre>.imageset/<nombre>.png
Uso:    python tools/make_textures.py   (requiere Pillow y numpy)
"""
import json
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "QuestMapIRL" / "Resources" / "Assets.xcassets"
rng = np.random.default_rng(7)
random.seed(7)


def save(name, image):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / f"{name}.png", "PNG")
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1}}, indent=2), encoding="utf-8")


def tileable_noise(size, sigma):
    """Ruido suavizado y periódico (sin costuras) en [0, 1]."""
    base = rng.random((size, size))
    freq = np.fft.fftfreq(size)[:, None] ** 2 + np.fft.fftfreq(size)[None, :] ** 2
    smooth = np.real(np.fft.ifft2(np.fft.fft2(base) * np.exp(-freq * (2 * np.pi * sigma) ** 2 / 2)))
    smooth -= smooth.min()
    return smooth / smooth.max()


def wrap_circle(draw, size, cx, cy, r, fill):
    for dx in (-size, 0, size):
        for dy in (-size, 0, size):
            draw.ellipse([cx + dx - r, cy + dy - r, cx + dx + r, cy + dy + r], fill=fill)


def canopy(size=128):
    """Copas de árbol vistas desde arriba: manchas redondas verdes con sombra."""
    img = Image.new("RGBA", (size, size), (20, 60, 22, 0))
    d = ImageDraw.Draw(img)
    for _ in range(46):
        cx, cy, r = random.randint(0, size), random.randint(0, size), random.randint(6, 11)
        wrap_circle(d, size, cx + 2, cy + 3, r, (10, 38, 14, 150))          # sombra
    for _ in range(46):
        cx, cy, r = random.randint(0, size), random.randint(0, size), random.randint(6, 11)
        shade = random.choice([(40, 104, 36, 235), (52, 120, 40, 235), (34, 88, 32, 235)])
        wrap_circle(d, size, cx, cy, r, shade)
        wrap_circle(d, size, cx - 2, cy - 2, max(2, r // 2), (92, 160, 62, 160))  # luz
    return img


def grass(size=128):
    """Variación suave de hierba: manchas claras y oscuras con poca opacidad."""
    n = tileable_noise(size, 6)
    fine = tileable_noise(size, 1.6)
    v = 0.65 * n + 0.35 * fine
    rgba = np.zeros((size, size, 4), dtype=np.uint8)
    light = v > 0.5
    rgba[..., 0] = np.where(light, 170, 40)
    rgba[..., 1] = np.where(light, 214, 90)
    rgba[..., 2] = np.where(light, 70, 24)
    rgba[..., 3] = (np.abs(v - 0.5) * 2 * 120).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


# ---- Mundo de bloques: texturas de 16 x 16 "píxeles" de 4 px ----------------
def blocky(size, cells, palette, weights=None, alpha=255):
    cell = size // cells
    img = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(img)
    for x in range(cells):
        for y in range(cells):
            color = random.choices(palette, weights=weights)[0]
            d.rectangle([x * cell, y * cell, (x + 1) * cell - 1, (y + 1) * cell - 1], fill=color + (alpha,))
    return img


def main():
    save("tex-canopy", canopy())
    save("tex-grass", grass())
    save("tex-block-grass", blocky(64, 16, [(104, 160, 58), (96, 150, 52), (112, 170, 64), (88, 140, 48)], [4, 3, 2, 2]))
    save("tex-block-leaves", blocky(64, 16, [(44, 104, 30), (36, 90, 26), (54, 120, 36), (28, 76, 22)], [3, 3, 2, 2]))
    save("tex-block-water", blocky(64, 16, [(46, 78, 178), (52, 88, 190), (40, 70, 166)], [4, 3, 2]))
    save("tex-block-sand", blocky(64, 16, [(220, 205, 150), (212, 196, 140), (228, 214, 162)], [4, 3, 2]))
    save("tex-block-path", blocky(64, 16, [(134, 100, 62), (122, 90, 54), (146, 110, 70), (110, 82, 50)], [3, 3, 2, 2]))
    save("tex-block-stone", blocky(64, 16, [(128, 128, 128), (118, 118, 118), (138, 138, 138), (106, 106, 106)], [3, 3, 2, 2]))
    save("tex-block-planks", blocky(64, 16, [(168, 130, 78), (156, 120, 70), (178, 140, 86)], [3, 3, 2]))
    print("Texturas generadas en", ASSETS)


if __name__ == "__main__":
    main()
