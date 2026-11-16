# 16 · Edificios 3D y control 2D/3D (Fase 2)

## Auditoría de capacidades

| Aspecto | Resultado |
|---|---|
| Motor | MapLibre Native 7.0.0: soporta `fill-extrusion`, `light` y cámara inclinada. No se usa terreno ni modelos. |
| Datos | OpenFreeMap (esquema OpenMapTiles). Capa `building`, tiles z13–14, con `render_height`, `render_min_height`, `hide_3d` y `colour` (consultado en el TileJSON real). |
| Altura | En las muestras (Deba, Bilbao, París) todos los edificios traen `render_height`. Sale de `height` / `building:levels` de OSM; si falta, el esquema pone un valor estimado (4–5 m). **No se puede distinguir en el tile cuál es real y cuál estimado.** |
| Altura mínima | `render_min_height` (voladizos, puentes de edificio): se usa como base. |
| Partes de edificio | `hide_3d` marca los volúmenes que ya cubren sus partes: se excluyen para no duplicar geometría. |

Tres niveles, por separado:

- **A. Edificios extruidos desde polígonos: implementado** (estilo Ciudad nocturna).
- **B. Terreno con elevación: NO implementado.** Haría falta una fuente DEM (p. ej. Terrarium de AWS/Mapzen, o Mapbox, que exige cuenta) y MapLibre Native admite terreno, pero añade descarga de datos, desalineaciones con la ruta si se calcula mal y una fuente nueva con licencia y coste a revisar. Queda fuera hasta que lo autorices.
- **C. Modelos 3D detallados o monumentos: NO implementado.** Requeriría modelos propios o con licencia; no se añaden modelos genéricos que puedan confundirse con edificios concretos.

## Cómo se dibuja

- Capa `building-3d` en el JSON (generada por `tools/build_styles.py`, clave `buildings_3d`): `fill-extrusion` sobre `source-layer: building`, visible solo a z ≥ 15, con altura limitada a 3–120 m.
- Aparece sin saltos: la altura crece de 0 a su valor entre z15 y z16.
- Color según altura (más alto = algo más claro). El tejado se distingue de la fachada por la luz del estilo y el degradado vertical, de forma discreta.
- Orden de capas: **después** de carreteras y puentes, **antes** de ruta, etiquetas, iconos, destino, selección y flecha del usuario. La ruta y la maniobra se dibujan siempre por encima: se ven aunque un edificio quede delante. Es una decisión de legibilidad; no es una visión «a través» de la geometría real.
- Las carreteras nunca se extruyen (un test lo comprueba).
- Empieza oculta (`visibility: none`). La app la enciende o apaga cambiando solo su visibilidad: no se recarga el estilo.

## Control 2D / 3D

- Botón en el mapa (y en navegación) solo en estilos con la capa (`supportsBuildings3D`).
- 2D = cenital (inclinación 0). 3D = 50° explorando; 45° conduciendo y 30° a pie.
- Transición animada de 0,6 s que conserva centro, zoom, rumbo, ruta, destino y marcadores.
- Preferencia guardada en `UserSettings.view3D` (por defecto 2D) con guardado al momento y valor por defecto en el modelo (migración segura).
- 2D sigue disponible siempre; en estilos sin 3D no aparece el botón y se mantiene su comportamiento anterior.

## Pendiente

- Fase 3: Fortnite y Minecraft (voxelización) con su propia configuración.
- Medir rendimiento en iPhone real (no se promete ninguna cifra de FPS).
