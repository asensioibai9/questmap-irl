# 22 · Previews reales, nombres de juegos y mejoras cartográficas

## Estilos realmente disponibles (9) y nombres

| Identificador interno (sin cambios) | Antes | Ahora |
|---|---|---|
| `ciudadNocturna` | Ciudad nocturna | **GTA V** |
| `islaRoyale` | Isla | **Fortnite** |
| `mundoBloques` | Mundo de bloques | **Minecraft** |
| `salvajeOeste` | Mapa del salvaje oeste | **Red Dead Redemption 2** |
| `ciudadCiber` | Ciudad ciber | **Cyberpunk 2077** |
| `mapaFantasia` | Mapa de fantasía | **Skyrim** |
| `redUrbana` | Red urbana | **Watch Dogs 2** |
| `rutasRally` | Rutas de rally | **Forza Horizon 5** |
| `minimalistaPro` | Minimalista Pro | Minimalista Pro (estilo propio, sin juego de referencia) |
| `retroArcade` | — | Placeholder sin cartografía: **no aparece en el selector** |

Los nombres están centralizados en `MapStyleNames.swift`. Los identificadores guardados en las preferencias no cambian, así que no hace falta migración (un test lo comprueba). El selector y los ajustes muestran los nombres nuevos; la app sigue llamándose «QuestMap IRL».

**Marca y distribución (a revisar antes de publicar, sin garantía de nada):** los nombres de videojuegos son marcas de terceros. El selector incluye un aviso de que identifican solo la referencia visual y de que la app no es oficial ni está afiliada. Conviene revisar con asesoría legal el uso de esos nombres en la interfaz, en la ficha y en las capturas de la tienda (las normas de propiedad intelectual de App Store pueden rechazar la app o pedir cambios) y valorar una redacción del tipo «estilo inspirado en…». No se usan logotipos ni recursos de los juegos.

## Previews reales

- **Método:** `MLNMapSnapshotter` (MapLibre Native) con el MISMO JSON de estilo que el mapa principal (`StyleManager`). Al cargar el estilo se registran las mismas imágenes que en el mapa principal (iconos, texturas, flecha del usuario) y se rellenan las capas de navegación (ruta, destino, usuario) con una ruta de ejemplo. Resultado: la preview enseña lo que el estilo dibuja de verdad. No hay imágenes estáticas ni capturas de juegos (se eliminaron las miniaturas anteriores).
- **Misma zona, encuadre, tamaño y zoom en todos:** Madrid Río (río Manzanares, autovía M-30 con enlaces y túneles, parque, manzanas de edificios, avenidas), zoom 15,2, vista cenital, 640×400 pt. Zona pública: nunca Casa/Trabajo ni nada del usuario, y nada se sube a ningún servidor (solo se descargan teselas del proveedor del mapa).
- **Solo 2D:** los edificios 3D y el relieve NO se capturan (cenital); no se simulan en la preview.
- **Marca de agua:** el snapshot incluye el logotipo de MapLibre y el crédito de datos; se mantienen (atribución).
- **Caché:** `Caches/QuestMapStylePreviews`, una imagen por estilo. La huella incluye el contenido del estilo, la versión de composición (`StylePreviewSpec.version`), la versión de la app y la escala; si cambia, se regenera solo ese estilo y se borra la versión vieja. Si cambias iconos o texturas sin tocar el JSON, sube `StylePreviewSpec.version`.
- **Carga:** al abrir el selector se leen de caché al instante y se generan las que falten, **una a una** y empezando por el estilo elegido (nunca varios mapas a la vez). Hay estado de carga, y si falla una preview se muestra el error de ESE estilo con «Reintentar», nunca la imagen de otro.
- **Tarjetas:** preview amplia (8:5), nombre, indicador «En uso», toda la tarjeta pulsable. Al elegir, el estilo se aplica y se guarda al instante; el mapa conserva posición, cámara, destino y ruta.

### Verificación realizada
Un test renderiza de verdad los 9 estilos con el motor en el simulador de CI (con red): comprueba tamaño, que no estén en blanco y que ninguna pareja sea la misma imagen. Pasó sin saltarse. Además revisé visualmente las 9 imágenes volcadas desde el simulador: se ven terreno, agua, edificios, vías de varios rangos, etiquetas, iconos, ruta, destino y flecha del usuario.

## Jerarquía vial y rasgos (reales, sin inventar nada)

Comprobado contra el esquema real de OpenFreeMap (`vector_layers`): `transportation` (class, ramp, brunnel, surface, expressway), `transportation_name` (`ref`), `boundary` (`admin_level`, `maritime`), `mountain_peak` (`name`, `ele`).

- **Autopistas y autovías:** contorno más grueso que el resto (`casing_boost`), ramales más finos con su propio contorno, **referencia de la vía** (campo `ref`) sobre autopistas/autovías, y orden de dibujo puentes > superficie > túneles (túneles tenues y discontinuos).
- **Ferrocarril:** vía fina continua + traviesas (marcas cortas repetidas) en todos los estilos.
- **Límites administrativos** (capa `boundary`, sin los marítimos) con trazo propio de cada estilo.
- **Cimas con nombre y altitud** (`mountain_peak`) en Fortnite, Red Dead Redemption 2, Skyrim y Forza Horizon 5. Es información real; no se dibujan montañas.
- **Caminos de tierra** (dato real `surface=unpaved`) discontinuos en Fortnite, Minecraft y Forza Horizon 5.

### Por estilo
- **GTA V**: grises apagados, ruta morada, iconos propios y flechas de selección (intactos); autopistas con más contorno y referencia discreta.
- **Fortnite**: caminos de tierra claros, cimas, costas con borde y límites suaves.
- **Minecraft**: caminos de tierra como bloques de camino, límites en trazo corto. No es voxel: los edificios son prismas.
- **Red Dead Redemption 2**: tinta, límites de «estado» en trazo punto-raya, cimas, ferrocarril marcado.
- **Cyberpunk 2077**: vías de cian con borde brillante jerarquizadas, referencias en amarillo, límites cian tenues.
- **Skyrim**: caminos rojo pardo (punteados los menores), límites punteados, cimas. Interpretación plana: sin relieve real (haría falta elevación).
- **Watch Dogs 2**: vías blancas, autopistas amarillo-naranja con referencia.
- **Forza Horizon 5**: jerarquía por ancho y color, caminos de tierra discontinuos, cimas.

## CarPlay
Los estilos nuevos se ven en CarPlay con la versión simplificada (sin puntos de interés, números de portal ni cimas); las referencias de autopista y los límites se mantienen. Sin probar en CarPlay.

## Pendiente / sin verificar
- Fluidez y consumo del selector en un iPhone real (la generación es secuencial y cacheada).
- Comparación píxel a píxel con las capturas de referencia de los juegos: no realizada.
- Probar cambio de estilo con ruta activa y reinicio de la app en iPhone.
