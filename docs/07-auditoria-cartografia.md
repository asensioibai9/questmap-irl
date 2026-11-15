# Auditoría del proyecto y decisión técnica de cartografía

Fecha de la auditoría: 15 nov 2026. Estado del código: commit `02c6f60`, compila y pasa 15 tests en CI. **No se ha ejecutado la app en un iPhone ni en un simulador**, así que todo lo que sigue sobre comportamiento visual es diagnóstico, no observación.

## 0. Lo que falta para empezar

**No ha llegado ninguna imagen de referencia.** El mensaje las menciona ("capturas adjuntas"), pero no he recibido ninguna. Mientras no las tenga no puedo afirmar fidelidad a nada ni elegir variante (minimapa, mapa completo, versión del juego). Todo lo de abajo trata los juegos como referencias que aún no he visto.

## 1. Qué hay realmente en el proyecto

| Área | Estado | Clasificación |
|---|---|---|
| Motor de mapas | SwiftUI `Map` de MapKit (iOS 17) | Implementado |
| Datos de mapa base | Apple Maps (vía MapKit) | Implementado |
| Búsqueda | `MKLocalSearch` con debounce y estados | Implementado |
| Rutas | `MKDirections`, alternativas, ordenadas por tiempo | Implementado |
| Navegación activa | Motor propio (`NavigationEngine`) sobre la polilínea, recálculo, voz | Implementado, **sin probar en movimiento real** |
| GPS | `CLLocationManager`, precisión por modo, suavizado, calidad de señal | Implementado, sin probar en iPhone |
| Temas | 6 temas = paleta de HUD + estilo base de MapKit + overlay `Canvas` | **Incompleto respecto al objetivo** (ver §2) |
| Pantalla completa | Causa probable corregida (faltaba `UILaunchScreen`) | **Corregido en teoría, no verificado** |
| Monetización | Eliminada; sin referencias en el código | Implementado |
| Niebla de guerra | Celdas y logros guardados; **no se dibuja sobre el mapa** | Incompleto |
| Minimapa compacto | No existe | No implementado |
| Mapa vectorial con estilo propio | No existe | No implementado (ver §2) |

Acoplamientos que condicionan una migración (revisados en el código):
- `RouteOption` contiene un `MKRoute`; `ActiveNavigationViewModel` y las vistas leen `route.route.polyline`, `steps`, `expectedTravelTime`.
- `PlaceSearchService` devuelve `[MKMapItem]`; `SearchView` y `HomeView` leen `item.placemark.coordinate`.
- `MapTheme.mapStyle` devuelve `MapStyle` de MapKit y las vistas usan `Map { ... }`, `MapPolyline`, `Annotation`, `MapCameraPosition`.
- Sí están desacoplados de MapKit: `NavigationEngine`, `FogGrid`, `ManeuverFormatter`, `LocationService`, `SpeechService`, SwiftData.

## 2. Qué puede y qué no puede hacer MapKit (comprobado)

MapKit no expone estilos de capa. Lo que el SDK permite sobre el mapa base:
- Elegir `MapStyle`: estándar, híbrido o imagen; énfasis (`automatic`/`muted`); elevación; filtro de puntos de interés; tráfico.
- Añadir **overlays propios** encima: polilíneas, polígonos, círculos, anotaciones.
- Añadir un `MKTileOverlay` con tiles propios; con `canReplaceMapContent = true` sustituye al mapa base, siempre que los tiles sean opacos y cubran todo.

No permite: cambiar el color de carreteras, agua, parques o edificios; controlar anchos o bordes de las vías por zoom; controlar etiquetas, tipografías ni sprites; reglas de visibilidad por zoom del mapa base; ordenar capas del mapa base.

**Conclusión: con MapKit solo no se puede reproducir el lenguaje cartográfico de un minimapa de videojuego.** Lo que hay hoy (colores de HUD, overlay, ruta en tres capas) es exactamente "un tema de app y un filtro", que es lo que describes como problema. Es una limitación técnica del motor, no un fallo de implementación.

## 3. Hallazgo legal que cambia el plan

Leído en el texto verbatim del Apple Developer Program License Agreement (sección *Attachment 6 – Additional Terms for the use of the Apple Maps Service*):
- §2.4: los datos de mapa de Apple, cuando se muestran en un mapa, **solo pueden mostrarse en un mapa de Apple** proporcionado por el servicio.
- §2.5: no se pueden cachear, precargar ni almacenar salvo de forma temporal y limitada.
- §2.2: prohibidas las descargas masivas y su uso como base de datos secundaria o derivada.
- §3.3.3(F)(iii): sí se permite superponer **tu propio contenido o ruta sobre mapas de Apple**; para guiado en tiempo real exige el aviso "YOUR USE OF THIS REAL TIME ROUTE GUIDANCE APPLICATION IS AT YOUR SOLE RISK…" en el EULA.

El acuerdo **no menciona expresamente** rutas o resultados de búsqueda sobre mapas no Apple; §2.4 lo desaconseja por implicación. Esto es una lectura mía del texto, no asesoría legal, y la versión exacta del acuerdo no se pudo fechar con certeza.

**Consecuencia:** si el mapa se dibuja con otro motor, las rutas (`MKDirections`) y los resultados de búsqueda (`MKLocalSearch`) de Apple no deberían mostrarse sobre él. Hay que **sustituir también el servicio de rutas y el de búsqueda**, no solo el renderizador.

## 4. Opciones de renderizado

| Opción | Fidelidad al objetivo | Licencia / riesgo | Coste de trabajo |
|---|---|---|---|
| A. Quedarse en MapKit + overlays | Baja: nunca cambia el mapa base | Sin riesgo | Ya hecho |
| B. `MKTileOverlay` con tiles raster propios | Alta *si* tienes tiles ya renderizados con el estilo | Zona gris: el mapa de Apple queda oculto pero sigue siendo el contenedor; exige servidor de tiles raster propio o proveedor | Alto: infraestructura de tiles; cambiar estilo = regenerar tiles; sin rotación vectorial ni inclinación estilizada |
| **C. MapLibre Native con tiles vectoriales y estilo JSON** | **Alta**: control de capas, anchos por zoom, bordes, orden, etiquetas, sprites, rotación e inclinación | Software BSD; datos OSM (ODbL) con atribución | Medio-alto: sustituir búsqueda y rutas |
| D. Renderizador propio (Metal/Canvas) | Máxima en teoría | Hay que escribir un renderizador de tiles vectoriales | Muy alto |

**Recomendación: C.** Es la única que cumple "si oculto la interfaz sigo reconociendo el estilo por cómo se dibuja el mapa" con datos reales e interactividad.

### Lo comprobado de MapLibre (fuente: página de releases y repo swiftui-dsl)
- Distribución iOS binaria: última estable **7.0.0** (28 oct). Mínimo **iOS 15.5**. Encaja con el iOS 17 del proyecto. Hubo cambio incompatible: la cabecera pasó a `MapLibre.h` (en Swift: `import MapLibre`).
- Wrapper SwiftUI `MapLibreSwiftUI` (repo `maplibre/swiftui-dsl`, BSD-3): **pre-1.0, sin versiones etiquetadas**, se instala desde `branch: main`; no garantiza API estable.
- **No verificado**: licencia de la librería nativa, nombres exactos de la API de fuentes y capas en tiempo de ejecución (`MLNShapeSource`, `MLNLineStyleLayer`) y API de ubicación de usuario del wrapper. Habrá que comprobarlos al compilar.
- **Decisión de ingeniería que propongo:** no depender del wrapper pre-1.0 sin versión; envolver `MLNMapView` yo mismo con `UIViewRepresentable`. Más código, pero API estable y control total de cámara, capas y anotaciones.

## 5. Proveedor de datos vectoriales (comprobado en los endpoints reales)

Candidato para prototipar: **OpenFreeMap** (público, sin clave). Verificado descargando su TileJSON y su estilo Liberty:
- TileJSON: `https://tiles.openfreemap.org/planet/latest` → HTTP 200, zoom 0–14, esquema **OpenMapTiles**.
- Source-layers reales: `aerodrome_label`, `aeroway`, `boundary`, `building`, `housenumber`, `landcover`, `landuse`, `mountain_peak`, `park`, `place`, `poi`, `transportation`, `transportation_name`, `water`, `water_name`, `waterway`.
- Campos útiles confirmados: `transportation.class/subclass/brunnel/ramp/oneway/expressway/layer`; `building.render_height/render_min_height/colour`; `landcover.class/subclass`; `landuse.class`; `water.class/brunnel`; `poi.class/subclass/rank`.
- Estilo oficial de ejemplo: `https://tiles.openfreemap.org/styles/liberty` (también `bright` y `positron`). Ese estilo referencia:
  - sprite: `https://tiles.openfreemap.org/sprites/ofm_f384/ofm`
  - glyphs: `https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf`
  - fuente vectorial: `https://tiles.openfreemap.org/planet`
- Atribución obligatoria: `OpenFreeMap © OpenMapTiles Data from OpenStreetMap` (MapLibre la añade sola).

**Riesgos del servicio público (de sus propios términos, actualizados 14 oct 2026):** se ofrece "as-is" y puede discontinuarse sin aviso; no hay SLA; prohíbe recolección automatizada salvo descargas offline limitadas (≤3.000 tiles o 50 MB, 4 peticiones paralelas, User-Agent propio). **No es una base sólida para una app publicada.** Alternativas: autoalojar (el planeta está disponible como `.pmtiles`/`.mbtiles`), o un proveedor comercial. Costes de cualquiera de ellas: **no verificados**.

Los sprites y glyphs del estilo oficial son de OpenFreeMap; para un estilo propio (iconos y tipografías originales) habrá que **alojar los nuestros** y apuntar a ellos desde el JSON.

## 6. Qué hay que sustituir al migrar (y qué no)

| Servicio | Hoy | Tras migrar | Estado de la decisión |
|---|---|---|---|
| Renderizador | MapKit | MapLibre Native | Propuesto |
| Datos de mapa | Apple | Tiles OpenMapTiles (OSM) | A elegir proveedor |
| Búsqueda | `MKLocalSearch` | Geocodificador basado en OSM (p. ej. Photon/Pelias/Nominatim, comercial o autoalojado) | **Sin elegir; costes y límites sin verificar** |
| Rutas | `MKDirections` | Motor de rutas OSM (p. ej. Valhalla, OSRM, GraphHopper, OpenRouteService; hospedado o autoalojado) | **Sin elegir; costes y límites sin verificar** |
| Voz | `AVSpeechSynthesizer` | Igual | Se conserva |
| GPS | Core Location | Igual | Se conserva |
| Navegación | `NavigationEngine` | Igual, alimentado con geometría y pasos del nuevo motor | Se conserva |
| Datos del usuario | SwiftData | Igual | Se conserva |

Importante: un motor de renderizado no calcula rutas. MapLibre dibuja; las rutas y los pasos de giro los tiene que dar un servicio aparte.

**Costes de infraestructura (aparte del "gratis para el usuario"):** hospedar tiles, geocodificador y motor de rutas tiene coste de servidor o de API que habría que asumir. Aún no tengo cifras verificadas.

## 7. Arquitectura propuesta

Protocolos y modelos neutrales, independientes de cualquier motor:

```
Domain/Models:   Coordinate · Place · Route (geometría, distancia, duración, pasos) · RouteStep
Services:        PlaceSearchProviding · RoutingProviding · LocationServiceProtocol
Map/             MapRenderer (protocolo)  →  MapLibreRenderer
                 MapStyleDefinition (id, nombre visible, JSON de estilo, sprites, glyphs,
                                     cámara por defecto, minimapa, ruta, usuario, atribución)
                 StyleManager (carga, validación, errores claros, restaurado de capas)
Navigation/      NavigationEngine (ya existe) · NavigationController
UI/              Vistas SwiftUI que solo hablan con MapRenderer y los protocolos
```

Reglas de implementación:
- Estilos como **JSON válido** con `source-layers` y campos reales (§5); la clave/URL del proveedor se lee de configuración, no del repositorio, y si falta se muestra un error claro.
- Al cambiar de estilo se conservan destino, ruta, posición y cámara; las capas de navegación (ruta, destino, usuario) se **añaden después de `didFinishLoading style`**, con identificadores fijos para evitar duplicados.
- Nombres visibles de cada estilo en datos configurables; nada afirma afiliación con ningún juego.

## 8. Referencias a videojuegos: qué es posible y qué no

Estilo = jerarquía de vías, colores, contornos, siluetas, etiquetas, iconografía y comportamiento de cámara. Eso se puede reproducir con datos reales. **No se extraen ni usan assets de los juegos** (texturas, iconos, fuentes, mapas, sprites): se dibujan equivalentes propios y se documenta la diferencia.

| Estilo | Qué sí se puede con tiles vectoriales + estilo | Qué NO se puede sin más |
|---|---|---|
| GTA V (minimapa y mapa) | Terreno oscuro, edificios como siluetas, jerarquía de vías con bordes, agua separada, etiquetas sobre calles, minimapa recortado con rumbo arriba | Los iconos y la fuente originales; el relieve y el arte del mapa completo; la vista exacta depende de qué captura uses |
| Fortnite | Paleta por tipo de terreno, costas, agua, zonas urbanas simplificadas, marcadores propios | Los biomas, el arte pintado y los puntos de interés del juego (ficticios; no se inventan) |
| Minecraft | Mapa cenital pixelado con paleta limitada requiere renderizado de tiles de baja resolución o una capa de cuantización | "Voxel 3D" real: requiere extrusión de edificios con `building.render_height` y un renderizado distinto; no se promete reconstrucción de edificios reales en bloques |
| RDR2 / Cyberpunk / Skyrim | Dependen de referencias concretas y de si se busca mapa plano o con relieve | Relieve 3D sin datos de elevación y renderizado adecuados |

Cada estilo tendrá su ficha (referencia usada, elementos reproducidos, adaptaciones al mundo real, limitaciones, recursos, diferencias pendientes) cuando se implemente.

## 9. Mapa de trabajo por fases

1. **Esta fase:** auditoría, decisión técnica (este documento).
2. Capa neutral: modelos de ruta/lugar, protocolos, y sustitución de `MKRoute`/`MKMapItem` en vistas. Se puede hacer sin elegir proveedor y mantiene la app funcionando con Apple Maps.
3. `MapLibreRenderer` + estilo base propio con tiles de prueba, ruta y usuario encima.
4. Estilo 1 (GTA) completo: pantalla completa, minimapa compacto recortado, navegación. Comparación antes/después con la misma ubicación y zoom, mapa sin interfaz, tres zooms.
5. Fortnite y Minecraft (tras confirmar qué Minecraft).
6. Resto de estilos y pulido.

## 10. Qué necesito de ti

1. **Las imágenes de referencia** (no han llegado). Para GTA: indicar si quieres el minimapa circular/cuadrado de juego, el mapa completo, o ambos.
2. **Decisión sobre el cambio de motor:** migrar a MapLibre implica sustituir búsqueda y rutas de Apple por otros servicios.
3. **Proveedores y presupuesto**: usar servicios públicos o gratuitos con límites (válido para prototipo, no para publicar) o aceptar un coste mensual por tiles, búsqueda y rutas.
4. **Minecraft**: ¿aspecto del objeto mapa, vista cenital de bloques o minimapa de un mod concreto?
5. **Fortnite**: ¿qué versión o temporada visual?
6. **Nombres visibles**: confirmar que en la app los estilos tendrán nombres propios ("Ciudad nocturna", "Isla", "Bloques"…) y que los juegos solo se citan en la documentación interna.
