# Verificación de entrega QA — 26 de septiembre de 2026

## Comprobado

| Comprobación | Resultado |
|---|---|
| Flutter analyze | Sin incidencias |
| Flutter test | 3 pruebas aprobadas: login responsive/validación, errores de fórmula/fila, apertura de la plantilla real |
| Pruebas de dominio Node | 8 aprobadas: agenda, venta mixta, compras, participación, roles, importación, anticipo, atomicidad |
| Emulador Firestore | 2 aprobadas: reglas de acceso y dos reservas reales concurrentes (una sola confirma) |
| Humo Functions desplegadas | 8 controles aprobados con los cuatro roles y Auth correo/contraseña |
| Navegador Chrome real | Acceso y recorrido de 9 módulos, escritorio y móvil, sin errores JS |
| Formulario real web | Venta de servicio + producto, artista, pago parcial y reverso enviados desde la interfaz |
| Exportaciones reales | PDF de una página y XLSX descargados desde Chrome; importes contrastados con el reporte: bruto 375.000 y neto 44.000 COP |
| Build web release | Correcto, servido por Firebase Hosting con HTTPS |
| GitHub Actions | Ejecución [36234772092](https://github.com/JairoAndresOrostegui/estudio_tatuajes_newzenda/actions/runs/36234772092) aprobada para `f7bf7e1`: análisis, pruebas, compilaciones web/Android y publicación de artefactos |
| Build Android release QA | Correcto; firmado con clave QA de depuración, no firma Play |
| Descarga Android | HTTP 200, 58.571.894 bytes tras descompresión HTTP; SHA-256 idéntico al APK local |
| Android emulado API 36 | APK instalado, inicio de sesión con correo/contraseña y carga del panel conectado a QA |
| Seguridad de dependencias npm | 0 vulnerabilidades reportadas por auditoría de dependencias de ejecución |
| Conciliación de demo | Bruto 375.000, estudio 86.000, neto 44.000, caja 215.000, CxC 100.000, CxP 55.000 COP |
| Recuperación | PITR 7 días, protección contra borrado y backup diario con retención 7 días configurados |

Evidencia local (ignorada por git): `artifacts/qa-smoke-results.json`,
`browser-smoke-results.json`, `browser-form-results.json`, `qa-reconciliation.json`,
capturas de login/panel web y Android, y logs de compilaciones/emuladores.
Las pruebas financieras dejan reversos auditables. Las cuentas temporales se
desactivan al cerrar las pruebas. La demo identificada `qa_demo_*` queda operativa.

SHA-256 del APK publicado el 27/09/2026 tras actualizar Flutter y la
configuración Android de este PC:
`6A3FA2D9245BA19211FAE64A5BBD91095C005CF83484E7D76660D0100DC0B3FC`.
El hash anterior del 26/09/2026 era
`11e7ef79ab7e4230ead451557c7f30bb7245cc0589d36f942510aa94be961803`.

La descarga QA está en
https://estudio-tatuajes-newzenda-qa.web.app/downloads/findink-qa.apk.

Se detectó y corrigió durante la prueba nativa una inicialización Firebase con
API key web distinta de la aplicación Android. Cada plataforma usa su propia
configuración pública. También se ajustó compilación Kotlin en Windows con
dependencias ubicadas en otra unidad. Una interrupción de red inicial se resolvió
y se repitieron los pasos afectados.

## Pendiente y límites de validación

- iOS: proyecto/configuración preparados; compilación, firma, dispositivo físico
  y TestFlight no ejecutados porque el dueño aplazó esa entrega.
- Google OAuth está implementado y configurado (dominios y SHA Android). La
  autorización interactiva de la cuenta personal del dueño debe comprobarla él;
  las pruebas automatizadas usaron cuentas ficticias con correo/contraseña.
- Android probado en emulador; falta aceptación en dispositivos físicos del estudio
  y firma/distribución Google Play si se desea publicación en tienda.
- La plantilla real se pudo abrir y auditar, pero no se importó información real.
  Falta aprobar equivalencias por artista, medio, categoría, reglas históricas,
  fechas dudosas y conciliación. El importador UI trabaja por grupos de equivalencia;
  el script admite un mapeo normalizado por fila para hojas mixtas.
- Horarios y tasas reales no fueron suministrados ni aprobados; los valores QA
  son ficticios. Debe aceptarse la asignación secuencial de pagos a líneas y el
  conteo del servicio al completar su cobro antes de producción.
- Respaldos configurados; no se ha ejecutado un simulacro de restauración ni se
  presenta la primera copia programada como ya verificada.
- El alcance no incluye pasarela bancaria, facturación electrónica, declaraciones,
  recetas automáticas de insumos ni múltiples estudios. Anular registra el reintegro;
  el dinero real lo devuelve la operación del estudio fuera de la aplicación.

La entrega es un ambiente de **QA verificable**, no una afirmación de aceptación
de negocio, migración histórica aprobada o publicación en todas las tiendas.
