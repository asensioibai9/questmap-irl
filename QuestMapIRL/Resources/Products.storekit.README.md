# Configuración StoreKit para pruebas

Crear en Xcode: File > New > File > StoreKit Configuration File, nombre `Products.storekit`, y añadir un grupo de suscripción "QuestMap Premium" con dos productos auto-renovables:

| Product ID | Nombre | Duración | Precio sugerido |
|---|---|---|---|
| `questmap.premium.monthly` | Premium mensual | 1 mes | 2,99 € |
| `questmap.premium.yearly` | Premium anual | 1 año | 19,99 € |

Después: Edit Scheme > Run > Options > StoreKit Configuration → `Products.storekit`.

Los mismos identificadores deben crearse en App Store Connect antes de enviar a revisión. Si se decide añadir la compra única ("Desbloqueo Quest"), añadir `questmap.premium.lifetime` como Non-Consumable y sumarlo a `StoreService.productIDs`.
