# Plan de pruebas

## Simulador (Xcode)

### Pantalla completa
Probar en **iPhone SE (3ª gen)**, **iPhone 15** y **iPhone 15 Pro Max**:
- El mapa llega a los cuatro bordes, sin bandas negras ni franjas de color.
- La barra de búsqueda no queda bajo la Dynamic Island ni el notch.
- La tarjeta de ruta y los controles no quedan bajo el indicador de inicio.
- Rotar el dispositivo: la app permanece en vertical (es intencional).
- `Settings > Accessibility > Larger Text` al máximo: ningún texto se recorta.
- Alternar Light/Dark (⌘⇧A en el simulador) en los 6 temas.

### GPS
`Features > Location`:
- **Apple** → posición fija: comprueba el marcador y el indicador de señal.
- **City Run** / **Freeway Drive** → movimiento: el marcador avanza suave, la flecha gira con el rumbo, la velocidad sube.
- **None** → a los 8 s debe aparecer "Señal GPS perdida" conservando la última posición.

### Permisos
- Primera ejecución: el onboarding pide ubicación en el paso 2.
- Denegar: debe aparecer el aviso con botón "Abrir Ajustes".
- `Settings > Privacy > Location Services > Off`: aviso de servicios desactivados.
- Reinstalar (borrar app del simulador) para repetir el flujo.

### Rutas y búsqueda
- Buscar "gasolinera", "Madrid", una dirección concreta y algo inexistente ("xyzxyz"): resultados, vacío y error.
- Modo avión: la búsqueda debe mostrar "Sin conexión" y la ruta un mensaje claro con botón Reintentar.
- Mantener pulsado el mapa: fija destino y calcula rutas.
- Cambiar entre Coche y A pie: recalcula.
- Iniciar navegación y usar Freeway Drive: comprobar que los anuncios de voz salen a ~500 m, ~150 m y en el giro.
- Desviarse (cambiar de ruta en el simulador): a los ~3 fixes fuera de ruta debe recalcular.

### Temas
Recorrer los 6 en Ajustes y verificar en navegación activa:
- La ruta se distingue del fondo en todos.
- El overlay no tapa la tarjeta de maniobra.
- Con *Reducir transparencia* activado, los overlays desaparecen.

### VoiceOver
Activar VoiceOver (⌘⌥⇧V en el simulador con Accessibility Inspector):
- La tarjeta de maniobra se lee como una unidad.
- Los botones de control anuncian su acción ("Silenciar voz", "Recentrar en mi ubicación").
- El indicador GPS anuncia la calidad.

## iPhone real

Imprescindible para lo que el simulador no cubre:

1. **GPS real**: pasear o conducir y comprobar que el marcador no vibra ni salta.
2. **Pantalla bloqueada**: iniciar navegación, bloquear, seguir conduciendo. La voz debe continuar y aparecer el indicador azul de ubicación en segundo plano.
3. **Batería**: navegación de 30-60 min; comparar consumo con el mapa abierto sin navegar (debe ser notablemente menor sin navegar).
4. **Sol directo**: probar el tema Minimalista Pro y Ciudad Criminal Nocturna al mediodía; confirmar que la ruta se ve.
5. **Audio**: con música sonando, la voz debe bajar el volumen de la música (ducking) y no cortarla.
6. **Llamada entrante** durante la navegación: al colgar, la voz debe reanudarse.
7. **Túnel o aparcamiento subterráneo**: debe aparecer el aviso de señal perdida sin que la app se bloquee.

## Automatizadas (GitHub Actions)

`ios-build.yml` ejecuta en cada push:
- Compilación completa.
- `NavigationEngineTests`: progreso, llegada, desvío, paso actual.
- `FogGridTests`: celdas y revelado a lo largo de una polilínea.
- `GamificationTests`: estadísticas, logros, niveles, integridad de los 6 temas.
- `ManeuverFormatterTests`: redondeo de distancias y símbolos de maniobra.
