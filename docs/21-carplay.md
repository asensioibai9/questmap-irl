# 21 · CarPlay (navegación)

## Estado (23-11-2026)

### A. Implementado en código
- **Escena principal:** declarada en el `Info.plist` (`CPTemplateApplicationSceneSessionRoleApplication` → `CarPlaySceneDelegate`).
- **Delegado:** implementa los métodos de navegación con la firma de Apple (`CPWindow`).
- **Interfaz:** `CPMapTemplate` como plantilla principal, búsqueda, listas, vista previa de rutas, `CPNavigationSession` y estado compartido con el iPhone.

### B. Compilado y probado
- **Comprobación estática en CI** (commit `954c049`):
  - La app compila y los tests pasan.
  - Tests de configuración: el `Info.plist` declara la escena, el delegado existe y sus métodos coinciden con la firma del protocolo.
  - El paso de empaquetado del IPA sin firmar falla si la escena no está en el `Info.plist` compilado, y ha pasado.
- **No probado en ejecución:**
  - Las plantillas de CarPlay (no hay Mac ni simulador de CarPlay).
  - Conexión y desconexión reales, el mapa en un coche y la ausencia de voz duplicada en un coche.

### C. Bloqueado por la aprobación de Apple
- Falta que Apple conceda `com.apple.developer.carplay-maps` (CarPlay Navigation) a tu cuenta de desarrollador.
- Apple: sin un permiso de CarPlay, el sistema no muestra la app en CarPlay.
- Escribir la clave en un archivo de entitlements no equivale a tenerla concedida.

### D. Pendiente de firma
- Falta un App ID con la capacidad CarPlay Navigation y un perfil de aprovisionamiento manual generado después de activarla.
- También falta una build firmada con ese perfil y con `QuestMapIRL-CarPlay.entitlements`.
- El workflow «iOS CarPlay (firmada)» está preparado, pero no se ha ejecutado nunca.

### E. Pendiente de prueba en un coche
Todo lo que depende de CarPlay en ejecución:
- Que aparezca en Ajustes › General › CarPlay › tu coche › Personalizar.
- Mapa, búsqueda, rutas, guiado y voz.
- Conexión y desconexión.

## Diagnóstico de firma en TU flujo actual

| Qué | Cómo lo sé |
|---|---|
| El IPA de GitHub se compila con `CODE_SIGNING_ALLOWED=NO`: no está firmado y no lleva ningún entitlement | **Configuración del workflow** (`ios-ipa.yml`). El registro del paso que lo muestra solo se ve con sesión iniciada en GitHub |
| Sideloadly firma ese IPA con un certificado y un perfil que obtiene a través de tu Apple ID | Así funciona la herramienta. **No he inspeccionado** el perfil que generó ni la app instalada en tu iPhone |
| Ningún perfil puede incluir `com.apple.developer.carplay-maps` si Apple no ha concedido antes ese permiso a la cuenta | Documentación de Apple: el permiso se añade a la cuenta tras aprobarlo y después al App ID y al perfil |
| Apple: con firma automática, iOS no instala la app en CarPlay. Hace falta un perfil manual | Documentación de Apple |
| No sé si Sideloadly puede firmar con un certificado y un perfil manual tuyos que incluyan CarPlay | **No comprobado** |

En resumen, en tu flujo faltan:
1. La autorización de Apple en tu cuenta.
2. Un App ID con la capacidad activada.
3. Un perfil manual que la incluya.
4. Una firma que use ese perfil y el archivo de entitlements de CarPlay.

Si algún día comprobamos que Sideloadly puede firmar con tu certificado y tu perfil manual, se podría seguir usando. Si no, el camino es el workflow firmado y TestFlight.

Fuentes de Apple:
- https://developer.apple.com/documentation/carplay/preparing-your-ios-app-for-carplay-development
- https://developer.apple.com/documentation/carplay/building-your-apps-initial-carplay-interface

## Pasos externos, en orden

1. **Solicitar el permiso** en https://developer.apple.com/contact/carplay/ (pide iniciar sesión con tu Apple ID).
   - Información de tu organización.
   - Tipo de app: **Navigation**.
   - Aceptar los términos.
   - Apple revisa cada solicitud con sus criterios y, si la aprueba, añade el permiso a tu cuenta.
   - No he podido confirmar si el formulario exige estar ya en el programa de pago. Sí es seguro que para crear App IDs con capacidades y perfiles manuales hace falta el **Apple Developer Program** (99 USD al año): https://developer.apple.com/programs/enroll/
2. **App ID**, solo tras la aprobación: Certificates, Identifiers & Profiles › Identifiers › App ID › Capabilities › **CarPlay Navigation**. El Bundle ID es `com.questmapirl.app`; si no está disponible en tu cuenta, se decide otro contigo antes de cambiar nada.
3. **Certificado de firma:** la clave privada y la solicitud de certificado (CSR) se crean en tu PC; Apple firma el certificado.
4. **Perfil manual:** de tipo App Store para TestFlight, o Development con el UDID de tu iPhone.
5. **Secretos en GitHub y ejecución del workflow:** consulta la sección «Seguridad de la firma en GitHub Actions». Subir a TestFlight solo con tu autorización expresa: la casilla está desactivada por defecto.

## Seguridad de la firma en GitHub Actions

**Al guardar el `.p12` como secreto, la clave privada del certificado SALE de tu PC.** GitHub la guarda cifrada y la descifra
en un Mac temporal suyo en cada ejecución del workflow. Cualquiera con permiso para modificar los workflows de este
repositorio podría usarla. Si sospechas una filtración, revoca el certificado en Apple Developer.

| Secreto | Qué contiene | Sensibilidad |
|---|---|---|
| `IOS_DIST_CERT_P12_BASE64` | Certificado de firma **y su clave privada**, en base64 | Alta |
| `IOS_DIST_CERT_PASSWORD` | Contraseña del `.p12` | Alta |
| `IOS_PROFILE_BASE64` | Perfil `.mobileprovision`: App ID, Team ID, permisos y, si es de desarrollo, los UDID de tus dispositivos | Media (datos de cuenta) |
| `IOS_TEAM_ID` | Identificador de tu equipo de Apple Developer | Baja |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` | Clave de API de App Store Connect, solo para TestFlight. La `.p8` es privada | Alta |

Medidas del workflow (`.github/workflows/ios-carplay-signed.yml`):
- **Ejecución:** solo a mano, con permisos de solo lectura sobre el repositorio y en un Mac alojado por GitHub (`macos-15-intel`), que es lo que exigen `xcodebuild` y `codesign`. La máquina se destruye al terminar.
- **Llavero temporal** con contraseña aleatoria. El `.p12` se borra justo después de importarlo.
- **Limpieza siempre, también si falla:** al final se borran el llavero, el perfil, la clave `.p8`, el archivo de exportación, el archivo de compilación y el IPA.
- **Registros mínimos**, porque el repositorio es público y sus registros también: comprobaciones de sí o no, solo los nombres de los entitlements y no los valores. El UUID del perfil se enmascara. No se imprimen el perfil, el Team ID ni el App ID.
- **Sin artefacto por defecto:** el IPA firmado lleva el perfil embebido, así que solo se guarda si lo marcas (durante 3 días).
- **Ningún certificado, clave ni perfil se publica nunca como artefacto.**

## Uso sin cuenta de desarrollador propia

Hay que distinguir dos cosas:
1. **El usuario de la app no necesita cuenta de desarrollador.** Nadie la necesita para usar una app ya publicada.
2. **La app sí tiene que estar autorizada y firmada por un desarrollador** con el permiso de CarPlay para que iOS la muestre en el coche. Ningún cambio de código elimina este requisito.

### Lo que puedes usar ahora con tu instalación actual (IPA sin firmar más Sideloadly)

Todo lo del iPhone, incluido el uso en el coche con el iPhone en un soporte:
- **Horizontal a ambos lados**, con la flecha y la cámara orientadas según la marcha. La brújula usa la referencia de la interfaz.
- **En navegación:** panel lateral con la maniobra, la hora de llegada, el tiempo y la distancia restantes, y los botones. Los botones de la derecha miden 52 pt si hay altura suficiente y 44 pt como mínimo.
- **Voz:** configuración de audio de navegación (`.playback` y `.voicePrompt`). La música baja durante el aviso y los pódcasts se pausan.
- **Salida de audio:** sale por donde indique el sistema (Bluetooth o cable del coche, auriculares, altavoz). Ajustes de navegación › «Salida de audio» muestra la salida actual y el selector del sistema (`AVRoutePickerView`).

Este modo es la pantalla del iPhone: **no es CarPlay** y no aparece en la pantalla del coche.

### Lo que seguirá sin aparecer en CarPlay

La app entera, mientras no exista una build firmada con `com.apple.developer.carplay-maps` concedido por Apple. La escena y las plantillas de CarPlay quedan en el código, preparadas, pero iOS no las usa.

### Distribución futura por otro desarrollador u organización

Un desarrollador o una organización con cuenta del Apple Developer Program puede encargarse legítimamente de:
- solicitar el permiso de CarPlay;
- registrar el App ID;
- firmar la app y distribuirla por TestFlight o la App Store bajo **su** cuenta.

Esto **no elimina los requisitos ni garantiza la aprobación**: solo cambia quién tiene la cuenta, quién firma y quién responde ante Apple de la app y su distribución.

Qué tendría que aportar esa persona u organización:
- **Su cuenta de pago** y la **solicitud del permiso** CarPlay Navigation (https://developer.apple.com/contact/carplay/) a su nombre, con sus datos de organización y la aceptación de los términos.
- **Bundle ID:** un App ID con la capacidad activada y su propio Bundle ID registrado en su cuenta. Cambiar `com.questmapirl.app` solo se hará si tú lo decides.
- **Firma:** su certificado y un perfil manual, usados con el workflow «iOS CarPlay (firmada)» o con su propio proceso. Los secretos se guardarían en el repositorio que ellos controlen.
- **TestFlight o App Store:** su App Store Connect para distribuir, con las obligaciones de privacidad y revisión que eso implica.
- **Un acuerdo contigo** sobre el código, la marca y los datos. Este repositorio no gestiona nada de eso.

No es aceptable usar permisos, perfiles o identidades de otra app para que esta pase por una app autorizada.

## Qué se ha construido

- **Escena**: declarada en el `Info.plist` (`CPTemplateApplicationSceneSessionRoleApplication` → `CarPlaySceneDelegate`) y también en `AppDelegate`, que elige la escena de CarPlay o la del iPhone. `UIApplicationSupportsMultipleScenes` pasa a `true` (CarPlay es una segunda escena). Sin entitlement el sistema nunca crea la escena de CarPlay, así que el iPhone no cambia.
- **Fuente de verdad única**: `NavigationHub` (fuera de cualquier vista). Guarda la sesión activa, recibe las lecturas reales de GPS, termina/cancela, guarda el viaje y suelta voz y GPS. El iPhone (`HomeView`) y CarPlay solo lo observan: no hay sesiones, recálculos ni voces duplicados. Funciona con el iPhone bloqueado o sin su pantalla creada.
- **Interfaz** (`CarPlayCoordinator`): `CPMapTemplate` raíz con botones «Destinos» y «Buscar» y botones de mapa (recentrar y 2D/3D si el estilo lo admite); `CPListTemplate` para Casa, Trabajo, Favoritos, Recientes y categorías cercanas; `CPSearchTemplate` conectado a la búsqueda real; vista previa con `CPTrip`/`CPRouteChoice` (varias rutas si el proveedor las da); navegación con `CPNavigationSession` (próxima maniobra y siguiente, distancia y tiempo a la maniobra, distancia/tiempo restantes), llegada (`finishTrip`) y cancelación (`cancelTrip`).
- **Mapa en el coche**: el mismo renderizador y los mismos estilos, en la ventana de CarPlay, sin gestos, en 2D por defecto, con puntos de interés, números de portal y marcadores de resultados ocultos. La ruta, el destino y tu posición se conservan. Edificios 3D opcionales con el botón. Crédito del mapa dentro del área segura.
- **Límite de velocidad**: la misma señal (borde rojo, fondo blanco, número negro) dentro del área segura de la ventana del coche, con los mismos datos y el mismo ajuste que el iPhone.
- Datos de usuario (Casa, Trabajo, favoritos, recientes) leídos del mismo almacén; no se registran.

## Sincronización iPhone ↔ CarPlay

- Ruta iniciada en el iPhone y luego se conecta el coche: CarPlay se une a LA MISMA sesión.
- Iniciada en CarPlay: el iPhone prepara su pantalla al reaccionar al centro.
- Cambiar destino: se cierra la sesión anterior y se abre otra (nunca dos).
- Cancelar desde cualquiera de los dos: termina para ambos.
- Desconectar durante la navegación: se liberan los recursos de CarPlay; **la navegación continúa en el iPhone** sin borrar la ruta ni crear otra. Al reconectar, CarPlay vuelve a unirse a la sesión.
- Modos de fondo: solo `location` y `audio` (los que ya existían).

## Música en CarPlay

No se implementa un reproductor en CarPlay: el entitlement de navegación no garantiza plantillas de audio y esta app no es una app de audio. La navegación convive con la música (la voz baja el volumen y lo recupera); para controlar la música se usa la experiencia del sistema. No se dibuja ningún reproductor falso ni se publican metadatos de otras apps.

## No implementado / depende del coche

- **CarPlay Dashboard, cuadro de instrumentos y head-up display**: no se han implementado (requieren escenas adicionales y dependen del vehículo y del sistema). No se afirma compatibilidad con CarPlay Ultra ni con todas las pantallas.
- Botones físicos o giratorios: se usan los controles estándar de las plantillas; no se han probado.
- Modo claro/oscuro: el mapa sigue el estilo elegido; las plantillas las adapta el sistema.
- Navegación sin conexión: no hay soporte (rutas y búsqueda necesitan internet; el límite de velocidad, también).
- Ubicación: con permiso «al usar la app» el comportamiento con el iPhone en el bolsillo está **sin verificar**.
