#!/usr/bin/env python3
"""Genera la familia de iconos PROPIA del estilo «Ciudad nocturna» (lenguaje de mapa de videojuego):
siluetas compactas, contorno oscuro marcado, pocos detalles y un color de acento por categoría.
Dibujados por código; no se ha copiado ningún icono ni archivo de ningún juego.

Salida:
  QuestMapIRL/Resources/Assets.xcassets/gta-<nombre>.imageset/gta-<nombre>.png   (96x96 px, se registran a @3x)
  docs/branding/poi-icons-contact-sheet.png                                       (hoja para revisar)
Uso: python tools/make_poi_icons.py        (Pillow; familia GTA V)
     python tools/make_poi_icons.py --vi   (familia GTA VI: gta6-poi-*)
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "QuestMapIRL" / "Resources" / "Assets.xcassets"
GRID = 64          # coordenadas de diseño
OUT = 96           # px de salida (a @3x = 32 pt)
SS = 4             # supersampling
OUTLINE = (12, 12, 12, 255)
LIGHT = (232, 232, 232, 255)
DARK = (28, 28, 28, 255)
WHITE = (255, 255, 255, 255)


def S(v):
    return v * OUT * SS / GRID


def box(draw, x0, y0, x1, y1, fill=255, radius=0):
    if radius:
        draw.rounded_rectangle([S(x0), S(y0), S(x1), S(y1)], radius=S(radius), fill=fill)
    else:
        draw.rectangle([S(x0), S(y0), S(x1), S(y1)], fill=fill)


def poly(draw, pts, fill=255):
    draw.polygon([(S(x), S(y)) for x, y in pts], fill=fill)


def oval(draw, x0, y0, x1, y1, fill=255):
    draw.ellipse([S(x0), S(y0), S(x1), S(y1)], fill=fill)


def line(draw, pts, width, fill=255):
    draw.line([(S(x), S(y)) for x, y in pts], fill=fill, width=int(S(width)), joint="curve")


# Cada glifo devuelve (máscara_base, máscara_detalle). El detalle se pinta con `detail_color`.
def g_house(b, d):
    poly(b, [(6, 31), (32, 8), (58, 31), (52, 31), (52, 56), (12, 56), (12, 31)])
    box(d, 27, 38, 37, 56)          # puerta (detalle oscuro)
    box(b, 44, 12, 50, 24)          # chimenea


def g_work(b, d):
    box(b, 7, 22, 57, 54, radius=5)
    box(b, 22, 11, 42, 24, radius=4)
    box(b, 27, 16, 37, 24, fill=0)  # hueco del asa
    box(d, 7, 35, 57, 39)           # franja
    box(d, 29, 33, 35, 42)


def g_shop(b, d):
    poly(b, [(10, 24), (54, 24), (50, 56), (14, 56)])
    line(b, [(22, 24), (22, 17), (32, 10), (42, 17), (42, 24)], 5)
    box(d, 24, 32, 28, 44)
    box(d, 36, 32, 40, 44)


def g_food(b, d):
    for x in (12, 18, 24):
        box(b, x, 8, x + 3, 26)    # púas del tenedor
    box(b, 12, 22, 27, 30, radius=3)
    box(b, 17, 26, 22, 56, radius=2)
    poly(b, [(40, 8), (46, 8), (50, 12), (50, 32), (46, 32), (46, 56), (40, 56), (40, 32), (38, 32), (38, 14)])


def g_bar(b, d):
    poly(b, [(8, 10), (56, 10), (32, 36)])
    box(b, 29, 34, 35, 52)
    box(b, 18, 52, 46, 57, radius=2)
    line(d, [(38, 4), (28, 24)], 2.5)   # pajita
    oval(d, 36, 16, 44, 24)


def g_fuel(b, d):
    box(b, 11, 9, 40, 56, radius=4)
    box(d, 17, 15, 34, 29)
    line(b, [(40, 24), (50, 24), (50, 44)], 5)
    oval(b, 45, 40, 55, 50)
    box(b, 7, 52, 44, 58, radius=2)


def g_parking(b, d):
    box(b, 7, 7, 57, 57, radius=10)
    box(d, 22, 15, 29, 50)
    oval(d, 22, 15, 47, 40)
    oval(b, 29, 22, 40, 33)         # hueco de la P (base visible)


def g_hospital(b, d):
    box(b, 7, 7, 57, 57, radius=10)
    box(d, 26, 14, 38, 50)
    box(d, 14, 26, 50, 38)


def g_train(b, d):
    box(b, 12, 8, 52, 46, radius=9)
    box(d, 17, 14, 47, 28, radius=3)
    oval(d, 19, 33, 26, 40)
    oval(d, 38, 33, 45, 40)
    line(b, [(18, 46), (10, 58)], 4)
    line(b, [(46, 46), (54, 58)], 4)
    box(b, 8, 54, 56, 58, radius=2)


def g_bank(b, d):
    poly(b, [(6, 24), (32, 7), (58, 24)])
    for x in (12, 29, 46):
        box(b, x, 28, x + 6, 48)
    box(b, 6, 51, 58, 58, radius=2)
    oval(d, 28, 14, 36, 22)


def g_destination(b, d):
    oval(b, 12, 6, 52, 46)
    poly(b, [(17, 36), (47, 36), (32, 60)])
    oval(d, 24, 18, 40, 34)


def g_cup(b, d):
    box(b, 10, 22, 42, 52, radius=7)
    line(b, [(42, 28), (52, 28), (52, 40), (42, 42)], 5)
    box(d, 16, 12, 20, 18)
    box(d, 26, 8, 30, 18)


def g_bed(b, d):
    box(b, 6, 14, 12, 52)
    box(b, 6, 36, 58, 46, radius=3)
    box(b, 52, 30, 58, 52)
    box(b, 14, 24, 36, 34, radius=4)
    oval(d, 15, 20, 26, 31)


def g_shield(b, d):
    poly(b, [(32, 6), (54, 14), (52, 34), (32, 58), (12, 34), (10, 14)])
    poly(d, [(32, 18), (36, 28), (46, 28), (38, 35), (41, 45), (32, 39), (23, 45), (26, 35), (18, 28), (28, 28)])


def g_bike(b, d):
    for cx in (17, 47):                       # dos ruedas (aro)
        oval(b, cx - 12, 32, cx + 12, 56)
        oval(d, cx - 7, 37, cx + 7, 51)
    line(b, [(17, 44), (28, 26), (44, 26), (47, 44)], 4.5)   # cuadro
    line(b, [(28, 26), (33, 44), (44, 26)], 4)
    line(b, [(24, 18), (32, 18)], 4)          # sillín
    line(b, [(44, 26), (41, 14), (49, 14)], 4)  # manillar


def g_bus_stop(b, d):
    box(b, 29, 26, 35, 60)                    # poste
    box(b, 10, 4, 54, 30, radius=6)           # placa
    box(d, 17, 10, 47, 20, radius=2)          # ventanillas del autobús
    oval(d, 19, 22, 25, 27)
    oval(d, 39, 22, 45, 27)


def g_signal(b, d):
    # Semáforo NEUTRO: tres luces grises iguales. No muestra ningún estado (rojo/ámbar/verde) porque no hay datos en vivo.
    box(b, 20, 4, 44, 52, radius=7)
    box(b, 29, 52, 35, 60)
    for y in (8, 21, 34):
        oval(d, 25, y, 39, y + 13)


# nombre -> (glifo, color base, color de detalle)
ICONS = {
    "home":        (g_house,       LIGHT,                DARK),
    "work":        (g_work,        LIGHT,                DARK),
    "shop":        (g_shop,        (90, 169, 255, 255),  WHITE),
    "food":        (g_food,        (242, 169, 59, 255),  WHITE),
    "bar":         (g_bar,         (255, 107, 157, 255), WHITE),
    "fuel":        (g_fuel,        (255, 138, 61, 255),  DARK),
    "parking":     (g_parking,     (90, 169, 255, 255),  WHITE),
    "hospital":    (g_hospital,    (255, 77, 77, 255),   WHITE),
    "transit":     (g_train,       LIGHT,                DARK),
    "bank":        (g_bank,        (94, 219, 148, 255),  DARK),
    "destination": (g_destination, (255, 212, 0, 255),   DARK),
    "cafe":        (g_cup,         (242, 169, 59, 255),  WHITE),
    "lodging":     (g_bed,         (127, 209, 255, 255), DARK),
    "police":      (g_shield,      (123, 134, 255, 255), WHITE),
    "bike":        (g_bike,        (60, 203, 127, 255),  DARK),
    "bus-stop":    (g_bus_stop,    LIGHT,                DARK),
    "signal":      (g_signal,      (40, 40, 40, 255),    (150, 150, 150, 255)),
}


def render(name):
    glyph, color, detail_color = ICONS[name]
    size = OUT * SS
    base = Image.new("L", (size, size), 0)
    detail = Image.new("L", (size, size), 0)
    db, dd = ImageDraw.Draw(base), ImageDraw.Draw(detail)
    glyph(db, dd)
    # El detalle solo existe encima del cuerpo, salvo el detalle de "bar" (pajita/aceituna) que sobresale.
    detail_on_base = detail if name in ("bar",) else Image.composite(detail, Image.new("L", (size, size), 0), base)
    silhouette = Image.new("L", (size, size), 0)
    silhouette.paste(255, mask=base)
    silhouette.paste(255, mask=detail_on_base)
    radius = int(2.6 * OUT * SS / GRID)
    outline = silhouette.filter(ImageFilter.MaxFilter(radius * 2 + 1))
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(Image.new("RGBA", (size, size), OUTLINE), mask=outline)
    canvas.paste(Image.new("RGBA", (size, size), color), mask=base)
    canvas.paste(Image.new("RGBA", (size, size), detail_color), mask=detail_on_base)
    return canvas.resize((OUT, OUT), Image.LANCZOS)


def save(name, image, prefix="gta-poi"):
    folder = ASSETS / f"{prefix}-{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / f"{prefix}-{name}.png", "PNG")
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{prefix}-{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1}}, indent=2), encoding="utf-8")


def selection_arrows():
    """Cuatro triángulos (arriba, abajo, izquierda, derecha) apuntando al centro, claros con contorno oscuro.
    Imagen de 160 px (53 pt a @3x) para rodear un icono de ~24 pt dejando hueco libre en el centro."""
    px = 160
    size = px * SS
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    c, gap, half, length = size / 2, 50 * SS, 17 * SS, 26 * SS
    d.polygon([(c - half, c - gap - length), (c + half, c - gap - length), (c, c - gap)], fill=255)   # arriba
    d.polygon([(c - half, c + gap + length), (c + half, c + gap + length), (c, c + gap)], fill=255)   # abajo
    d.polygon([(c - gap - length, c - half), (c - gap - length, c + half), (c - gap, c)], fill=255)   # izquierda
    d.polygon([(c + gap + length, c - half), (c + gap + length, c + half), (c + gap, c)], fill=255)   # derecha
    outline = mask.filter(ImageFilter.MaxFilter(2 * 4 * SS + 1))
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(Image.new("RGBA", (size, size), OUTLINE), mask=outline)
    canvas.paste(Image.new("RGBA", (size, size), (240, 240, 240, 255)), mask=mask)
    return canvas.resize((px, px), Image.LANCZOS)


# ---- Familia «costa tropical» (estilo GTA VI) -----------------------------------------------------------------
# Tratamiento de las capturas de referencia: burbuja de esquinas redondeadas color melocotón, glifo oscuro y una
# punta pequeña abajo. Los glifos son los MISMOS dibujos propios de arriba (no se ha copiado ningún icono del juego);
# solo cambia el soporte. Casa y Trabajo usan una burbuja azul grisácea para distinguir los lugares personales
# (adaptación propia).
VI_BUBBLE = (247, 217, 203, 255)
VI_GLYPH = (26, 27, 32, 255)
VI_EDGE = (88, 94, 108, 255)
VI_PERSONAL = (186, 201, 233, 255)
VI_PERSONAL_GLYPH = (28, 40, 72, 255)
VI_NEUTRAL = (206, 210, 218, 255)
VI_SPECIAL = {"home": (VI_PERSONAL, VI_PERSONAL_GLYPH), "work": (VI_PERSONAL, VI_PERSONAL_GLYPH),
              "signal": (VI_NEUTRAL, VI_GLYPH)}


def render_bubble(name):
    glyph = ICONS[name][0]
    bubble_color, glyph_color = VI_SPECIAL.get(name, (VI_BUBBLE, VI_GLYPH))
    size = OUT * SS
    shape = Image.new("L", (size, size), 0)
    sd = ImageDraw.Draw(shape)
    box(sd, 9, 5, 55, 49, radius=10)
    poly(sd, [(26, 48), (38, 48), (32, 57)])
    edge = shape.filter(ImageFilter.MaxFilter(int(S(1.1)) * 2 + 1))
    # Glifo reducido dentro de la burbuja; el detalle se recorta con el color de la burbuja.
    base = Image.new("L", (size, size), 0)
    detail = Image.new("L", (size, size), 0)
    glyph(ImageDraw.Draw(base), ImageDraw.Draw(detail))
    inner = int(S(30))
    base = base.resize((inner, inner), Image.LANCZOS)
    detail = detail.resize((inner, inner), Image.LANCZOS)
    glyph_mask = Image.new("L", (size, size), 0)
    detail_mask = Image.new("L", (size, size), 0)
    offset = (int(S(17)), int(S(12)))
    glyph_mask.paste(base, offset)
    detail_mask.paste(Image.composite(detail, Image.new("L", detail.size, 0), base), offset)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(Image.new("RGBA", (size, size), VI_EDGE), mask=edge)
    canvas.paste(Image.new("RGBA", (size, size), bubble_color), mask=shape)
    canvas.paste(Image.new("RGBA", (size, size), glyph_color), mask=glyph_mask)
    canvas.paste(Image.new("RGBA", (size, size), bubble_color), mask=detail_mask)
    return canvas.resize((OUT, OUT), Image.LANCZOS)


def render_vi_destination():
    """Pin turquesa con contorno oscuro y punto central oscuro (como el pin visible en las capturas)."""
    glyph, _, _ = ICONS["destination"]
    size = OUT * SS
    base = Image.new("L", (size, size), 0)
    detail = Image.new("L", (size, size), 0)
    glyph(ImageDraw.Draw(base), ImageDraw.Draw(detail))
    outline = base.filter(ImageFilter.MaxFilter(int(S(2.4)) * 2 + 1))
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(Image.new("RGBA", (size, size), (27, 30, 38, 255)), mask=outline)
    canvas.paste(Image.new("RGBA", (size, size), (63, 216, 194, 255)), mask=base)
    canvas.paste(Image.new("RGBA", (size, size), (27, 30, 38, 255)), mask=detail)
    return canvas.resize((OUT, OUT), Image.LANCZOS)


def main_vi():
    names = [n for n in ICONS if n != "destination"]
    images = {n: render_bubble(n) for n in names}
    images["destination"] = render_vi_destination()
    images["selection-arrows"] = selection_arrows()      # mismas mini flechas de selección que el resto
    sheet = Image.new("RGBA", (OUT * 5 + 60, (OUT + 10) * ((len(images) + 4) // 5) + 10), (182, 188, 197, 255))
    for i, (name, image) in enumerate(images.items()):
        save(name, image, prefix="gta6-poi")
        thumb = image if image.size == (OUT, OUT) else image.resize((OUT, OUT), Image.LANCZOS)
        sheet.alpha_composite(thumb, (10 + (i % 5) * (OUT + 10), 10 + (i // 5) * (OUT + 10)))
    out = ROOT / "docs" / "branding"
    out.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(out / "poi-icons-gta6-contact-sheet.png")
    print("Iconos GTA VI:", ", ".join(images))


def main():
    names = list(ICONS)
    rows = (len(names) + 1 + 4) // 5          # +1: flechas de selección
    sheet = Image.new("RGBA", (OUT * 5 + 60, (OUT + 10) * rows + 10), (25, 25, 25, 255))
    for i, name in enumerate(names):
        image = render(name)
        save(name, image)
        sheet.alpha_composite(image, (10 + (i % 5) * (OUT + 10), 10 + (i // 5) * (OUT + 10)))
    arrows = selection_arrows()
    save("selection-arrows", arrows)
    sheet.alpha_composite(arrows.resize((OUT, OUT), Image.LANCZOS), (10 + (len(names) % 5) * (OUT + 10), 10 + (len(names) // 5) * (OUT + 10)))
    out = ROOT / "docs" / "branding"
    out.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(out / "poi-icons-contact-sheet.png")
    print("Iconos:", ", ".join(names), "+ selection-arrows")


if __name__ == "__main__":
    import sys
    # --vi: solo la familia del estilo GTA VI (no regenera los iconos del resto de estilos).
    main_vi() if "--vi" in sys.argv else main()
