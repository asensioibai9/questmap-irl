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


# ---- Glifos adicionales SOLO para la familia GTA VI (dibujos propios; no se copia ningún icono) ---------------
def arc(draw, x0, y0, x1, y1, start, end, width, fill=255):
    draw.arc([S(x0), S(y0), S(x1), S(y1)], start, end, fill=fill, width=int(S(width)))


def g_burger(b, d):
    oval(b, 8, 6, 56, 38)
    box(b, 8, 24, 56, 40, fill=0)           # solo la mitad superior del pan
    box(b, 5, 27, 59, 34, radius=3)         # carne
    box(b, 9, 38, 55, 52, radius=6)         # pan inferior
    for x, y in ((20, 13), (31, 10), (42, 14)):
        oval(d, x, y, x + 4, y + 4)         # sésamo


def g_mug(b, d):
    box(b, 12, 18, 44, 58, radius=5)
    arc(b, 36, 24, 58, 48, 270, 90, 5)      # asa
    for x0, x1 in ((9, 25), (20, 36), (31, 47)):
        oval(b, x0, 8, x1, 24)              # espuma
    box(d, 20, 30, 24, 52)
    box(d, 32, 30, 36, 52)


def g_headphones(b, d):
    arc(b, 9, 8, 55, 54, 180, 360, 6)
    box(b, 5, 30, 19, 56, radius=5)
    box(b, 45, 30, 59, 56, radius=5)


def g_bottle(b, d):
    box(b, 27, 3, 37, 15, radius=2)
    poly(b, [(26, 14), (38, 14), (43, 26), (43, 59), (21, 59), (21, 26)])
    box(d, 25, 33, 39, 47, radius=2)        # etiqueta


def g_basket(b, d):
    poly(b, [(5, 26), (59, 26), (52, 57), (12, 57)])
    line(b, [(16, 26), (27, 7)], 5)
    line(b, [(48, 26), (37, 7)], 5)
    for x in (19, 30, 41):
        box(d, x, 32, x + 4, 51)


def g_cart(b, d):
    line(b, [(3, 9), (13, 9), (19, 41), (52, 41)], 5)
    poly(b, [(15, 15), (59, 15), (53, 36), (19, 36)])
    oval(b, 16, 45, 27, 56)
    oval(b, 42, 45, 53, 56)
    box(d, 27, 20, 31, 32)
    box(d, 39, 20, 43, 32)


def g_tshirt(b, d):
    poly(b, [(21, 7), (27, 7), (32, 13), (37, 7), (43, 7), (59, 20), (51, 31), (46, 27), (46, 57), (18, 57),
             (18, 27), (13, 31), (5, 20)])


def g_shoe(b, d):
    poly(b, [(6, 34), (9, 15), (24, 15), (31, 27), (47, 32), (57, 38), (59, 47), (6, 47)])
    box(b, 5, 47, 59, 54, radius=2)
    box(d, 21, 22, 25, 26)
    box(d, 27, 27, 31, 31)


def g_scissors(b, d):
    line(b, [(21, 41), (47, 5)], 6)
    line(b, [(43, 41), (17, 5)], 6)
    oval(b, 5, 36, 27, 58)
    oval(b, 37, 36, 59, 58)
    oval(d, 11, 42, 21, 52)
    oval(d, 43, 42, 53, 52)


def g_tattoo(b, d):
    line(b, [(13, 51), (40, 24)], 11)       # cuerpo de la máquina
    line(b, [(9, 55), (4, 60)], 3)          # aguja
    oval(b, 34, 6, 58, 30)                  # bobina
    oval(d, 41, 13, 51, 23)
    poly(b, [(52, 40), (47, 50), (57, 50)])  # gota de tinta
    oval(b, 46, 46, 58, 58)


def g_phone(b, d):
    box(b, 17, 3, 47, 61, radius=7)
    box(d, 22, 10, 42, 47, radius=2)
    oval(d, 28, 51, 36, 58)


def g_wrench(b, d):
    line(b, [(14, 50), (40, 24)], 10)
    oval(b, 33, 5, 59, 31)
    poly(b, [(45, 3), (55, 3), (51, 18), (46, 18)], fill=0)   # boca de la llave
    oval(b, 5, 41, 23, 59)
    oval(d, 10, 46, 18, 54)


def car_shape(b, d, dy=0):
    poly(b, [(14, 30 + dy), (20, 15 + dy), (44, 15 + dy), (50, 30 + dy)])
    box(b, 5, 28 + dy, 59, 46 + dy, radius=6)
    oval(b, 11, 39 + dy, 25, 53 + dy)
    oval(b, 39, 39 + dy, 53, 53 + dy)
    poly(d, [(19, 28 + dy), (23, 19 + dy), (41, 19 + dy), (45, 28 + dy)])
    oval(d, 9, 32 + dy, 16, 38 + dy)
    oval(d, 48, 32 + dy, 55, 38 + dy)


def g_car(b, d):
    car_shape(b, d, 2)


def g_car_wash(b, d):
    car_shape(b, d, 9)
    for x in (16, 32, 48):                  # gotas de agua
        poly(b, [(x, 1), (x - 5, 9), (x + 5, 9)])
        oval(b, x - 5, 5, x + 5, 15)


def g_bolt(b, d):
    poly(b, [(38, 3), (12, 36), (29, 36), (23, 61), (52, 24), (35, 24), (44, 3)])


def g_anchor(b, d):
    oval(b, 24, 3, 40, 19)
    oval(d, 28, 7, 36, 15)
    box(b, 29, 17, 35, 56)
    box(b, 16, 23, 48, 29, radius=2)
    arc(b, 8, 22, 56, 58, 20, 160, 6)
    poly(b, [(3, 42), (16, 36), (11, 51)])
    poly(b, [(61, 42), (48, 36), (53, 51)])


def g_boat(b, d):
    poly(b, [(3, 37), (61, 37), (50, 55), (14, 55)])
    box(b, 17, 22, 47, 37, radius=2)
    box(b, 26, 8, 33, 22)
    box(d, 21, 26, 28, 33)
    box(d, 36, 26, 43, 33)


def g_clapper(b, d):
    box(b, 6, 25, 58, 57, radius=4)
    poly(b, [(5, 12), (54, 4), (57, 16), (8, 24)])
    poly(d, [(15, 11), (23, 9), (20, 21), (12, 22)])
    poly(d, [(31, 8), (39, 7), (36, 19), (28, 20)])
    box(d, 12, 33, 52, 37)


def g_mask(b, d):
    poly(b, [(8, 10), (32, 6), (56, 10), (54, 34), (44, 52), (32, 58), (20, 52), (10, 34)])
    oval(d, 15, 19, 27, 29)
    oval(d, 37, 19, 49, 29)
    arc(d, 18, 26, 46, 48, 20, 160, 4)      # sonrisa


def g_flame(b, d):
    poly(b, [(32, 3), (45, 19), (53, 35), (49, 50), (39, 59), (25, 59), (15, 50), (11, 36), (19, 23), (24, 33),
             (27, 16)])
    poly(d, [(32, 29), (40, 41), (38, 52), (26, 52), (24, 42)])


def g_pill(b, d):
    box(b, 5, 21, 59, 43, radius=11)
    box(d, 30, 21, 34, 43)                  # división de la cápsula
    oval(d, 41, 27, 47, 33)


def g_tooth(b, d):
    poly(b, [(13, 10), (25, 7), (32, 12), (39, 7), (51, 10), (55, 22), (51, 36), (46, 58), (39, 58), (36, 41),
             (28, 41), (25, 58), (18, 58), (13, 36), (9, 22)])


def g_dumbbell(b, d):
    box(b, 14, 28, 50, 36)
    box(b, 4, 17, 13, 47, radius=3)
    box(b, 13, 21, 20, 43, radius=2)
    box(b, 51, 17, 60, 47, radius=3)
    box(b, 44, 21, 51, 43, radius=2)


def g_golf(b, d):
    box(b, 22, 5, 27, 54)
    poly(b, [(27, 5), (53, 14), (27, 24)])
    oval(b, 9, 50, 41, 60)


def g_coin(b, d):
    oval(b, 5, 5, 59, 59)
    arc(d, 17, 15, 47, 49, 45, 315, 5)       # signo del euro
    box(d, 12, 26, 33, 30)
    box(d, 12, 34, 33, 38)


def g_banknote(b, d):
    box(b, 3, 15, 61, 49, radius=4)
    oval(d, 23, 21, 41, 43)
    box(d, 8, 20, 14, 26)
    box(d, 50, 38, 56, 44)


def g_obelisk(b, d):
    poly(b, [(27, 8), (32, 1), (37, 8)])
    poly(b, [(27, 8), (37, 8), (41, 47), (23, 47)])
    box(b, 15, 47, 49, 53)
    box(b, 10, 53, 54, 59)


def g_castle(b, d):
    box(b, 9, 23, 55, 59)
    for x in (9, 21, 33, 45):
        box(b, x, 11, x + 10, 23)
    box(d, 26, 41, 38, 59, radius=5)
    box(d, 15, 30, 20, 36)
    box(d, 44, 30, 49, 36)


def g_star(b, d):
    import math
    pts = []
    for i in range(10):
        r = 28 if i % 2 == 0 else 12
        a = math.radians(-90 + i * 36)
        pts.append((32 + r * math.cos(a), 34 + r * math.sin(a)))
    poly(b, pts)


def g_envelope(b, d):
    box(b, 5, 13, 59, 51, radius=4)
    line(d, [(8, 16), (32, 35), (56, 16)], 4)


def g_book(b, d):
    poly(b, [(5, 11), (30, 16), (30, 57), (5, 52)])
    poly(b, [(34, 16), (59, 11), (59, 52), (34, 57)])


def g_icecream(b, d):
    oval(b, 15, 4, 49, 34)
    poly(b, [(17, 27), (47, 27), (32, 61)])
    line(d, [(23, 33), (38, 48)], 2.5)
    line(d, [(41, 33), (28, 46)], 2.5)


def g_bread(b, d):
    oval(b, 4, 16, 60, 52)
    for x in (16, 29, 42):
        line(d, [(x, 24), (x + 7, 42)], 3.5)


def g_note(b, d):
    oval(b, 6, 42, 26, 58)
    box(b, 20, 8, 26, 50)
    poly(b, [(20, 8), (50, 3), (50, 14), (26, 19)])
    box(b, 44, 3, 50, 42)
    oval(b, 30, 34, 50, 50)


def g_palette(b, d):
    oval(b, 4, 8, 60, 56)
    oval(b, 12, 34, 24, 46, fill=0)          # hueco del pulgar
    for x, y in ((18, 15), (31, 11), (44, 16), (47, 31)):
        oval(d, x - 4, y, x + 4, y + 8)


def g_paw(b, d):
    oval(b, 17, 30, 47, 57)
    oval(b, 6, 19, 17, 33)
    oval(b, 19, 7, 30, 22)
    oval(b, 34, 7, 45, 22)
    oval(b, 47, 19, 58, 33)


def g_gift(b, d):
    box(b, 8, 25, 56, 59, radius=2)
    box(b, 5, 16, 59, 26, radius=2)
    oval(b, 16, 5, 32, 19)
    oval(b, 32, 5, 48, 19)
    box(d, 29, 16, 35, 59)


def g_flower(b, d):
    box(b, 30, 40, 34, 61)
    oval(b, 24, 3, 40, 21)
    oval(b, 24, 29, 40, 47)
    oval(b, 11, 16, 29, 32)
    oval(b, 35, 16, 53, 32)
    oval(d, 26, 18, 38, 30)


def g_diamond(b, d):
    poly(b, [(15, 8), (49, 8), (60, 22), (32, 58), (4, 22)])
    line(d, [(6, 22), (58, 22)], 2.5)
    line(d, [(22, 9), (32, 22), (42, 9)], 2.5)


def g_glasses(b, d):
    oval(b, 3, 21, 29, 47)
    oval(b, 35, 21, 61, 47)
    oval(d, 9, 27, 23, 41)
    oval(d, 41, 27, 55, 41)
    box(b, 26, 28, 38, 32)


# nombre de recurso -> glifo (el color de la burbuja depende del grupo: VI_ICON_GROUP)
VI_EXTRA = {
    "burger": g_burger, "mug": g_mug, "nightclub": g_headphones, "bottle": g_bottle, "basket": g_basket,
    "cart": g_cart, "clothes": g_tshirt, "shoes": g_shoe, "beauty": g_scissors, "tattoo": g_tattoo,
    "electronics": g_phone, "car-repair": g_wrench, "car": g_car, "car-wash": g_car_wash, "charging": g_bolt,
    "marina": g_anchor, "ferry": g_boat, "cinema": g_clapper, "theatre": g_mask, "fire": g_flame,
    "pharmacy": g_pill, "dentist": g_tooth, "gym": g_dumbbell, "golf": g_golf, "coin": g_coin, "atm": g_banknote,
    "monument": g_obelisk, "castle": g_castle, "attraction": g_star, "post": g_envelope, "books": g_book,
    "ice-cream": g_icecream, "bakery": g_bread, "music": g_note, "art": g_palette, "vet": g_paw, "gift": g_gift,
    "florist": g_flower, "jewelry": g_diamond, "optician": g_glasses,
}


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
# punta pequeña abajo. Los glifos son dibujos propios (no se ha copiado ningún icono del juego ni de ninguna web); el
# color de cada burbuja sale del grupo de su categoría (VI_GROUPS / VI_ICON_GROUP).
VI_BUBBLE = (247, 217, 203, 255)
VI_GLYPH = (26, 27, 32, 255)
VI_EDGE = (88, 94, 108, 255)
VI_PERSONAL = (186, 201, 233, 255)
VI_PERSONAL_GLYPH = (28, 40, 72, 255)
VI_NEUTRAL = (206, 210, 218, 255)
# Color de burbuja POR GRUPO, tomado de la leyenda del mapa interactivo de gtabase.com (solo el color: los glifos son
# propios). Colores planos de la web: actividades #7b1fa2, propiedades #00897b, concesionario #1565c0, lugares
# #ef6c00. Colores medidos (aprox.) en el relleno de sus burbujas: tiendas ≈ #f6dcdc, comida y bebida ≈ #e2e8f6,
# comida callejera ≈ #f7f6fd, vehículos y transporte ≈ #e4eaf6, garajes ≈ #3ce4d2, bancos ≈ #87db8a.
WHITE_GLYPH = (255, 255, 255, 255)
VI_GROUPS = {
    "shops": ((246, 220, 220, 255), VI_GLYPH),
    "food": ((226, 232, 246, 255), VI_GLYPH),
    "street_food": ((247, 246, 253, 255), VI_GLYPH),
    "vehicles": ((228, 234, 248, 255), VI_GLYPH),
    "garages": ((60, 228, 210, 255), VI_GLYPH),
    "banks": ((135, 219, 138, 255), VI_GLYPH),
    "dealer": ((21, 101, 192, 255), WHITE_GLYPH),
    "activities": ((123, 31, 162, 255), WHITE_GLYPH),
    "properties": ((0, 137, 123, 255), WHITE_GLYPH),
    "places": ((239, 108, 0, 255), WHITE_GLYPH),
    "neutral": (VI_NEUTRAL, VI_GLYPH),
}
VI_ICON_GROUP = {
    # Tiendas (incluye talleres de tuneo, mismo color en la web)
    "shop": "shops", "clothes": "shops", "shoes": "shops", "beauty": "shops", "tattoo": "shops",
    "electronics": "shops", "gift": "shops", "florist": "shops", "jewelry": "shops", "optician": "shops",
    "books": "shops", "music": "shops", "art": "shops", "car-repair": "shops",
    # Comida y bebida (tiendas de conveniencia y licorerías están en este grupo en la web)
    "food": "food", "cafe": "food", "bar": "food", "mug": "food", "burger": "food", "bottle": "food",
    "basket": "food", "cart": "food",
    "ice-cream": "street_food", "bakery": "street_food",
    # Vehículos y transporte
    "fuel": "vehicles", "charging": "vehicles", "car-wash": "vehicles", "transit": "vehicles",
    "bus-stop": "vehicles", "ferry": "vehicles", "bike": "vehicles",
    "parking": "garages", "car": "dealer",
    "bank": "places", "coin": "banks", "atm": "banks",
    "gym": "activities", "golf": "activities",
    "home": "properties", "work": "properties",
    # Lugares (cine, bomberos, hospitales, emblemáticos, discoteca, comisarías, puertos deportivos)
    "marina": "places", "cinema": "places", "theatre": "places", "fire": "places", "hospital": "places",
    "pharmacy": "places", "dentist": "places", "vet": "places", "monument": "places", "castle": "places",
    "attraction": "places", "nightclub": "places", "police": "places",
    "signal": "neutral",
}
# Sin categoría equivalente en la web (alojamiento, correos): se quedan en el melocotón de las capturas.
VI_SPECIAL = {name: VI_GROUPS[group] for name, group in VI_ICON_GROUP.items()}


def render_bubble(name):
    glyph = VI_EXTRA[name] if name in VI_EXTRA else ICONS[name][0]
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
    names = [n for n in ICONS if n != "destination"] + list(VI_EXTRA)
    images = {n: render_bubble(n) for n in names}
    images["destination"] = render_vi_destination()
    images["selection-arrows"] = selection_arrows()      # mismas mini flechas de selección que el resto
    cols = 10
    sheet = Image.new("RGBA", (10 + (OUT + 10) * cols, (OUT + 10) * ((len(images) + cols - 1) // cols) + 10), (182, 188, 197, 255))
    for i, (name, image) in enumerate(images.items()):
        save(name, image, prefix="gta6-poi")
        thumb = image if image.size == (OUT, OUT) else image.resize((OUT, OUT), Image.LANCZOS)
        sheet.alpha_composite(thumb, (10 + (i % cols) * (OUT + 10), 10 + (i // cols) * (OUT + 10)))
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
