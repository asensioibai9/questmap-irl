# Instalar QuestMap IRL en tu iPhone desde Windows

Sin Mac y sin cuenta de pago de Apple Developer solo hay una vía: un `.ipa` **sin firmar** que tú firmas en tu PC con tu Apple ID mediante una herramienta de *sideloading*. Es el mismo mecanismo que usa Xcode con una cuenta gratuita.

## Limitaciones de la firma gratuita (Apple las impone, no la app)
- La app **caduca a los 7 días**: hay que volver a instalarla (reinstalar no borra tus datos).
- Máximo **3 apps** firmadas así a la vez por Apple ID y **10 dispositivos** al año.
- Las **compras (StoreKit)** no funcionan: la pantalla Premium se mostrará pero no se podrá comprar. Todo lo demás (GPS, rutas, voz, niebla, logros) sí funciona.
- Si tu Apple ID tiene verificación en dos pasos, la herramienta te pedirá el código.

## Paso 1 — Descargar el .ipa
1. Entra en https://github.com/asensioibai9/questmap-irl/actions/workflows/ios-ipa.yml
2. Abre la última ejecución en verde.
3. Abajo, en **Artifacts**, descarga `QuestMapIRL-unsigned-ipa` (es un .zip; dentro está `QuestMapIRL-unsigned.ipa`). Descomprímelo.

## Paso 2 — Instalar Sideloadly (recomendado en Windows)
1. Descarga Sideloadly desde su web oficial: https://sideloadly.io
2. Instálalo. Necesita **iTunes** e **iCloud para Windows** descargados desde la web de Apple (NO desde la Microsoft Store); el instalador de Sideloadly lo indica.

## Paso 3 — Firmar e instalar
1. Conecta el iPhone por cable y desbloquéalo. Si pregunta "¿Confiar en este ordenador?", acepta.
2. Abre Sideloadly. Arrastra `QuestMapIRL-unsigned.ipa` a la ventana.
3. En **Apple account**, escribe tu Apple ID (tu correo). Pulsa **Start**.
4. Te pedirá la contraseña del Apple ID y, si procede, el código de verificación. Introdúcelos tú en la ventana de Sideloadly.
5. Espera a que termine. La app aparece en el iPhone.

## Paso 4 — Confiar en el desarrollador (solo la primera vez)
En el iPhone: **Ajustes > General > VPN y gestión de dispositivos** → toca tu Apple ID bajo "App del desarrollador" → **Confiar**.

## Paso 5 — Probar
- Al abrir, pasa el onboarding y acepta ubicación "Al usar la app".
- Busca un destino o mantén pulsado el mapa, elige ruta y pulsa **Iniciar misión**.
- Para que se guarden viajes y niebla, llega al destino o pulsa **Finalizar**.

## Alternativa: AltStore
Mismo flujo: AltServer en el PC (también requiere iTunes/iCloud de la web de Apple), AltStore en el iPhone, y desde AltStore "+" para instalar el .ipa. Refresca cada 7 días automáticamente cuando el iPhone y el PC están en la misma red.

## Cuando quieras pasar a algo serio
Con una cuenta Apple Developer (99 €/año) la distribución correcta es **TestFlight**: sin caducidad semanal, hasta 10.000 probadores y compras en sandbox. Para eso haría falta un Mac (o Xcode Cloud) con el certificado; podemos prepararlo en GitHub Actions con los secretos de firma cuando llegue el momento.
