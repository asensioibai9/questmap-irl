# Voz de navegación

## Cómo funciona (implementado)
- `Services/Speech/NavigationVoice.swift` genera la voz con `AVSpeechSynthesizer` (voces nativas de iOS). Sin servicios externos, claves ni pagos.
- Selector **Chica / Chico** en Perfil › Ajustes de navegación › «Voz de navegación». Se guarda en `UserDefaults` (`questmap.navigationVoiceGender`) y se aplica a la **siguiente** indicación, porque la voz y el tono se leen al crear cada frase.
- Selección de voz (`VoiceSelector`): 1) es-ES del género pedido, 2) otra variante del español del género pedido, 3) la mejor voz es-ES disponible, 4) la mejor voz española, 5) la predeterminada del sistema. En 2-5 la interfaz muestra un aviso. Dentro de cada grupo se prefiere la calidad premium > mejorada > estándar.
- Velocidad inicial 0,48. Tono: chica 1,08; chico 0,90.
- Sesión de audio: categoría `.playback`, modo `.spokenAudio`, opción `.duckOthers`; se libera con `.notifyOthersOnDeactivation` al terminar de hablar para que la música recupere el volumen.
- Una indicación nueva cancela la anterior; la misma frase no se repite dos veces seguidas (se reinicia al terminar la navegación). La primera indicación de la ruta se encola tras «Empezamos la ruta…».
- «Escuchar prueba de voz» suena siempre, aunque las indicaciones estén desactivadas.

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
