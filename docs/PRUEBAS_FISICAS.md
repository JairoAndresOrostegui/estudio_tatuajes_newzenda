# Pruebas físicas y decisión de salida — Findink House

Fecha de preparación: 27 de septiembre de 2026. Entorno: **QA**, con datos ficticios.
Web: https://estudio-tatuajes-newzenda-qa.web.app. Android:
https://estudio-tatuajes-newzenda-qa.web.app/downloads/findink-qa.apk.
APK QA: 60.788.866 bytes, SHA-256
`6A3FA2D9245BA19211FAE64A5BBD91095C005CF83484E7D76660D0100DC0B3FC`.

## Antes de empezar

- El administrador invita a cada persona con su correo y rol. No compartir una
  cuenta entre encargados. La prueba de Google con la cuenta real del dueño debe
  hacerla el titular.
- Registrar marca/modelo, Android o iOS y versión, navegador, red, rol y fecha.
  Probar al menos un teléfono Android real y un navegador de escritorio. iOS
  sigue aplazado y no hay paquete instalable para iPhone.
- El APK QA actual usa el certificado debug de este PC. Si el teléfono tiene un
  APK QA firmado en el PC anterior, Android puede impedir la actualización:
  desinstalar la versión anterior y reinstalar esta. Los datos del servidor no se
  borran, pero se pierde la sesión y cualquier dato local de la app.
- Usar únicamente datos ficticios identificables como prueba. No importar el
  Excel real ni introducir clientes reales hasta aprobar reglas y conciliación.

## Recorrido de aceptación

| Responsable | Acción en teléfono y web | Resultado que debe comprobar |
| --- | --- | --- |
| Dueño / administrador | Entrar con Google, crear o desactivar una cuenta de prueba y configurar artista, camilla, catálogo y reglas | La cuenta sin invitación no entra; los cambios se ven al volver a abrir la app |
| Recepción | Crear cita, intentar un horario/camilla ocupado y cambiar su estado | El solapamiento se rechaza y la agenda coincide en ambos dispositivos |
| Recepción | Crear venta mixta, pago parcial y anticipo; cobrar saldo y reversar con motivo | Caja, CxC, stock y auditoría cambian una sola vez, incluso tras reintentar por red inestable |
| Recepción | Registrar compra pendiente, pago y ajuste de insumo | Stock, costo y CxP quedan coherentes, sin doble entrada |
| Artista | Entrar y consultar agenda, participación y pagos | Ve únicamente sus datos y no puede modificar finanzas ni reglas |
| Auditor | Abrir reporte, exportar PDF y XLSX | Importes coinciden con la pantalla; no puede escribir |
| Administrador | Previsualizar XLSX ficticio con fórmula y fila repetida | Muestra fila/campo problemático y evita duplicar la carga |

En Android comprobar además rotación, volver desde segundo plano, pérdida y
recuperación de red, permisos de descarga, inicio de sesión tras cerrar la app y
legibilidad con texto ampliado. Repetir los recorridos críticos en Wi-Fi y datos
móviles. Registrar cualquier resultado diferente con captura, hora, pasos y rol.

## Acta de decisión

Para cada caso anotar **aprobado**, **falló** o **no probado**, dispositivo y
responsable. El go de QA requiere que los recorridos críticos anteriores estén
aprobados en dispositivos reales y que no queden fallos de acceso, pérdida de
datos, importes o permisos.

El paso posterior de limpieza/migración a producción requiere además: aprobación
escrita de horarios, tasas, regla de pagos y equivalencias históricas; conciliación
del Excel real; prueba de restauración de backup; firma de distribución Android
si se va a publicar; revisión de App Check y aceptación del alcance iOS. No
limpiar datos QA ni cargar datos reales como sustituto de esa decisión.
