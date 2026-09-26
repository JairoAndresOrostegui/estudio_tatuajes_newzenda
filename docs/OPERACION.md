# Operación QA

Proyecto Firebase: `estudio-tatuajes-newzenda`; sitio secundario
`estudio-tatuajes-newzenda-qa`; estudio interno `findink-house-qa`.
Base Firestore `(default)` en `us-central1`. Functions de segunda generación
Node 22, 256 MiB, mínimo 0 y máximo 5 instancias por función. Los límites no son
un presupuesto: configurar alertas de facturación en Google Cloud según el monto
que apruebe el dueño. No se crea otro proyecto ni se altera una instancia productiva.

El hosting da subdominio web.app y firebaseapp.com sin comprar un dominio propio.
Auth autoriza esos dominios QA. Los certificados SHA1/SHA256 de la firma Android
de pruebas local se registraron; una nueva firma o una firma Play requiere
registrar sus hashes. No publicar la clave privada de firma.

## Respaldos y restauración

Configurados en QA: protección de borrado de base, recuperación puntual (PITR)
con ventana de siete días y respaldo diario con retención siete días. Verificar
la primera ejecución programada en consola; configurar no equivale a haber
realizado una prueba de restauración.

Antes de producción hacer un simulacro: identificar backup/snapshot, restaurar
en una **base nueva**, aplicar reglas/índices, verificar miembros, documentos,
sumas del ledger y agregados, probar acceso aislado y sólo entonces planear el
cambio. Nunca restaurar sobre datos actuales sin un respaldo y un plan acordado.
La restauración no incluye Firebase Auth: inventariar usuarios/roles y exportar
Auth de forma privada con Firebase CLI bajo autorización del responsable.

```powershell
firebase firestore:backups:list --project estudio-tatuajes-newzenda
firebase firestore:backups:schedules:list --project estudio-tatuajes-newzenda
firebase firestore:databases:get '(default)' --project estudio-tatuajes-newzenda
```

Artifacts de builds de Functions tienen política de limpieza de siete días.
No almacenar originales Excel, documentos personales ni binarios históricos en
Firestore. El importador procesa archivos localmente; Storage no es necesario.

## Scripts de administración

Desde `functions`, `node scripts/cloud.mjs` admite `enable`, `config`, `domains`,
`bootstrap <correo>`, `seed` y `demo`. Reutiliza una sesión local de Firebase CLI,
sin imprimir ni persistir sus tokens. `seed`/`demo` son idempotentes; no usarlos
como migración de datos reales. `config` recupera las configuraciones públicas.
En sistemas sin instalación npm global Windows, indicar `FIREBASE_TOOLS_PATH`
con la ruta de instalación de firebase-tools.

Pruebas remotas:

```powershell
node scripts/qa-smoke.mjs
node scripts/browser-smoke.mjs
node scripts/qa-smoke.mjs --cleanup
```

Crean cuentas ficticias temporales con contraseñas aleatorias en un archivo local
ignorado `artifacts/qa-browser-credentials.local.json`. Nunca añadirlo a git.
El último comando desactiva cuentas y membresías de prueba. El usuario dueño
no se modifica. Las operaciones financieras de humo se reversan; permanecen en
auditoría. Las cuentas de prueba no se publican como acceso demo.

## Límites operativos

La agenda usa refresco cada 30 segundos, no una conexión permanente de snapshots.
Una pérdida de red muestra error y no inventa éxito. En un reintento de idénticos
datos se conserva la clave de comando durante la sesión. Tras cerrar navegador
en un resultado incierto, comprobar primero la lista/bitácora antes de repetir.
No hay capturas offline, integración bancaria, impuestos oficiales, push/SMS ni
facturación electrónica.

Pruebas OAuth interactivas con la cuenta personal del dueño, firma Play y
publicación en tiendas requieren las cuentas del responsable. iOS fue aplazado
explícitamente; no se distribuye en TestFlight en esta entrega.
