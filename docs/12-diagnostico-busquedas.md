# Diagnóstico: «No se pudo buscar» y avisos de «sin conexión»

Fecha del análisis: 16 nov 2026. Evidencia obtenida ejecutando las mismas peticiones que hace la app desde un ordenador (no desde el iPhone del usuario).

## Qué usaba realmente la app
| Función | Proveedor real |
|---|---|
| Categorías (Gasolineras, Restaurantes…) | **Overpass** (`overpass-api.de`), no MapKit |
| Buscar direcciones | Photon (`photon.komoot.io`) |
| Rutas | OSRM (`router.project-osrm.org`) |
| Mapa | Tiles vectoriales de OpenFreeMap |

## Causa confirmada de «No se pudo buscar. Inténtalo de nuevo»
Con la consulta exacta de la app (gasolineras, Madrid, 2,5 km):
- `overpass-api.de` → **HTTP 502** «This Overpass API server is currently at capacity. All query workers are busy and the request queue is full.»; otra petición **agotó 25 s** sin respuesta.
- `z.overpass-api.de` → **HTTP 429**; `lz4.overpass-api.de`, `overpass.kumi.systems` y `overpass.private.coffee` → tiempo de espera agotado; `maps.mail.ru` → error de conexión.
- La app cortaba a los 20 s y convertía tanto el 502 como el tiempo de espera en el error genérico `.server` («No se pudo buscar»).

Conclusión: el servidor público de Overpass estaba saturado. **No era un problema del 5G del usuario.** (Desde este ordenador no se puede descartar que además haya un problema puntual en la red del iPhone: para eso está el diagnóstico exportable.)

## Falsos avisos de «sin conexión» (confirmado en el código)
- `PhotonSearchService` y `OSRMRouteService` convertían `timedOut`, `cannotFindHost`, `cannotConnectToHost` y `networkConnectionLost` en `.offline` («Sin conexión»): un servidor lento se mostraba como si no hubiera internet.
- El banner «Sin conexión» salía en cuanto `NWPathMonitor` informaba de `unsatisfied` un instante (cambio wifi ↔ 5G, etc.), sin margen.
- El texto «conexión inestable» **no existe** en la app; el más parecido es el aviso del mapa «El mapa tarda demasiado en cargar. Comprueba tu conexión.» (15 s sin cargar el estilo).
- No se puede confirmar, sin los datos del iPhone, que el aviso que viste fuera el banner de red o uno de los errores mal clasificados.

## Qué se cambió
1. **Búsqueda por categorías sin Overpass:** se leen los puntos de interés de los **mismos tiles vectoriales del mapa** (archivos estáticos). En las pruebas: TileJSON 0,19 s; 9 tiles descargados y decodificados en 1,6 s; resultados completos y cercanos para farmacias, cafés, restaurantes, hoteles, cajeros, supermercados, aparcamientos, metro/tren y gasolineras (solo `subclass=fuel`, sin puntos de recarga). Photon se descartó para esto: busca por nombre y devolvió resultados a kilómetros o de otros países.
2. **Errores con causa real** (`SearchError`): sin conexión, conexión cortada, tiempo agotado, servicio no disponible (5xx), límite de peticiones, configuración/autenticación (400/401/403/404/TLS), respuesta ilegible e inesperado. Cada uno con su mensaje; «sin conexión» solo para los dos primeros.
3. **Cancelaciones y vacíos:** una cancelación nunca se muestra como error; «sin resultados» es un estado propio; cada búsqueda lleva un token para que una respuesta antigua no pise a la nueva.
4. **Reintentos limitados** (`RetryPolicy`): máximo 2 reintentos con espera creciente, solo para 5xx y conexión cortada; 1 solo para tiempo agotado; `429` respetando `Retry-After` ≤ 4 s; nunca para sin conexión, configuración o respuesta ilegible. «Reintentar» lanza una búsqueda nueva.
5. **Aviso de red con margen:** solo aparece si la red sigue sin estar disponible 3 s, e indica la causa que da iOS (p. ej. datos móviles denegados a la app).
6. **Ubicación:** la búsqueda por categorías explica por qué no hay ubicación (permiso denegado, restringida, servicios desactivados, sin señal GPS) y permite elegir una zona.

## Diagnóstico desde el iPhone
Perfil › Centro de ayuda › **Diagnóstico de conexión**:
- «Probar conexión» comprueba, uno a uno y sin reintentos, TileJSON, un tile de Madrid, Photon y OSRM (puntos fijos de Madrid: no se envía tu ubicación).
- Muestra el estado de red que da iOS (wifi/cellular, restricciones, motivo).
- «Compartir informe» exporta texto con: versión de la app y de iOS, red, resultado de las pruebas y los últimos eventos (servicio, operación, tipo y código de error, estado HTTP, duración, intento). **No incluye** coordenadas, textos de búsqueda, claves ni URLs completas.

### Qué necesito si vuelve a fallar
Con el fallo visible (o justo después), abre ese diagnóstico, pulsa «Probar conexión» y envíame el informe de «Compartir informe». Si el aviso es «QuestMap IRL no tiene permiso para usar datos móviles», revisa Ajustes › Datos móviles › QuestMap IRL.

## Límites que siguen vigentes
- Photon, OSRM y OpenFreeMap son servicios públicos sin garantía de servicio ni clave: sirven para pruebas, no para publicar con muchos usuarios.
- Los tiles pesan hasta ~1 MB cada uno en el centro de ciudades grandes; una búsqueda descarga 1-4 tiles (se cachean en memoria por sesión).
