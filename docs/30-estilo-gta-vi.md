# 30 · Estilo «GTA VI» (id interno `costaTropical`)

Estilo independiente. **No sustituye ni modifica «GTA V»** (`ciudadNocturna`): su JSON, sus iconos y su flecha siguen
idénticos (lo comprueban los tests). El nombre visible se cambia en `MapStyleNames`; el identificador guardado en las
preferencias es `costaTropical` y no depende del nombre.

La app no es oficial ni está afiliada a Rockstar Games. No usa logotipos, texturas, tipografías ni iconos del juego. La
geografía es la real de OpenStreetMap (OpenMapTiles vía OpenFreeMap); no se añade ni se desplaza nada.

## Referencias usadas

| Referencia | Origen | Qué muestra | Uso |
|---|---|---|---|
| Fotograma de «Una mirada extendida» (Rockstar, 27-08-2026), copia acreditada a Rockstar en allthings.how | Oficial (vía tercero) | Minimapa conduciendo: rectángulo redondeado claro, ruta rosa que se desvanece, flecha blanca en círculo negro, «N» en el borde, sin etiquetas | Ruta, flecha, forma del minimapa |
| Captura 1: ciudad (pausa, clara) | Aportada por el usuario. **Origen no verificado** | Suelo urbano, edificios, agua, autopistas, iconos, etiquetas de zonas | Paleta urbana, agua, iconos, etiquetas |
| Captura 2: campo (pausa, clara) | Aportada por el usuario. **Origen no verificado** | Vegetación, zonas urbanas grises, agua, carreteras, nombres de región, pin turquesa, flecha | Verdes, carreteras rurales, destino |
| Capturas 3 y 4: costa y base aérea (pausa, oscuras) | Aportadas por el usuario. **Origen no verificado** | Mismo lenguaje con un régimen oscuro completo: agua violeta, tierra verde oscuro, ciudad azul marino | Analizadas; **no aplicadas** (ver abajo) |

Descartado: ilustración con minimapa circular de neón (gtanerd: no es del juego), mods de aficionados (FiveM / GTA V),
el mapa filtrado retirado por DMCA y los iconos de gtabase.com (no se copian recursos del juego ni de terceros).

## Lo que NO se reproduce (indicado por el usuario)

Zonas negras sin descubrir, sus bordes difuminados, niebla de guerra, cursor circular central, contorno blanco de área
seleccionada, nombres ficticios y artefactos de compresión. Todo el mapa real es visible con el tratamiento de las zonas
descubiertas (test `testWholeMapIsVisibleWithoutFogOrDarkMasks`).

## Ficha visual (mapa completo y minimapa claros)

HEX **aproximados**: medidos por cuantización de color y parches ampliados en capturas comprimidas, descartando lo
negro. No son valores oficiales. Comparación píxel a píxel no realizada.

| Elemento | Referencia | Implementación |
|---|---|---|
| Suelo urbano | Gris frío claro (≈ #afb4be–#c4c8ce) | Fondo `#b6bcc5`; residencial `#bbc0c9`, comercial `#c2c6ce`, industrial `#b2b8c2` |
| Edificios | Azul pizarra plano (≈ #879ab3) | `#93a5c3`, borde `#7d91b3` desde z15,5 |
| Agua | Turquesa (≈ #42a0bd–#50aac7) | `#43aed0` en mar, ríos y lagos (mismo color en ambas capturas claras) |
| Costa | Borde claro fino | Línea `#b7e6f2` |
| Vegetación | Verde agua desaturado (≈ #5b947c–#7aa894) | Hierba y humedal `#78a892`, bosque `#5f957f`, campo `#86ae9b` |
| Calles | Casi blancas, sin borde marcado | `#e3e6ea`–`#eef0f2`; contorno apenas más oscuro que el suelo |
| Autopistas | Crema, finas, calzadas paralelas | `#e6e2c6` (troncales `#e9e6d1`); más finas que en GTA V |
| Ferrocarril | No distinguible | Línea discontinua gris `#8b93a4` (adaptación) |
| Zonas / ciudades | Blanco en negrita con contorno oscuro | Ciudades `#ffffff` con halo `#373c4b`; barrios `#eef0f4` en negrita con halo fino |
| Calles (nombres) | No se ven en la pausa | Texto `#4e5566` con halo claro (adaptación, para navegar) |
| Iconos | Burbuja melocotón con glifo negro y punta | Familia propia `gta6-poi-*` (mismos glifos propios que GTA V, nuevo soporte) |
| Casa / Trabajo | No hay equivalente | Burbuja azul grisácea (adaptación) |
| Destino | Pin turquesa en las capturas (función no acreditada) | Pin turquesa propio `gta6-poi-destination` |
| Selección | No se ve | Mismas mini flechas de selección que el resto |
| Ruta | Rosa en el minimapa oficial | `#f0559e` con contorno blanco (el contorno es adaptación) |
| Usuario | Flecha blanca en círculo negro | Avatar «Flecha clásica» dibujado dentro de un disco `#16181d`; los demás avatares no cambian |
| Minimapa | Rectángulo redondeado claro | `roundedRectangle`: apaisado 3:2, radio 18, borde claro de 2 pt |

### Iconos ampliados (categorías de la referencia con equivalente real)

Se han tomado como guía las **categorías** que lista el mapa interactivo de gtabase.com (solo los nombres de categoría:
no se ha descargado ni copiado ningún icono, ni del juego ni de esa web). Cada una se ha cruzado con las clases y
subclases reales de OpenMapTiles, comprobadas en teselas de Madrid, Barcelona y Valencia. Los 40 glifos nuevos son
dibujos propios (`tools/make_poi_icons.py`, `VI_EXTRA`) sobre la misma burbuja.

| Categoría de la referencia | Dato real (clase / subclase) | Icono |
|---|---|---|
| Comida rápida | `fast_food` | hamburguesa |
| Cafés | `cafe` | taza (ya existía) |
| Comida callejera | `ice_cream`, `bakery` | helado, pan |
| Bares | `bar` / `beer`, `pub` | copa (ya existía) / jarra |
| Discoteca | subclase `nightclub` | auriculares |
| Licorerías | `alcohol_shop` | botella |
| Tiendas de conveniencia | `convenience`, `kiosk` / `supermarket`, `grocery` | cesta / carro |
| Ropa · Calzado | `clothing_store` / `shoes` | camiseta / zapatilla |
| Peluquería y belleza | `hairdresser`, `beauty`, `cosmetics`, `perfumery` | tijeras |
| Tatuajes | subclase `tattoo` | máquina de tatuar |
| Electrónica | `mobile_phone`, `electronics`, `computer` | móvil |
| Gasolineras | `fuel` / `charging_station` | surtidor (ya existía) / rayo |
| Talleres · Lavaderos · Concesionario | `car_repair` / `car_wash` / `car` | llave inglesa / coche con gotas / coche |
| Transporte público | `railway`, `bus`, `ferry_terminal` | tren, parada (ya existían), barco |
| Puertos deportivos | `harbor`, `marina` | ancla |
| Cine · Teatro | `cinema` / `theatre` | claqueta / máscara |
| Parques de bomberos | `fire_station` | llama |
| Hospitales | `hospital` / `pharmacy` / `dentist` / `veterinary` | cruz (ya existía) / cápsula / muela / huella |
| Comisarías | `police` | escudo (ya existía) |
| Lugares emblemáticos | `attraction` / `monument` / `castle` / `museum` | estrella / obelisco / castillo / columnas |
| Gimnasio · Golf | `sports_centre` / `golf` | mancuerna / bandera |
| Bancos | `bank` / `atm` | moneda / billete |
| Otros comercios reales | `gift`, `florist`, `jewelry`, `optician`, `books`, `music`, `art_gallery`, `post` | regalo, flor, diamante, gafas, libro, nota, paleta, sobre |

Sin icono porque no existen fuera del juego: atracos, préstamos rápidos, peristas, coleccionables, saltos, complejos de
banda, eventos aleatorios, armerías, Pay 'n' Spray, armas para recoger y apariciones de vehículos. «Pisos francos» ya
corresponde a Casa y Trabajo.

Los números de portal (z18) se dibujan **por debajo** de los iconos en este estilo: si van encima, MapLibre los coloca
primero y esconden casi todos los lugares. (Los demás estilos tienen ese mismo orden antiguo; no se han tocado.)

### Densidad por zoom

- z ≤ 12: tierra, agua, vegetación, autopistas y principales; nombres de ciudades.
- z 13–15: toda la red, barrios, edificios desde z14–15.
- z ≥ 15: iconos escalonados como en GTA V (transporte, gasolineras y salud antes; comida y comercio a z17) y nombres
  cortos debajo (≤ 22 caracteres con «…», nombre completo en la ficha, respetan «Mostrar nombres de los lugares»).

### Régimen oscuro (capturas 3 y 4): no aplicado

Las capturas oscuras no son «otra agua»: oscurecen todo a la vez (agua violeta ≈ #36386a–#4c508c, tierra verde oscuro
≈ #205357, ciudad azul marino ≈ #101434). Mezclar su violeta con el turquesa crearía una profundidad marina inventada,
sin datos que la respalden. Puede añadirse como variante nocturna aparte si se quiere.

## 2D, 3D y CarPlay

- 2D por defecto. El 3D (capa `building-3d`) es una **adaptación propia**: las referencias son planas. Usa alturas reales
  de OpenMapTiles, tonos del mismo azul pizarra y queda por debajo de ruta, iconos, selección, destino y usuario.
- CarPlay usa el modo simplificado existente (sin iconos de lugares, números de portal ni resultados): prioriza ruta y
  maniobras.

## Integración

- Cambiar de estilo conserva Casa, Trabajo, favoritos, ruta, GPS, música, voz, capas del usuario, nombres de lugares,
  señal de velocidad y 2D/3D: el cambio solo recarga el JSON y `MapController.styleDidLoad` vuelve a aplicar todo.
- La preview del selector la genera la app con el propio estilo (misma zona y encuadre que el resto) y se guarda en
  caché por huella del JSON: se regenera sola si el estilo cambia.

## Archivos

- `tools/build_styles.py`: configuración `COSTA`; halos y fuente de nombres de lugar configurables (los demás estilos
  generan exactamente el mismo JSON).
- `tools/make_poi_icons.py --vi`: familia `gta6-poi-*` y hoja `docs/branding/poi-icons-gta6-contact-sheet.png`.
- `QuestMapIRL/Resources/style-costa-tropical.json` y `Assets.xcassets/gta6-poi-*.imageset`.
- `MapTheme.swift` (`costaTropical`, `roundedRectangle`, `gameBubbles`, `userArrowBadgeHex`), `ThemeCatalog.swift`,
  `MapStyleNames.swift`, `GameIcons.swift`, `MapAvatar.swift`, `UserArrowImage.swift`, `MapController.swift`,
  `QuestMapView.swift`, `StylePreviewRenderer.swift`, `MinimapView.swift`, `tools/preview/index.html`.
- Tests: `GTA6StyleTests.swift` (nuevo), `StylePreviewTests.swift` (nombre y número de estilos).

## Diferencias pendientes

- Las capturas no muestran ruta, selección, nombres de calles ni Casa/Trabajo en el mapa de pausa: son adaptaciones.
- Tipografía: el juego usa una fuente estrecha para regiones; aquí solo están disponibles Noto Sans Regular, Bold e
  Italic del proveedor de teselas.
- Iconos de marca (los azules de las capturas) no se reproducen: no hay datos de marca fiables y serían logotipos.
- Variante nocturna (capturas oscuras) sin implementar.
