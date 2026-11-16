# 15 · Persistencia de Casa y Trabajo

## Causa

Lectura del código (no confirmada con registros del iPhone del usuario):

1. `QuestMapIRLApp` abría el almacén de SwiftData y, **si fallaba, recreaba uno en memoria sin avisar**. En ese
   modo todo parece funcionar mientras la app está abierta y se pierde al cerrarla.
2. Casa/Trabajo se guardaban con `modelContext.insert(...)` y **sin `save()`**; se confiaba en el autoguardado.
   Cerrar la app a la fuerza poco después de confirmar podía perder el cambio. Los borrados tampoco guardaban
   ni mostraban errores (`try?` en el borrado total).

## Ahora

- `PersonalPlaceStore` (`Core/Persistence`): un único registro `SavedPlace` por tipo con nombre, dirección legible
  (nota), latitud y longitud. `set`/`delete` guardan **en el momento** con `save()`; si falla se deshace el cambio
  pendiente, se avisa con «Reintentar» y los datos anteriores siguen intactos. Editar uno no toca al otro.
- `ContainerFactory`: reintenta una vez; si el disco no abre, usa un almacén temporal **marcado y avisado** y nunca
  borra ni sustituye el archivo del disco.
- `RootView`: guarda al salir de primer plano y deja un único registro por tipo al arrancar.
- Borrar Casa/Trabajo pide confirmación; «Eliminar mis datos» borra ambos y solo muestra éxito si guardó.
- Registro técnico (`storage`): modo de almacenamiento y presencia `casa=si/no trabajo=si/no`. Nunca direcciones
  ni coordenadas.

## Pruebas

`PersonalPlacePersistenceTests` abre un contenedor NUEVO sobre el mismo archivo y comprueba lo guardado.

## Prueba manual en iPhone (pendiente)

A guardar ambas · B cerrar/abrir paneles · C cambiar de estilo · D segundo plano y volver · E cerrar la app del
todo (deslizar) y abrir · F abrir en modo avión · G editar solo Casa y reiniciar · H borrar solo Trabajo y reiniciar.
Además: confirmar y cerrar la app a la fuerza de inmediato.
