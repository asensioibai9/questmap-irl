# 23 · Spotify y otros reproductores

## Solución elegida para Spotify

**Spotify iOS SDK (App Remote) v5.0.1**, oficial, añadido por Swift Package Manager (`project.yml`). Controla la app de Spotify instalada; la reproducción la hace Spotify, no QuestMap IRL. Con él: canción, artista, carátula, reproduciendo/pausado, reanudar, pausar, siguiente y anterior (estos dos solo si Spotify lo permite en ese momento: `playbackRestrictions`).

- **No se usa la Web API** (no hace falta para estas funciones; tendría sus propias cuotas y endpoints limitados en modo desarrollo) ni el Web Playback SDK (es para reproducir en navegador, no en una app iOS).
- **Autorización**: la del propio SDK, a través de la app de Spotify, con el permiso mínimo `app-remote-control`. No hay client secret ni servidor. El token se guarda en el **Llavero** (solo este dispositivo), nunca en UserDefaults.
- **Aviso importante (documentado por Spotify):** para autorizar, el SDK abre Spotify con `authorizeAndPlayURI("")`, y «una URI vacía reproduce la última canción del usuario o elige una al azar». Por eso solo ocurre al pulsar **Conectar/Reconectar**, tras un aviso que lo explica. Abrir la app, mostrar el reproductor o volver del segundo plano **nunca** abre Spotify ni inicia música.
- **Caducidad**: App Remote no ofrece renovación del token desde el móvil sin servidor. Al volver a la app se reconecta en silencio con el token guardado (si Spotify está abierto); si Spotify lo rechaza, el estado pasa a «Sesión caducada» y hay que pulsar Reconectar (vuelve a abrir Spotify). Spotify recomienda desconectar App Remote al salir de primer plano: se hace (sin pausar la música).
- **Spotify no instalado**: estado propio; no se intenta conectar.

## Lo que tienes que hacer tú (sin Mac)

1. **Spotify for Developers** (https://developer.spotify.com/dashboard) con tu cuenta (en modo desarrollo **el dueño necesita Spotify Premium**):
   - Create app. En «Which API/SDKs are you planning to use?» marca **iOS**.
   - **Redirect URI**: `questmap-irl://spotify-login-callback` (exactamente así).
   - **iOS app bundle ID**: `com.questmapirl.app`. ⚠️ Si Sideloadly cambia el identificador al instalar, Spotify puede rechazar la autorización; en ese caso añade también el identificador que muestre Sideloadly.
   - Copia el **Client ID** (no es secreto; NO copies el client secret, no se usa).
   - En **User Management** añade el correo de cada cuenta de Spotify que vaya a usarlo (máximo 5).
2. **GitHub** (repositorio questmap-irl) › Settings › Secrets and variables › Actions › pestaña **Variables** › New repository variable: nombre `SPOTIFY_CLIENT_ID`, valor = tu Client ID.
3. Haz un push (o lanza a mano el workflow «iOS IPA (sin firmar)»). El IPA nuevo llevará el Client ID; instálalo con Sideloadly como siempre.
4. En el iPhone: instala Spotify e inicia sesión. En QuestMap IRL: Perfil › Ajustes de navegación › Música › Servicio: Spotify › Conectar.

Dónde va cada valor: el Client ID entra por el ajuste de compilación `SPOTIFY_CLIENT_ID` (`project.yml`, vacío por defecto) → clave `QMSpotifyClientID` del `Info.plist`. El esquema `questmap-irl` y la consulta `spotify` ya están en el `Info.plist`. Sin Client ID la app compila y muestra «Falta configurar Spotify».

## Restricciones actuales (Spotify)

- **Modo desarrollo** (todas las apps nuevas): dueño con Premium, un Client ID por desarrollador, **máximo 5 usuarios** añadidos a la lista, uso personal/no comercial ([anuncio de Spotify, feb. 2026](https://developer.spotify.com/blog/2026-02-06-update-on-developer-access-and-platform-security); [modos de cuota](https://developer.spotify.com/documentation/web-api/concepts/quota-modes)).
- **Modo ampliado** (cualquier usuario): solo para organizaciones registradas con servicio lanzado y ≥250.000 usuarios activos mensuales. Para un particular no es viable hoy: **que funcione con tu cuenta no significa que funcione con cualquiera**.
- Spotify no detalla si la lista de 5 usuarios aplica igual a App Remote que a la Web API; hay que asumir que sí.
- Reproducir algo concreto a demanda exige Premium ([SDK](https://github.com/spotify/ios-sdk)); el control de lo que ya suena depende de las restricciones que informe Spotify (los botones se desactivan según ellas).
- Usar el SDK implica aceptar los términos de desarrollador de Spotify.

## Otros servicios

| Servicio | Canción actual | Carátula / artista | Pausar / reanudar | Siguiente / anterior | Requisitos | Modelo | Clase |
|---|---|---|---|---|---|---|---|
| **Apple Música** | Sí | Sí | Sí | Sí | Permiso de biblioteca | Controla la app Música | **A** |
| **Spotify** | Sí | Sí | Sí | Sí (si Spotify lo permite) | Client ID, Premium del dueño, lista de 5 usuarios | Controla la app de Spotify | **A** (pendiente de tu Client ID para probar) |
| YouTube Music | No | No | No | No | — | No hay API pública de control ni de «ahora suena» | **D** |
| Amazon Music | Solo de colas creadas por la propia app (Web API) | — | Solo de esa cola | Solo de esa cola | Sin SDK público; acceso limitado hasta aprobación de Amazon | Reproduciría dentro de nuestra app, no controla la app de Amazon | **D** para controlar su app |
| TIDAL | No (de la app oficial) | — | No | No | Registro en su plataforma | Su SDK reproduce dentro de tu app; controlar la app oficial no está soportado | **D** para controlar su app |
| Deezer | No | — | No | No | — | Su FAQ dice que la API no permite controlar la reproducción; Deezer Connect cerró en 2025 | **D** |

Fuentes consultadas: [Spotify iOS SDK](https://github.com/spotify/ios-sdk), [Amazon Music: visión general del programa](https://developer.amazon.com/docs/music/get_started_program-overview.html) y [Playback V2](https://developer.amazon.com/docs/music/API_playback_overview_v2.html), [TIDAL SDK](https://github.com/tidal-music/tidal-sdk) y su [anuncio iOS/Android](https://github.com/orgs/tidal-music/discussions/70), [Deezer FAQ para desarrolladores](https://support.deezer.com/hc/en-gb/articles/360011538897-Deezer-FAQs-For-Developers). Para YouTube Music no se encontró ninguna API oficial de control.

- iOS **no** permite leer qué suena en cualquier app. `MPNowPlayingInfoCenter` y el nuevo framework «Now Playing» de Apple (WWDC26) sirven para **publicar** el audio de tu propia app, no para leer el de otras. No se usan para eso.
- No se usan APIs privadas, scraping ni reproductores web embebidos.

## CarPlay

No hay controles de música en la interfaz de CarPlay de QuestMap IRL: la categoría de navegación no garantiza plantillas de audio y esta app no es la fuente de la música. No se publican metadatos de Spotify como propios. La navegación convive con la música del sistema (la voz baja el volumen y lo recupera). No se usa audio silencioso.
