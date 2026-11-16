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

## Bloqueos externos (no resolubles desde el código)

1. **Entitlement `com.apple.developer.carplay-maps`**: lo concede Apple tras una solicitud (categoría «Navegación») y la firma de un adendo; se añade a tu cuenta como capacidad gestionada. Apple no publica criterios detallados ni plazos. Escribir la clave en un archivo de entitlements **no** equivale a la autorización.
2. **Cuenta de desarrollador de pago.** Una cuenta gratuita y la firma de Sideloadly no pueden llevar esa capacidad.
3. **Firma y perfil de aprovisionamiento**: el perfil debe incluir el entitlement aprobado.
4. **Verificación**: sin Mac no se puede ver el simulador de CarPlay. Queda pendiente comprobar si el simulador exige o no la aprobación de Apple.

### Cómo activarlo cuando Apple lo apruebe

- Sustituir `QuestMapIRL.entitlements` por el contenido de `QuestMapIRL/Resources/QuestMapIRL-CarPlay.entitlements` (archivo preparado y excluido del paquete; con la firma actual **falla**, por eso no se activa por defecto).
- Firmar con tu Team ID de pago y el perfil con la capacidad.
- No añadir ningún otro entitlement: el de navegación no incluye plantillas de audio.

## Qué se ha construido

- **Escena**: `AppDelegate` elige la escena de CarPlay (`CarPlaySceneDelegate`) o la del iPhone. `UIApplicationSupportsMultipleScenes` pasa a `true` (CarPlay es una segunda escena). Sin entitlement el sistema nunca crea la escena de CarPlay, así que el iPhone no cambia.
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
