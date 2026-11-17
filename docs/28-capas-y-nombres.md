# 28 · Nombres bajo los iconos y «Capas del mapa»

## Revisión previa (datos reales del proveedor)

Se inspeccionaron teselas reales de OpenFreeMap (esquema OpenMapTiles) en Madrid:

| Necesidad | Dato real | Resultado |
|---|---|---|
| Nombre del sitio | `poi.name`, `poi.name:es` (no existe un campo de nombre corto) | Implementado |
| Restaurantes, cafeterías, bares | `poi.class` restaurant, fast_food, cafe, bakery, ice_cream, bar, pub, beer | Implementado |
| Tiendas y supermercados | shop, clothing_store, …, grocery (supermarket) | Implementado |
| Gasolineras / salud | fuel / hospital, pharmacy, doctors, dentist, veterinary | Implementado |
| Aparcamientos | `poi.class = parking` (con nombre, p. ej. «El Corte Inglés») | Implementado, sin plazas ni precios |
| Estaciones | railway (metro, tren), bus (estaciones) | Implementado, sin horarios |
| Paradas de autobús | bus / subclass bus_stop | Implementado (antes se omitían) |
| Líneas de metro y tren | `transportation.class` transit / rail | Implementado (las de autobús no existen en los datos) |
| Vías ciclistas | `transportation` path + subclass cycleway o bicycle = designated | Implementado (los carriles pintados en la calzada no están en los datos) |
| Aparcabicis / alquiler de bici | bicycle_parking / bicycle_rental | Implementado, sin bicis ni anclajes libres |
| Semáforos | No están en las teselas | **No disponible** (ver abajo) |
| Tráfico en directo | No hay fuente gratuita | **No disponible** |

## Nombres bajo los iconos

- Se dibujan con el propio motor (MapLibre), en la MISMA capa que el icono: icono y nombre colisionan como una unidad;
  si no cabe el nombre, el icono se mantiene (`text-optional`); nunca se solapan con otros iconos ni con nombres de calles.
- Nombre: `name:es` → `name` → categoría breve solo donde ayuda (Parking, Gasolinera, Farmacia, Hospital, Aparcabicis).
  Nunca la dirección. Tildes, espacios y caracteres originales intactos.
- Más de 22 caracteres: se muestra a 21 + «…» (expresión `slice`, soportada en MapLibre iOS ≥ 6.0; el proyecto usa
  7.0.0). Es SOLO presentación: el dato no se toca y al tocar el lugar la ficha muestra el nombre completo.
- Una línea, centrado debajo, halo del estilo. Aparece algo después que el icono y por importancia: gasolineras,
  estaciones y hospitales antes; comida y tiendas solo muy cerca. Las capas más importantes ganan las colisiones.
- Ajuste «Mostrar nombres de los lugares» (en el panel de capas y en Ajustes de navegación › Mapa). Al apagarlo solo se
  vacía el texto de esas capas: los iconos siguen.
- Comprobado con el validador oficial de MapLibre (los 9 estilos sin errores) y evaluando la expresión con nombres reales:
  «Aparcamiento Plaza de España - Gran Vía» → «Aparcamiento Plaza de…»; sin nombre → «Parking»; «Parking Ñandú Álvarez»
  intacto.

## Panel «Capas del mapa»

Se abre con el botón flotante de capas que ya existía (antes abría solo los estilos): un único control. Arriba enlaza con
«Estilo de mapa» (GTA, Fortnite…); debajo, las capas sobre ese estilo, agrupadas: Lugares, Transporte público, Bicicleta y
Tráfico. Restablecer capas, cerrar.

- Cada interruptor cambia solo la VISIBILIDAD de capas ya presentes en el estilo: sin recargar el estilo, sin mover la
  cámara, sin tocar ubicación ni ruta, sin descargas nuevas (los datos ya vienen en las teselas).
- Por defecto: activado lo que ya se veía (lugares y estaciones); lo nuevo (paradas, líneas, bici) empieza apagado.
- Siempre visibles aunque su categoría esté oculta: resultados de una búsqueda, destino, lugar seleccionado y Casa/Trabajo
  (son capas aparte).
- Ocultar una capa no cambia el cálculo de rutas.
- Las líneas de bici y de transporte se dibujan discontinuas y por debajo de la ruta, con colores distintos de ella.
- Se conservan al cambiar de estilo (se reaplican tras cargarlo) y al cerrar la app (`UserSettings.mapLayersRaw`, formato
  `id=1,id=0`: una capa nueva en el futuro toma su valor por defecto).

## No disponibles (y por qué)

- **Semáforos**: no vienen en las teselas. La fuente gratuita (API pública Overpass de OpenStreetMap) indica que es para
  herramientas usadas por personas, no para uso automático desde apps, y en la prueba respondió «at capacity». Se deja
  preparada la capa y un icono NEUTRO (tres luces grises, sin estado). Alternativas: servidor Overpass propio (gratis,
  requiere un ordenador o servidor) o teselas propias con semáforos.
- **Tráfico en directo**: requiere un proveedor de pago (TomTom, HERE, Mapbox). No contratado.
- Horarios en directo, plazas libres, precios y bicicletas disponibles: no hay integración; no se muestran.

## CarPlay

No copia el panel: el mapa del coche es simplificado (sin iconos de lugares ni nombres, para conducir) y no aplica las
capas del iPhone. Comparte estilo, ruta, destino, voz y límite de velocidad.

## Probar en el iPhone

1. Instala el IPA nuevo con Sideloadly.
2. Acerca el mapa en una zona con comercios: los nombres aparecen bajo los iconos, cortos y sin solaparse.
3. Toca un icono o su nombre: se selecciona (flechas) y la ficha muestra el nombre completo.
4. Botón de capas: apaga «Restaurantes y cafeterías», enciende «Vías ciclistas» y «Paradas de autobús»; cámbialos
   rápido varias veces. El mapa no debe recargarse ni moverse.
5. Cambia de estilo con capas activadas: deben seguir igual.
6. Con una ruta y una búsqueda activas, apaga categorías: la ruta, el destino y los resultados siguen.
7. Cierra la app del todo y ábrela: las capas siguen como las dejaste.
