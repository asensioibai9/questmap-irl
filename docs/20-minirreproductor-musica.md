# 20 · Minirreproductor de música (Fase 3)

## Qué integra de verdad

**Apple Música / app Música del iPhone**, vía `MPMusicPlayerController.systemMusicPlayer` (MediaPlayer, API pública). Observa el estado real (notificaciones de cambio de canción y de estado) y envía las órdenes reproducir/pausar, anterior y siguiente. Carátula, título y artista salen del elemento en reproducción.

- Permiso: biblioteca multimedia (`NSAppleMusicUsageDescription`). **No** necesita entitlement ni cuenta de desarrollador de pago (a diferencia de MusicKit).
- **No** inicia música al abrir la app ni al conectar; **no** sustituye ni toca la cola (la interfaz `MusicBackend` no tiene operaciones para ello). «Reproducir» solo reanuda lo que el sistema ya tiene en cola.
- **No** controla Spotify ni ninguna otra app: iOS no permite leer y controlar el audio de otras apps de forma universal. Spotify (App Remote) requiere un Client ID tuyo y está pendiente; no se anuncia compatibilidad con otros servicios.

## Estados

Sin configurar · Conectando · Permiso denegado · Restringido · Servicio no disponible · Conectado sin información de reproducción · Reproduciendo · Pausado. «Conexión caducada» no aplica a Apple Música (el permiso lo concede o revoca el sistema; la revocación se detecta al refrescar).

- No recibir metadatos no se interpreta como «no hay audio»: si suena algo sin datos, se muestra «Reproduciendo en Música».
- Las órdenes se confirman leyendo el estado real; si no surten efecto, la interfaz mantiene el estado real y muestra un mensaje discreto. Los botones se desactivan cuando no hay reproducción informada.

## Pantalla

- Tarjeta redondeada con colores del tema, botones de 44 pt, texto que se reduce, sin animaciones.
- Exploración: abajo a la izquierda, sobre el crédito del mapa, sin pasar por la columna de botones laterales; se oculta con el panel expandido.
- Navegación: fila propia encima del panel inferior. Empuja hacia arriba la fila de la señal de velocidad y los botones, sin taparlos ni tapar la ruta ni la maniobra.
- Ajustes: Perfil › Ajustes de navegación › Música (mostrar minirreproductor, servicio, estado, conectar/desconectar). «Desconectar» deja de observar y olvida la conexión; para revocar el permiso hay que usar Ajustes del iPhone (no se puede revocar por código).
- Preferencias persistentes (`showMiniPlayer`, `musicConnected`, `musicServiceRaw`) con guardado al instante. No hay credenciales ni tokens (no se usa ninguna cuenta externa).

## Audio y voz

La voz de navegación usa `.playback` + `.spokenAudio` + `.duckOthers`: baja la música mientras habla y la recupera al desactivar la sesión (`notifyOthersOnDeactivation`). No se pausa ni se reanuda la música por indicación, y abrir la app no activa la sesión de audio.

## Sin verificar

No probado en iPhone: cómo informa el sistema de canciones en streaming que no están en la biblioteca, ni la convivencia con la voz con música real.
