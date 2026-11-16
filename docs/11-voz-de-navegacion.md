# Voz de navegación

## Cómo funciona (implementado)
- `Services/Speech/NavigationVoice.swift` genera la voz con `AVSpeechSynthesizer` (voces nativas de iOS). Sin servicios externos, claves ni pagos.
- Selector **Chica / Chico** en Perfil › Ajustes de navegación › «Voz de navegación». Se guarda en `UserDefaults` (`questmap.navigationVoiceGender`) y se aplica a la **siguiente** indicación, porque la voz y el tono se leen al crear cada frase.
- Selección de voz (`VoiceSelector`): 1) es-ES del género pedido, 2) otra variante del español del género pedido, 3) la mejor voz es-ES disponible, 4) la mejor voz española, 5) la predeterminada del sistema. En 2-5 la interfaz muestra un aviso. Dentro de cada grupo se prefiere la calidad premium > mejorada > estándar.
- Velocidad 0,48. **Tono natural (1,0) para las dos voces**: ya no se simula chica o chico cambiando el tono (empeoraba la naturalidad). El género lo da la voz elegida.
- **Elegir voz:** Perfil › Ajustes de navegación › «Elegir voz» lista las voces españolas realmente instaladas con su calidad (Estándar, Mejorada, Premium), permite escucharlas y elegir una por género. Se muestran el nombre, el idioma y la calidad reales de la voz que se usa. Las voces del género contrario nunca se ofrecen como válidas; las de género no indicado por iOS aparecen aparte. La lista se actualiza al volver a la app y cuando iOS avisa de cambios de voces. No se listan voces que iOS no expone a las apps (p. ej., normalmente las de Siri) ni voces de efecto.
- Sesión de audio: categoría `.playback`, modo `.spokenAudio`, opción `.duckOthers`; se libera con `.notifyOthersOnDeactivation` al terminar de hablar para que la música recupere el volumen.
- Una indicación nueva cancela la anterior; la misma frase no se repite dos veces seguidas (se reinicia al terminar la navegación). La primera indicación de la ruta se encola tras «Empezamos la ruta…».
- «Escuchar prueba de voz» suena siempre, aunque las indicaciones estén desactivadas. Mientras suena muestra «Reproduciendo… (toca para parar)»; al salir de la pantalla de ajustes la prueba se corta.

## Robustez
- **Parada inmediata:** `stopImmediately()` corta la voz, descarta las frases pendientes, olvida la última frase y libera la sesión de audio. Se usa al cancelar la ruta, al cambiar de destino, al silenciar y al pasar la app a segundo plano **si no se está navegando** (navegando, la voz sigue con la pantalla bloqueada).
- **Llegada:** «Has llegado a tu destino» no se corta al terminar la navegación (`releaseAfterSpeaking()`); la sesión de audio se libera cuando termina la frase.
- **Cancelaciones tardías:** iOS avisa con retraso de que una frase cancelada terminó. Las frases se siguen por identidad, así que ese aviso tardío no libera la sesión mientras suena la frase nueva.
- **Fallos del sintetizador:** `AVSpeechSynthesizer` no informa de errores. Un vigilante da la frase por perdida si no avisa de que terminó y deja de hablar (mínimo 8 s o ~0,25 s por carácter + 4 s), para no quedar en «Reproduciendo…» ni con el audio activo para siempre. Si no se puede activar la sesión de audio se muestra un aviso y se intenta hablar igualmente.
- **Sin voces españolas instaladas:** no falla; se usa la voz predeterminada del sistema y se avisa en la interfaz (puede leer mal el español).
- **Inicio doble:** si la navegación se inicia dos veces, «Empezamos la ruta…» suena una vez.

## Prueba manual en iPhone
Todo esto sigue **sin probarse en un dispositivo real**; no hay ningún resultado físico registrado. Hazlo con la app instalada, volumen del iPhone medio y los auriculares desconectados (salvo el último punto).

1. **Voz de chica y de chico:** Perfil › Ajustes de navegación › Voz de navegación. Elige «Chica» y pulsa «Escuchar prueba de voz»; luego «Chico» y repite. Comprueba que se oye la frase «Prueba de voz. En doscientos metros, gira a la derecha.», que el tono de chico es algo más grave y que debajo aparece «Voz actual: española — chica/chico (nombre)». Si falta una voz, debe aparecer el aviso naranja y la pista de descarga.
2. **Botón de prueba:** mientras suena debe poner «Reproduciendo… (toca para parar)»; tócalo y debe callarse; al terminar solo, vuelve a «Escuchar prueba de voz». Sal de la pantalla a mitad de frase: debe cortarse.
3. **Indicaciones desactivadas:** apaga «Indicaciones de voz» y pulsa el botón de prueba: debe sonar igualmente. Reactívalas después.
4. **Silencio físico:** activa el interruptor lateral de silencio y pulsa la prueba: debe oírse (categoría `.playback`).
5. **Música sonando:** reproduce música (Música, Spotify…), pulsa la prueba: la música debe bajar de volumen mientras habla y recuperarlo al terminar (`.duckOthers`).
6. **Navegación real:** inicia una ruta corta. Deben oírse, por orden y sin cortarse, «Empezamos la ruta hacia…» y la primera indicación («En … metros, …»). Camina o conduce hasta la primera maniobra y comprueba que se anuncia al acercarse y que cada indicación nueva corta la anterior.
7. **Pantalla bloqueada:** con la ruta en marcha, bloquea el iPhone. Las indicaciones deben seguir oyéndose.
8. **Cambio de voz durante una ruta:** con la ruta activa, pasa a segundo plano, cambia entre Chica y Chico en Perfil › Ajustes de navegación y vuelve; la **siguiente** indicación debe usar la otra voz.
9. **Cancelar y llegada:** cancela la ruta a mitad de una frase: debe cortarse al instante. Termina otra ruta: «Has llegado a tu destino.» debe oírse completa.
10. **Fuera de navegación:** pulsa la prueba y vuelve a la pantalla de inicio: debe callarse.

### La calidad depende de las voces instaladas
La app solo usa las voces que tiene el iPhone. Las voces estándar suenan más robóticas. Para mejorarlas: Ajustes › Accesibilidad › Contenido hablado › Voces › Español, elige la variante «España» y descarga una voz **Mejorada** o **Premium** (tocando el icono de descarga). Descarga una de chica y otra de chico si quieres poder elegir; después reabre Ajustes de navegación para comprobar que el estado muestra la voz nueva. Algunas voces pueden tardar un momento en aparecer tras descargarse.

## Qué se valida automáticamente y qué no
- **En CI (simulador):** compilación, tests unitarios con sintetizador y sesión de audio falsos (preferencia guardada y persistente, elección chico/chica, frase de prueba, velocidad y tono, parada inmediata, cancelación, no repetición, avisos de voz, estado «Reproduciendo», vigilante, inicio doble y orden de las primeras frases de la navegación) y la petición exacta de `.playback` / `.spokenAudio` / `.duckOthers` a `AVAudioSession` mediante un doble de prueba. Un test adicional usa la sesión real del simulador y puede saltarse si el entorno no la admite; el resumen de CI lo indica.
- **Solo en un iPhone real:** que suene, volúmenes, silencio físico, música, pantalla bloqueada, calidad de voces y comportamiento ante interrupciones (llamadas, Siri).

## Límites de las voces nativas
- Las voces disponibles dependen de las instaladas en el iPhone; el usuario puede descargar más en Ajustes › Accesibilidad › Contenido hablado › Voces › Español. La app no puede descargarlas ni garantizar que exista una de chica y otra de chico.
- Las voces estándar suenan más robóticas que las mejoradas/premium, que ocupan decenas de MB y las instala el usuario.
- El género lo declara el sistema o, si no, se deduce del nombre de la voz (lista corta); puede fallar con voces nuevas.
- Las frases las genera `InstructionBuilder` en español; no hay otro idioma de voz.

## Voz neuronal gratuita: recomendación (NO integrada)
Opción más realista: **sherpa-onnx** (Apache-2.0) con voces **Piper** en español de España, ejecutadas en el dispositivo.
- Hay un paquete Swift Package Manager de terceros ([sherpa-onnx-spm](https://swiftpackageregistry.com/willwade/sherpa-onnx-spm)) que empaqueta los XCFrameworks para iOS.
- Voces es_ES en el repositorio [rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices/tree/v1.0.0/es/es_ES): carlfm, davefx, mls_10246, mls_9972 y sharvard.
- Peso: una voz es_ES «low» ronda los 63 MB según un espejo del repositorio ([mls_10246](https://huggingface.co/wide-video/piper-voices-v1.0.1/tree/main/es/es_ES/mls_10246/low)); cuantizar a FP16 podría reducirlo a la mitad, pero es un experimento de un tercero ([discusión](https://github.com/IhorShevchuk/piper-ios-app/issues/1)).
- Licencias: el repositorio está etiquetado MIT, pero **cada voz hereda la licencia de sus datos**. La ficha de sharvard indica [CC BY 3.0](https://huggingface.co/rhasspy/piper-voices/blob/0c9c5d340496a47205a799eb046aab69334a88e9/es/es_ES/sharvard/medium/MODEL_CARD) (exige atribución); para davefx no se confirmó la licencia de los datos. Hay que revisar la ficha de la voz elegida antes de publicar.

Por qué no se integra ahora: requiere descargar o empaquetar un modelo de decenas de MB, una dependencia binaria de terceros sin verificar en este entorno y una revisión de licencias por voz. Si más adelante se quiere, el punto de enganche es `SpeechSynthesizing` (protocolo que ya usa `NavigationVoice`): una implementación con sherpa-onnx que genere audio y lo reproduzca con `AVAudioPlayer` puede sustituir al sintetizador nativo sin tocar el resto.

## Validado y pendiente
- Validado en CI: compilación, tests unitarios (preferencia guardada, elección chico/chica, frase de prueba, velocidad, tono, constantes de la sesión de audio, cancelación y no repetición, selección y avisos de voz) e IPA.
- **Requiere prueba manual en iPhone:** que suene realmente, el volumen frente a la música (ducking), el sonido con el interruptor de silencio, la calidad de las voces instaladas y el comportamiento con la pantalla bloqueada.
