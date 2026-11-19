#!/usr/bin/env python3
"""Genera los estilos vectoriales (MapLibre style spec v8) de QuestMap IRL.

Los estilos se escriben en QuestMapIRL/Resources/ y se validan con tools/validate_style.py
contra el esquema real (OpenMapTiles) del proveedor.

IMPORTANTE:
- Los source-layers, clases y campos usados aquí se han comprobado contra tiles reales de
  OpenFreeMap (ver tools/inspect_tile.py). No hay capas inventadas.
- {{TILES_URL}} y {{GLYPHS_URL}} se sustituyen en la app (StyleManager) desde la configuración
  del proveedor; no hay claves ni secretos en el repositorio.
- Los colores son decisiones de diseño PROPIAS. No se han copiado de ningún juego. La
  referencia al estilo de minimapa de videojuego es de lenguaje visual (jerarquía de vías,
  contraste, siluetas); la comparación con capturas concretas está pendiente.

Uso:  python tools/build_styles.py
"""
import json
import os

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "QuestMapIRL", "Resources")
FONT = ["Noto Sans Regular"]
FONT_BOLD = ["Noto Sans Bold"]
FONT_ITALIC = ["Noto Sans Italic"]
CLEAR = "rgba(0,0,0,0)"


def interp(stops, base=1.4):
    """Expresión `interpolate` exponencial sobre el zoom."""
    expr = ["interpolate", ["exponential", base], ["zoom"]]
    for z, v in stops:
        expr += [z, v]
    return expr


def scaled(stops, k=1.0, add=0.0):
    return [(z, round(v * k + add, 3)) for z, v in stops]


def match(prop, mapping, fallback):
    expr = ["match", ["get", prop]]
    for classes, value in mapping:
        expr += [classes if isinstance(classes, list) else [classes], value]
    expr.append(fallback)
    return expr


def lit(values):
    return ["literal", values]


def is_in(prop, values):
    return ["match", ["get", prop], values, True, False]


# Anchos (px) del relleno de cada tier de vía por zoom.
ROAD_WIDTH = {
    "motorway": [(5, 0.8), (8, 1.5), (11, 3.2), (14, 7.5), (16, 15), (18, 36), (20, 90)],
    "trunk": [(6, 0.6), (9, 1.2), (11, 2.6), (14, 6.5), (16, 13), (18, 30), (20, 76)],
    "primary": [(8, 0.6), (11, 1.9), (14, 5.5), (16, 11), (18, 26), (20, 64)],
    "secondary": [(9, 0.5), (11, 1.5), (14, 4.4), (16, 9), (18, 21), (20, 52)],
    "tertiary": [(10, 0.4), (12, 1.3), (14, 3.6), (16, 7.5), (18, 17), (20, 42)],
    "minor": [(11, 0.3), (13, 1.0), (14, 2.4), (16, 5.5), (18, 13), (20, 32)],
    "service": [(13, 0.4), (15, 1.3), (17, 3.2), (18, 7), (20, 18)],
}
ROAD_MINZOOM = {"motorway": 4, "trunk": 5, "primary": 7, "secondary": 8,
                "tertiary": 9.5, "minor": 11, "service": 13}
TIER_CLASSES = {
    "motorway": ["motorway"],
    "trunk": ["trunk"],
    "primary": ["primary"],
    "secondary": ["secondary"],
    "tertiary": ["tertiary"],
    "minor": ["minor"],
    "service": ["service", "service_construction", "track", "busway", "raceway"],
}
TIERS = ["service", "minor", "tertiary", "secondary", "primary", "trunk", "motorway"]


def road_filter(tier, brunnel, ramps):
    """Filtro de carreteras: tier + estructura (superficie/túnel/puente) + rampa."""
    f = ["all",
         ["==", ["geometry-type"], "LineString"],
         is_in("class", TIER_CLASSES[tier]) if len(TIER_CLASSES[tier]) > 1
         else ["==", ["get", "class"], TIER_CLASSES[tier][0]]]
    if brunnel == "surface":
        f.append(["!", is_in("brunnel", ["bridge", "tunnel"])])
    else:
        f.append(["==", ["get", "brunnel"], brunnel])
    f.append(["==", ["coalesce", ["get", "ramp"], 0], 1] if ramps else ["!=", ["coalesce", ["get", "ramp"], 0], 1])
    return f


def build_style(cfg):
    p = cfg["palette"]
    layers = []
    lab = cfg.get("labels", {})
    label_font = lab.get("font", FONT)
    label_upper = lab.get("upper", False)
    halo_w = lab.get("halo", 1.8)

    def overlays(stage):
        """Texturas (fill-pattern) superpuestas a un color base, por etapa de dibujo."""
        for tex in cfg.get("overlays", []):
            if tex["after"] != stage:
                continue
            layer = {"id": tex["id"], "type": "fill", "source": "openmaptiles", "source-layer": tex["layer"],
                     "paint": {"fill-pattern": tex["pattern"], "fill-opacity": tex.get("opacity", 1)}}
            if tex.get("classes"):
                layer["filter"] = is_in("class", tex["classes"])
            if tex.get("minzoom"):
                layer["minzoom"] = tex["minzoom"]
            add(layer)

    def text_layout(extra):
        layout = dict(extra)
        layout["text-font"] = label_font
        if label_upper:
            layout["text-transform"] = "uppercase"
        return layout

    def add(layer):
        layers.append(layer)

    add({"id": "background", "type": "background", "paint": {"background-color": p["land"]}})
    if cfg.get("background_pattern"):
        # Suelo base con textura: un polígono que cubre el mundo (background-pattern no es fiable entre motores).
        add({"id": "ground-pattern", "type": "fill", "source": "world",
             "paint": {"fill-pattern": cfg["background_pattern"], "fill-antialias": False}})

    # ---- Suelo -----------------------------------------------------------
    add({"id": "landcover", "type": "fill", "source": "openmaptiles", "source-layer": "landcover",
         "paint": {"fill-color": match("class", [
             (["grass", "wetland"], p["grass"]), ("wood", p["wood"]), ("sand", p["sand"]),
             ("farmland", p["farm"]), (["rock", "ice"], p["rock"])], CLEAR),
             "fill-opacity": interp([(5, 0.5), (12, 1)])}})
    add({"id": "landuse", "type": "fill", "source": "openmaptiles", "source-layer": "landuse",
         "minzoom": 8,
         "paint": {"fill-color": match("class", [
             (["residential", "suburb", "neighbourhood"], p["residential"]),
             (["commercial", "retail"], p["commercial"]),
             (["industrial", "garages", "railway", "quarry"], p["industrial"]),
             (["school", "university", "college", "kindergarten", "hospital", "library"], p["institution"]),
             (["pitch", "playground", "stadium", "track", "theme_park", "zoo"], p["sports"]),
             ("cemetery", p["cemetery"]), ("military", p["military"])], CLEAR)}})

    overlays("landuse")

    # ---- Agua ------------------------------------------------------------
    add({"id": "water", "type": "fill", "source": "openmaptiles", "source-layer": "water",
         "paint": {"fill-color": p["water"]}})
    overlays("water")
    if cfg.get("shore"):
        sh = cfg["shore"]
        add({"id": "water-shore", "type": "line", "source": "openmaptiles", "source-layer": "water",
             "minzoom": 6, "layout": {"line-join": "round"},
             "paint": {"line-color": sh["color"], "line-opacity": sh.get("opacity", 0.6),
                       "line-width": interp([(8, 4), (14, 14), (18, 40)]),
                       "line-offset": interp([(8, 2), (14, 7), (18, 20)]),
                       "line-blur": interp([(8, 2), (14, 6), (18, 14)])}})
    add({"id": "water-edge", "type": "line", "source": "openmaptiles", "source-layer": "water",
         "minzoom": 9,
         "paint": {"line-color": p["water_edge"], "line-opacity": 0.9,
                   "line-width": interp([(9, 0.5), (14, 1.2), (18, 2.2)])}})
    add({"id": "waterway", "type": "line", "source": "openmaptiles", "source-layer": "waterway",
         "minzoom": 8, "filter": is_in("class", ["river", "canal", "stream"]),
         "paint": {"line-color": p["water_edge"],
                   "line-width": interp([(8, 0.4), (12, 1.2), (16, 3.5), (18, 7)])}})

    # ---- Aeropuertos -----------------------------------------------------
    add({"id": "aeroway", "type": "line", "source": "openmaptiles", "source-layer": "aeroway",
         "minzoom": 10, "filter": is_in("class", ["runway", "taxiway"]),
         "paint": {"line-color": p["runway"],
                   "line-width": interp([(10, 1), (14, 6), (18, 30)])}})

    # ---- Límites administrativos (capa real `boundary`; excluye los marítimos) ------------------------
    bd = cfg.get("boundaries", {})
    if bd.get("enabled", True):
        add({"id": "boundary", "type": "line", "source": "openmaptiles", "source-layer": "boundary", "minzoom": 3,
             "filter": ["all", ["<=", ["coalesce", ["get", "admin_level"], 99], bd.get("max_level", 6)],
                        ["!=", ["coalesce", ["get", "maritime"], 0], 1]],
             "layout": {"line-join": "round"},
             "paint": {"line-color": bd.get("color", p["place_text"]), "line-opacity": bd.get("opacity", 0.5),
                       "line-dasharray": bd.get("dash", [3, 2]),
                       "line-width": interp([(3, 0.6), (10, bd.get("width", 1.4)), (16, bd.get("width", 1.4) + 0.8)])}})

    # ---- Edificios (siluetas geométricas) --------------------------------
    add({"id": "building", "type": "fill", "source": "openmaptiles", "source-layer": "building",
         "minzoom": 14,
         "paint": {"fill-color": p["building"], "fill-opacity": interp([(14, 0.0), (15, p["building_opacity"])]),
                   "fill-antialias": True}})
    overlays("building")
    add({"id": "building-outline", "type": "line", "source": "openmaptiles", "source-layer": "building",
         "minzoom": 15.5,
         "paint": {"line-color": p["building_edge"], "line-opacity": interp([(15.5, 0), (17, 0.9)]),
                   "line-width": interp([(15.5, 0.4), (18, 1.1)])}})

    # ---- Peatonal (áreas y senderos) ------------------------------------
    add({"id": "pedestrian-area", "type": "fill", "source": "openmaptiles", "source-layer": "transportation",
         "minzoom": 15, "filter": ["==", ["geometry-type"], "Polygon"],
         "paint": {"fill-color": p["pedestrian"], "fill-opacity": 0.9}})
    add({"id": "path", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
         "minzoom": 15, "filter": ["all", ["==", ["geometry-type"], "LineString"], ["==", ["get", "class"], "path"]],
         "layout": {"line-cap": "round"},
         "paint": {"line-color": p["path"], "line-dasharray": [2, 2],
                   "line-width": interp([(15, 0.5), (18, 1.6)])}})

    # ---- Ferrocarril -----------------------------------------------------
    rail_filter = ["all", ["==", ["get", "class"], "rail"], ["!", is_in("brunnel", ["tunnel"])]]
    ties = cfg.get("rail_ties", True)
    add({"id": "rail", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
         "minzoom": 11, "filter": rail_filter,
         "paint": {"line-color": p["rail"], "line-width": interp([(11, 0.6), (16, 1.4)]),
                   **({} if ties else {"line-dasharray": [3, 3]})}})
    if ties:
        # Traviesas: marcas cortas y anchas repetidas a lo largo de la vía (representan el ferrocarril real, no inventan vías).
        add({"id": "rail-ties", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
             "minzoom": 13, "filter": rail_filter,
             "paint": {"line-color": p["rail"], "line-dasharray": [0.3, 2.4],
                       "line-width": interp([(13, 2.2), (16, 4.2), (18, 7)])}})

    # ---- Túneles (tenues, discontinuos) ---------------------------------
    for tier in TIERS:
        add({"id": f"tunnel-{tier}", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
             "minzoom": ROAD_MINZOOM[tier], "filter": road_filter(tier, "tunnel", False),
             "layout": {"line-join": "round"},
             "paint": {"line-color": p["tunnel"], "line-opacity": 0.55, "line-dasharray": [2, 1.4],
                       "line-width": interp(scaled(ROAD_WIDTH[tier], 0.9))}})

    # ---- Carreteras en superficie: primero contornos, luego rellenos ----
    road_k = cfg.get("road_k", 1.0)
    tier_k = cfg.get("tier_k", {})

    def casing(tier, brunnel, ramps, ident):
        widths = scaled(ROAD_WIDTH[tier], road_k * tier_k.get(tier, 1.0))
        k = 0.7 if ramps else 1.0
        boost = cfg.get("casing_boost", {"motorway": 1.5, "trunk": 1.25}).get(tier, 1.0)
        stops = [(z, round(w * k + max(p["casing_min"], w * k * p["casing_ratio"]) * boost, 3)) for z, w in widths]
        return {"id": ident, "type": "line", "source": "openmaptiles", "source-layer": "transportation",
                "minzoom": ROAD_MINZOOM[tier] + (0.5 if ramps else 0),
                "filter": road_filter(tier, brunnel, ramps),
                "layout": {"line-cap": "butt", "line-join": cfg.get("road_join", "round")},
                "paint": {"line-color": p["casing"], "line-width": interp(stops)}}

    def fill(tier, brunnel, ramps, ident):
        widths = scaled(ROAD_WIDTH[tier], road_k * tier_k.get(tier, 1.0))
        k = 0.7 if ramps else 1.0
        dash = cfg.get("dash_tiers", {}).get(tier)
        paint = {"line-color": p["road"][tier], "line-width": interp(scaled(widths, k))}
        if dash:
            paint["line-dasharray"] = dash     # caminos y sendas discontinuos (jerarquía por trazo)
        return {"id": ident, "type": "line", "source": "openmaptiles", "source-layer": "transportation",
                "minzoom": ROAD_MINZOOM[tier] + (0.5 if ramps else 0),
                "filter": road_filter(tier, brunnel, ramps),
                "layout": {"line-cap": "butt" if dash else cfg.get("road_cap", "round"), "line-join": cfg.get("road_join", "round")},
                "paint": paint}

    no_casing = cfg.get("no_casing", False)   # estilos de tinta: líneas finas sin contorno
    for tier in (TIERS if not no_casing else []):
        add(casing(tier, "surface", False, f"road-casing-{tier}"))
    for tier in (("secondary", "primary", "trunk", "motorway") if not no_casing else ()):
        add(casing(tier, "surface", True, f"ramp-casing-{tier}"))
    for tier in TIERS:
        add(fill(tier, "surface", False, f"road-{tier}"))
    for tier in ("secondary", "primary", "trunk", "motorway"):
        add(fill(tier, "surface", True, f"ramp-{tier}"))

    # ---- Caminos sin asfaltar (dato real `surface`), solo en estilos que los distinguen ----------
    if cfg.get("unpaved"):
        up = cfg["unpaved"]
        add({"id": "road-unpaved", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
             "minzoom": 12, "filter": ["all", ["==", ["geometry-type"], "LineString"],
                                       ["==", ["get", "surface"], "unpaved"],
                                       ["!", is_in("brunnel", ["bridge", "tunnel"])]],
             "layout": {"line-cap": "butt", "line-join": "round"},
             "paint": {"line-color": up["color"], "line-dasharray": up.get("dash", [2, 1.6]),
                       "line-width": interp([(12, 0.8), (15, 2.2), (18, 6)])}})

    # ---- Puentes (encima de todo lo anterior) ---------------------------
    for tier in (TIERS if not no_casing else []):
        add(casing(tier, "bridge", False, f"bridge-casing-{tier}"))
    for tier in TIERS:
        add(fill(tier, "bridge", False, f"bridge-{tier}"))

    # ---- Edificios 3D (extrusión de huellas) ------------------------------
    # Datos: capa `building` de OpenMapTiles (render_height, render_min_height, hide_3d). La altura sale de las
    # etiquetas height / building:levels de OSM; si faltan, el propio esquema aporta un valor estimado (4-5 m).
    # Va DESPUÉS de las carreteras (los edificios no se pintan bajo ellas) y ANTES de la ruta, etiquetas e iconos,
    # que se dibujan por encima: ningún edificio tapa la ruta ni la maniobra. Empieza oculta: la app la activa.
    b3 = cfg.get("buildings_3d")
    if b3:
        raw = ["max", b3.get("min_height", 3), ["min", b3.get("max_height", 120),
               ["to-number", ["coalesce", ["get", "render_height"], 6], 6]]]
        step = b3.get("height_step")
        # Alturas escalonadas (múltiplos de `height_step` m): volúmenes simplificados / bloques de altura fija.
        height = ["max", step, ["*", step, ["round", ["/", raw, step]]]] if step else raw
        base = ["max", 0, ["to-number", ["coalesce", ["get", "render_min_height"], 0], 0]]
        if step:
            base = ["*", step, ["round", ["/", base, step]]]
        paint = {
            # Crecen suavemente entre z15 y z16 para evitar saltos bruscos al acercar.
            "fill-extrusion-height": interp([(15, 0), (16, height)]),
            "fill-extrusion-base": interp([(15, 0), (16, base)]),
            "fill-extrusion-opacity": b3.get("opacity", 1.0),
            "fill-extrusion-vertical-gradient": b3.get("vertical_gradient", True)}
        if b3.get("pattern"):
            paint["fill-extrusion-pattern"] = b3["pattern"]
        else:
            paint["fill-extrusion-color"] = ["interpolate", ["linear"], height] + [x for z, c in b3["colors"] for x in (z, c)]
        add({"id": "building-3d", "type": "fill-extrusion", "source": "openmaptiles", "source-layer": "building",
             "minzoom": 15, "layout": {"visibility": "none"},
             "filter": ["!=", ["coalesce", ["get", "hide_3d"], False], True],
             "paint": paint})

    # ---- Capas opcionales («Capas del mapa»), ocultas por defecto y SIEMPRE bajo la ruta -------------
    # Vías ciclistas: carriles bici segregados y caminos designados para bici (datos reales de OpenMapTiles).
    add({"id": "layer-cycleways", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
         "minzoom": 13, "filter": ["all", ["==", ["get", "class"], "path"],
                                   ["any", ["==", ["get", "subclass"], "cycleway"], ["==", ["get", "bicycle"], "designated"]]],
         "layout": {"visibility": "none", "line-cap": "round"},
         "paint": {"line-color": p.get("cycle", "#3ccb7f"), "line-opacity": 0.9, "line-dasharray": [3, 1.5],
                   "line-width": interp([(13, 1), (16, 2.2), (18, 3.5)])}})
    # Metro, tren ligero y tren: recorridos reales (los túneles se ven discontinuos y tenues).
    add({"id": "layer-transit-lines", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
         "minzoom": 11, "filter": is_in("class", ["transit", "rail"]),
         "layout": {"visibility": "none", "line-cap": "round"},
         "paint": {"line-color": p.get("transit_line", "#7aa7ff"),
                   "line-opacity": ["match", ["get", "brunnel"], ["tunnel"], 0.45, 0.85],
                   "line-dasharray": [1, 1.5], "line-width": interp([(11, 1), (15, 2), (18, 3.2)])}})

    # ---- Capas de navegación bajo las etiquetas -------------------------
    add({"id": "route-glow", "type": "line", "source": "route",
         "layout": {"line-cap": "round", "line-join": "round"},
         "paint": {"line-color": cfg["route"]["glow"], "line-opacity": cfg["route"]["glow_opacity"],
                   "line-blur": 4, "line-width": interp([(8, 7), (14, 18), (18, 40)])}})
    add({"id": "route-casing", "type": "line", "source": "route",
         "layout": {"line-cap": "round", "line-join": "round"},
         "paint": {"line-color": cfg["route"]["casing"],
                   "line-width": interp([(8, 5), (14, 11), (18, 24)])}})
    add({"id": "route-core", "type": "line", "source": "route",
         "layout": {"line-cap": "round", "line-join": "round"},
         "paint": {"line-color": cfg["route"]["core"],
                   "line-width": interp([(8, 3), (14, 6.5), (18, 14)])}})

    def housenumber_layer():
        return {"id": "label-housenumber", "type": "symbol", "source": "openmaptiles", "source-layer": "housenumber",
                "minzoom": 18,
                "layout": {"text-field": ["get", "housenumber"], "text-font": FONT, "text-size": 10},
                "paint": {"text-color": p["road_text"], "text-opacity": 0.7}}

    # Números de portal bajo los iconos: MapLibre coloca primero las capas superiores, y si van encima ganan las
    # colisiones y esconden casi todos los lugares a zoom 18.
    if cfg.get("housenumbers_below_pois"):
        add(housenumber_layer())

    # ---- POI: una capa por CATEGORÍA (la app las activa o desactiva con «Capas del mapa» cambiando solo su
    # visibilidad, sin recargar el estilo). Orden: abajo lo menos importante; MapLibre coloca primero las capas
    # superiores, así que transporte, gasolineras y salud ganan las colisiones a comida y tiendas.
    poi_icons = [
        (["fuel"], "poi-fuel"),
        (["parking"], "poi-parking"),
        (["hospital", "pharmacy", "doctors", "dentist", "veterinary"], "poi-health"),
        (["police", "fire_station", "prison"], "poi-police"),
        (["restaurant", "fast_food"], "poi-food"),
        (["cafe", "bakery", "ice_cream"], "poi-cafe"),
        (["bar", "pub", "beer"], "poi-bar"),
        (["grocery"], "poi-grocery"),
        (["shop", "clothing_store", "butcher", "alcohol_shop", "laundry", "hairdresser"], "poi-shop"),
        (["museum", "attraction", "castle", "monument", "theatre", "cinema", "art_gallery", "library"], "poi-culture"),
        (["bank", "atm"], "poi-bank"),
        (["lodging"], "poi-lodging"),
        (["bicycle_parking", "bicycle_rental"], "poi-bike"),
        (["bus", "railway"], "poi-transit"),
    ]
    not_bus_stop = ["!=", ["get", "subclass"], "bus_stop"]
    poi_categories = [
        # (id, clases, filtro extra, icono fijo o None)
        ("other", ["police", "fire_station", "prison", "museum", "attraction", "castle", "monument", "theatre",
                   "cinema", "art_gallery", "library", "bank", "atm", "lodging"], None, None),
        ("food", ["restaurant", "fast_food", "cafe", "bakery", "ice_cream", "bar", "pub", "beer"], None, None),
        ("shops", ["shop", "clothing_store", "butcher", "alcohol_shop", "laundry", "hairdresser", "grocery"], None, None),
        ("bike-parking", ["bicycle_parking"], None, "poi-bike"),
        ("bike-rental", ["bicycle_rental"], None, "poi-bike"),
        ("bus-stop", ["bus"], ["==", ["get", "subclass"], "bus_stop"], "poi-bus-stop"),
        ("parking", ["parking"], None, None),
        ("health", ["hospital", "pharmacy", "doctors", "dentist", "veterinary"], None, None),
        ("fuel", ["fuel"], None, None),
        ("transit", ["railway", "bus"], not_bus_stop, None),
    ]
    # Zoom de aparición (icono, nombre) por clase. Los estilos con «poi_tiers» escalonan; el resto aparece a la vez.
    default_zooms = (15, 15.8)
    class_zoom = {}
    for _tier_id, classes, icon_zoom, _label_zoom in cfg.get("poi_tiers", []):
        for c in classes:
            class_zoom[c] = (icon_zoom, icon_zoom + 0.6)
    extra_zoom = {"bicycle_parking": (17, 17.6), "bicycle_rental": (16.5, 17.1)}
    bus_stop_zoom = (16.5, 17.3)

    # Nombre corto SOLO de presentación: nombre en español o el original (con tildes y espacios intactos); si no
    # tiene, una categoría breve solo donde ayuda. Más de 22 caracteres: se corta a 21 y se añade «…». El dato
    # completo no se toca: al tocar el lugar, la ficha muestra el nombre entero.
    poi_fallback = match("class", [("parking", "Parking"), ("fuel", "Gasolinera"), ("pharmacy", "Farmacia"),
                                   ("hospital", "Hospital"), ("bicycle_parking", "Aparcabicis")], "")
    full_name = ["to-string", ["coalesce", ["get", "name:es"], ["get", "name"], poi_fallback]]
    short_name = ["case", [">", ["length", full_name], 22], ["concat", ["slice", full_name, 0, 21], "\u2026"], full_name]

    def poi_icon_expression():
        if not cfg.get("poi_class_icons") and not cfg.get("poi_subclass_icons"):
            return match("class", poi_icons, "poi-shop")
        by_class = {}
        for classes, icon in poi_icons + cfg.get("poi_class_icons", []):
            for c in classes:
                by_class[c] = icon
        grouped = {}
        for c, icon in by_class.items():
            grouped.setdefault(icon, []).append(c)
        expression = match("class", [(cls, icon) for icon, cls in grouped.items()], "poi-shop")
        if cfg.get("poi_subclass_icons"):
            seen = set()
            pairs = []
            for subclasses, icon in cfg["poi_subclass_icons"]:
                unique = [x for x in subclasses if x not in seen]
                seen.update(unique)
                if unique:
                    pairs.append((unique, icon))
            expression = match("subclass", pairs, expression)
        return expression

    poi_icon = poi_icon_expression()

    def zooms_for(classes, is_bus_stop):
        if is_bus_stop:
            return {c: bus_stop_zoom for c in classes}
        return {c: extra_zoom.get(c, class_zoom.get(c, default_zooms)) for c in classes}

    tiered = bool(cfg.get("poi_tiers"))
    extra_classes = cfg.get("extra_poi_classes", {})
    for cat_id, classes, extra, fixed_icon in poi_categories:
        classes = classes + [c for c in extra_classes.get(cat_id, []) if c not in classes]
        zooms = zooms_for(classes, cat_id == "bus-stop")
        icon_min = min(z[0] for z in zooms.values())
        icon_zooms = sorted({z[0] for z in zooms.values()})
        label_zooms = sorted({z[1] for z in zooms.values()})
        flt = ["all", is_in("class", classes)]
        if extra:
            flt.append(extra)
        elif cat_id != "transit":
            flt.append(not_bus_stop)
        if len(icon_zooms) > 1:
            # Clases con distinto zoom en la misma categoría: cada una aparece en su nivel.
            flt.append([">=", ["zoom"], match("class", [(c, z[0]) for c, z in zooms.items()], icon_min)])
        if cat_id not in ("bus-stop", "bike-parking"):
            flt.append(["<=", ["coalesce", ["get", "rank"], 99], interp_rank()])
        # Nombre: aparece a su zoom (por clase) dentro de un `step` de nivel superior.
        text = ["step", ["zoom"], ""]
        for z in label_zooms:
            shown = [c for c, cz in zooms.items() if cz[1] <= z]
            text += [z, short_name if len(shown) == len(classes) else ["case", is_in("class", shown), short_name, ""]]
        icon_k = cfg.get("poi_icon_scale", 1.0)    # burbujas: el glifo ocupa menos del icono, se dibujan algo mayores
        size = (interp(scaled([(14.5, 0.5), (17, 0.72), (19, 0.92)], icon_k)) if tiered
                else interp(scaled([(15, 0.55), (17, 0.85), (19, 1.1)], icon_k)))
        add({"id": f"poi-icon-{cat_id}", "type": "symbol", "source": "openmaptiles", "source-layer": "poi",
             "minzoom": icon_min, "filter": flt,
             "layout": {"icon-image": fixed_icon or poi_icon,
                        "icon-size": size,
                        "icon-allow-overlap": False, "icon-padding": 6 if tiered else 3,
                        "symbol-sort-key": ["coalesce", ["get", "rank"], 99],
                        "text-field": text,
                        **text_layout({"text-size": interp([(15, 9.5), (17, 10.5), (19, 12)]),
                                       "text-offset": [0, 1.1], "text-anchor": "top",
                                       "text-max-width": 30, "text-padding": 2, "text-optional": True})},
             "paint": {"text-color": p["poi_text"], "text-halo-color": p["halo"], "text-halo-width": halo_w}})

    # Semáforos: los carga la app desde OpenStreetMap (Overpass) solo con la capa activada y mucho zoom. Icono neutro:
    # NUNCA indica rojo/ámbar/verde (no hay estado en tiempo real).
    add({"id": "layer-traffic-signals", "type": "symbol", "source": "traffic-signals", "minzoom": 16,
         "layout": {"visibility": "none", "icon-image": "poi-traffic-signal",
                    "icon-size": interp([(16, 0.42), (19, 0.62)]), "icon-allow-overlap": False, "icon-padding": 2}})

    # ---- Etiquetas -------------------------------------------------------
    road_label_zoom = [("motorway", 10.5), ("trunk", 11), ("primary", 11.5), ("secondary", 12.5),
                       ("tertiary", 13.5), ("minor", 15)]
    for cls, z in (road_label_zoom if lab.get("roads", True) else []):
        add({"id": f"label-road-{cls}", "type": "symbol", "source": "openmaptiles",
             "source-layer": "transportation_name", "minzoom": z,
             "filter": ["==", ["get", "class"], cls],
             "layout": {"symbol-placement": "line", "symbol-spacing": lab.get("spacing", 320),
                        "text-field": ["coalesce", ["get", "name:es"], ["get", "name"]],
                        **text_layout({"text-size": interp([(11, 9.5), (16, lab.get("road_size", 12.5)), (19, lab.get("road_size", 12.5) + 3)]),
                                       "text-max-angle": 28, "text-letter-spacing": 0.04 if label_upper else 0.02,
                                       "text-padding": 6})},
             "paint": {"text-color": p["road_text"], "text-halo-color": p["halo"], "text-halo-width": halo_w}})
    if cfg.get("refs", True):
        # Número/referencia de la vía (campo real `ref` de transportation_name), solo en autopistas y autovías.
        add({"id": "label-road-ref", "type": "symbol", "source": "openmaptiles", "source-layer": "transportation_name",
             "minzoom": 9, "filter": ["all", is_in("class", ["motorway", "trunk"]), ["has", "ref"]],
             "layout": {"symbol-placement": "line", "symbol-spacing": lab.get("ref_spacing", 460),
                        "text-field": ["get", "ref"],
                        **text_layout({"text-size": interp([(9, 9), (14, 11), (18, 13)]), "text-max-angle": 30,
                                       "text-letter-spacing": 0.05, "text-padding": 6})},
             "paint": {"text-color": p.get("ref_text", p["road_text"]), "text-halo-color": p["halo"], "text-halo-width": halo_w}})
    if cfg.get("peaks"):
        # Cimas con nombre y altitud (capa real `mountain_peak`): da sentido al relieve sin inventar montañas.
        pk = cfg["peaks"]
        add({"id": "label-peak", "type": "symbol", "source": "openmaptiles", "source-layer": "mountain_peak",
             "minzoom": 11, "filter": ["has", "name"],
             "layout": {"text-field": ["format", ["coalesce", ["get", "name:es"], ["get", "name"]], {},
                                       ["case", ["has", "ele"], ["concat", "\n", ["to-string", ["get", "ele"]], " m"], ""],
                                       {"font-scale": 0.8}],
                        **text_layout({"text-size": interp([(11, 10), (15, 12)]), "text-max-width": 7, "text-padding": 6}),
                        "text-font": pk.get("font", FONT_ITALIC), "text-transform": "none"},
             "paint": {"text-color": pk.get("color", p["place_text"]), "text-halo-color": p["halo"], "text-halo-width": halo_w}})
    add({"id": "label-water", "type": "symbol", "source": "openmaptiles", "source-layer": "water_name",
         "minzoom": 10,
         "layout": {"text-field": ["coalesce", ["get", "name:es"], ["get", "name"]], "text-font": FONT_ITALIC,
                    "text-size": 12, "text-max-width": 8, "text-letter-spacing": 0.1},
         "paint": {"text-color": p["water_text"], "text-halo-color": p["water"], "text-halo-width": 1.2}})
    add({"id": "label-place-small", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
         "minzoom": 12, "maxzoom": 17,
         "filter": is_in("class", ["suburb", "quarter", "neighbourhood", "village", "hamlet"]),
         "layout": {"text-field": ["coalesce", ["get", "name:es"], ["get", "name"]], "text-font": cfg.get("place_font", FONT),
                    "text-size": interp([(12, 10), (16, 14)]),
                    **({"text-transform": "uppercase"} if cfg.get("place_upper", True) else {}),
                    "text-letter-spacing": 0.14 if cfg.get("place_upper", True) else 0.04, "text-max-width": 8},
         "paint": {"text-color": p["place_text"], "text-halo-color": p.get("place_halo", p["halo"]), "text-halo-width": cfg.get("place_halo_width", 1.4),
                   "text-opacity": interp([(12, 0.65), (16, 0.9)])}})
    add({"id": "label-place-city", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
         "maxzoom": 14, "filter": is_in("class", ["city", "town"]),
         "layout": {"text-field": ["coalesce", ["get", "name:es"], ["get", "name"]], "text-font": FONT_BOLD,
                    "text-size": interp([(4, 11), (10, 17), (13, 22)]), "text-max-width": 8,
                    "text-letter-spacing": 0.04},
         "paint": {"text-color": p["city_text"], "text-halo-color": p.get("city_halo", p["halo"]), "text-halo-width": 2}})
    if not cfg.get("housenumbers_below_pois"):
        add(housenumber_layer())

    # ---- Resultados de búsqueda / lugares mostrados ------------------------
    add({"id": "results-halo", "type": "circle", "source": "results",
         "paint": {"circle-color": cfg["results"]["color"], "circle-opacity": 0.25,
                   "circle-radius": interp([(10, 9), (16, 17)])}})
    add({"id": "results-core", "type": "circle", "source": "results",
         "paint": {"circle-color": cfg["results"]["color"], "circle-radius": interp([(10, 4), (16, 7)]),
                   "circle-stroke-color": cfg["results"]["stroke"], "circle-stroke-width": 2}})
    add({"id": "results-label", "type": "symbol", "source": "results", "minzoom": 13,
         "layout": {"text-field": ["get", "name"], "text-font": FONT_BOLD, "text-size": 12,
                    "text-offset": [0, 1.1], "text-anchor": "top", "text-max-width": 8, "text-optional": True},
         "paint": {"text-color": p["city_text"], "text-halo-color": p.get("city_halo", p["halo"]), "text-halo-width": 1.8}})

    # ---- Destino y usuario (siempre encima) -----------------------------
    if cfg.get("saved_places"):
        # Casa y Trabajo guardados por el usuario (iconos propios, visibles desde zoom medio).
        add({"id": "saved-places", "type": "symbol", "source": "saved", "minzoom": 9,
             "layout": {"icon-image": ["get", "icon"], "icon-size": interp([(9, 0.5), (15, 0.75), (18, 0.9)]),
                        "icon-allow-overlap": True, "icon-ignore-placement": True}})
    if cfg.get("selection"):
        # Cuatro flechas alrededor del punto seleccionado. Imagen única anclada a la coordenada: sigue al
        # punto al mover, rotar o ampliar, y conserva el tamaño en pantalla.
        add({"id": "selection-arrows", "type": "symbol", "source": "selection",
             "layout": {"icon-image": "selection-arrows", "icon-size": 1, "icon-allow-overlap": True,
                        "icon-ignore-placement": True, "icon-rotation-alignment": "viewport",
                        "icon-pitch-alignment": "viewport"},
             "paint": {"icon-opacity": 1, "icon-opacity-transition": {"duration": 220, "delay": 0}}})
    if cfg["destination"].get("icon"):
        add({"id": "destination-core", "type": "symbol", "source": "destination",
             "layout": {"icon-image": cfg["destination"]["icon"], "icon-size": 0.8, "icon-anchor": "bottom",
                        "icon-allow-overlap": True, "icon-ignore-placement": True}})
    else:
        add({"id": "destination-halo", "type": "circle", "source": "destination",
             "paint": {"circle-color": cfg["destination"]["color"], "circle-opacity": 0.28,
                       "circle-radius": interp([(8, 14), (16, 26)])}})
        add({"id": "destination-core", "type": "circle", "source": "destination",
             "paint": {"circle-color": cfg["destination"]["color"], "circle-radius": interp([(8, 6), (16, 10)]),
                       "circle-stroke-color": cfg["destination"]["stroke"], "circle-stroke-width": 2.5}})
    add({"id": "user-halo", "type": "circle", "source": "user",
         "paint": {"circle-color": cfg["user"]["halo"], "circle-opacity": 0.22,
                   "circle-radius": interp([(8, 16), (16, 30)])}})
    add({"id": "user-arrow", "type": "symbol", "source": "user",
         "layout": {"icon-image": "user-arrow", "icon-rotate": ["coalesce", ["get", "heading"], 0],
                    "icon-rotation-alignment": "map", "icon-pitch-alignment": "map",
                    "icon-allow-overlap": True, "icon-ignore-placement": True,
                    "icon-size": cfg["user"].get("size", 1)}})

    empty = {"type": "FeatureCollection", "features": []}
    return {
        "version": 8,
        "name": cfg["name"],
        "metadata": {"questmap:generator": "tools/build_styles.py", "questmap:style-id": cfg["id"],
                     "questmap:reference": cfg["reference"],
                     "questmap:images": sorted({t["pattern"] for t in cfg.get("overlays", [])}
                                                  | ({cfg["background_pattern"]} if cfg.get("background_pattern") else set()))},
        "glyphs": "{{GLYPHS_URL}}",
        "sources": {
            "openmaptiles": {"type": "vector", "url": "{{TILES_URL}}"},
            **({"world": {"type": "geojson", "data": {"type": "Feature", "properties": {}, "geometry": {
                "type": "Polygon", "coordinates": [[[-180, -85], [180, -85], [180, 85], [-180, 85], [-180, -85]]]}}}}
               if cfg.get("background_pattern") else {}),
            "route": {"type": "geojson", "data": empty},
            "results": {"type": "geojson", "data": empty},
            "destination": {"type": "geojson", "data": empty},
            **({"selection": {"type": "geojson", "data": empty}} if cfg.get("selection") else {}),
            **({"saved": {"type": "geojson", "data": empty}} if cfg.get("saved_places") else {}),
            "user": {"type": "geojson", "data": empty},
            "traffic-signals": {"type": "geojson", "data": empty},
        },
        **({"light": cfg["buildings_3d"]["light"]} if cfg.get("buildings_3d") else {}),
        "layers": layers,
    }


def interp_rank():
    """Densidad de POI según el zoom: a menos zoom, solo los de mayor importancia (rank bajo)."""
    return interp([(15, 6), (16, 12), (17, 30), (18, 99)])


NOIR = {
    "id": "ciudadNocturna",
    "name": "Ciudad nocturna",
    "reference": "Lenguaje visual de mapa urbano de videojuego nocturno. Referencias: captura del mapa de pausa aportada por el usuario (carreteras gris medio, manzanas gris oscuro, ruta violeta) y captura anterior de casco urbano. Los HEX son una propuesta de partida afinada a ojo: NO son colores extraídos exactamente. Comparación píxel a píxel NO realizada.",
    "road_k": 1.3,
    # Calles secundarias y caminos más finos que las principales, sin que desaparezcan.
    "tier_k": {"motorway": 1.15, "trunk": 1.1, "primary": 1.0, "secondary": 0.9, "tertiary": 0.8, "minor": 0.68, "service": 0.55},
    # Etiquetas menos dominantes: texto normal (con tildes y mayúsculas originales), fuente regular y poco halo.
    "labels": {"font": FONT, "upper": False, "halo": 1.6, "road_size": 11, "spacing": 340},
    "palette": {
        "land": "#191919", "grass": "#1c1c1c", "wood": "#1a1a1a", "sand": "#202020", "farm": "#1b1b1b",
        "rock": "#202020", "residential": "#1a1a1a", "commercial": "#1d1d1d", "industrial": "#1b1b1b",
        "institution": "#1e1e1e", "sports": "#1e1e1e", "cemetery": "#1b1b1b", "military": "#1c1b1c",
        "water": "#26343A", "water_edge": "#34464d", "water_text": "#8fa3ab",
        "runway": "#2a2a2a",
        "building": "#303030", "building_edge": "#3b3b3b", "building_opacity": 1.0,
        "pedestrian": "#2a2a2a", "path": "#686868", "rail": "#5a5a5a", "tunnel": "#6a6a6a",
        "casing": "#0f0f0f", "casing_min": 0.7, "casing_ratio": 0.18,
        "road": {"motorway": "#A6A6A6", "trunk": "#A6A6A6", "primary": "#A6A6A6", "secondary": "#858585",
                 "tertiary": "#7a7a7a", "minor": "#707070", "service": "#5a5a5a"},
        "road_text": "#b5b5b5", "halo": "#121212", "place_text": "#8a8a8a", "city_text": "#c4c4c4",
        "poi_text": "#b0b0b0",
    },
    # Niveles de aparición (id, clases, zoom del icono, zoom del nombre): lo importante antes, comida y comercio muy cerca.
    "poi_tiers": [
        ("a", ["fuel", "hospital", "police", "railway", "bus"], 14.5, 16.5),
        ("b", ["parking", "pharmacy", "doctors", "dentist", "veterinary", "bank", "atm", "lodging", "grocery",
               "museum", "attraction", "castle", "monument", "theatre", "cinema", "art_gallery", "library",
               "fire_station", "prison"], 16, 17.2),
        ("c", ["restaurant", "fast_food", "cafe", "bakery", "ice_cream", "bar", "pub", "beer", "shop",
               "clothing_store", "butcher", "alcohol_shop", "laundry", "hairdresser"], 17, 18),
    ],
    "place_upper": False,       # barrios con mayúsculas y tildes originales, sin forzar versalitas
    "selection": True,
    "saved_places": True,
    "boundaries": {"color": "#6a6a6a", "opacity": 0.55},
    # Volumen gris oscuro: más claro cuanto más alto. Tejado distinto de fachada por la luz y el degradado vertical.
    "buildings_3d": {"colors": [(0, "#2b2b2b"), (40, "#383838"), (120, "#464646")], "max_height": 120,
                     "light": {"anchor": "viewport", "color": "#ffffff", "intensity": 0.45, "position": [1.15, 205, 40]}},
    "route": {"core": "#A855E8", "casing": "#0f0f0f", "glow": "#A855E8", "glow_opacity": 0.28},
    "destination": {"color": "#ffd400", "stroke": "#0a0b0d", "icon": "poi-destination"},
    "results": {"color": "#5AA9FF", "stroke": "#0f0f0f"},
    "user": {"halo": "#ffffff", "size": 1.35},
}

CLARO = {
    "id": "minimalistaPro",
    "name": "Minimalista Pro",
    "reference": "Estilo propio claro y legible para conducir de día. Sin referencia a videojuegos.",
    "palette": {
        "land": "#f3f4f7", "grass": "#dfeed8", "wood": "#d3e6cc", "sand": "#f0ebdc", "farm": "#eef0e2",
        "rock": "#e4e6ea", "residential": "#eff0f4", "commercial": "#ebecf2", "industrial": "#e8e9ee",
        "institution": "#ecebf4", "sports": "#dcecd9", "cemetery": "#dfe9dc", "military": "#ecdfe3",
        "water": "#bcd8f0", "water_edge": "#9cc3e4", "water_text": "#4d7fae",
        "runway": "#d5d8df",
        "building": "#e3e5ec", "building_edge": "#cfd2dc", "building_opacity": 0.95,
        "pedestrian": "#eceef3", "path": "#b9bec9", "rail": "#c1c6d1", "tunnel": "#a9afbd",
        "casing": "#c9cdd8", "casing_min": 0.7, "casing_ratio": 0.16,
        "road": {"motorway": "#ffd27d", "trunk": "#ffe3a8", "primary": "#ffffff", "secondary": "#ffffff",
                 "tertiary": "#ffffff", "minor": "#ffffff", "service": "#fbfbfd"},
        "road_text": "#3b4252", "halo": "#ffffff", "place_text": "#6b7385", "city_text": "#1f2430",
        "poi_fuel": "#f08a2c", "poi_parking": "#2f86e8", "poi_health": "#e5484d", "poi_police": "#5865e6",
        "poi_food": "#f2b21a", "poi_shop": "#d94fb7", "poi_culture": "#1fb89a", "poi_other": "#8a93a6",
        "poi_stroke": "#ffffff", "poi_text": "#4a5163",
    },
    "route": {"core": "#0a84ff", "casing": "#ffffff", "glow": "#0a84ff", "glow_opacity": 0.2},
    "destination": {"color": "#ff3b30", "stroke": "#ffffff"},
    "results": {"color": "#ff9f0a", "stroke": "#ffffff"},
    "user": {"halo": "#0a84ff"},
}


ISLA = {
    "id": "islaRoyale",
    "name": "Isla",
    "reference": "Vista cenital de isla de battle royale, referencia: mapa de la Temporada 3 del Capítulo 1 (galería de theclick.gg, analizada en navegador). Técnicas: verde saturado por clases de suelo, copas de árbol y hierba con texturas procedurales, aguas poco profundas, zonas urbanas claras. Comparación píxel a píxel NO realizada.",
    "road_k": 0.55,
    "labels": {"font": FONT_BOLD, "upper": True, "halo": 2.4, "roads": False},
    "shore": {"color": "#55b4ea", "opacity": 0.55},
    "overlays": [
        {"id": "tex-wood", "layer": "landcover", "classes": ["wood"], "pattern": "tex-canopy", "after": "landuse"},
        {"id": "tex-grass", "layer": "landcover", "classes": ["grass", "wetland", "farmland"], "pattern": "tex-grass",
         "after": "landuse", "opacity": 0.7, "minzoom": 12},
    ],
    "palette": {
        "land": "#74a83a", "grass": "#86b947", "wood": "#3d7a2a", "sand": "#d8ca90", "farm": "#b8b83e",
        "rock": "#8f8672", "residential": "#9ab05c", "commercial": "#c6c4ae", "industrial": "#a49e86",
        "institution": "#b4be84", "sports": "#98c957", "cemetery": "#78a045", "military": "#8c8c6c",
        "water": "#1e5c9e", "water_edge": "#7cc8f2", "water_text": "#eaf7ff",
        "runway": "#b8b39b",
        "building": "#ebe8de", "building_edge": "#a29e8c", "building_opacity": 1.0,
        "pedestrian": "#d9d5c1", "path": "#c8b888", "rail": "#8c8470", "tunnel": "#bdb28e",
        "casing": "#8f8561", "casing_min": 0.6, "casing_ratio": 0.12,
        "road": {"motorway": "#f2ebd3", "trunk": "#ede5c9", "primary": "#e7ddbd", "secondary": "#dfd4b1",
                 "tertiary": "#d7cba5", "minor": "#d0c39b", "service": "#c5b88f"},
        "road_text": "#ffffff", "halo": "#18290f", "place_text": "#ffffff", "city_text": "#ffffff",
        "poi_text": "#ffffff",
    },
    # Volúmenes simplificados: alturas en escalones de 6 m, tope bajo y colores cálidos y claros sobre el verde.
    "unpaved": {"color": "#fff3c4", "dash": [2.2, 1.4]},
    "peaks": {"color": "#ffffff"},
    "boundaries": {"color": "#fff6d0", "opacity": 0.55},
    "buildings_3d": {"colors": [(0, "#f3ecda"), (24, "#f2d27a"), (48, "#eca35c"), (90, "#d0674a")], "max_height": 72,
                     "height_step": 6,
                     "light": {"anchor": "viewport", "color": "#fff6e0", "intensity": 0.5, "position": [1.15, 215, 50]}},
    "route": {"core": "#ff2e93", "casing": "#ffffff", "glow": "#ff2e93", "glow_opacity": 0.35},
    "destination": {"color": "#ffe600", "stroke": "#18290f"},
    "results": {"color": "#00e5ff", "stroke": "#18290f"},
    "user": {"halo": "#ffffff", "size": 1.2},
}

BLOQUES = {
    "id": "mundoBloques",
    "name": "Mundo de bloques",
    "reference": "Vista cenital de mundo de bloques (referencia: apariencia de BlueMap sobre mundos de Minecraft, bluecolored.de/bluemap). Técnicas: texturas de 16x16 'píxeles' repetidas (hierba, hojas, arena, agua, caminos, tablones), vías de extremos rectos y esquinas en ángulo. NO es un mundo voxel ni 3D. Comparación píxel a píxel NO realizada.",
    "road_k": 0.8,
    "road_cap": "butt",
    "road_join": "miter",
    "labels": {"font": FONT_BOLD, "upper": False, "halo": 2.6, "road_size": 12.5},
    "background_pattern": "tex-block-grass",
    "overlays": [
        {"id": "tex-wood", "layer": "landcover", "classes": ["wood"], "pattern": "tex-block-leaves", "after": "landuse"},
        {"id": "tex-sand", "layer": "landcover", "classes": ["sand"], "pattern": "tex-block-sand", "after": "landuse"},
        {"id": "tex-farm", "layer": "landcover", "classes": ["farmland"], "pattern": "tex-block-path", "after": "landuse",
         "opacity": 0.85},
        {"id": "tex-urban", "layer": "landuse", "classes": ["industrial", "commercial", "railway", "garages", "quarry"],
         "pattern": "tex-block-stone", "after": "landuse"},
        {"id": "tex-water", "layer": "water", "pattern": "tex-block-water", "after": "water"},
        {"id": "tex-building", "layer": "building", "pattern": "tex-block-planks", "after": "building", "minzoom": 14},
    ],
    "palette": {
        "land": "#68a53f", "grass": CLEAR, "wood": "#2c6620", "sand": "#dccd96", "farm": "#9a7a4a",
        "rock": "#7d7d7d", "residential": CLEAR, "commercial": "#8a8a8a", "industrial": "#6e6e6e",
        "institution": CLEAR, "sports": CLEAR, "cemetery": CLEAR, "military": CLEAR,
        "water": "#2f56b8", "water_edge": "#1d3a8a", "water_text": "#ffffff",
        "runway": "#8a8a8a",
        "building": "#a8824e", "building_edge": "#3a2a14", "building_opacity": 1.0,
        "pedestrian": "#9b7b4c", "path": "#7d5f37", "rail": "#555555", "tunnel": "#6a5030",
        "casing": "#3d2e18", "casing_min": 1.0, "casing_ratio": 0.18,
        "road": {"motorway": "#b5b5b5", "trunk": "#a8a8a8", "primary": "#a98a58", "secondary": "#a08150",
                 "tertiary": "#987a4a", "minor": "#9b7b4c", "service": "#8c6e42"},
        "road_text": "#ffffff", "halo": "#1d1d1d", "place_text": "#ffffff", "city_text": "#ffffff",
        "poi_text": "#ffffff",
    },
    # Prismas rectangulares con alturas en múltiplos de 3 m y la textura de tablones en las paredes.
    # NO son voxels: la huella real del edificio se extruye tal cual (ver docs/17).
    "unpaved": {"color": "#7d5f37", "dash": [1.2, 1.2]},
    "boundaries": {"color": "#1d1d1d", "opacity": 0.5, "dash": [1.2, 1.2]},
    "buildings_3d": {"pattern": "tex-block-planks", "max_height": 60, "height_step": 3,
                     "light": {"anchor": "viewport", "color": "#e9dcc4", "intensity": 0.55, "position": [1.15, 215, 35]}},
    "route": {"core": "#ffe14d", "casing": "#1d1d1d", "glow": "#ffe14d", "glow_opacity": 0.3},
    "destination": {"color": "#ff4d4d", "stroke": "#1d1d1d"},
    "results": {"color": "#4dd9ff", "stroke": "#1d1d1d"},
    "user": {"halo": "#ffffff", "size": 1.2},
}


# ---------------------------------------------------------------------------------------------
# Estilos de la Fase 4. Referencias: capturas CONSULTADAS en navegador (ver docs/18). Los colores son
# interpretaciones propias; no se ha extraído ningún color ni asset de los juegos.
# ---------------------------------------------------------------------------------------------

OESTE = {
    "id": "salvajeOeste",
    "name": "Mapa del salvaje oeste",
    "reference": "Interpretación de un mapa de tinta sobre papel ocre. Referencia consultada: imagen del mapa completo de un juego del oeste (vista general de baja resolución, sin detalle de símbolos a zoom alto). Rasgos trasladados: papel ocre, trazo fino negro sin contornos, agua como lavado gris verdoso, edificios como pequeñas manchas de tinta, etiquetas espaciadas en versalitas. Comparación píxel a píxel NO realizada.",
    "road_k": 0.4,
    "tier_k": {"motorway": 1.5, "trunk": 1.4, "primary": 1.25, "secondary": 1.1, "tertiary": 0.95, "minor": 0.8, "service": 0.7},
    "no_casing": True,
    "dash_tiers": {"service": [3, 2.2], "minor": [6, 1.6]},
    "boundaries": {"color": "#2b2118", "opacity": 0.7, "dash": [5, 2, 1, 2], "width": 1.6},
    "peaks": {"color": "#3a2c1c"},
    "ref_text": "#2b2118",
    "labels": {"font": FONT_BOLD, "upper": True, "halo": 1.4, "road_size": 10, "spacing": 380},
    "overlays": [
        {"id": "tex-wood", "layer": "landcover", "classes": ["wood"], "pattern": "tex-ink-stipple", "after": "landuse", "opacity": 0.9},
    ],
    "palette": {
        "land": "#cfae77", "grass": "#cfae77", "wood": "#c4a36d", "sand": "#dcc189", "farm": "#d3b57e",
        "rock": "#bd9d68", "residential": "#cfae77", "commercial": "#cdac75", "industrial": "#c8a770",
        "institution": "#cfae77", "sports": "#cfae77", "cemetery": "#cfae77", "military": "#cfae77",
        "water": "#98a393", "water_edge": "#4b4a3c", "water_text": "#3f4538",
        "runway": "#a98d5f",
        "building": "#7d6544", "building_edge": "#2b2118", "building_opacity": 0.55,
        "pedestrian": "#c9a972", "path": "#4a3b2a", "rail": "#2b2118", "tunnel": "#6b5a44",
        "casing": "#2b2118", "casing_min": 0.5, "casing_ratio": 0.1,
        "road": {"motorway": "#241a10", "trunk": "#241a10", "primary": "#2b2118", "secondary": "#2b2118",
                 "tertiary": "#33281c", "minor": "#3a2d1f", "service": "#4a3b2a"},
        "road_text": "#3a2c1c", "halo": "#d4b47e", "place_text": "#3a2c1c", "city_text": "#241a10",
        "poi_text": "#3a2c1c",
    },
    "route": {"core": "#a31f1f", "casing": "#f1e2bd", "glow": "#a31f1f", "glow_opacity": 0.18},
    "destination": {"color": "#a31f1f", "stroke": "#f1e2bd"},
    "results": {"color": "#2f5d62", "stroke": "#f1e2bd"},
    "user": {"halo": "#3a2c1c", "size": 1.2},
}

CIBER = {
    "id": "ciudadCiber",
    "name": "Ciudad ciber",
    "reference": "Jerarquía de un mapa urbano futurista. Referencia consultada: captura de un mapa de pausa de un juego de ciencia ficción (con interfaz): manzanas en rojo sangre con relieve, vías como bandas de cian translúcido con borde brillante y más anchas cuanto mayor es su rango, agua y vacíos casi negros, marcadores amarillos. NO es neón sobre negro: el rojo de los volúmenes y el cian de las vías cumplen funciones distintas. Comparación píxel a píxel NO realizada; el color de la ruta (amarillo) es una elección propia.",
    "road_k": 1.15,
    "tier_k": {"motorway": 1.2, "trunk": 1.1, "primary": 1.0, "secondary": 0.9, "tertiary": 0.78, "minor": 0.62, "service": 0.5},
    "labels": {"font": FONT_BOLD, "upper": True, "halo": 1.8, "road_size": 10.5, "spacing": 360},
    "boundaries": {"color": "#2fd0e4", "opacity": 0.4, "dash": [2, 3]},
    "ref_text": "#ffe94d",
    "palette": {
        "land": "#14060c", "grass": "#16080e", "wood": "#14070d", "sand": "#1a0a10", "farm": "#15070d",
        "rock": "#1a0a10", "residential": "#17080e", "commercial": "#1b0a11", "industrial": "#150810",
        "institution": "#1a0a11", "sports": "#16080e", "cemetery": "#16080e", "military": "#17080e",
        "water": "#08111f", "water_edge": "#1f4a66", "water_text": "#5fa8c9",
        "runway": "#103642",
        "building": "#7e1424", "building_edge": "#e04a5c", "building_opacity": 0.95,
        "pedestrian": "#0f2a33", "path": "#1b7f90", "rail": "#1b7f90", "tunnel": "#2c8a98",
        "casing": "#2fd0e4", "casing_min": 0.6, "casing_ratio": 0.16,
        "road": {"motorway": "#127484", "trunk": "#116a79", "primary": "#0f5d6b", "secondary": "#0d505c",
                 "tertiary": "#0b434d", "minor": "#093740", "service": "#072c34"},
        "road_text": "#9aeaf5", "halo": "#05080f", "place_text": "#d96a7a", "city_text": "#ffd1d8",
        "poi_text": "#e8f6f8",
    },
    "buildings_3d": {"colors": [(0, "#6a1020"), (40, "#9c1a2c"), (120, "#d03047")], "max_height": 140,
                     "light": {"anchor": "viewport", "color": "#ffd6dc", "intensity": 0.5, "position": [1.15, 205, 40]}},
    "route": {"core": "#fcee0a", "casing": "#05080f", "glow": "#fcee0a", "glow_opacity": 0.3},
    "destination": {"color": "#fcee0a", "stroke": "#05080f"},
    "results": {"color": "#2fd0e4", "stroke": "#05080f"},
    "user": {"halo": "#2fd0e4", "size": 1.25},
}

NORDICO = {
    "id": "mapaFantasia",
    "name": "Mapa de fantasía",
    "reference": "Interpretación PLANA (sin relieve real) de un mapa de pergamino envejecido. Referencia consultada: imagen del mapa de una provincia nórdica de fantasía alojada en una wiki de fans (papel sepia con pliegues, caminos en rojo pardo —continuos los principales y punteados los menores—, cerros dibujados en «^», ríos de tinta oscura). Rasgos trasladados: sepia oscuro, caminos rojo pardo, cerros y arbolado por textura de tinta, etiquetas en mayúsculas espaciadas. NO se promete relieve equivalente: haría falta una fuente de elevación y un motor de terreno. Comparación píxel a píxel NO realizada.",
    "road_k": 0.5,
    "tier_k": {"motorway": 1.4, "trunk": 1.3, "primary": 1.2, "secondary": 1.05, "tertiary": 0.9, "minor": 0.8, "service": 0.7},
    "no_casing": True,
    "dash_tiers": {"minor": [1, 2.4], "service": [1, 2.8]},
    "road_cap": "round",
    "boundaries": {"color": "#8c3a2a", "opacity": 0.8, "dash": [0.8, 2.2], "width": 1.8},
    "peaks": {"color": "#3b2a1c"},
    "ref_text": "#4a2418",
    "labels": {"font": FONT_BOLD, "upper": True, "halo": 1.6, "road_size": 10, "spacing": 400},
    "overlays": [
        {"id": "tex-hills", "layer": "landcover", "classes": ["rock", "ice"], "pattern": "tex-ink-hills", "after": "landuse"},
        {"id": "tex-trees", "layer": "landcover", "classes": ["wood"], "pattern": "tex-ink-trees", "after": "landuse"},
    ],
    "palette": {
        "land": "#c6ae84", "grass": "#c6ae84", "wood": "#bca37a", "sand": "#d3bd93", "farm": "#c9b088",
        "rock": "#b99f75", "residential": "#c6ae84", "commercial": "#c3aa80", "industrial": "#bea67c",
        "institution": "#c6ae84", "sports": "#c6ae84", "cemetery": "#c6ae84", "military": "#c6ae84",
        "water": "#b4bdb2", "water_edge": "#3f3a2f", "water_text": "#3f3a2f",
        "runway": "#a89070",
        "building": "#5a4634", "building_edge": "#33261a", "building_opacity": 0.7,
        "pedestrian": "#bfa67c", "path": "#7a3a2a", "rail": "#4a3a2a", "tunnel": "#8a6a52",
        "casing": "#33261a", "casing_min": 0.5, "casing_ratio": 0.1,
        "road": {"motorway": "#7a2a1e", "trunk": "#7a2a1e", "primary": "#832f22", "secondary": "#8c3a2a",
                 "tertiary": "#8c4030", "minor": "#8c4a35", "service": "#8c4a35"},
        "road_text": "#4a2418", "halo": "#cdb68c", "place_text": "#3b2a1c", "city_text": "#2b1d12",
        "poi_text": "#3b2a1c",
    },
    "route": {"core": "#b5321f", "casing": "#f0e0bd", "glow": "#b5321f", "glow_opacity": 0.2},
    "destination": {"color": "#b5321f", "stroke": "#f0e0bd"},
    "results": {"color": "#2e5a66", "stroke": "#f0e0bd"},
    "user": {"halo": "#3b2a1c", "size": 1.2},
}

RED = {
    "id": "redUrbana",
    "name": "Red urbana",
    "reference": "Mapa diurno, claro y plano de una ciudad costera. Referencia consultada: captura de un mapa de pausa de un juego de hackers en una bahía (manzanas gris claro con calles blancas, parques verdes, agua azul claro, autopistas amarillo-naranja, marcadores rojos pequeños). Es un lenguaje cartográfico claro, no un efecto de «interfaz hacker»: sin cuadrículas ni brillos. Comparación píxel a píxel NO realizada; el color de la ruta es propio.",
    "road_k": 1.1,
    "tier_k": {"motorway": 1.25, "trunk": 1.15, "primary": 1.0, "secondary": 0.9, "tertiary": 0.8, "minor": 0.7, "service": 0.55},
    "labels": {"font": FONT_BOLD, "upper": False, "halo": 2.0, "road_size": 11, "spacing": 330},
    "palette": {
        "land": "#d9dadc", "grass": "#9fd48f", "wood": "#86c777", "sand": "#ece3c4", "farm": "#cfe3b6",
        "rock": "#c9cacd", "residential": "#d6d7da", "commercial": "#d0d1d5", "industrial": "#cdced2",
        "institution": "#d3d6dc", "sports": "#a9d99a", "cemetery": "#b9dca9", "military": "#d2d0d4",
        "water": "#62b3e8", "water_edge": "#3c8fc9", "water_text": "#ffffff",
        "runway": "#c4c5c9",
        "building": "#c5c6ca", "building_edge": "#aeb0b6", "building_opacity": 0.9,
        "pedestrian": "#e6e7ea", "path": "#b0b2b8", "rail": "#9b9da3", "tunnel": "#bcbec4",
        "casing": "#b4b6bc", "casing_min": 0.6, "casing_ratio": 0.14,
        "road": {"motorway": "#f4b63d", "trunk": "#f6c45a", "primary": "#ffffff", "secondary": "#ffffff",
                 "tertiary": "#ffffff", "minor": "#fbfbfc", "service": "#f3f3f5"},
        "road_text": "#4a4d55", "halo": "#ffffff", "place_text": "#6a6d75", "city_text": "#2c2e34",
        "poi_text": "#4a4d55",
    },
    "buildings_3d": {"colors": [(0, "#dcdde0"), (60, "#c2c3c8"), (140, "#a9abb2")], "max_height": 140,
                     "light": {"anchor": "viewport", "color": "#ffffff", "intensity": 0.45, "position": [1.15, 210, 45]}},
    "route": {"core": "#e8452c", "casing": "#ffffff", "glow": "#e8452c", "glow_opacity": 0.22},
    "destination": {"color": "#e8452c", "stroke": "#ffffff"},
    "results": {"color": "#1f6fe8", "stroke": "#ffffff"},
    "user": {"halo": "#1f6fe8", "size": 1.2},
}

RALLY = {
    "id": "rutasRally",
    "name": "Rutas de rally",
    "reference": "Mapa de terreno vivo con red viaria jerarquizada. Referencia consultada: imagen del mapa completo de un juego de conducción (vista general de baja resolución: terreno satelital verde/ocre/oscuro, costa turquesa, red de carreteras en líneas claras de grosor jerárquico). Rasgos trasladados: tierra saturada, carreteras claras con contorno oscuro y jerarquía por ancho y color, caminos sin asfaltar discontinuos (dato real `surface`). No se dibujan carreras, eventos ni coleccionables: solo los lugares reales del usuario. Los símbolos del juego no se pudieron analizar a este nivel de detalle. Comparación píxel a píxel NO realizada.",
    "road_k": 1.0,
    "tier_k": {"motorway": 1.25, "trunk": 1.15, "primary": 1.05, "secondary": 0.95, "tertiary": 0.82, "minor": 0.68, "service": 0.55},
    "unpaved": {"color": "#f0d79b", "dash": [2, 1.5]},
    "peaks": {"color": "#ffffff"},
    "boundaries": {"color": "#ffffff", "opacity": 0.4},
    "labels": {"font": FONT_BOLD, "upper": True, "halo": 2.2, "road_size": 11, "spacing": 330},
    "palette": {
        "land": "#6e8f45", "grass": "#78a04a", "wood": "#4d7236", "sand": "#d8c38e", "farm": "#b48b44",
        "rock": "#5b4a3c", "residential": "#8a9a62", "commercial": "#9aa070", "industrial": "#8b8468",
        "institution": "#86a05a", "sports": "#7fae52", "cemetery": "#6a9448", "military": "#7a8456",
        "water": "#1f95ad", "water_edge": "#8fe0e8", "water_text": "#eefcff",
        "runway": "#cfc9b6",
        "building": "#a8a08a", "building_edge": "#6a6352", "building_opacity": 0.95,
        "pedestrian": "#b9b49c", "path": "#e5cf94", "rail": "#7c7561", "tunnel": "#bdb7a0",
        "casing": "#2a2723", "casing_min": 0.8, "casing_ratio": 0.2,
        "road": {"motorway": "#ffffff", "trunk": "#fbf6e6", "primary": "#f7f1de", "secondary": "#f2ebd3",
                 "tertiary": "#ece4c8", "minor": "#e6dcbc", "service": "#ddd1ac"},
        "road_text": "#ffffff", "halo": "#1d241a", "place_text": "#ffffff", "city_text": "#ffffff",
        "poi_text": "#ffffff",
    },
    "route": {"core": "#ff7a00", "casing": "#ffffff", "glow": "#ff7a00", "glow_opacity": 0.3},
    "destination": {"color": "#ff7a00", "stroke": "#ffffff"},
    "results": {"color": "#35d0ff", "stroke": "#1d241a"},
    "user": {"halo": "#ffffff", "size": 1.25},
}


# Ficha visual (docs/30-estilo-gta-vi.md). Todos los HEX son APROXIMADOS: medidos en capturas comprimidas con
# cuantización de color y lectura de parches ampliados, descartando las zonas negras sin descubrir. No son valores
# oficiales.
COSTA = {
    "id": "costaTropical",
    "name": "Costa tropical",
    "reference": "Mapa de pausa claro de un videojuego de costa tropical. Referencias: cuatro capturas aportadas por el usuario (origen no verificado: no se ha acreditado que sean oficiales) y un fotograma del minimapa del avance oficial «Una mirada extendida» (ruta rosa, flecha blanca en círculo negro, rectángulo redondeado). Se reproduce el tratamiento de las zonas DESCUBIERTAS de las dos capturas claras: suelo urbano gris frío, edificios azul pizarra, agua turquesa con borde claro, vegetación verde agua desaturada, calles casi blancas sin contorno marcado y autopistas crema. Las zonas negras sin descubrir, el cursor, el contorno de selección y los nombres ficticios NO se reproducen. Las dos capturas oscuras (agua violeta, tierra verde oscuro) son otro régimen de luz completo, no un tipo de agua: no se mezclan con este estilo. Ruta, destino, etiquetas de calles y edificios 3D son adaptaciones propias. HEX aproximados medidos a ojo y por cuantización; comparación píxel a píxel NO realizada.",
    # Autopistas finas como en la referencia: varias calzadas paralelas reales no deben fundirse en una banda que tape
    # las calles de al lado.
    "road_k": 1.0,
    "tier_k": {"motorway": 0.9, "trunk": 0.88, "primary": 0.95, "secondary": 0.85, "tertiary": 0.78, "minor": 0.68, "service": 0.52},
    # Contorno apenas más oscuro que el suelo: en las capturas las calles no llevan borde; aquí solo separa.
    "casing_boost": {"motorway": 1.3, "trunk": 1.15},
    "rail_ties": False,
    "labels": {"font": FONT, "upper": False, "halo": 1.5, "road_size": 11, "spacing": 340},
    "palette": {
        # Suelo base gris frío (zonas urbanas claras de la captura de ciudad); la vegetación y el campo, verde agua.
        "land": "#b6bcc5", "grass": "#78a892", "wood": "#5f957f", "sand": "#d6d7cf", "farm": "#86ae9b",
        "rock": "#a4abb3", "residential": "#bbc0c9", "commercial": "#c2c6ce", "industrial": "#b2b8c2",
        "institution": "#bec3cc", "sports": "#82b29b", "cemetery": "#7caa94", "military": "#b0b5be",
        "water": "#43aed0", "water_edge": "#b7e6f2", "water_text": "#effaff",
        "runway": "#dadde3",
        "building": "#93a5c3", "building_edge": "#7d91b3", "building_opacity": 1.0,
        "pedestrian": "#cdd1d8", "path": "#eceef1", "rail": "#8b93a4", "tunnel": "#d3d7de",
        "casing": "#9ba3b1", "casing_min": 0.5, "casing_ratio": 0.1,
        "road": {"motorway": "#e6e2c6", "trunk": "#e9e6d1", "primary": "#eef0f2", "secondary": "#eceef1",
                 "tertiary": "#e8eaee", "minor": "#e3e6ea", "service": "#d9dce2"},
        "road_text": "#4e5566", "halo": "#eef0f3", "ref_text": "#5c6372",
        # Nombres de lugares: blanco con contorno oscuro (como «Centro» en la captura); barrios gris muy claro.
        "place_text": "#eef0f4", "place_halo": "#4a5061", "city_text": "#ffffff", "city_halo": "#373c4b",
        "poi_text": "#3f4656", "cycle": "#4fae86", "transit_line": "#6f7fd8",
    },
    "poi_tiers": [
        ("a", ["fuel", "hospital", "police", "railway", "bus", "ferry_terminal", "fire_station"], 14.5, 16.5),
        ("b", ["parking", "pharmacy", "doctors", "dentist", "veterinary", "bank", "atm", "lodging", "grocery",
               "museum", "attraction", "castle", "monument", "theatre", "cinema", "art_gallery", "library",
               "prison", "car", "harbor", "sports_centre", "golf", "post"], 16, 17.2),
        ("c", ["restaurant", "fast_food", "cafe", "bakery", "ice_cream", "bar", "pub", "beer", "shop",
               "clothing_store", "butcher", "alcohol_shop", "laundry", "hairdresser", "music"], 17, 18),
    ],
    # Categorías de la referencia con equivalente REAL en OpenStreetMap (clases y subclases de OpenMapTiles comprobadas
    # en teselas reales). Las que no existen fuera del juego (atracos, coleccionables, armerías…) no tienen icono.
    "extra_poi_classes": {"shops": ["car", "music"], "other": ["harbor", "sports_centre", "golf", "post"],
                          "transit": ["ferry_terminal"]},
    "poi_class_icons": [
        (["fast_food"], "poi-burger"), (["beer"], "poi-mug"), (["alcohol_shop"], "poi-bottle"),
        (["grocery"], "poi-cart"), (["clothing_store"], "poi-clothes"), (["hairdresser"], "poi-beauty"),
        (["car"], "poi-car"), (["harbor"], "poi-marina"), (["ferry_terminal"], "poi-ferry"),
        (["cinema"], "poi-cinema"), (["theatre"], "poi-theatre"), (["fire_station"], "poi-fire"),
        (["pharmacy"], "poi-pharmacy"), (["dentist"], "poi-dentist"), (["sports_centre"], "poi-gym"),
        (["golf"], "poi-golf"), (["bank"], "poi-coin"), (["atm"], "poi-atm"), (["monument"], "poi-monument"),
        (["castle"], "poi-castle"), (["attraction"], "poi-attraction"), (["post"], "poi-post"),
        (["library"], "poi-books"), (["ice_cream"], "poi-ice-cream"), (["bakery"], "poi-bakery"),
        (["music"], "poi-music"), (["art_gallery"], "poi-art"), (["veterinary"], "poi-vet"),
    ],
    "poi_subclass_icons": [
        (["nightclub"], "poi-nightclub"), (["pub"], "poi-mug"), (["convenience", "kiosk"], "poi-basket"),
        (["supermarket"], "poi-cart"), (["shoes"], "poi-shoes"), (["tattoo"], "poi-tattoo"),
        (["beauty", "cosmetics", "perfumery"], "poi-beauty"),
        (["mobile_phone", "electronics", "computer"], "poi-electronics"),
        (["car_repair"], "poi-car-repair"), (["car_wash"], "poi-car-wash"), (["charging_station"], "poi-charging"),
        (["marina"], "poi-marina"), (["gift"], "poi-gift"), (["florist"], "poi-florist"),
        (["jewelry"], "poi-jewelry"), (["optician"], "poi-optician"), (["books"], "poi-books"),
    ],
    "poi_icon_scale": 1.3,
    "housenumbers_below_pois": True,
    "place_upper": False,
    "place_font": FONT_BOLD,
    "place_halo_width": 0.9,
    "selection": True,
    "saved_places": True,
    "boundaries": {"color": "#ffffff", "opacity": 0.4},
    # Adaptación propia: las referencias son planas. Volúmenes en el mismo azul pizarra, más claros cuanto más altos.
    "buildings_3d": {"colors": [(0, "#879cbf"), (40, "#97abcc"), (120, "#adbedb")], "max_height": 140,
                     "light": {"anchor": "viewport", "color": "#ffffff", "intensity": 0.4, "position": [1.15, 210, 40]}},
    # Ruta: rosa del minimapa del avance oficial (aproximado). Contorno blanco: adaptación para separarla de las calles.
    "route": {"core": "#f0559e", "casing": "#ffffff", "glow": "#f0559e", "glow_opacity": 0.3},
    # Destino: pin turquesa como el que aparece en las capturas (su función en el juego no está acreditada).
    "destination": {"color": "#3fd8c2", "stroke": "#1b1e26", "icon": "poi-destination"},
    "results": {"color": "#7b6cf0", "stroke": "#ffffff"},
    "user": {"halo": "#1b1e26", "size": 1.2},
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for cfg, filename in ((NOIR, "style-ciudad-nocturna.json"), (CLARO, "style-minimalista-pro.json"),
                           (ISLA, "style-isla.json"), (BLOQUES, "style-bloques.json"),
                           (OESTE, "style-salvaje-oeste.json"), (CIBER, "style-ciudad-ciber.json"),
                           (NORDICO, "style-mapa-fantasia.json"), (RED, "style-red-urbana.json"),
                           (RALLY, "style-rutas-rally.json"), (COSTA, "style-costa-tropical.json")):
        style = build_style(cfg)
        path = os.path.join(OUT_DIR, filename)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(style, f, ensure_ascii=False, indent=1)
            f.write("\n")
        print(f"{filename}: {len(style['layers'])} capas")


if __name__ == "__main__":
    main()
