# 18 · Estilos de la Fase 4

Cinco estilos nuevos, cada uno con su propia configuración en `tools/build_styles.py` (`OESTE`, `CIBER`, `NORDICO`, `RED`, `RALLY`). La app no usa nombres de juegos, no se presenta como oficial ni afiliada, y no incluye ningún asset ni color extraído de ellos: los colores son interpretaciones propias.

## Referencias consultadas (lo que se pudo ver)

Se abrieron en el navegador. Solo se analizaron **mapas completos o de pausa**; **no se analizó ningún minimapa ni interfaz de navegación** (no se encontró una referencia fiable de ellos). Ninguna comparación píxel a píxel.

| Estilo | Referencia vista | Limitación |
|---|---|---|
| Salvaje oeste | Imagen del mapa completo en [GamesRadar](https://www.gamesradar.com/red-dead-redemption-2-map) | Vista general de baja resolución: no se ven símbolos ni etiquetas a zoom alto |
| Ciudad ciber | Captura del mapa de pausa en [PCGamesN](https://www.pcgamesn.com/cyberpunk-2077/cyberpunk-2077-map) | Incluye interfaz del juego; el color de la ruta (amarillo) es elección propia |
| Mapa de fantasía | Imagen del mapa en la [wiki UESP](https://en.uesp.net/wiki/File:SR-map-Skyrim.jpg) | Imagen con copyright del juego: solo se usó como referencia visual; solo vi la parte superior |
| Red urbana | Captura del mapa de pausa en [WCCFtech](https://wccftech.com/watch-dogs-2-full-san-francisco-map-revealed/) | Captura de un vídeo con marcos de streamer; el color de la ruta es propio |
| Rutas de rally | Imagen del mapa completo en [Racing Games](https://racinggames.gg/article/forza-horizon-5-full-map-revealed) | Vista general de baja resolución; no se vieron los símbolos ni los eventos |

## Qué se traslada y en qué se diferencian

| | Terreno | Agua | Edificios | Carreteras | Etiquetas | Ruta |
|---|---|---|---|---|---|---|
| **Salvaje oeste** | Papel ocre, bosque a puntillismo | Lavado gris verdoso con borde de tinta | Manchas de tinta tenues | Línea negra fina **sin contorno**; menores a trazos | Versalitas espaciadas | Carmesí |
| **Ciudad ciber** | Casi negro | Casi negro azulado | **Rojo sangre**, con 3D | Bandas de **cian con borde brillante**, más anchas y claras según rango | Mayúsculas, cian | Amarilla |
| **Mapa de fantasía** | Sepia envejecido con cerros «^» y arbolado de tinta | Gris pálido | Manchas tenues | **Rojo pardo**: continuas las principales, **punteadas** las menores | Mayúsculas espaciadas | Rojo ladrillo |
| **Red urbana** | Gris claro, parques verdes | **Azul claro** | Gris claro, con 3D | Calles blancas; **autopistas amarillo-naranja** | Minúsculas, halo blanco | Naranja rojizo |
| **Rutas de rally** | Verde/ocre/oscuro saturado | Turquesa | Grises tenues | Claras con contorno oscuro, jerarquía por ancho y color; **caminos de tierra discontinuos** (dato real `surface`) | Mayúsculas blancas | Naranja |

- **Skyrim (mapa de fantasía):** se decide una **interpretación plana, sin relieve**. No se promete relieve equivalente: requeriría datos de elevación y un motor de terreno. Reutiliza el tema «Mapa de fantasía» que estaba como «Próximamente».
- **Forza (rutas de rally):** no se dibujan carreras, eventos ni coleccionables. Solo se muestran los lugares reales del usuario; los símbolos se adaptan a funciones reales de la app (combustible, comida, aparcamiento…).
- **3D:** solo en Ciudad ciber y Red urbana (la reutilizan con su configuración). Los demás son planos a propósito.
- **Texturas nuevas (propias, procedurales):** `tex-ink-stipple`, `tex-ink-trees`, `tex-ink-hills` (`tools/make_textures.py ink`).
- **Miniaturas:** esquemas dibujados con la paleta de cada estilo (`tools/make_style_previews.py`); **no son capturas**.
- **Minimapa:** cada estilo usa una forma distinta (círculo o cuadrado redondeado); no se ha modelado un minimapa real de ningún juego.

## Pendiente / límites

- Los iconos de puntos de interés son símbolos del sistema con los colores del estilo; solo el estilo GTA tiene familia de iconos propia.
- La selección con mini flechas y los iconos de Casa/Trabajo en el mapa solo existen en el estilo GTA (igual que antes en Isla y Bloques).
- Sin probar en iPhone ni en MapLibre Native; la vista previa fue con MapLibre GL JS.
