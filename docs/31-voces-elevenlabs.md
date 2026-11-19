# Voces de navegación generadas con ElevenLabs

Estado: **app integrada, audios sin generar**.

- **En la app:** Ajustes de navegación › Voz de las indicaciones › **Voces disponibles** muestra «Voz generada · chica» y «Voz generada · chico» como «No incluida en esta versión». No se pueden elegir.
- **Por qué faltan los audios:** el plan gratuito de ElevenLabs no deja usar por la API las voces de la biblioteca (error 402) ni distribuir lo generado. Con un plan de pago, elige las voces con `samples`, genera los paquetes y ejecuta `build`.
- **Candidatas españolas:**
  - Ernesto `y61xxgIMVdoS4fQJ9kHP`
  - Rodrigo `HfvB83WfJmz9muzlBPPN`
  - Cristina `dNjJKg63Fr5AXwIdkATa`
  - Sara Martin `gD1IexrzCvsXPHUuT0s3`

## En la app

- **Carga:** `GeneratedVoicePacks.swift` lee `<slug>.voicepack.json` del bundle una sola vez. Solo carga el índice; el audio se lee al reproducir.
- **Disponibilidad:** el paquete está listo solo si existen todas las frases obligatorias. Si no, la voz no se puede elegir y la navegación usa la voz del sistema.
- **Selección:** se guarda en el mismo campo que el perfil grabado activo, así que elegir uno deselecciona el otro. No cambia el esquema de datos.
- **Archivo dañado:** la indicación se dice completa con la voz del sistema, también en el modo «solo grabaciones».
- **Cola:** es la misma que la de los perfiles grabados, con la misma atenuación de la música y las mismas interrupciones.

## Cómo encaja en la app

La app ya tiene perfiles de voz grabada: `VoicePhraseID`, `VoicePromptComposer` (distancia + maniobra),
`VoicePlaybackPlanner` (respaldo híbrido) y `RecordedPromptPlayer` (recorte, ganancia, sin solapes). Un paquete generado
es **otro origen de esos mismos fragmentos**, incluido en la app. No hay un sistema paralelo, y no se pide nada a
ElevenLabs durante la ruta.

- **Mismos IDs:** se usan los `rawValue` de `VoicePhraseID`. Son 40 frases, 16 de ellas obligatorias.
- **Calles y números de salida:** se ven en pantalla. En modo híbrido, la indicación completa se dice con la voz del sistema, nunca mezclando voces.

## Archivos

| Archivo | Para qué |
|---|---|
| `tools/voice_packs/manifest.json` | Frases, contexto de entonación y frases excluidas con su motivo |
| `tools/voice_packs/packs.json` | Voz, modelo y ajustes fijos de cada paquete |
| `tools/elevenlabs_voice_pack.py` | Generación, verificación, preescucha, aprobación y empaquetado |
| `tools/voice_packs/work/` | Maestros WAV, estado y preescucha. Está **fuera de git** |
| `QuestMapIRL/Resources/VoicePacks/` | Salida para la app: `.m4a` AAC de 64 kbps, 24 kHz, mono, y un `*.voicepack.json` por paquete |

## Pasos

1. **Clave de API.** Defínela solo en tu terminal; no la pegues en el chat ni en el código:
   `$env:ELEVENLABS_API_KEY = Read-Host "Clave"`
2. `python tools/elevenlabs_voice_pack.py account` muestra el plan y los créditos. No consume créditos.
3. `python tools/elevenlabs_voice_pack.py voices` lista las voces en español con su ID real.
4. `python tools/elevenlabs_voice_pack.py samples --voice ID1 ID2 ID3 ID4` genera 5 frases por voz, unos 134 caracteres por voz.
5. Rellena `voice_id` y `voice_name` en `packs.json` con las voces elegidas.
6. `generate --pack …` es reanudable: solo genera lo que falta o no es válido, y nunca sobrescribe lo aprobado.
7. `verify` y `review`: escucha `review.html` y después `approve`.
8. `build --pack … --require-approval` y compilación en CI.

## Coste y condiciones (consultado el 19-11-2026)

- **Tamaño:** 1.090 caracteres por paquete y 2.180 los dos. Multilingual v2 gasta 1 crédito por carácter.
- **Plan gratuito:** solo permite uso **no comercial** (Términos 1(c)(i); Política de uso, apartado 12). Vale para escuchar muestras, no para distribuir el paquete.
- **Starter:** 6 $/mes (el primer mes 1 $), 30.000 créditos e incluye licencia comercial. Basta un mes.
- **Atribución:** no he encontrado ninguna obligación.
- **Transparencia:** hay que indicar que es IA si la ley lo exige o si ocultarlo engañaría. La app lo indicará con el texto «Voz generada con IA (ElevenLabs)» cuando se integren los paquetes.
- **Sin confirmar:**
  - Si una voz de la biblioteca concreta tiene restricciones propias.
  - Las condiciones de las voces predefinidas para apps distribuidas. El centro de ayuda dio 403.

## Frases no incluidas

«Mantente en el centro», «Continúa por la vía principal», «La ruta se ha actualizado», «Ubicación no disponible»,
«Ahora», «Después» y «Y después». El motor no las produce o la app no las anuncia por voz. El motivo de cada una está
en `manifest.json`.
