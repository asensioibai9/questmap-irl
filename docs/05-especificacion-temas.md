# Especificación de los 6 temas visuales

Todos los temas son creaciones propias. No usan nombres, marcas, logotipos, paletas exactas, tipografías, iconos ni assets de ningún juego comercial. Las referencias son estéticas amplias (noir urbano, isla tropical, voxel, cartografía fantástica, synthwave, minimalismo), no obras concretas.

## Límite técnico que condiciona todo

**MapKit no permite recolorear el mapa base.** No existe API pública para cambiar el color de calles, agua o edificios. Por eso cada tema actúa sobre cuatro capas que sí controlamos:

1. **Estilo base de MapKit**: `.standard` (normal), `.standard(emphasis: .muted)` (calles atenuadas) o `.hybrid` (satélite). Los POI del sistema se ocultan (`pointsOfInterest: .excludingAll`) para que no compitan con nuestra iconografía.
2. **Ruta**: tres polilíneas superpuestas (resplandor, borde oscuro, núcleo) y, opcionalmente, una cuarta discontinua animada.
3. **HUD**: paneles, tipografía, iconos, marcadores.
4. **Overlay decorativo**: viñeta, rejilla synthwave, grano de pergamino o cuadrícula de bloques, dibujado con `Canvas` sobre el mapa y bajo el HUD.

Los colores de carreteras, agua, vegetación y edificios de cada tema se guardan en el modelo (`road`, `water`, `vegetation`, `building`): se usan hoy en la miniatura del selector de temas y en los marcadores, y quedan listos por si en el futuro se añade un mapa base vectorial propio.

## Tipografías

Todos los temas usan **la fuente del sistema (SF Pro)** con un `Font.Design` distinto. Es gratuita, con licencia para apps de Apple, soporta Dynamic Type y no añade peso al binario:

| Tema | `Font.Design` | Efecto |
|---|---|---|
| Ciudad Criminal Nocturna | `.default` | Neutra, alta legibilidad |
| Isla Battle Royale | `.rounded` | Amable, redondeada |
| Mundo de Bloques | `.monospaced` | Rejilla fija, aire pixel |
| Mapa de Fantasía | `.serif` | Manuscrito, cartográfico |
| Retro Arcade | `.monospaced` | Terminal / arcade |
| Minimalista Pro | `.default` | Neutra |

Alternativas libres con licencia comercial si más adelante se quieren fuentes propias: **Inter** y **Space Grotesk** (SIL OFL), **JetBrains Mono** (OFL), **IBM Plex Serif** (OFL), **Press Start 2P** (OFL, solo para títulos cortos: ilegible en texto corrido).

---

## A. Ciudad Criminal Nocturna

Noche urbana, asfalto, neón y alto contraste.

| Elemento | HEX |
|---|---|
| Fondo / viñeta | `#0B0D10` |
| Panel HUD | `#15181E` (94 %) |
| Borde de panel | `#F2C94C` (55 %) |
| Acento | `#F2C94C` |
| Texto principal | `#F5F5F0` |
| Texto secundario | `#A3A8B3` |
| Ruta (núcleo) | `#C8F542` |
| Ruta (borde) | `#0B0D10` |
| Ruta (resplandor) | `#C8F542` (35 %) |
| Origen | `#4CC9F0` |
| Destino | `#F2C94C` |
| Carretera | `#2A2E36` |
| Agua | `#0E1A26` |
| Vegetación | `#16221A` |
| Edificios | `#1C2027` |

- **Mapa base**: `.standard(emphasis: .muted)`, POI ocultos. Modo oscuro por defecto.
- **Ruta**: 7 pt núcleo verde lima, borde negro de 11 pt, resplandor de 20 pt. Sin animación: en conducción nocturna el parpadeo cansa.
- **Iconos**: SF Symbols `.fill` con peso `bold` (gasolinera, cubiertos, P, cruz, escudo, bolsa, estrella, bandera).
- **Overlay**: viñeta radial al 55 %.
- **Legibilidad**: el verde lima sobre negro supera 7:1 de contraste. El borde negro de la ruta garantiza separación del asfalto gris.

## B. Isla Battle Royale

Color saturado, luz de día, lectura rápida desde arriba.

| Elemento | HEX |
|---|---|
| Fondo | `#E8F6FF` |
| Panel HUD | `#FFFFFF` (94 %) |
| Borde de panel | `#00C2FF` (60 %) |
| Acento | `#FF2E93` |
| Texto principal | `#14213D` |
| Texto secundario | `#4F5D75` |
| Ruta (núcleo) | `#00C2FF` |
| Ruta (borde) | `#FFFFFF` |
| Origen | `#3DDC97` |
| Destino | `#FF2E93` |
| Carretera | `#F4E9CD` |
| Agua | `#3FB8F0` |
| Vegetación | `#7ED957` |
| Edificios | `#FFB84C` |

- **Mapa base**: `.hybrid` (satélite con etiquetas): aporta el verde y el azul reales de la isla sin inventar datos.
- **Ruta**: 8 pt cian con borde blanco de 12 pt y **animación de recorrido** (trazo discontinuo que avanza).
- **Iconos**: SF Symbols `.circle.fill`, peso `heavy`, esquinas 20 pt.
- **Overlay**: ninguno; el satélite ya aporta textura.
- **Legibilidad**: cian sobre satélite + borde blanco. El magenta se reserva al destino para que destaque siempre.

## C. Mundo de Bloques

Voxel, bloques y madera.

| Elemento | HEX |
|---|---|
| Fondo (cielo) | `#87CEEB` |
| Panel HUD | `#3B2A1E` (94 %) |
| Borde de panel | `#8B5A2B` |
| Acento | `#F5D547` |
| Texto principal | `#FFF6DC` |
| Texto secundario | `#D2B48C` |
| Ruta (núcleo) | `#F5D547` |
| Ruta (borde) | `#3B2A1E` |
| Origen | `#5CB85C` |
| Destino | `#E74C3C` |
| Carretera | `#8C8C8C` |
| Agua | `#3F76E4` |
| Vegetación | `#5CB85C` |
| Edificios | `#B8860B` |

- **Mapa base**: `.standard`, POI ocultos.
- **Ruta**: 9 pt dorado con borde marrón oscuro de 13 pt (lectura de "camino de bloques").
- **Iconos**: SF Symbols cuadrados (`square.fill`, `cube.fill`, `shippingbox.fill`), peso `black`, **radio de esquina 4 pt** en todos los paneles para la sensación de pixel.
- **Overlay**: cuadrícula de 28 pt al 18 %.
- **Legibilidad**: el dorado sobre gris claro necesita el borde oscuro; sin él bajaría de 3:1.

## D. Mapa de Fantasía

Pergamino, tinta sepia y oro.

| Elemento | HEX |
|---|---|
| Fondo (pergamino) | `#EBDCB5` |
| Panel HUD | `#F6EBD0` (96 %) |
| Borde de panel | `#7A4A1F` |
| Acento | `#7A4A1F` |
| Texto principal | `#3B2412` |
| Texto secundario | `#6E5438` |
| Ruta (núcleo) | `#D4A017` |
| Ruta (borde) | `#3B2412` |
| Origen | `#4A6B3A` |
| Destino | `#9B1C1C` |
| Camino | `#C9A66B` |
| Agua | `#6A93B8` |
| Bosque | `#6B8E4E` |
| Ruinas / edificios | `#A0714F` |

- **Mapa base**: `.standard(emphasis: .muted)`: las calles atenuadas se parecen a trazos de tinta.
- **Ruta**: 5 pt dorada con borde sepia de 8 pt y resplandor sutil. Fina a propósito: evoca el trazo de pluma.
- **Iconos**: `scroll.fill` (misión), `tent.fill` (posada), `sparkles` (tesoro), `flame.fill`, `cup.and.saucer.fill`. Peso `semibold`, tipografía serif.
- **Overlay**: tinte pergamino en `multiply` al 40 % más viñeta sepia.
- **Legibilidad**: tema claro, pensado para uso diurno y a pie. El rojo del destino (`#9B1C1C`) contrasta 6:1 sobre el pergamino.

## E. Retro Arcade

Synthwave, rejilla y neón.

| Elemento | HEX |
|---|---|
| Fondo | `#12022B` |
| Panel HUD | `#1F0A47` (94 %) |
| Borde de panel | `#FF3CAC` (70 %) |
| Acento | `#FFE14D` |
| Texto principal | `#FFF7D6` |
| Texto secundario | `#7DF9FF` |
| Ruta (núcleo) | `#FF3CAC` |
| Ruta (borde) | `#12022B` |
| Ruta (resplandor) | `#7DF9FF` (40 %) |
| Origen | `#7DF9FF` |
| Destino | `#FFE14D` |
| Carretera | `#2E1A5E` |
| Agua | `#0B2A4A` |
| Edificios | `#3A1E6E` |

- **Mapa base**: `.standard(emphasis: .muted)`, modo oscuro.
- **Ruta**: 7 pt magenta, borde oscuro de 11 pt, resplandor cian de 22 pt y **animación** de trazo.
- **Overlay**: rejilla en perspectiva dibujada con `Canvas` (líneas que convergen en un punto de fuga) al 35 %, en `plusLighter`.
- **Legibilidad**: la rejilla se dibuja solo en la mitad inferior y nunca bajo los paneles. El amarillo del HUD mantiene 9:1 sobre el morado.

## F. Minimalista Pro

Para conducir de verdad.

| Elemento | HEX |
|---|---|
| Fondo | `#FFFFFF` |
| Panel HUD | `#FFFFFF` (96 %) |
| Borde de panel | `#000000` (12 %) |
| Acento / ruta | `#0A84FF` |
| Texto principal | `#111111` |
| Texto secundario | `#5C5C5C` |
| Origen | `#34C759` |
| Destino | `#FF3B30` |
| Carretera | `#E5E5EA` |
| Agua | `#BFD9F2` |
| Vegetación | `#D5E8D0` |
| Edificios | `#F2F2F7` |

- **Mapa base**: `.standard` con POI ocultos.
- **Ruta**: azul de 7 pt con borde blanco de 11 pt. Sin animación ni efectos.
- **Overlay**: ninguno.
- **Legibilidad**: es el tema recomendado con sol directo. Sigue el modo claro/oscuro del sistema si el usuario lo fuerza en Ajustes.

---

## Reglas comunes de legibilidad al conducir

1. **La ruta siempre lleva borde de contraste** (oscuro en temas claros, claro en temas oscuros). Sin él, cualquier color se pierde sobre el asfalto.
2. **Los POI del sistema se ocultan** en todos los temas: menos ruido y menos texto pequeño.
3. **La tarjeta de maniobra no cambia de tamaño entre temas**: distancia a 34 pt heavy e instrucción a 20 pt, con `minimumScaleFactor` para que nunca se recorte.
4. **Los overlays nunca se dibujan sobre el HUD**: van entre el mapa y los paneles, y se desactivan solos si el usuario activa *Reducir transparencia* en Accesibilidad.
5. **Ningún tema altera datos**: trazado, maniobras, distancias y ETA salen siempre de Apple Maps.
6. **Contraste mínimo 4,5:1** en todo texto del HUD; los pares de colores que deben distinguirse (origen / destino) difieren además en luminosidad, no solo en tono.
