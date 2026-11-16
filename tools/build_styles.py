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

    def add(layer):
        layers.append(layer)

    add({"id": "background", "type": "background", "paint": {"background-color": p["land"]}})

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

    # ---- Agua ------------------------------------------------------------
    add({"id": "water", "type": "fill", "source": "openmaptiles", "source-layer": "water",
         "paint": {"fill-color": p["water"]}})
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
    def casing(tier, brunnel, ramps, ident):
        widths = ROAD_WIDTH[tier]
        k = 0.7 if ramps else 1.0
        stops = [(z, round(w * k + max(p["casing_min"], w * k * p["casing_ratio"]), 3)) for z, w in widths]
        return {"id": ident, "type": "line", "source": "openmaptiles", "source-layer": "transportation",
                "minzoom": ROAD_MINZOOM[tier] + (0.5 if ramps else 0),
                "filter": road_filter(tier, brunnel, ramps),
                "layout": {"line-cap": "butt", "line-join": "round"},
                "paint": {"line-color": p["casing"], "line-width": interp(stops)}}

    def fill(tier, brunnel, ramps, ident):
        widths = ROAD_WIDTH[tier]
        k = 0.7 if ramps else 1.0
        return {"id": ident, "type": "line", "source": "openmaptiles", "source-layer": "transportation",
                "minzoom": ROAD_MINZOOM[tier] + (0.5 if ramps else 0),
                "filter": road_filter(tier, brunnel, ramps),
                "layout": {"line-cap": "round", "line-join": "round"},
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

    # ---- POI: puntos de color por clase (iconos propios en un sprite futuro)
    poi_colors = [
        (["fuel"], p["poi_fuel"]),
        (["parking"], p["poi_parking"]),
        (["hospital", "pharmacy", "doctors", "dentist", "veterinary"], p["poi_health"]),
        (["police", "fire_station", "prison"], p["poi_police"]),
        (["restaurant", "fast_food", "cafe", "bar", "pub", "beer", "ice_cream", "bakery"], p["poi_food"]),
        (["shop", "grocery", "clothing_store", "butcher", "alcohol_shop", "laundry", "hairdresser"], p["poi_shop"]),
        (["museum", "attraction", "castle", "monument", "theatre", "cinema", "art_gallery", "library"], p["poi_culture"]),
    ]
    poi_classes = [c for classes, _ in poi_colors for c in classes]
    poi_filter = ["all", is_in("class", poi_classes),
                  ["<=", ["coalesce", ["get", "rank"], 99], interp_rank()]]
    add({"id": "poi-dot", "type": "circle", "source": "openmaptiles", "source-layer": "poi",
         "minzoom": 15, "filter": poi_filter,
         "paint": {"circle-color": match("class", poi_colors, p["poi_other"]),
                   "circle-radius": interp([(15, 2.4), (17, 4.2), (19, 6)]),
                   "circle-stroke-color": p["poi_stroke"], "circle-stroke-width": interp([(15, 0.8), (18, 1.6)])}})
    add({"id": "poi-label", "type": "symbol", "source": "openmaptiles", "source-layer": "poi",
         "minzoom": 16.5, "filter": poi_filter,
         "layout": {"text-field": ["coalesce", ["get", "name:es"], ["get", "name"]],
                    "text-font": FONT, "text-size": interp([(16.5, 10), (19, 12)]),
                    "text-offset": [0, 0.9], "text-anchor": "top", "text-max-width": 7,
                    "text-optional": True},
         "paint": {"text-color": p["poi_text"], "text-halo-color": p["halo"], "text-halo-width": 1.4}})

    # ---- Etiquetas -------------------------------------------------------
    road_label_zoom = [("motorway", 10.5), ("trunk", 11), ("primary", 11.5), ("secondary", 12.5),
                       ("tertiary", 13.5), ("minor", 15)]
    for cls, z in road_label_zoom:
        add({"id": f"label-road-{cls}", "type": "symbol", "source": "openmaptiles",
             "source-layer": "transportation_name", "minzoom": z,
             "filter": ["==", ["get", "class"], cls],
             "layout": {"symbol-placement": "line", "symbol-spacing": 320,
                        "text-field": ["coalesce", ["get", "name:es"], ["get", "name"]],
                        "text-font": FONT, "text-size": interp([(11, 9.5), (16, 12.5), (19, 15)]),
                        "text-max-angle": 28, "text-letter-spacing": 0.02, "text-padding": 6},
             "paint": {"text-color": p["road_text"], "text-halo-color": p["halo"], "text-halo-width": 1.8}})
    add({"id": "label-water", "type": "symbol", "source": "openmaptiles", "source-layer": "water_name",
         "minzoom": 10,
         "layout": {"text-field": ["coalesce", ["get", "name:es"], ["get", "name"]], "text-font": FONT_ITALIC,
                    "text-size": 12, "text-max-width": 8, "text-letter-spacing": 0.1},
         "paint": {"text-color": p["water_text"], "text-halo-color": p["water"], "text-halo-width": 1.2}})
    add({"id": "label-place-small", "type": "symbol", "source": "openmaptiles", "source-layer": "place",
         "minzoom": 12, "maxzoom": 17,
         "filter": is_in("class", ["suburb", "quarter", "neighbourhood", "village", "hamlet"]),
         "layout": {"text-field": ["coalesce", ["get", "name:es"], ["get", "name"]], "text-font": FONT,
                    "text-size": interp([(12, 10), (16, 14)]), "text-transform": "uppercase",
                    "text-letter-spacing": 0.14, "text-max-width": 8},
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

    # ---- Destino y usuario (siempre encima) -----------------------------
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
                    "icon-allow-overlap": True, "icon-ignore-placement": True, "icon-size": 1}})

    empty = {"type": "FeatureCollection", "features": []}
    return {
        "version": 8,
        "name": cfg["name"],
        "metadata": {"questmap:generator": "tools/build_styles.py", "questmap:style-id": cfg["id"],
                     "questmap:reference": cfg["reference"]},
        "glyphs": "{{GLYPHS_URL}}",
        "sources": {
            "openmaptiles": {"type": "vector", "url": "{{TILES_URL}}"},
            "route": {"type": "geojson", "data": empty},
            "destination": {"type": "geojson", "data": empty},
            "user": {"type": "geojson", "data": empty},
        },
        "layers": layers,
    }


def interp_rank():
    """Densidad de POI según el zoom: a menos zoom, solo los de mayor importancia (rank bajo)."""
    return interp([(15, 6), (16, 12), (17, 30), (18, 99)])


NOIR = {
    "id": "ciudadNocturna",
    "name": "Ciudad nocturna",
    "reference": "Lenguaje visual de minimapa urbano nocturno (referencia: GTA V). Comparación con capturas concretas PENDIENTE.",
    "palette": {
        "land": "#161b24", "grass": "#1a2d27", "wood": "#17281f", "sand": "#222a2c", "farm": "#1b2420",
        "rock": "#222831", "residential": "#1a202a", "commercial": "#212835", "industrial": "#191e27",
        "institution": "#1f2733", "sports": "#1d3230", "cemetery": "#1b2a26", "military": "#271d24",
        "water": "#0c1c33", "water_edge": "#2c6aa3", "water_text": "#6aa0d6",
        "runway": "#2a3140",
        "building": "#2b3342", "building_edge": "#46536b", "building_opacity": 0.9,
        "pedestrian": "#222a36", "path": "#4a5568", "rail": "#3b4558", "tunnel": "#6b7587",
        "casing": "#07090d", "casing_min": 0.8, "casing_ratio": 0.2,
        "road": {"motorway": "#f2c14e", "trunk": "#e9d28c", "primary": "#e3e7ef", "secondary": "#c2c9d6",
                 "tertiary": "#9aa4b5", "minor": "#76809a", "service": "#566077"},
        "road_text": "#d3dbea", "halo": "#0a0d13", "place_text": "#8a98b3", "city_text": "#e6ecf7",
        "poi_fuel": "#ff8a3d", "poi_parking": "#5aa9ff", "poi_health": "#ff4d6d", "poi_police": "#7b86ff",
        "poi_food": "#ffd24d", "poi_shop": "#ff6fd8", "poi_culture": "#47e3c3", "poi_other": "#8d99b0",
        "poi_stroke": "#07090d", "poi_text": "#c0c9db",
    },
    "route": {"core": "#b6ff3b", "casing": "#07090d", "glow": "#b6ff3b", "glow_opacity": 0.3},
    "destination": {"color": "#ff3d71", "stroke": "#ffffff"},
    "user": {"halo": "#4cc9f0"},
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
    "user": {"halo": "#0a84ff"},
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for cfg, filename in ((NOIR, "style-ciudad-nocturna.json"), (CLARO, "style-minimalista-pro.json")):
        style = build_style(cfg)
        path = os.path.join(OUT_DIR, filename)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(style, f, ensure_ascii=False, indent=1)
            f.write("\n")
        print(f"{filename}: {len(style['layers'])} capas")


if __name__ == "__main__":
    main()
