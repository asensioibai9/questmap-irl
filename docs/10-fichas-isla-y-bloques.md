# Fichas de estilo: Isla (Fortnite T3) y Mundo de bloques (Minecraft)

Generados por `tools/build_styles.py`; texturas por `tools/make_textures.py`. Validados con el validador oficial de MapLibre y el esquema real de OpenMapTiles. Visualizados con MapLibre GL JS sobre Deba; **no** con MapLibre Native en un iPhone, y **no** comparados píxel a píxel con los juegos.

## Isla (referencia: mapa de la Temporada 3 del Capítulo 1, visto en theclick.gg)
| Rasgo de la referencia | Qué se ha reproducido | Cómo |
|---|---|---|
| Verde saturado con zonas más amarillas/oscuras | Sí, por clase de suelo (hierba, cultivo, bosque, parque) | Colores por clase |
| Manchas densas de arbolado | Sí | Textura de copas procedural sobre bosque |
| Variación de hierba | Parcial | Textura suave sobre hierba/cultivo |
| Mar azul con borde claro | Sí | Relleno + banda de aguas poco profundas |
| Caminos finos y claros | Sí | Vías estrechas, sin contorno marcado |
| Zonas urbanas claras | Parcial | Edificios claros; el verde bajo ellos sigue siendo suelo real |
| Etiquetas blancas en mayúsculas | Sí | Lugares y puntos de interés; calles ocultas |
| Biomas por región (zona amarilla, zona marrón) | **No** | Dependería del lugar real, no de una isla fija |
| Pintado a mano / relieve | **No** | Requeriría relieve (DEM) o texturas pintadas por un artista |
| Ubicaciones ficticias de la isla | No se copian | Se usan lugares reales |

## Mundo de bloques (referencia: BlueMap sobre mundos de Minecraft)
| Rasgo | Qué se ha reproducido | Cómo |
|---|---|---|
| Suelo, agua, arena, bosque con textura de bloques | Sí (2D) | Texturas de 16x16 "píxeles" repetidas |
| Casas de madera | Parcial | Edificios reales con textura de tablones (planos, sin volumen) |
| Caminos de tierra | Sí | Vías de extremos rectos y esquinas en ángulo |
| Árboles como bloques individuales | **No** | Solo textura de hojas sobre el bosque |
| Terreno voxel, alturas, sombras | **No** | Requeriría datos de elevación y un renderizador 3D |
| Píxeles perfectamente nítidos | Parcial | El motor suaviza las texturas al escalar |
