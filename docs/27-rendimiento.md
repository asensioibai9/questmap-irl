# 27 · Revisión de rendimiento

Sin Mac no hay Instruments ni perfilado en un iPhone. Lo que sigue distingue **causas confirmadas en el código** (con
prueba automática de la lógica) de **lo que falta medir en el iPhone**. No se da ninguna cifra de FPS ni de milisegundos
del iPhone porque no se ha medido allí; los tiempos del simulador de CI no representan un iPhone real.

## 1. Bloqueo al cambiar la señal de velocidad (y cualquier ajuste de navegación)

**Causa encontrada (en el código):** la pantalla «Ajustes de navegación» sigue montada debajo de «Señal de límite» (pila de
navegación). Cualquier cambio en `UserSettings` la redibuja, y su `body` leía `statusText`, `voiceDetails`, `warning`,
`onlyBasicVoicesInstalled`, `selection`… cada una llamaba a `AVSpeechSynthesisVoice.speechVoices()`, que enumera TODAS las
voces instaladas en iOS y es lento. Unas 6 llamadas por redibujado, en el hilo principal.

**No** se recargaba el mapa, ni el estilo, ni el GPS, ni la navegación, ni se volvía a pedir el límite: el cambio de diseño
solo toca la presentación (`SpeedSignAppearance`) y el componente `SpeedLimitSign` usa el dato que ya existe.

**Arreglo:** `NavigationVoice` guarda la lista de voces por revisión: se lee una vez y solo se vuelve a leer al volver a la
app o cuando iOS avisa de voces nuevas (`refreshVoices`). Prueba: `testInstalledVoicesAreReadOnceNotOnEveryRedraw`
(20 redibujados → 1 lectura; antes ~120).

Además:
- Elegir la opción que ya estaba no escribe ni guarda nada; el setter de la apariencia solo escribe los campos que cambian
  (cada escritura en SwiftData notifica a todas las vistas que leen los ajustes).
- `PersistenceCommit.save` no guarda si no hay cambios.
- Cambios rápidos: cada toque se aplica y guarda en orden, de forma síncrona; gana el último (prueba
  `testRapidSignChangesKeepTheLastChoice`).

## 2. Causa compartida: la pantalla principal se redibujaba con cada lectura GPS

`HomeView` observaba en su `body` cada lectura de posición y cada cambio de brújula (`onChange` de la posición y del rumbo,
`near:` del buscador y del selector de direcciones, indicador GPS). Con GPS activo, toda la pantalla — panel inferior,
botones, hoja de búsqueda con sus listas — se recalculaba varias veces por segundo, también mientras se arrastra el panel,
se hace scroll o se escribe.

**Arreglo:** `HomeLocationFeeder` lleva las lecturas al mapa fuera de SwiftUI; el buscador recibe un origen que solo cambia
al moverse más de 100 m; el indicador GPS es una vista pequeña que observa la ubicación por sí misma. La navegación y la
flecha siguen recibiendo todas las lecturas (sin pérdida de fiabilidad). Queda una lectura por GPS en la pantalla principal
solo mientras hay un lugar seleccionado (su distancia).

## 3. Previews del selector de estilos

- La huella de cada estilo (leer el JSON + SHA-256) se calculaba en el hilo principal cada vez que se abría el selector;
  ahora una vez por ejecución.
- Las previews de la caché (1920×1200) se decodificaban en el hilo principal al dibujarlas durante el scroll; ahora se
  decodifican fuera de él (función asíncrona no aislada) y reducidas al ancho de la pantalla (~2,6 veces menos memoria por
  imagen). Una imagen de caché dañada se regenera.
- Se mantiene: generación de una en una, la elegida primero, sin mapas simultáneos, caché con invalidación por contenido.

## 4. Fin de ruta

`TripRepository.save` cargaba TODAS las celdas exploradas (crece con el uso) al terminar cada ruta. Ahora consulta solo las
del viaje y solo la clave.

## Revisado sin cambios (correcto)

- Búsqueda: ya espera a que termines de escribir, cancela búsquedas viejas y descarta respuestas antiguas.
- Mapa: el estilo solo se recarga si cambia de verdad; la flecha usa un `CADisplayLink` solo mientras se mueve; las capas
  y fuentes se reutilizan.
- Música: por notificaciones del sistema/SDK, sin sondeo.
- GPS: un único gestor; temporizador de estado cada 2 s.
- CarPlay: misma navegación, misma voz y mismo límite; observa la ubicación fuera de SwiftUI.
- Voz grabada: cada indicación lee 1–3 fragmentos cortos (AAC, unos segundos) — medido con un aviso si pasa de 30 ms.

## Instrumentación (sin datos personales)

`PerformanceTrace` marca intervalos `os_signpost` y anota en el registro de diagnóstico existente las operaciones lentas:
guardado de ajustes, lista de voces, huella de estilos, carga de imágenes de un estilo de mapa, fin de ruta, voz grabada.
`MainThreadHangMonitor` (solo con la app abierta) anota cualquier bloqueo del hilo principal de 250 ms o más, con la última
operación medida. Nada de ubicaciones, textos ni audio.

## Probar en el iPhone (2 minutos)

1. Instala el IPA nuevo con Sideloadly.
2. Perfil › Ajustes de navegación › Señal de límite: cambia el diseño 10 veces seguidas, luego tamaño y posición.
3. Abre y cierra Ajustes; abre el selector de estilos y haz scroll; cambia de estilo; activa y desactiva 3D.
4. Con el GPS activo, arrastra el panel y escribe y borra en el buscador.
5. Perfil › Centro de ayuda › Diagnóstico de conexión › Compartir, y envíame el texto. Las líneas `performance.*` indican
   qué se bloqueó y cuánto (si no aparece ninguna `main-thread-hang`, no hubo bloqueos ≥ 250 ms).

## Pendiente de medir en un iPhone

Fluidez real del mapa en 3D y con edificios, coste de cambiar de estilo (carga de teselas y glifos por red), memoria con
todas las previews, batería en navegación larga, y el arrastre del panel con muchos resultados.
