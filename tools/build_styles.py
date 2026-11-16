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
    add({"id": "rail", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
         "minzoom": 11, "filter": ["all", ["==", ["get", "class"], "rail"],
                                   ["!", is_in("brunnel", ["tunnel"])]],
         "paint": {"line-color": p["rail"], "line-dasharray": [3, 3],
                   "line-width": interp([(11, 0.6), (16, 1.6)])}})

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
        stops = [(z, round(w * k + max(p["casing_min"], w * k * p["casing_ratio"]), 3)) for z, w in widths]
        return {"id": ident, "type": "line", "source": "openmaptiles", "source-layer": "transportation",
                "minzoom": ROAD_MINZOOM[tier] + (0.5 if ramps else 0),
                "filter": road_filter(tier, brunnel, ramps),
                "layout": {"line-cap": "butt", "line-join": cfg.get("road_join", "round")},
                "paint": {"line-color": p["casing"], "line-width": interp(stops)}}

    def fill(tier, brunnel, ramps, ident):
        widths = scaled(ROAD_WIDTH[tier], road_k * tier_k.get(tier, 1.0))
        k = 0.7 if ramps else 1.0
        return {"id": ident, "type": "line", "source": "openmaptiles", "source-layer": "transportation",
                "minzoom": ROAD_MINZOOM[tier] + (0.5 if ramps else 0),
                "filter": road_filter(tier, brunnel, ramps),
                "layout": {"line-cap": cfg.get("road_cap", "round"), "line-join": cfg.get("road_join", "round")},
                "paint": {"line-color": p["road"][tier], "line-width": interp(scaled(widths, k))}}

    for tier in TIERS:
        add(casing(tier, "surface", False, f"road-casing-{tier}"))
    for tier in ("secondary", "primary", "trunk", "motorway"):
        add(casing(tier, "surface", True, f"ramp-casing-{tier}"))
    for tier in TIERS:
        add(fill(tier, "surface", False, f"road-{tier}"))
    for tier in ("secondary", "primary", "trunk", "motorway"):
        add(fill(tier, "surface", True, f"ramp-{tier}"))

    # ---- Puentes (encima de todo lo anterior) ---------------------------
    for tier in TIERS:
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
        height = ["max", b3.get("min_height", 3), ["min", b3.get("max_height", 120),
                  ["to-number", ["coalesce", ["get", "render_height"], 6], 6]]]
        base = ["max", 0, ["to-number", ["coalesce", ["get", "render_min_height"], 0], 0]]
        add({"id": "building-3d", "type": "fill-extrusion", "source": "openmaptiles", "source-layer": "building",
             "minzoom": 15, "layout": {"visibility": "none"},
             "filter": ["!=", ["coalesce", ["get", "hide_3d"], False], True],
             "paint": {
                 "fill-extrusion-color": ["interpolate", ["linear"], height] + [x for z, c in b3["colors"] for x in (z, c)],
                 # Crecen suavemente entre z15 y z16 para evitar saltos bruscos al acercar.
                 "fill-extrusion-height": interp([(15, 0), (16, height)]),
                 "fill-extrusion-base": interp([(15, 0), (16, base)]),
                 "fill-extrusion-opacity": b3.get("opacity", 1.0),
                 "fill-extrusion-vertical-gradient": True}})

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

    # ---- POI: iconos (registrados por la app con el nombre "poi-*") --------
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
        (["bus", "railway"], "poi-transit"),
    ]
    poi_classes = [c for classes, _ in poi_icons for c in classes]
    poi_filter = ["all", is_in("class", poi_classes),
                  ["<=", ["coalesce", ["get", "rank"], 99], interp_rank()]]
    poi_name = ["coalesce", ["get", "name:es"], ["get", "name"]]
    if cfg.get("poi_tiers"):
        # Menos saturación: lo importante aparece antes; comida y comercio solo muy cerca. Las paradas
        # de autobús se omiten (hay miles). Los nombres aparecen un nivel de zoom después que el icono.
        for tier_id, classes, icon_zoom, label_zoom in cfg["poi_tiers"]:
            add({"id": f"poi-icon-{tier_id}", "type": "symbol", "source": "openmaptiles", "source-layer": "poi",
                 "minzoom": icon_zoom,
                 "filter": ["all", is_in("class", classes), ["!=", ["get", "subclass"], "bus_stop"],
                            ["<=", ["coalesce", ["get", "rank"], 99], interp_rank()]],
                 "layout": {"icon-image": match("class", poi_icons, "poi-shop"),
                            "icon-size": interp([(14.5, 0.5), (17, 0.72), (19, 0.92)]),
                            "icon-allow-overlap": False, "icon-padding": 6,
                            "symbol-sort-key": ["coalesce", ["get", "rank"], 99],
                            "text-field": ["step", ["zoom"], "", label_zoom, poi_name],
                            **text_layout({"text-size": interp([(16.5, 10), (19, 11.5)]),
                                           "text-offset": [0, 1.1], "text-anchor": "top", "text-max-width": 7,
                                           "text-padding": 4, "text-optional": True})},
                 "paint": {"text-color": p["poi_text"], "text-halo-color": p["halo"], "text-halo-width": halo_w}})
    else:
        add({"id": "poi-icon", "type": "symbol", "source": "openmaptiles", "source-layer": "poi",
             "minzoom": 15, "filter": poi_filter,
             "layout": {"icon-image": match("class", poi_icons, "poi-shop"),
                        "icon-size": interp([(15, 0.55), (17, 0.85), (19, 1.1)]),
                        "icon-allow-overlap": False, "icon-padding": 3,
                        "text-field": ["step", ["zoom"], "", 16.5, poi_name],
                        **text_layout({"text-size": interp([(16.5, 10.5), (19, 12.5)]),
                                       "text-offset": [0, 1.15], "text-anchor": "top", "text-max-width": 7,
                                       "text-optional": True})},
             "paint": {"text-color": p["poi_text"], "text-halo-color": p["halo"], "text-halo-width": halo_w}})

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
    add({"id": "label-water", "type": "symbol", "source": "openmaptiles", "source-layer": "water_name",
         "minzoom": 10,
         "layout": {"text-field": ["coalesce", ["get", "name:es"], ["get", "name"]], "text-font": FONT_ITALIC,
                    "text-size": 12, "text-max-width": 8, "text-letter-spacing": 0.1},
         "paint": {"text-color": p["water_text"], "text-halo-color": p["water"], "text-halo-width": 1.2}})
    add({"id": "label-place-small", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
         "minzoom": 12, "maxzoom": 17,
         "filter": is_in("class", ["suburb", "quarter", "neighbourhood", "village", "hamlet"]),
         "layout": {"text-field": ["coalesce", ["get", "name:es"], ["get", "name"]], "text-font": FONT,
                    "text-size": interp([(12, 10), (16, 14)]),
                    **({"text-transform": "uppercase"} if cfg.get("place_upper", True) else {}),
                    "text-letter-spacing": 0.14 if cfg.get("place_upper", True) else 0.04, "text-max-width": 8},
         "paint": {"text-color": p["place_text"], "text-halo-color": p["halo"], "text-halo-width": 1.4,
                   "text-opacity": interp([(12, 0.65), (16, 0.9)])}})
    add({"id": "label-place-city", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
         "maxzoom": 14, "filter": is_in("class", ["city", "town"]),
         "layout": {"text-field": ["coalesce", ["get", "name:es"], ["get", "name"]], "text-font": FONT_BOLD,
                    "text-size": interp([(4, 11), (10, 17), (13, 22)]), "text-max-width": 8,
                    "text-letter-spacing": 0.04},
         "paint": {"text-color": p["city_text"], "text-halo-color": p["halo"], "text-halo-width": 2}})
    add({"id": "label-housenumber", "type": "symbol", "source": "openmaptiles", "source-layer": "housenumber",
         "minzoom": 18,
         "layout": {"text-field": ["get", "housenumber"], "text-font": FONT, "text-size": 10},
         "paint": {"text-color": p["road_text"], "text-opacity": 0.7}})

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
         "paint": {"text-color": p["city_text"], "text-halo-color": p["halo"], "text-halo-width": 1.8}})

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
    "route": {"core": "#ffe14d", "casing": "#1d1d1d", "glow": "#ffe14d", "glow_opacity": 0.3},
    "destination": {"color": "#ff4d4d", "stroke": "#1d1d1d"},
    "results": {"color": "#4dd9ff", "stroke": "#1d1d1d"},
    "user": {"halo": "#ffffff", "size": 1.2},
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for cfg, filename in ((NOIR, "style-ciudad-nocturna.json"), (CLARO, "style-minimalista-pro.json"),
                           (ISLA, "style-isla.json"), (BLOQUES, "style-bloques.json")):
        style = build_style(cfg)
        path = os.path.join(OUT_DIR, filename)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(style, f, ensure_ascii=False, indent=1)
            f.write("\n")
        print(f"{filename}: {len(style['layers'])} capas")


if __name__ == "__main__":
    main()
