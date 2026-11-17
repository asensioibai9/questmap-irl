# 26 · Voces personalizadas (grabaciones del usuario)

Reproducción de grabaciones REALES del usuario. No hay clonación de voz ni síntesis con IA: un perfil solo puede decir las
frases grabadas. Gratuito y desbloqueado. Todo local.

## Dónde está

Perfil › Ajustes de navegación › Voz de navegación › **Voz de las indicaciones**: voz del sistema, mis perfiles, «Crear nuevo
perfil», y qué hacer con lo no grabado. Flujo: crear perfil → grabar frases → Probar voz → Usar esta voz → navegar.

## Auditoría (fase 1)

- Motor: OSRM. Cada paso trae `maneuver.type`, `modifier` y `exit` (rotondas), y `exits` (números de salida). Antes solo se
  guardaba el texto; ahora `RouteStep.maneuver` conserva esos datos para elegir grabaciones sin interpretar el texto.
- Avisos de voz (`ActiveNavigationViewModel`): inicio, maniobra a ~550 m, ~180 m y en el punto (la primera lejana solo al
  empezar), llegada confirmada por el motor, «recalculando» y fallo al recalcular. Se reutilizan tal cual: no hay un segundo
  motor de navegación.
- Una sola salida de voz (`NavigationVoice`), compartida por iPhone y CarPlay.
- Almacenamiento: SwiftData (con la regla de valores por defecto en el modelo) + Application Support.

## Catálogo (versión 1, español)

Clave estable = `VoicePhraseID` (p. ej. `dir.right`), nunca el texto. **O** = obligatoria, o = opcional.

| Categoría | Frases |
|---|---|
| Inicio y estado | Iniciando ruta **O** · Continúa por la ruta indicada **O** · Recalculando ruta **O** · Cuando sea posible, vuelve a la ruta indicada **O** · Has llegado a tu destino **O** · Tu destino está a la derecha o · Tu destino está a la izquierda o |
| Direcciones | Continúa recto **O** · Gira a la derecha **O** · Gira a la izquierda **O** · Gira ligeramente a la derecha **O** · Gira ligeramente a la izquierda **O** · Gira pronunciadamente a la derecha/izquierda o · Mantente a la derecha/izquierda o · Realiza un cambio de sentido cuando esté permitido o |
| Incorporaciones y salidas | Incorpórate a la vía o · Toma la incorporación a la derecha/izquierda o · Toma la salida a la derecha/izquierda o · En la bifurcación, mantente a la derecha/izquierda o |
| Rotondas | Entra en la rotonda o · En la rotonda, toma la primera/segunda/tercera salida **O** · cuarta/quinta/sexta o · Sal de la rotonda o |
| Distancias | En cien / doscientos / quinientos metros **O** · En cincuenta / trescientos / ochocientos metros, en un / dos kilómetros o |

Fuera del catálogo porque el motor no lo produce: «Mantente en el centro» (sin datos de carril), «Continúa por la vía
principal», «Después / Y después» (se anuncia una maniobra cada vez), «Ahora» (cerca de la maniobra se dice solo la
maniobra), «La ruta se ha actualizado» y «La ubicación no está disponible» (no se anuncian por voz). Añadido porque el motor
sí lo produce: «Toma la incorporación a la derecha/izquierda» y «Entra en la rotonda».

Si una versión futura añade frases, sube `VoicePromptCatalog.version`; los perfiles existentes las verán como pendientes, sin
perder nada.

## Cómo se forman las indicaciones

- Distancia + maniobra: «En doscientos metros» + 0,12 s + «gira a la derecha». La distancia grabada solo se usa si está a
  ±20 % (mínimo ±30 m) de la real; a ~175 m → «doscientos», a ~545 m → «quinientos». A 1,2 km o a 650 m no hay grabación
  correcta → respaldo. Por debajo de 40 m, solo la maniobra (igual que la voz del sistema). En millas no hay grabaciones.
- Rotondas: salidas 1 a 6. Una 7.ª o superior NUNCA se dice con otro número → respaldo.
- «Has llegado» con tu voz solo cuando el motor confirma la llegada; al acercarse, solo «tu destino está a la derecha/izquierda».
- Reproducción: se salta el silencio inicial/final (sin modificar el archivo; margen de 80 ms delante y 150 ms detrás para no
  cortar consonantes), se aplica una ganancia para que todas suenen parecido (máx. +12 dB y -1 dBFS de pico) y fundidos de
  10 ms para evitar chasquidos.

## Nombres de calles y lo no grabado (ajuste «Indicaciones sin grabación»)

- **Híbrido (por defecto)**: si la indicación se puede decir con grabaciones, tu voz; si no, la indicación COMPLETA con la voz
  del sistema. Nunca se mezclan voces dentro de una frase. Las salidas numeradas se dicen con la voz del sistema (incluye el
  número).
- **Solo mis grabaciones**: lo que no se pueda decir con seguridad queda solo en pantalla, sin voz. Requiere el perfil completo
  (obligatorias); con un perfil incompleto se usa siempre el híbrido para no dejar sin voz lo esencial.
- Los nombres de calles nunca se dicen con grabaciones: siguen en pantalla.

## Grabación y validación

- Botón «Grabar» explícito, cuenta atrás configurable (0/3/5 s), medidor de nivel, contador, máximo 10 s, detener, escuchar,
  repetir, guardar, siguiente frase. No se graba durante una navegación ni se pide el micrófono conduciendo.
- Permiso de micrófono al pulsar «Grabar» por primera vez (`NSMicrophoneUsageDescription`). Si se deniega: botón a Ajustes.
- Comprobaciones del SONIDO: archivo legible, duración (0,3–10 s), vacío, voz insuficiente, nivel bajo, saturación, silencios
  largos. No comprueban las palabras (no hay reconocimiento de voz): la app lo dice.
- Llamadas u otras interrupciones: la grabación a medias se descarta.

## Almacenamiento y privacidad

- Audio: AAC (.m4a), 44,1 kHz, mono, en `Application Support/VoiceProfiles/<id del perfil>/<frase>-<uuid>.m4a` (privado y
  persistente; no caché ni temporal).
- Metadatos (SwiftData): `VoiceProfile` (id, nombre, idioma, fecha, versión del catálogo, avatar) y `VoiceRecording` (perfil,
  id de frase, ruta relativa, duración, fecha, inicio/fin de voz, ganancia). Ajustes: perfil activo y respaldo.
- Guardado: se copia el archivo nuevo, se guardan los metadatos y SOLO entonces se borra el anterior. Si algo falla, la
  grabación anterior sigue intacta. Sin espacio (< 20 MB libres) no se guarda y se avisa.
- Limpieza segura: al abrir la pantalla de voces se borran archivos que ningún metadato referencia; nunca uno referenciado.
- Copia de seguridad: los audios entran en la copia de seguridad normal del iPhone (iCloud u ordenador) como el resto de datos
  de la app. No se suben a servidores propios, no van a analítica, no se registran en logs.

## Música, interrupciones y CarPlay

- Misma sesión de audio que la voz del sistema (`.playback`, `.spokenAudio`, baja el volumen de la música y lo devuelve al
  terminar). Sin pausar Apple Music/Spotify con comandos. Sin audio silencioso.
- Una sola voz a la vez: una indicación nueva corta la anterior; las no urgentes esperan (máximo 2 en cola). Al recalcular
  se descartan los giros pendientes; al terminar la ruta se corta todo. Llamadas o cambio de salida (CarPlay, auriculares)
  cortan la frase en curso.
- CarPlay usa el mismo perfil (misma `NavigationVoice`), sin duplicados. Grabar y editar solo en el iPhone.

## Pruebas

`VoicePromptCatalogTests`, `AudioQualityAnalyzerTests`, `VoiceProfileStoreTests`, `RecordedVoiceNavigationTests` (CI,
simulador). Sin probar en un iPhone: grabación real con micrófono, sonido real, permisos, convivencia con música, CarPlay.

## Probar en el iPhone

1. Instala el IPA nuevo con Sideloadly.
2. Perfil › Ajustes de navegación › Voz de las indicaciones › Crear mi primera voz.
3. Graba las obligatorias (botón «Continuar con la siguiente pendiente»). Deniega una vez el micrófono para ver el aviso.
4. «Probar voz» → «Usar esta voz».
5. Navega (de copiloto) con música sonando: escucha giros, rotondas y una calle con nombre (debe decirlo la voz del sistema).
6. Cierra la app del todo, ábrela y comprueba que el perfil y el progreso siguen.
7. Borra el perfil activo: las indicaciones vuelven a la voz del sistema.
