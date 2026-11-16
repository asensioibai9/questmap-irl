# Rediseño de la interfaz (16 nov 2026)

## Estructura
- **Pantalla principal**: `Features/Home/HomeView.swift`. Mapa a pantalla completa, tres controles flotantes a la derecha (estilo de mapa, orientación, recentrar) y panel inferior.
- **Panel inferior**: hoja nativa con tres alturas (compacta, media, expandida). La hoja gestiona el arrastre, el teclado y el conflicto entre scroll y arrastre; el mapa sigue siendo manejable detrás hasta la altura media. Contenido: `Features/Panel/SearchPanelView.swift`; estado (texto, resultados, categoría, marcadores) en `SearchPanelModel`, que vive en la pantalla principal para no perder el texto al cambiar de altura.
- **Perfil**: `Features/Profile/ProfileSheetView.swift` y `ProfileSubviews.swift`.
- **Sistema de diseño**: `DesignSystem/Components/AppUI.swift` (botones circulares, filas, grupos, barra de búsqueda, accesos, tarjetas, estados vacíos, mensajes).
- **Marca**: `Features/Splash/` (símbolo y animación de inicio), `tools/make_brand_assets.py` (icono y recursos de lanzamiento), `docs/branding/app-icon-master.svg` (maestro vectorial).

## Datos reales
- Persistencia (SwiftData): Casa, Trabajo, favoritos, historial (`RecentSearch`), viajes, zonas exploradas y ajustes (`UserSettings`: estilo, avatar, voz, unidades, orientación, modo preferido, historial).
- Lugares cercanos por categoría: Overpass sobre datos de OpenStreetMap (instancia pública, sin garantías). Búsqueda de texto: Photon. Rutas: OSRM. Mapa: OpenFreeMap.
- «Eliminar mis datos» borra todo lo anterior y reinicia las preferencias; no puede borrar registros de los servicios externos.

## Configuración pendiente (`App/AppConfig.swift`)
- `appStoreID`: sin valor, la fila «Valóranos» no se muestra.
- `discordInvite`: sin valor, la fila de Discord no se muestra.
- Política de privacidad y términos: son textos dentro de la app. Para publicar en App Store hará falta además una URL pública de la política.

## Decisiones y omisiones
- «Idioma» no se incluye: la app solo tiene español.
- «Icono de la app» no se incluye: no hay iconos alternativos implementados.
- Las tarjetas de recomendación usan ilustraciones propias dibujadas con formas, no fotografías (no hay imágenes con licencia incluidas).
- Los estilos de Fortnite y Minecraft aún no existen; la galería solo muestra los estilos terminados.
- Sin Mac ni dispositivo no se ha podido ver la app ejecutándose: la interfaz está comprobada solo por compilación y tests.
