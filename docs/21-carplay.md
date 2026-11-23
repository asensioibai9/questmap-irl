# 21 · CarPlay (navegación)

## Estado honesto

| Nivel | Estado |
|---|---|
| Implementado | Sí (escena, plantillas, mapa, destinos, vista previa, navegación guiada, límite de velocidad) |
| Compilado | Sí (CI) |
| Probado con tests | La lógica compartida (centro de navegación, textos, configuración). **No** las plantillas de CarPlay |
| Probado en simulador de CarPlay | **No** (no hay Mac) |
| Probado en iPhone | **No** |
| Probado en coche real | **No** |
| Autorización de Apple | **Pendiente. Sin ella CarPlay no se conecta.** |

## Diagnóstico (23-11-2026): por qué no aparece en Ajustes › General › CarPlay

Fuente: documentación de Apple «Preparing your iOS app for CarPlay development» y «Building your app's initial CarPlay
interface».

| Tipo | Problema | Estado |
|---|---|---|
| A. Código | El delegado de escena recibía `UIWindow` en vez de `CPWindow`. Son métodos opcionales de Objective-C: con otro tipo, CarPlay no los llama nunca | **Corregido** |
| B. Configuración | El `Info.plist` no declaraba la escena `CPTemplateApplicationSceneSessionRoleApplication`. Apple: CarPlay toma la escena y su delegado de este manifiesto | **Corregido** |
| C. Permiso de Apple | Hace falta que Apple conceda `com.apple.developer.carplay-maps` a una cuenta de pago. Apple: sin ese permiso, el sistema no muestra la app en CarPlay | **Pendiente (bloqueo externo)** |
| D. Firma | El IPA de CI va sin firmar y no lleva entitlements. Sideloadly lo firma con un perfil automático de tu Apple ID, sin CarPlay. Apple: con firma automática, iOS no instala la app en CarPlay | **Confirmado por la configuración**: este flujo no puede dar una build para CarPlay |
| E. Ejecución | Requiere logs del dispositivo con una build ya firmada correctamente | No comprobable todavía |

Escribir la clave en un archivo de entitlements **no** equivale a la autorización.

## Pasos externos (los haces tú en la web de Apple; sin Mac)

1. **Programa de desarrolladores de pago.**
2. **Solicitud del permiso:** https://developer.apple.com/contact/carplay/
   - Datos de tu organización.
   - Tipo de app: **Navigation** (indicaciones giro a giro).
   - Aceptar los términos.
   - Apple revisa cada solicitud con sus criterios y, si la aprueba, añade el permiso a tu cuenta.
3. **App ID:** Certificates, Identifiers & Profiles › Identifiers › tu App ID › Capabilities › activar **CarPlay Navigation**. El Bundle ID del proyecto es `com.questmapirl.app`; si no está libre en tu cuenta, hay que decidir otro antes de seguir.
4. **Certificado de firma, sin Mac:** crea la clave y la solicitud (CSR) en tu PC con OpenSSL, sube el CSR en «Certificates» y convierte el `.cer` descargado a `.p12`. La clave privada no sale de tu PC.
5. **Perfil MANUAL** con ese App ID:
   - App Store, para TestFlight. Es la forma de instalar sin Mac.
   - O Development, con el UDID de tu iPhone registrado.
6. **Secretos en GitHub** (Settings › Secrets and variables › Actions):
   - `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`, `IOS_PROFILE_BASE64` e `IOS_TEAM_ID`.
   - Para TestFlight, además: `ASC_KEY_ID`, `ASC_ISSUER_ID` y `ASC_KEY_P8_BASE64`.
7. **Build:** Actions › **iOS CarPlay (firmada)** › Run workflow. El workflow se detiene con un error claro si el perfil no incluye `com.apple.developer.carplay-maps`, si es de otro App ID o si la app firmada no lleva el permiso.
8. **Instalación:** por TestFlight (método `app-store`, con la casilla de subida marcada). Sideloadly no sirve: vuelve a firmar con su propio perfil y quita el permiso.

## Comprobación en el coche (solo con la build firmada del paso 7)

1. Instala esa build y ábrela una vez en el iPhone.
2. Conecta el coche y mira Ajustes › General › CarPlay › tu coche › Personalizar.
3. Si no aparece, recoge las pruebas:
   - El registro de la ejecución del paso 7, con los entitlements firmados.
   - La versión instalada que muestra TestFlight.
   - Ajustes › Privacidad y seguridad › Análisis y mejoras › Datos de análisis, buscando entradas de QuestMap o CarPlay.

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
