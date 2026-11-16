# 19 · Límite de velocidad (Fase 2 del plan musical/CarPlay)

## Fuente de datos (comprobada con servicios reales)

| Fuente | Resultado |
|---|---|
| Tiles OpenFreeMap | La capa `transportation` **no** incluye `maxspeed`. |
| OSRM público | `annotations=maxspeed` da error; `speed` es la velocidad estimada del perfil, **no** el límite legal. |
| Overpass público | «At capacity» y pensado para uso humano, no para apps. |
| **Valhalla público (FOSSGIS)** `trace_attributes` | Devuelve `speed_limit` real (OSM `maxspeed`) por tramo cuando existe la etiqueta. **Elegido** (autorizado por el usuario). |

Coste: ninguno. Sin clave. Licencia de datos: OpenStreetMap (ODbL), ya atribuida. Es un servidor de demostración sin garantías: para producción hay que usar uno propio o contratado (`ValhallaSpeedLimitService.endpoint`).

## Cómo funciona

1. Al empezar la navegación (y tras recalcular) se hace **una consulta por ruta**: la geometría se divide en trozos de ~15 km, se adelgaza y se envía a `trace_attributes` (`map_snap`, `units=kilometers`, solo `edge.speed_limit` y `edge.length`). Resultado cacheado en memoria.
2. Con las aristas se construye una tabla de límites por **metros recorridos de la ruta activa**. No hay consultas por lectura GPS.
3. La posición sobre la ruta (la misma que usa la navegación) indica el tramo. Al usar la ruta activa se evitan los saltos entre autopista y calle lateral, las vías paralelas, las salidas y los puentes.
4. `SpeedLimitTracker` decide qué se muestra:
   - Señal **oculta**: ajuste desactivado, sin tabla (cargando o fallo del servicio), fuera de ruta, precisión > 80 m, lectura inválida o ubicación de hace > 10 s.
   - **«–» sin dato**: tramo cubierto pero sin etiqueta (o trozo cuyo ajuste no cuadra con la longitud real: se descarta).
   - **Cifra**: dato fiable. Un cambio de límite necesita 2 lecturas seguidas (anti-parpadeo); la primera lectura se muestra al instante.
5. Nunca se muestra un límite estimado por clase de carretera, ni se interpreta «sin dato» como «sin límite» (el valor 255 del servicio, otros valores fuera de 5–200 y textos no numéricos se descartan).

## Alcance y límites

- Vehículo: **turismo**. No se evalúan límites condicionales (horarios, lluvia), variables ni por vehículo: quedan sin dato.
- Solo con **ruta activa**. Sin ruta (conducción libre) no se muestra límite en esta versión.
- La precisión depende de OSM: puede estar incompleta o desactualizada. Prevalece la señalización real (texto en el ajuste y en el Centro de ayuda).
- km/h y mph (en mph se redondea a múltiplos de 5, como las señales).
- Privacidad: al activar el ajuste se envía la geometría de la ruta a ese servicio. Desactivado, no se hace ninguna consulta.
- Sin avisos sonoros de exceso de velocidad (decisión de esta fase).

## Pantalla

Señal circular blanca con borde rojo y número negro (60 pt), **separada** de la velocidad actual (texto «km/h» del panel y del modo HUD). En modo mapa va abajo a la izquierda, en la fila de los botones laterales; en modo HUD, a la derecha del minimapa. Etiqueta de accesibilidad explícita. La imagen de referencia no llegó al chat: el diseño sigue las medidas descritas.

## Ajuste

Perfil › Ajustes de navegación › Velocidad › «Mostrar límite de velocidad» (por defecto activado, persistente, guardado al instante, efecto inmediato).
