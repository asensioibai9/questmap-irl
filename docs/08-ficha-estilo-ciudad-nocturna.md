# Ficha de estilo: «Ciudad nocturna» (primer estilo completo)

Archivo del estilo: `QuestMapIRL/Resources/style-ciudad-nocturna.json` (generado por `tools/build_styles.py`).
Nombre visible en la app: **Ciudad nocturna** (configurable en `ThemeCatalog`). No se presenta como oficial ni afiliado a ningún videojuego.

## Referencia visual utilizada
- **Ninguna captura concreta.** No han llegado las imágenes de referencia. El estilo sigue la descripción escrita del encargo (terreno oscuro, edificios como siluetas, jerarquía de vías con contraste, agua separada, etiquetas sobre las calles, ruta que destaca sin borrar la ciudad) y el lenguaje general del minimapa urbano nocturno de GTA V.
- **No se ha comparado con GTA V**, por lo que no se afirma que sea idéntico ni se puede medir la fidelidad.
- Pendiente de fijar cuando haya capturas: si el objetivo es el minimapa de juego, el mapa completo o ambos, y la paleta exacta.

## Elementos reproducidos
| Elemento | Cómo se resuelve |
|---|---|
| Terreno oscuro | `background` y `landuse` en tonos pizarra, con variación suave por tipo de suelo |
| Edificios como siluetas | Relleno `building` desde zoom 14, contorno claro desde 15,5; datos reales de OSM |
| Jerarquía de vías | 7 niveles (autopista a servicio), cada uno con contorno y relleno, anchos interpolados por zoom |
| Autopistas e intercambiadores | Autopistas en ámbar, rampas con capas propias, puentes por encima y túneles discontinuos |
| Cruces limpios | Todos los contornos se dibujan antes que todos los rellenos: los cruces se funden |
| Agua | Relleno azul oscuro con borde azul claro de 1 px: se separa del terreno |
| Parques y verde | `landcover` y `landuse` en verdes apagados, sin saturar |
| Etiquetas | Nombres de calle sobre la vía (por tipo de vía y zoom), barrios en mayúsculas espaciadas, agua en cursiva |
| Puntos de interés | Puntos de color por categoría (combustible, parking, salud, policía, comida, tienda, cultura), con densidad según zoom (`rank`) |
| Ruta | Tres capas: resplandor, borde casi negro y núcleo lima brillante; no tapa las etiquetas de calle |
| Usuario y destino | Flecha propia orientada por rumbo y marcador de destino con halo |

## Adaptaciones para el mundo real
- Se mantienen las calles reales de la ubicación del usuario; no hay mapa ficticio.
- La ruta usa un color (lima) que no se parece a ninguna clase de vía, para no confundirse con la cartografía.
- Los POI son reales (OpenStreetMap), no ficticios.

## Limitaciones
- **No hay iconos de POI propios todavía**: se dibujan como puntos de color. Hace falta crear un sprite propio (iconos originales, sin copiar los del juego).
- **Fuente tipográfica**: solo están disponibles en el proveedor `Noto Sans` Regular, Bold e Italic. Una tipografía distinta exige alojar glyphs propios.
- **Minimapa**: es otra vista de mapa real recortada con la forma configurada (círculo para este estilo); no hay todavía forma personalizada según una captura.
- **Sin relieve ni 3D**: el estilo es plano; los edificios no se extruyen.
- **Tiles**: se sirven desde la instancia pública de OpenFreeMap, sin garantías de servicio.

## Recursos necesarios para acercarse más
1. Capturas de referencia concretas (minimapa y mapa completo).
2. Un sprite de iconos propio y, opcionalmente, una tipografía con licencia comercial.
3. Un servidor de tiles/glyphs/sprites propio o contratado para publicar.

## Diferencias pendientes respecto a la referencia
No medibles hasta tener las capturas. Se compararán, sobre la misma ubicación y zoom: color de terreno, color y grosor de vías, tratamiento de edificios, agua, densidad de etiquetas y tamaño de iconos.

## Cómo se validó
- El JSON pasa el validador oficial de la especificación de estilos de MapLibre.
- Todas las capas y campos existen en el esquema real del proveedor (`tools/validate_style.py`).
- Se renderizó con MapLibre GL JS sobre Madrid a zoom 13, 16 y 18 (`tools/preview/index.html`). **No se ha renderizado todavía con MapLibre Native en un iPhone.**
