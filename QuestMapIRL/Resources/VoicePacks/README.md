# Paquetes de voz generados

Esta carpeta la escribe `python tools/elevenlabs_voice_pack.py build --pack <id>`. Contiene `<slug>-<frase>.m4a` y
`<slug>.voicepack.json` por paquete (`elf` = chica, `elm` = chico). Los archivos se copian sin carpeta al bundle, por eso
llevan el prefijo del paquete. Mientras esta carpeta no tenga un índice, la app muestra la voz como «No incluida en
esta versión».

Ver `docs/31-voces-elevenlabs.md`.
