# QuestMap IRL — Producto, MVP y arquitectura (fase 0)

> Documento de trabajo. Nada de lo aquí descrito es código final: es la base para confirmar alcance antes de generar el proyecto completo.

## 1. Nombre y concepto

**Nombre provisional:** QuestMap IRL.

**Aviso de marca:** "IRL" y "Maps" se parecen mucho a Game Maps IRL. Antes de publicar conviene hacer búsqueda de marca (USPTO, EUIPO, OEPM y App Store). Alternativas a valorar: **Rutaquest**, **Quest Drive**, **Tramo Quest**, **Mapa Vivo**.

**Concepto en una frase:** navegación GPS real con la estética de un minimapa de videojuego: la ruta es tu "misión", las zonas que exploras se revelan como niebla de guerra y cada viaje suma progreso cosmético.

**Principio no negociable:** la estética cambia; la precisión no. Los temas solo alteran color, tipografía, iconos y efectos. Los datos de ruta, maniobras y ETA salen siempre de Apple Maps.

## 2. Público objetivo

- Conductores urbanos y de carretera que quieren una navegación más visual y entretenida.
- Jugadores casuales y fans de mapas de videojuegos (sin usar marcas ajenas).
- Personas que exploran ciudades a pie o en transporte público.
- Usuarios que valoran personalización (temas, pines, favoritos) más que la competencia de funciones de Waze o Google Maps.

## 3. Propuesta de valor y diferenciación

| Eje | QuestMap IRL | Navegadores típicos |
|---|---|---|
| Estética | Temas de videojuego propios, 6 de inicio | Estilo corporativo fijo |
| Motivación | Fog of War, logros, niveles cosméticos | Casi nula |
| Privacidad | Historial y niebla en el dispositivo; sin venta de datos | Varía |
| Precisión | Apple Maps Directions (datos reales) | Datos propios |

## 4. Limitaciones técnicas que hay que aceptar (importante)

Esto condiciona el diseño. Conviene decidirlo ahora:

1. **MapKit no permite reestilizar el mapa base** (calles, agua, edificios) con colores arbitrarios. Los temas "voxel", "retro" o "pergamino" se consiguen con:
   - Overlays propios (texturas, gradientes, ruido, viñetas) sobre `Map`.
   - Estilo propio de la ruta, marcadores e iconos (polilíneas en capas con glow, anotaciones).
   - Elección de `MapStyle` (`standard`, `imagery`, `hybrid`) y de esquema de color día/noche.
   - Si quieres un mapa base totalmente temático (p. ej. voxel real), habrá que usar un proveedor de vector tiles (MapLibre + tiles con licencia). Es una decisión de coste, licencias y mantenimiento. **Recomendación MVP: MapKit + overlays.**
2. **Límite de velocidad y tráfico/incidencias:** la API pública de MapKit no ofrece límites de velocidad ni incidencias de obras/accidentes de forma general. En MVP se muestra la velocidad actual (Core Location) y se deja el límite y las incidencias como función condicionada a una fuente de datos licenciada (versión 1.1 o posterior).
3. **Voces:** `AVSpeechSynthesizer` usa voces del sistema. "Voces originales" exige generar voces propias con un TTS con licencia comercial (o grabar actores con contrato). En MVP: 2 voces de sistema con perfil de "tono de juego" (velocidad y tono distintos) y dejar las voces originales para la versión premium.
4. **CarPlay:** requiere solicitar el entitlement de app de navegación a Apple. No se puede activar solo con código. Plazo y aprobación no controlables; se planifica como versión 1.1 con solicitud temprana.
5. **Transporte público:** `MKDirections` con `.transit` está disponible solo en ciudades soportadas. Se mostrará solo cuando la respuesta sea válida.
6. **Navegación en segundo plano:** requiere `UIBackgroundModes` (`location`, y `audio` para la voz) y justificación clara en App Review.
7. **Ubicación "Always":** no se pedirá en MVP. Solo "When In Use" más, opcionalmente, "Allow while navigating" si el flujo lo permite.

## 5. Alcance por fases

### MVP (primera versión publicable)
- Onboarding con explicación de permisos de ubicación y aviso legal de tráfico.
- Mapa con ubicación GPS en tiempo real, zoom, rotación, recentrado y brújula.
- Búsqueda de destinos (MKLocalSearch) y pulsación larga en el mapa.
- Rutas en coche y a pie con MKDirections (varias alternativas: tiempo, distancia, tipo).
- Vista previa de ruta con botón "Iniciar".
- Navegación activa: próxima maniobra grande, distancia restante, ETA, progreso, recálculo si hay desvío.
- Voz en español (2 voces de sistema) con silencio rápido.
- Modo día/noche automático y manual.
- Velocidad actual.
- Casa y Trabajo como accesos rápidos.
- Favoritos con nombre y nota (SwiftData) y pines personalizados.
- 3 temas gratuitos: "Mapa minimalista", "Retro arcade" (versión limitada) y "Neón nocturno" (versión limitada).
- Fog of War básico: zonas visitadas (celdas geohash en el dispositivo) con revelado progresivo.
- Estadísticas básicas: km, rutas completadas, lugares visitados.
- Compartir ubicación/ruta mediante enlace de Apple Maps.
- StoreKit 2: paywall, compra del desbloqueo, restaurar compras.
- Ajustes: tema, idioma de voz, unidades métricas/imperiales, privacidad.

### Versión 1.1
- Los 3 temas restantes completos: "Mundo voxel", "Mapa de aventura", "Cyber-city".
- Logros completos y niveles cosméticos.
- Marcadores tipo quest, tienda, combustible, comida, parking, punto de interés (iconografía propia).
- Fog of War avanzado (revelado por desplazamiento y por tipo de vía).
- Historial y estadísticas ampliadas (gráficas, rachas).
- CarPlay (mapa, maniobra, ETA, búsqueda reciente, controles mínimos).
- Voces premium.

### Versiones futuras
- iPad (layout de dos columnas).
- Límites de velocidad e incidencias con fuente licenciada.
- Mapa base temático con MapLibre (si la licencia lo justifica).
- Widgets y Live Activities (ETA en Dynamic Island).
- Apple Watch (maniobra y vibración).
- Modo "rally" o compartir progreso entre amigos (con cuenta opcional).

## 6. Arquitectura técnica

### Capas

```
┌──────────────────────────────────────────────┐
│  UI (SwiftUI)                                │  Vistas, componentes, animaciones
├──────────────────────────────────────────────┤
│  ViewModels (@Observable, MainActor)         │  Estado de pantalla, acciones
├──────────────────────────────────────────────┤
│  Dominio / Navegación                        │  Motor de ruta, maniobras, recálculo
│  Mapas · Temas · Gamificación · Compras      │  Reglas de negocio puras (sin UI)
├──────────────────────────────────────────────┤
│  Servicios                                   │  LocationService, RouteService,
│                                              │  SearchService, SpeechService,
│                                              │  StoreService, ThemeService
├──────────────────────────────────────────────┤
│  Almacenamiento                              │  SwiftData (favoritos, historial,
│                                              │  ajustes, niebla), Keychain opcional
└──────────────────────────────────────────────┘
```

Reglas:
- Las vistas no llaman a CoreLocation, MapKit ni StoreKit directamente: siempre pasan por un servicio.
- Los servicios se inyectan por protocolo (facilita tests y CarPlay más adelante).
- El motor de navegación no conoce SwiftUI: recibe ubicaciones y devuelve estado (`NavigationState`).

### Tecnologías
- SwiftUI + Observation (`@Observable`), iOS 17.0 mínimo.
- MapKit (`Map`, `MapPolyline`, `MapCameraPosition`, `MapStyle`).
- Core Location (`CLLocationManager`, permisos, `allowsBackgroundLocationUpdates`).
- MapKit Directions (`MKDirections`) y `MKLocalSearch`.
- AVFoundation (`AVSpeechSynthesizer`) para voz.
- SwiftData para persistencia.
- StoreKit 2 (`Product`, `Transaction.currentEntitlements`, `AppStore.sync()`).
- Futuro: CarPlay (`CPTemplateApplicationScene`).

### Modelos principales (resumen; detalle en fase 2)
- `UserSettings` (SwiftData): tema, voz, unidades, modo noche, tipo de ruta preferido.
- `SavedPlace` (SwiftData): nombre, coordenada, nota, icono, tipo (casa, trabajo, favorito, pin).
- `VisitedCell` (SwiftData): celda geohash visitada y fecha; base del Fog of War.
- `TripRecord` (SwiftData): distancia, duración, ruta resumida, fecha.
- `Achievement`, `Progress` (estáticos + desbloqueos).
- `MapThemeID` (enum) → `MapTheme` (struct con tokens de color, tipografía, iconos y efectos).
- `Subscription` / `Entitlement` (derivado de StoreKit 2; nunca se guarda como fuente de verdad local).

### Flujo de navegación activa
1. `LocationService` emite ubicaciones (cada ~1 s en navegación).
2. `NavigationEngine` proyecta la posición sobre la polilínea, calcula distancia restante y próxima maniobra.
3. Si la distancia a la ruta supera un umbral (p. ej. 50 m durante 3 s), dispara `RouteService.recalculate`.
4. `SpeechService` anuncia maniobras a 500 m, 150 m y en el punto.
5. `TripRecorder` acumula km y tiempo; al terminar, guarda `TripRecord` y actualiza niebla y logros.

## 7. Estructura de carpetas del proyecto Xcode

Ver el árbol completo en `docs/02-estructura-proyecto.md` y el código inicial en `QuestMapIRL/`.

## 8. Pantallas principales

1. **Onboarding:** 3 pasos (qué hace, por qué necesita ubicación, aviso de tráfico). Botón "Permitir ubicación al usar la app".
2. **Home:** mapa a pantalla completa, barra de búsqueda flotante arriba, accesos rápidos Casa/Trabajo/Favoritos, botón de recentrar, botón de ajustes.
3. **Búsqueda:** campo de texto, resultados de MKLocalSearch, recientes, pulsación larga en el mapa como alternativa.
4. **Vista previa de ruta:** alternativas (tiempo, distancia, tipo), selector coche / a pie, tarjeta inferior con ETA, distancia y botón grande "Iniciar".
5. **Navegación activa:** maniobra grande arriba, distancia y ETA abajo, velocidad, barra de progreso, botones silenciar / ver ruta / buscar / finalizar.
6. **Ajustes:** tema, voz, unidades, modo noche, privacidad, restaurar compras.
7. **Perfil y logros:** nivel cosmético, estadísticas, niebla (porcentaje explorado), logros.
8. **Paywall:** beneficios, precio (mensual/anual o compra única), restaurar, enlaces legales.
9. **CarPlay (1.1):** plantilla de mapa + maniobra + ETA + lista de búsquedas recientes.

## 9. Monetización (MVP)

- App gratuita con navegación básica y 3 temas.
- Suscripción mensual/anual (StoreKit 2 auto-renovable) o compra única "Desbloqueo Quest" a decidir. **Recomendación:** suscripción anual + compra única de lanzamiento; valorar después.
- Incluye: todos los temas, voces premium, Fog of War avanzado, estadísticas ampliadas, CarPlay (cuando exista).
- Sin anuncios en MVP (evita complicaciones de privacidad y de ATT).

## 10. Privacidad y cumplimiento (checklist inicial)

- Ubicación: `NSLocationWhenInUseUsageDescription` con texto claro. Sin "Always" en MVP.
- Datos recogidos: ubicación (solo en el dispositivo salvo que el usuario comparta), historial de viajes local, datos de compra (Apple). Declarar en "Etiquetas de privacidad" de App Store.
- No se venden datos personales. No hay analítica de terceros en MVP.
- Aviso legal dentro de la app: "Herramienta de navegación. Respeta las normas de tráfico y no uses la app mientras conduces."
- Política de privacidad y términos de uso: a redactar y revisar por un abogado antes de publicar.
- Licencias: Apple Maps / MapKit se usan según sus términos (mostrar logo y atribución de Apple Maps). Revisar cualquier fuente extra.
- Accesibilidad: VoiceOver en maniobras, Dynamic Type, contraste mínimo WCAG AA en temas.

## 11. Plan de pruebas (resumen; detalle en fase final)

- GPS: simulación de rutas (GPX), pérdida de señal, túneles.
- Rutas: destinos cercanos y lejanos, recálculo por desvío, ruta a pie y coche.
- Permisos: denegado, restringido, "solo esta vez".
- Batería: navegación de 60 min con pantalla bloqueada.
- Modo oscuro y temas: contraste, legibilidad con sol directo (modo día alto contraste).
- VoiceOver y Dynamic Type en navegación activa.
- CarPlay: simulador de CarPlay (cuando haya entitlement).
- Compras: sandbox de StoreKit, compra, restaurar, cancelación, reembolso.

## 12. Siguientes pasos (pendientes de tu confirmación)

1. Confirmar nombre provisional o elegir alternativa (y hacer búsqueda de marca).
2. Confirmar que el mapa base sigue siendo MapKit (con overlays temáticos) para el MVP.
3. Confirmar voces de sistema para MVP y voces originales para premium.
4. Confirmar modelo de monetización (suscripción, compra única o ambas).
5. Después: generar el código completo, modelos SwiftData, servicios, temas, paywall y textos de App Store.
