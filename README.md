# Findink House V2

Aplicación Flutter en español para un estudio: agenda, camillas, artistas,
ventas mixtas, anticipos, pagos parciales, CxC/CxP, gastos, compras, inventario,
participaciones, liquidaciones, reportes PDF/XLSX e importación revisable de Excel.
Backend Firebase Auth + Firestore + Cloud Functions Node 22.

**QA:** https://estudio-tatuajes-newzenda-qa.web.app

El entorno contiene exclusivamente ejemplos ficticios. La cuenta del dueño fue
autorizada mediante invitación: entrar con Google con el correo indicado durante
la configuración. No hay contraseña administrativa compartida ni usuario demo
público. Los accesos de prueba automatizada se deshabilitan tras verificarlos.

## Ejecutar

Requisitos: Flutter 3.41.6 / Dart 3.11.4, Node 22, Firebase CLI y Java 21 para
emuladores. Android SDK 36 para APK; macOS/Xcode para iOS.

```powershell
flutter pub get
npm --prefix functions ci
flutter run -d chrome --dart-define-from-file=config/firebase.qa.json
```

La configuración Firebase de `config/firebase.qa.json`, `google-services.json` y
`GoogleService-Info.plist` es configuración **pública del cliente**, no una cuenta
de servicio. No añadir tokens, claves privadas, contraseñas ni el Excel real al
repositorio. Los originales permanecen fuera del proyecto, en `../Docs`.

## Verificar

```powershell
flutter analyze
flutter test
npm --prefix functions test
firebase emulators:exec --only firestore --project demo-findink "npm --prefix functions run test:rules"
```

Las pruebas incluyen intervalos/nocturno, reservas concurrentes, venta mixta,
pagos e idempotencia, compra pendiente, inventario, umbral 8/6, cambio de mes,
reversos, permisos, importación duplicada y lectura local de la plantilla real
cuando existe (sin imprimir registros personales). `docs/VERIFICACION.md` registra
qué se comprobó realmente en esta entrega.

Para probar también Auth y Functions localmente:

```powershell
firebase emulators:start --only "auth,firestore,functions" --project demo-findink
flutter run -d chrome --dart-define-from-file=config/firebase.emulator.json --dart-define=EMULATORS=true
```

Crear los usuarios/membresías en los emuladores mediante Admin SDK; la semilla
ficticia está en `functions/test/fixtures/seed.json`. Nunca abrir reglas para
facilitar una prueba. Para Android emulado usar `EMULATOR_HOST=10.0.2.2`.

## Compilar y desplegar QA

```powershell
flutter build web --release --dart-define-from-file=config/firebase.qa.json
flutter build apk --release --dart-define-from-file=config/firebase.qa.json
firebase deploy --only "firestore,functions,hosting" --project estudio-tatuajes-newzenda
```

El APK QA usa la firma de depuración local, registrada en Firebase. No es una
firma de publicación en Google Play. El archivo está en
`build/app/outputs/flutter-apk/app-release.apk`; también se distribuye desde
`https://estudio-tatuajes-newzenda-qa.web.app/downloads/findink-qa.apk` cuando se
copia a `build/web/downloads` antes del despliegue. `scripts/deploy-qa.ps1` automatiza
compilaciones y copia, y aborta si un paso falla.

iOS está preparado con identificador `com.newzenda.findinkHouse`, configuración
Firebase y retorno OAuth. Su compilación, firma y distribución quedaron aplazadas
por indicación del dueño. Hay un workflow manual para compilar sin firma en macOS;
no se afirma que iOS haya sido probado o publicado.

## Documentación

- [Mapa de requisitos y decisiones](docs/REQUISITOS.md)
- [Arquitectura, esquema y reglas de negocio](docs/ARQUITECTURA.md)
- [Guía por rol y demostración](docs/GUIA.md)
- [Operación, backups, costos y despliegue](docs/OPERACION.md)
- [Verificaciones y límites de entrega](docs/VERIFICACION.md)

Pendientes de aceptación del dueño: tasas/horarios reales, interpretación de cobro
por línea y regla vigente, equivalencias históricas y conciliación del Excel.
Los documentos comerciales se revisaron localmente y no se publicaron.
