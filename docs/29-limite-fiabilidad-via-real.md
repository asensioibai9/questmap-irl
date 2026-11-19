# 29 · Límite de velocidad: identificar la vía REAL

La app no ve señales físicas ni paneles variables: consulta datos cartográficos (OpenStreetMap, etiqueta `maxspeed`) a
través del servidor público de Valhalla. Vehículo: turismo.

## Diagnóstico del flujo anterior (antes de cambiarlo)

| Dato | De dónde salía |
|---|---|
| Límite | Valhalla `trace_attributes`, campo `edge.speed_limit` (km/h): dato explícito del proveedor |
| Tramo actual | **Navegando: el de la RUTA planificada** en el punto de avance (proyección del GPS sobre la ruta). Sin ruta (opcional): map matching del recorrido reciente |
| Sentido | Aristas dirigidas de Valhalla (límite del sentido si OSM lo distingue) |
| Caché | Perfil de la ruta en memoria, 30 min, por firma de la ruta |
| Otras señales | La app no muestra otras señales de tráfico (ni stop, ni prohibiciones, ni restricciones de giro, altura o peso) |
| Datos de demostración | Solo la vista previa de Ajustes, rotulada |

**Punto débil confirmado en el código:** navegando, la cifra era la de la ruta siempre que la posición estuviera a menos
de 25 m de ella (y con precisión ≤ 35 m). Una vía de servicio, un lateral, el arranque de una salida o un paso a otro
nivel suelen estar a menos de 25 m: se mostraba el límite de la vía de la ruta aunque se circulara por otra. Además se
mantenía ese límite durante los primeros metros de una salida hasta superar los 25 m.

**Comprobado con el proveedor real** (consultas de muestra, sin datos personales):
- Una línea a ~25 m del eje del Paseo de la Castellana (Madrid) se asoció a la calzada lateral, con límite 30 frente a
  50 del tronco: la vía elegida cambia el dato.
- Valhalla devuelve `edge.way_id` (identificador de la vía de OSM) y `edge.names`; así se puede saber QUÉ vía es, no solo
  qué tan cerca está.
- En un tramo sin límite general (A9, Alemania) devuelve el texto `"unlimited"`; sin etiqueta, no devuelve nada.
- Con `units = kilometers`, los límites llegan en km/h.

Revisado sin fallo: respuestas tardías (ligadas a su ruta / con número de orden), lecturas antiguas o imprecisas,
pérdida de señal, km/h ↔ mph (conversión al entero con «≈ mph»), valores no numéricos (no se convierten en cifra), sin
valores por tipo de vía, y la posición animada de la flecha no se usa (solo lecturas reales).

## Mejoras

- **Comprobación de la vía con tu recorrido (navegando, activada por defecto):** además de la ruta, se hace map matching
  del recorrido real reciente (continuidad, sentido y conectividad de la red los resuelve el proveedor) y se compara la vía
  por su identificador:
  - misma vía y mismo límite que la ruta → ruta (sitúa el punto de cambio con precisión);
  - misma vía con otro límite → el del recorrido (límite por sentido);
  - vía distinta (paralela, salida, desvío, otro nivel) → la del recorrido; la ruta no se usa;
  - el proveedor no identifica la vía con seguridad → «tramo incierto», sin cifra.
- **Sin comprobación** (aún no hay respuesta, sin red, desactivado o cerca de Casa/Trabajo): solo la ruta y solo si vas
  pegado a ella (≤ 10 m y precisión ≤ 20 m); si no, «tramo incierto».
- La evidencia del recorrido vale hasta el FINAL de la vía identificada (+40 m): al tomar una salida o pasar un cruce
  deja de valer y no se arrastra el límite anterior.
- Estados: A límite explícito · B vía identificada sin dato · C tramo incierto · D ubicación no utilizable · E error del
  proveedor. Solo A muestra cifra; el resto «—» u oculto según el ajuste. Ninguno usa la señal de fin de limitación.
- Estabilidad: un cambio de cifra se confirma con 2 lecturas seguidas; pasar a C o D es inmediato (no se mantiene una
  cifra dudosa).
- **Modo diagnóstico (solo desarrollo):** 7 toques en la vista previa de Ajustes › Señal de límite activan una tarjeta
  junto a la señal con: fuente, identificador y nombre de la vía, valor recibido, valor interpretado y unidad, antigüedad,
  precisión del GPS, motivo y motivo del último cambio. Sin coordenadas y sin registrar nada.

## Limitaciones de los datos (no se arreglan con código)

- Cobertura: solo hay cifra donde OSM tiene `maxspeed`; muchas calles no lo tienen → «—».
- Límites condicionales (`maxspeed:conditional`: horarios, lluvia, camiones) y orientativos (`maxspeed:advisory`): el
  servicio NO los entrega. La cifra es el límite general etiquetado; si ese tramo tiene una condición, la app no lo sabe.
- No se ha podido confirmar si el servicio traduce límites implícitos por zona (p. ej. `ES:urban`) a cifra.
- Paneles de velocidad variable y obras: no hay datos en tiempo real.
- Las demás señales (stop, ceda, prohibido el paso, restricciones de giro, altura o peso) no se muestran: no hay una
  fuente integrada que diga si aplican a tu sentido y vía. El motor de rutas (OSRM) sí usa sentidos únicos y restricciones
  de giro de OSM para calcular la ruta.

## Alternativas (no aplicadas: requieren tu decisión)

| Opción | Cobertura | Requisitos | Coste / licencia |
|---|---|---|---|
| Servidor Valhalla propio | La misma de OSM, sin límites de uso ni dependencia del servidor de demostración | Ordenador o servidor con varios GB, actualizar datos OSM | Gratis (ODbL, atribución) |
| HERE (Routing / Map Attributes, `speedLimit`) | Comercial, alta en Europa, límites por sentido y condicionales | Cuenta y clave | Capa gratuita mensual limitada; después de pago |
| TomTom (Snap to Roads / Routing con `speedLimit`) | Comercial, alta | Cuenta y clave | Capa gratuita diaria limitada; después de pago |
| Mapbox (Map Matching con `maxspeed`) | Mezcla OSM y propios | Cuenta y token | Capa gratuita mensual; después de pago |

Ninguna se ha contratado ni añadido.

## Probar en el iPhone (con el coche parado o un acompañante)

1. Instala el IPA nuevo con Sideloadly.
2. Perfil › Ajustes de navegación › Señal de límite: deja «Comprobar la vía con tu recorrido» activado. Toca 7 veces la
   vista previa para activar el diagnóstico.
3. Navega por un tramo conocido con vía de servicio o lateral, y por una salida. El acompañante mira la tarjeta:
   «fuente», «vía» y «motivo». Al entrar en la vía de servicio o la salida, la cifra debe cambiar o pasar a «—».
4. Si una cifra no coincide con la señal real, anota el nombre de la vía y el «dato» de la tarjeta: si el dato ya viene mal
   de OSM, se corrige en OpenStreetMap (no en la app).
5. Desactiva el diagnóstico con otros 7 toques.
