# 17 · 3D adaptado a cada estilo (Fase 3)

Misma capa `building-3d` (datos y orden de capas de la Fase 2), con configuración propia por estilo en `tools/build_styles.py` (`buildings_3d`). No hay arquitectura duplicada.

| Estilo | Tratamiento | Notas |
|---|---|---|
| Ciudad nocturna (GTA) | Gris oscuro; alturas reales hasta 120 m; color más claro cuanto más alto | Igual que en la Fase 2 |
| Isla (Fortnite) | **Volúmenes simplificados**: altura en escalones de 6 m, tope 72 m; colores cálidos y claros (crema → amarillo → naranja) sobre el verde | No convierte edificios reales en modelos detallados del juego |
| Mundo de bloques (Minecraft) | **Prismas** con altura en múltiplos de 3 m (un «bloque»), tope 60 m, y textura de tablones en paredes y tejado | **No es voxelización** |

## Minecraft: prisma frente a voxel

- Lo implementado: la huella real del edificio se extruye tal cual y solo se redondea su altura a bloques de 3 m. Las esquinas y los muros siguen la forma real, no una cuadrícula.
- Voxelizar de verdad exigiría rasterizar cada huella en una cuadrícula de bloques y dibujar un cubo por celda (geometría propia). Se haría en el cliente con las huellas visibles, y se recalcularía al mover el mapa. Coste estimado: decenas de miles de polígonos en zonas densas, más memoria y batería, y riesgo de desalinear coordenadas. No está hecho; no se llama «mundo Minecraft 3D completo».
- Vegetación y terreno: siguen siendo texturas planas (no hay datos de relieve).

## Límites

- Isla: la relación terreno–edificios–vegetación es solo cromática; sin relieve ni árboles 3D.
- Se comprobó en MapLibre GL JS (vista previa web), no en MapLibre Native ni en iPhone. `fill-extrusion-pattern` con la textura de tablones debe verificarse en el dispositivo.
