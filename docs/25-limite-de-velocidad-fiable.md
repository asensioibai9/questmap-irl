# 25 · Señal de límite de velocidad: fiabilidad y ajustes

Se refiere a la señal de velocidad MÁXIMA de la vía, no al indicador de cobertura GPS.

## Diagnóstico (código real + respuestas reales del proveedor)

Fuente: servidor público de demostración de Valhalla (FOSSGIS), `trace_attributes` con `shape_match: map_snap`. El dato es la etiqueta `maxspeed` de OpenStreetMap; las aristas son dirigidas (límite por sentido si OSM lo distingue). Sin dato, el campo `speed_limit` no aparece. Se comprobó con consultas reales de muestra (Madrid, sin datos personales).

| Revisión | Resultado |
|---|---|
| Valores de ejemplo o predeterminados | No había: sin dato no se ponía cifra. Se mantiene (sin 50/90/120 automáticos). |
| Límite de una vía anterior | **Sí**: con señal perdida no llegan lecturas y la señal se quedaba con la última cifra indefinidamente (el cálculo solo corría con lecturas nuevas). |
| Calle paralela | **Posible**: el perfil se construía estirando las longitudes de las aristas a lo largo de trozos de 15 km (tolerancia ±25 %), así que un cambio de límite podía quedar desplazado cientos de metros; y no se comprobaba si el proveedor había ajustado la ruta a otra vía. En una consulta real con puntos separados, Valhalla asoció parte del trazado a una vía de servicio paralela (sin límite) y otro punto, a 17 m, a una vía lateral de 30. |
| Solo al iniciar ruta | **Sí**: sin ruta no había señal; con ruta, una consulta al empezar y otra al recalcular. |
| Respuestas antiguas | Riesgo bajo (cancelación), pero sin comprobar a qué ruta pertenecía la respuesta. |
| Errores | **Sí**: un fallo de red dejaba la señal sin datos el resto del viaje (no se reintentaba; `try?` ocultaba el error). |
| Velocidad actual vs. máxima | No se confundían. La velocidad actual sí mostraba 0 cuando el GPS no la daba. |
| km/h y mph | El dato llega en km/h; en mph se **redondeaba a múltiplos de 5** (50 km/h → «30»), lo que parecía una señal local exacta. |
| Ubicación imprecisa | Se mostraba con hasta 80 m de error: no distingue una vía de su paralela. |
| ¿Entrega límites o categoría? | Entrega límites numéricos donde OSM los tiene (comprobado). No hemos podido confirmar si en algún país convierte etiquetas de zona (p. ej. `ES:urban`) en cifra; si lo hiciera, llegaría como límite del proveedor. Los límites condicionales (horario, lluvia) y los orientativos **no** los entrega: se muestra el límite general. |

## Cambios

- **Asociación punto a punto** (`SpeedLimitProfileBuilder`): se envía un punto cada ~20 m de la ruta y se usan `matched_points` (arista, fracción, distancia a la vía). Cada cambio de límite se coloca con unos metros de error. Un tramo queda SIN DATO si un punto no se asocia, queda a más de 15 m de la vía elegida (paralela, otro nivel, puente o paso inferior) o si el camino del proveedor no se parece en longitud al de la ruta (salida, desvío).
- **Estados honestos** (`SpeedLimitDisplay`): oculta (desactivada) · ubicación insuficiente · sin dato · límite explícito. Nunca se deduce, nunca «sin límite».
- **Estabilidad**: un cambio de cifra necesita 2 lecturas seguidas; aparecer tras «sin dato» es inmediato. Sin cifra si la precisión es peor de 35 m, la lectura tiene más de 6 s, se está fuera de la ruta o a más de 25 m de ella.
- **Pérdida de señal**: el centro de navegación también reacciona a los cambios de estado de la ubicación (cada pocos segundos sin lecturas) y retira la cifra.
- **Respuestas y reintentos**: cada respuesta va ligada a su ruta (se descartan las de una ruta anterior). Si falla o queda incompleta, reintento a los 15 s, 30 s, 60 s y luego cada 2 min mientras dure la navegación.
- **Caché**: en memoria, solo perfiles completos, 6 rutas, 30 min. Nada en disco.
- **También sin ruta** (opcional, desactivado por defecto): map matching del recorrido real reciente (~400 m), con continuidad y sentido. Solo en movimiento (> ~14 km/h), cada ≥ 12 s y ≥ 200 m; el resultado caduca al dejar la vía identificada (+ margen) o a los 3 min. Las respuestas llevan número de orden. **Nunca se envían puntos a menos de 300 m de Casa o Trabajo** (y si no se pueden leer, no se envía nada).
- **Unidades**: ajuste general de la app. mph = conversión redondeada al entero, con «≈ mph» debajo de la señal y en VoiceOver.
- Todo usa las lecturas REALES del GPS, nunca la posición animada de la flecha.

## Ajustes › Ajustes de navegación › Señal de límite de velocidad

Mostrar señal · También sin ruta · Diseño (Automático según país, Circular europea, Rectangular EE. UU., Minimalista) · Tamaño (pequeño/mediano/grande, adaptado al tamaño de texto) · Posición en el iPhone (Automática, arriba izquierda, arriba derecha; huecos reservados del diseño) · Sin dato (indicador neutro «—» u ocultar) · Mi velocidad junto a la señal (recuadro aparte con «tú») · Unidades (informativo) · Restablecer esta sección. Vista previa con valor de demostración y el mismo componente que el mapa.

«Automático» usa la rectangular en EE. UU. y territorios cuando el proveedor indica el país; si no, la circular europea (por defecto documentado).

## CarPlay

Misma fuente (`NavigationHub.speedLimit`). Se aplican: mostrar/ocultar, también sin ruta, diseño y «sin dato». Solo iPhone: tamaño, posición y velocidad actual (en CarPlay, tamaño fijo abajo a la izquierda dentro del área segura). **Compilado, no probado** (requiere el permiso de Apple).

## Limitaciones reales

- La calidad depende de OSM: muchas vías no tienen `maxspeed` y se verá «—».
- Servidor público sin garantías ni acuerdo de servicio; puede limitar peticiones o caer. Alternativas sin coste: servidor Valhalla propio (requiere un ordenador o servidor y descargar datos OSM). De pago (no añadidas): HERE, TomTom, Mapbox; requieren contrato y clave.
- Sin límites condicionales ni por tipo de vehículo.
- Nada de esto se ha probado en un iPhone.

## Probar en el iPhone

1. Instala el IPA nuevo con Sideloadly.
2. Perfil › Ajustes de navegación › Señal de límite de velocidad: cambia diseño, tamaño y «sin dato» y mira la vista previa.
3. Navega (de copiloto) por vías que conozcas: autovía con vía de servicio, una salida, un cambio de 50 a 30.
4. Activa «También sin ruta» y circula sin ruta.
5. Pasa por un túnel: la cifra debe desaparecer y volver al salir.
6. Modo avión un momento: «—» y vuelve sola al recuperar la red.
7. Cierra la app del todo y ábrela: los ajustes siguen.
