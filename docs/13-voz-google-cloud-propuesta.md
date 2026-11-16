# Propuesta: voz neuronal con Google Cloud Text-to-Speech (NO integrada)

Estado: **solo investigación**. No se ha creado ninguna cuenta, no se ha habilitado ningún servicio con coste, no hay credenciales en el repositorio ni en el `.ipa`. Hace falta la autorización del propietario antes de empezar.

## Qué ofrece Google (datos consultados el 16 nov 2026)
- **Chirp 3: HD** es una familia de voces de alta calidad; el español de España (`es-ES`) figura entre los idiomas soportados ([documentación de Chirp 3: HD](https://docs.cloud.google.com/text-to-speech/docs/chirp3-hd)).
- Precio de lista: **30 $ por millón de caracteres**, con el primer millón mensual gratis según las tablas localizadas de la [página de precios](https://cloud.google.com/text-to-speech/pricing) y un [agregador de terceros](https://diyai.io/ai-tools/audio-generation/google-cloud-text-to-speech-pricing/). La página en inglés que encontré solo cita la franquicia gratuita para voces Standard, así que **hay que confirmar la franquicia de Chirp 3: HD en la consola antes de presupuestar**.
- Hay que **habilitar la facturación** para usar el servicio; lo que exceda la franquicia se cobra automáticamente.
- Los nombres exactos y el género de las voces `es-ES-Chirp3-HD-*` **no los he podido verificar**; se obtienen con `list_voices()` o en la [lista de voces](https://cloud.google.com/text-to-speech/docs/voices). Tampoco se debe asumir que sean «la voz de Google Maps».
- Hay otras voces `es-ES` anteriores (p. ej. Studio) que son un producto distinto.
- Disponibilidad regional de Chirp 3: HD limitada a ciertos endpoints (a revisar en la documentación vigente).

## Estimación de coste (orden de magnitud, con los datos anteriores)
Una indicación mide ~60 caracteres. Una ruta de 30 minutos genera ~25 frases ≈ 1.500 caracteres ≈ **0,045 $** sin caché. El millón de caracteres gratis equivaldría a ~650 rutas de ese tipo al mes. Con caché de frases repetidas (p. ej. «Gira a la derecha» a distintas distancias) el consumo baja. Es una estimación, no un presupuesto.

## Qué hace falta (requiere tu autorización)
1. **Cuenta de Google Cloud con facturación habilitada** (tarjeta). Recomendado: presupuesto con **alertas y tope** (p. ej. 5 $/mes) y cuota diaria de la API limitada.
2. **Proyecto** con la API Cloud Text-to-Speech habilitada.
3. **Backend propio** (p. ej. Cloud Run o Cloud Functions) que guarde la credencial de servicio y llame a Google. **La app nunca recibe la credencial.**
4. **Autenticación de la app frente al backend:** App Check (App Attest) o inicio de sesión anónimo, para que solo la app legítima pueda gastar cuota; límite de peticiones por dispositivo y por día.
5. **Caché de audios** en el backend (clave = voz + texto normalizado) y en el iPhone (disco, con tope de tamaño).
6. **Decisiones de producto:** voz de chico y de chica concretas, coste máximo asumible y qué hacer al agotar la cuota (volver a la voz de Apple).

## Diseño propuesto para la app
- `NavigationVoice` ya depende de `SpeechSynthesizing`; se añadiría un proveedor remoto con el mismo contrato y la voz de Apple como **respaldo**.
- **Tiempo de espera corto** (≈ 1,2 s para indicaciones urgentes): si el audio remoto no llega, se habla con la voz de Apple y no se retrasa la maniobra.
- **Precarga:** al calcular la ruta se piden las frases previsibles de las primeras maniobras para tenerlas en caché.
- **Caducidad:** cada audio lleva el identificador de maniobra y de tramo; si llega cuando la maniobra ya cambió, se descarta (no se reproducen instrucciones antiguas).
- **Datos enviados al backend/Google:** solo el texto de la frase («En 200 metros, gira a la derecha»), el identificador de la voz y la versión de la app. **Nunca** coordenadas, nombre del destino, historial ni identificadores personales (el backend ve la IP, como cualquier servidor; habría que reflejarlo en la política de privacidad).
- Si falla la red, el backend o la cuota: voz local de Apple, sin mostrar errores en mitad de una ruta.
- Pruebas: proveedor remoto falso (éxito, lentitud, error, respuesta tardía) para comprobar respaldo, descarte de audios caducados y caché.

## Alternativas sin servidor propio
- Mejorar las voces de Apple (implementado: elección de voz real, calidad visible y guía para descargar voces Mejoradas/Premium).
- Voz neuronal local (sherpa-onnx + Piper) descrita en `docs/11-voz-de-navegacion.md`: sin coste por uso, pero ~60 MB por voz y licencias por voz a revisar.

## Qué necesito de ti para seguir
Autorización expresa, tope de gasto mensual y, si procede, quién creará la cuenta de Google Cloud (yo no la creo ni introduzco datos de pago).
