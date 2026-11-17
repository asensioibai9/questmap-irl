# 24 · Flecha GPS y cámara fluidas

## Causa de los tirones (diagnóstico)

| Parte | Lo que pasaba |
|---|---|
| Lecturas GPS | Correctas: un solo `CLLocationManager` (`LocationService`), ~1 Hz navegando, `distanceFilter` 8 m en reposo. No había que pedir más GPS. |
| Procesado | Filtro exponencial siempre activo con señal media: añadía retraso en marcha sin quitar los saltos visuales. |
| Marcador | Capa de símbolo `user-arrow` sobre la fuente GeoJSON `user`. No se recreaba (bien), pero **el punto se sustituía de golpe** en cada lectura: MapLibre no anima cambios de datos de una fuente, así que la flecha saltaba entre lecturas. |
| Orientación | `icon-rotate` lee el atributo `heading`, que también cambiaba de golpe. **Cambio duro entre brújula y rumbo GPS a 1,5 m/s**, sin histéresis: a esa velocidad alternaba en cada lectura. Brújula sin filtro de calibración. |
| Cámara | `setCenter(…, animated: true)` en **cada** lectura **y en cada evento de brújula** (varios por segundo): cada animación cortaba la anterior (con aceleración y frenada propias) → avanzar-parar constante. La inclinación 3D usaba otra animación (`setCamera` 0,6 s) que competía con la de seguimiento. |
| Hilo principal | Sin bloqueos detectados en el código (no hay trabajo pesado por lectura). Los estilos, rutas y edificios 3D no se recalculan con la posición. |

## Qué se cambió

- `Map/Motion/MarkerMotion.swift` (nuevo, lógica pura): separa **posición confirmada** (última lectura real) y **posición presentada**.
  - Transición **lineal** (velocidad constante, sin easing) desde la posición presentada *actual* hasta la lectura nueva. Si llega otra lectura a mitad, se continúa desde donde está la flecha, no desde el inicio.
  - Duración = cadencia real medida con las **marcas de tiempo** de las lecturas (media móvil), entre 0,12 s y **1 s como máximo**.
  - **Sin extrapolación**: la flecha nunca pasa de la última lectura real; sin señal, se queda quieta en ella.
  - Parado: ignora movimientos menores que el ruido (≥ 2,5 m, según precisión). Un desplazamiento real sí se sigue.
  - Correcciones grandes (> 120 m o más que 4 s de marcha + precisión): se aplican de golpe, sin cruzar la ciudad. Tras ≥ 3 s sin lecturas, la siguiente se alcanza en 0,3 s.
  - Giro: aproximación exponencial por el **camino más corto** (359° → 1° = +2°), rápida en marcha (τ 0,14 s) y más calmada parado (τ 0,3 s, ignorando vibraciones < 4°).
- `Map/Motion/FollowCameraSmoother.swift` (nuevo, lógica pura): cámara que sigue a la flecha **presentada** fotograma a fotograma (centro, zoom, inclinación y rumbo), sin pasarse y por el giro más corto. Retraso en marcha ≈ 1,3 m a 50 km/h.
- `Map/MapController.swift`:
  - Un `CADisplayLink` (sincronizado con la pantalla, 30–60 Hz) **solo mientras hay algo que mover**; se para solo cuando flecha y cámara llegan. Usuario quieto = ningún temporizador activo. Se invalida al quitar el mapa.
  - La fuente `user` y la capa se conservan; solo se cambia el punto/atributo cuando de verdad cambia.
  - Siguiendo, **no se lanzan animaciones de cámara de MapLibre por lectura**: la cámara la mueve solo el bucle. La inclinación 2D/3D también, durante el seguimiento.
  - Recentrar desde lejos (fuera de pantalla o > 2 niveles de zoom): un único vuelo animado y después el seguimiento suave.
  - Un gesto del usuario desactiva el seguimiento al instante (como antes); el botón de recentrar lo reanuda.
- `Services/Location/HeadingSourceSelector.swift` (nuevo): rumbo GPS por encima de 2 m/s, brújula por debajo de 1 m/s, se mantiene la fuente entre ambos. No usa `course` inválido o con precisión > 45°, ni brújula sin calibrar.
- `LocationService`: usa el selector; el filtro exponencial ya no actúa en marcha clara (la suavidad la pone la animación; filtrar también solo añadía retraso).
- `HomeView` y `CarPlayCoordinator` pasan la lectura completa (con su hora, velocidad y precisión).

**Datos de navegación separados:** `NavigationHub` (progreso, llegada, desvíos, recálculo, límite de velocidad) sigue usando `currentLocation`, la lectura real. La posición animada vive solo dentro de `MapController` y no sale de él.

**Reducir movimiento:** flecha y cámara van directamente a cada lectura, sin transiciones.

## Pruebas (CI, simulador; recorridos generados en las pruebas, nada en la app)

`MarkerMotionTests`, `FollowCameraSmootherTests`, `HeadingSourceSelectorTests`: usuario quieto con ruido, conducción recta a 50 km/h (velocidad por fotograma constante, sin paradas), curva de 180°, giro de 90°, cruce 359°→1°, lecturas irregulares, pérdida de señal (no avanza), recuperación tras 10 s, corrección de 2 km, solo cambio de brújula, vuelta de segundo plano, reducir movimiento, cámara (sin pasarse, por el norte, retraso acotado) e histéresis brújula/GPS.

No medido: FPS reales, consumo de batería, comportamiento en iPhone ni en CarPlay.

## Qué comprobar en el iPhone

1. Instala el IPA nuevo con Sideloadly.
2. Quieto en casa: la flecha no debe temblar ni girar sola más allá de lo que gires el móvil.
3. Andando y en coche (de copiloto): avance continuo, sin saltos; en curvas y giros la flecha gira enseguida.
4. Rumbo arriba y norte arriba, en 2D y 3D: la cámara acompaña sin pequeños tirones.
5. Mueve el mapa con el dedo: deja de seguirte y no «tira» de vuelta. Pulsa recentrar: vuelve suave.
6. Túnel o sin señal: la flecha se para en la última posición; al recuperar, va a la nueva sin cruzar el mapa despacio.
7. Sal a otra app y vuelve: sin giros raros.
8. Ajustes del iPhone › Accesibilidad › Movimiento › Reducir movimiento: la flecha salta a cada lectura (es lo esperado).
