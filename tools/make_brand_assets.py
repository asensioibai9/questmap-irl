#!/usr/bin/env python3
"""Genera la marca de la app a partir de UNA geometría (la misma que BrandMark.swift):

  docs/branding/app-icon-master.svg      recurso vectorial maestro
  QuestMapIRL/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png   1024x1024 RGB, sin transparencia
  QuestMapIRL/Resources/Assets.xcassets/LaunchMark.imageset/*.png        pin+flecha con fondo transparente

Símbolo: una chincheta de ubicación (dorada) con una flecha de navegación recortada, de pie
sobre un anillo de ruta magenta. Diseño propio, sin texto ni elementos de otras marcas.
Requisitos de destino: icono de iOS 1024x1024 px, sin canal alfa y sin esquinas redondeadas
(iOS aplica la máscara). Dependencias: Pillow y numpy.
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "QuestMapIRL" / "Resources" / "Assets.xcassets"

# --- Geometría normalizada (0..1), compartida con BrandMark.swift ---------------
CX, CY, R, TIP_Y = 0.5, 0.42, 0.215, 0.80
RING_C, RING_RX, RING_RY, RING_W = (0.5, 0.815), 0.215, 0.072, 0.034
ARROW = [(0.5, 0.285), (0.592, 0.525), (0.5, 0.462), (0.408, 0.525)]

BG_CENTER, BG_EDGE = (0x1D, 0x22, 0x33), (0x0A, 0x0A, 0x1A)   # coincide con LaunchBackground
GOLD_TOP, GOLD_BOTTOM = (0xFF, 0xDF, 0x7A), (0xF0, 0xA2, 0x2E)
MAGENTA = (0xF2, 0x3F, 0xC4)


def pin_polygon(samples: int = 96):
    d = TIP_Y - CY
    theta = math.acos(R / d)
    rx, ry = R * math.sin(theta), R * math.cos(theta)
    pts = [(CX - rx, CY + ry), (CX, TIP_Y), (CX + rx, CY + ry)]
    a0 = math.atan2(ry, rx)
    a1 = math.pi - a0
    sweep = (a1 - 2 * math.pi) - a0
    for i in range(1, samples):
        a = a0 + sweep * i / samples
        pts.append((CX + R * math.cos(a), CY + R * math.sin(a)))
    return pts


def scaled(points, size):
    return [(x * size, y * size) for x, y in points]


def vertical_gradient(size, top, bottom, y0, y1):
    ys = np.linspace(0, 1, size)[:, None]
    t = np.clip((ys - y0) / (y1 - y0), 0, 1)
    arr = np.zeros((size, size, 3), dtype=np.float32)
    for c in range(3):
        arr[:, :, c] = (top[c] * (1 - t) + bottom[c] * t) * np.ones((1, size))
    return Image.fromarray(arr.astype(np.uint8), "RGB")


def radial_background(size):
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32) / size
    dist = np.clip(np.sqrt((xs - 0.5) ** 2 + (ys - 0.42) ** 2) / 0.75, 0, 1)
    arr = np.zeros((size, size, 3), dtype=np.float32)
    for c in range(3):
        arr[:, :, c] = BG_CENTER[c] * (1 - dist) + BG_EDGE[c] * dist
    return Image.fromarray(arr.astype(np.uint8), "RGB")


def draw_mark(size, with_background):
    """Dibuja ring + pin + flecha a `size` px. Devuelve RGBA."""
    big = size * 4
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    if with_background:
        canvas.paste(radial_background(big).convert("RGBA"))

    # Anillo de ruta
    ring = Image.new("L", (big, big), 0)
    rd = ImageDraw.Draw(ring)
    cx, cy = RING_C[0] * big, RING_C[1] * big
    rx, ry, w = RING_RX * big, RING_RY * big, RING_W * big
    rd.ellipse([cx - rx - w / 2, cy - ry - w / 2, cx + rx + w / 2, cy + ry + w / 2], fill=255)
    rd.ellipse([cx - rx + w / 2, cy - ry + w / 2, cx + rx - w / 2, cy + ry - w / 2], fill=0)
    canvas.paste(Image.new("RGBA", (big, big), MAGENTA + (255,)), mask=ring)

    # Chincheta con degradado dorado
    pin_mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(pin_mask).polygon(scaled(pin_polygon(), big), fill=255)
    gold = vertical_gradient(big, GOLD_TOP, GOLD_BOTTOM, CY - R, TIP_Y).convert("RGBA")
    canvas.paste(gold, mask=pin_mask)

    # Flecha de navegación recortada (transparente o color de fondo)
    arrow_mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(arrow_mask).polygon(scaled(ARROW, big), fill=255)
    if with_background:
        canvas.paste(Image.new("RGBA", (big, big), BG_EDGE + (255,)), mask=arrow_mask)
    else:
        alpha = canvas.getchannel("A")
        alpha.paste(0, mask=arrow_mask)
        canvas.putalpha(alpha)
    return canvas.resize((size, size), Image.LANCZOS)


def svg_master():
    def pts(points, scale=1024):
        return " ".join(f"{x * scale:.1f},{y * scale:.1f}" for x, y in points)

    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <title>QuestMap IRL - icono maestro</title>
  <defs>
    <radialGradient id="bg" cx="0.5" cy="0.42" r="0.75">
      <stop offset="0" stop-color="#{''.join(f'{v:02x}' for v in BG_CENTER)}"/>
      <stop offset="1" stop-color="#{''.join(f'{v:02x}' for v in BG_EDGE)}"/>
    </radialGradient>
    <linearGradient id="gold" gradientUnits="userSpaceOnUse" x1="0" y1="{(CY - R) * 1024:.1f}" x2="0" y2="{TIP_Y * 1024:.1f}">
      <stop offset="0" stop-color="#{''.join(f'{v:02x}' for v in GOLD_TOP)}"/>
      <stop offset="1" stop-color="#{''.join(f'{v:02x}' for v in GOLD_BOTTOM)}"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <ellipse cx="{RING_C[0] * 1024:.1f}" cy="{RING_C[1] * 1024:.1f}" rx="{RING_RX * 1024:.1f}" ry="{RING_RY * 1024:.1f}"
           fill="none" stroke="#{''.join(f'{v:02x}' for v in MAGENTA)}" stroke-width="{RING_W * 1024:.1f}"/>
  <polygon points="{pts(pin_polygon())}" fill="url(#gold)"/>
  <polygon points="{pts(ARROW)}" fill="#{''.join(f'{v:02x}' for v in BG_EDGE)}"/>
</svg>
"""


def main():
    # Icono principal: 1024x1024, RGB (sin alfa), sin esquinas redondeadas.
    icon = draw_mark(1024, with_background=True).convert("RGB")
    assert icon.size == (1024, 1024) and icon.mode == "RGB"
    out = ASSETS / "AppIcon.appiconset"
    out.mkdir(parents=True, exist_ok=True)
    icon.save(out / "AppIcon.png", "PNG")

    # Marca de lanzamiento: pin + flecha transparente, SIN anillo (la animación lo dibuja).
    launch_dir = ASSETS / "LaunchMark.imageset"
    launch_dir.mkdir(parents=True, exist_ok=True)
    for scale in (1, 2, 3):
        size = 120 * scale
        big = size * 4
        canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        pin_mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(pin_mask).polygon(scaled(pin_polygon(), big), fill=255)
        canvas.paste(vertical_gradient(big, GOLD_TOP, GOLD_BOTTOM, CY - R, TIP_Y).convert("RGBA"), mask=pin_mask)
        arrow_mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(arrow_mask).polygon(scaled(ARROW, big), fill=255)
        alpha = canvas.getchannel("A")
        alpha.paste(0, mask=arrow_mask)
        canvas.putalpha(alpha)
        canvas.resize((size, size), Image.LANCZOS).save(launch_dir / f"LaunchMark@{scale}x.png", "PNG")

    brand = ROOT / "docs" / "branding"
    brand.mkdir(parents=True, exist_ok=True)
    (brand / "app-icon-master.svg").write_text(svg_master(), encoding="utf-8")
    icon.resize((256, 256), Image.LANCZOS).save(brand / "app-icon-preview-256.png", "PNG")
    print("OK: AppIcon.png", icon.size, icon.mode, "| LaunchMark @1x/2x/3x | app-icon-master.svg")


if __name__ == "__main__":
    main()
