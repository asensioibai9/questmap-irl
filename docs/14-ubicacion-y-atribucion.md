# Ubicación («GPS perdido») y atribución del mapa

## 1. Causas encontradas en el código (confirmadas por lectura, no probadas en el iPhone)
`LocationService` declaraba «GPS perdido» en estas situaciones que NO son una pérdida:
1. **Sin primera lectura todavía:** `checkStale()` ponía `isSignalLost = true` a los 2 s de arrancar si `currentLocation == nil`. Así, aunque hubiera conexión y permiso, la app mostraba «GPS perdido» antes de que iOS pudiera dar la primera posición.
2. **Usuario quieto:** con `distanceFilter = 8 m` iOS no entrega lecturas sin movimiento; a los 8 s la lectura «envejecía» y se declaraba pérdida.
3. **Lecturas descartadas por precisión:** `ingest` rechazaba `horizontalAccuracy ≥ 500 m`. Con el permiso de **ubicación aproximada** iOS entrega precisiones de varios kilómetros: todas se descartaban y la app quedaba sin posición.
4. **Lectura en caché:** al arrancar iOS suele entregar primero la última posición guardada (con más de 10 s de antigüedad); se rechazaba y, quieto, no llegaba otra.
5. **`locationUnknown`:** un error temporal marcaba «perdido».
6. **Segundo plano:** la ubicación se paraba también en `.inactive` (p. ej. al aparecer el diálogo de permiso).
7. `start()` no recordaba que se había pedido arrancar si todavía no había permiso: dependía de que la interfaz lo repitiera.

No hay conflicto con el SDK del mapa: `MLNMapView.showsUserLocation = false`, la posición la dibuja la app. El `LocationService` vive en `AppEnvironment` (no se recrea al cambiar de estilo, abrir paneles o reconstruir vistas). `Info.plist` tiene `NSLocationWhenInUseUsageDescription` y la clave `Navigation` de precisión temporal; no se pide «Siempre».

> Sin los registros del iPhone no puedo afirmar cuál de ellas fue la que viste; las tres primeras bastan para explicar el aviso nada más abrir la app.

## 2. Qué cambia
- **Estados reales** (`LocationStatus`): permiso pendiente, obteniendo ubicación, disponible, ubicación aproximada, precisión baja (±m), última ubicación conocida sin confirmar (hace N s), error temporal, permiso denegado, restringido y localización desactivada. Desaparece «GPS perdido».
- **Se aceptan todas las lecturas válidas** (también imprecisas o aproximadas); solo se descartan las inválidas (precisión negativa, coordenada fuera de rango o 0,0, lectura más antigua que la ya aceptada) y se registra el motivo.
- **Estar quieto no es perder la señal:** la vigencia admite hasta 75 s quieto (20 s moviéndose en reposo; 25/10 s navegando). Antes de llegar al límite se pide una lectura puntual (`requestLocation`) para confirmarla.
- **Error temporal:** conserva la última posición; solo se muestra como estado si pasan más de 12 s sin ninguna lectura.
- **Volver del segundo plano:** margen de 8 s de «obteniendo ubicación» mientras llega una lectura fresca; el GPS solo se para en `.background`.
- **Botón de ubicación:** comprueba el permiso (lo pide o explica cómo cambiarlo con acceso a Ajustes), pide una lectura nueva, centra si hay posición y, si no, lo explica. Con ubicación aproximada ofrece «Activar precisa».
- **Indicador:** muestra el estado y, con lectura reciente, «Precisión ±N m». Las barras son una valoración basada solo en la precisión de la lectura, no un porcentaje de señal GPS.

## 3. Diagnóstico desde el iPhone
Perfil › Centro de ayuda › **Diagnóstico de conexión y ubicación › Compartir informe**. Incluye: estado, permiso, precisión concedida, actualizaciones activas/paradas, modo, edad y precisión de la última lectura, velocidad, y eventos `location` (auth, start/stop, reading, error, discarded, status). **Sin coordenadas.**

### Qué necesito si vuelve a aparecer un aviso de ubicación
Envíame el informe de «Compartir informe» **mientras** se ve el aviso, y dime: si estabas quieto o en movimiento, en interior o exterior, y qué permiso tiene la app (Ajustes › QuestMap IRL › Ubicación: «Al usar la app» y «Ubicación exacta» sí/no).

## 4. Atribución
- **Qué la colocaba arriba:** una franja propia en `HomeView.browsingOverlay` (texto `CartographyStyle.attribution`); además el logo y el botón «i» nativos de MapLibre quedaban detrás del panel inferior.
- **Requisitos revisados:** el TileJSON del proveedor declara «OpenFreeMap © OpenMapTiles Data from OpenStreetMap»; OpenStreetMap exige «© OpenStreetMap contributors». El OSMF ha manifestado que una atribución escondida solo tras un botón «i» **no** cumple los requisitos, así que no se oculta.
- **Ahora:** crédito corto («© OpenStreetMap contributors» / «© OpenMapTiles · OpenFreeMap») en dos líneas de 9 pt, a la **izquierda y justo por encima del panel inferior** (sigue a su altura; se oculta solo cuando el panel está totalmente expandido y el mapa deja de verse), con un icono `info` que abre los créditos completos y enlaces. También está en Perfil › Créditos del mapa. Se ocultan el logo y el botón nativos para no duplicar. En navegación sigue el texto del panel inferior del HUD.
- No se ha verificado el texto íntegro de la guía final del OSMF para móviles; si publicas la app, conviene releerla.

## 5. Pendiente de probar en un iPhone
Todo lo anterior está validado solo con pruebas automáticas (gestor de ubicación y reloj simulados). Falta comprobar con un iPhone real: primera posición al abrir, quieto 2-3 minutos, caminando/en coche, volver del segundo plano, ubicación aproximada, permiso denegado, y que el crédito no choque con el panel ni los controles en tu modelo de iPhone.
