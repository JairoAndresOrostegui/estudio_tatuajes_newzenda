# Findink House V2 — mapa previo a implementación

Fuentes leídas: Lista de requerimientos.docx, Cotizacion_V2_FINDINK_HOUSE.pdf,
Prompt_Codex_V2_FINDINK_HOUSE.txt y estructura/fórmulas de la plantilla XLSX en ../Docs.
El repositorio remoto sólo contiene README. Stack elegido según requisito: Flutter
para web/Android/iOS, Firebase Auth, Firestore y Cloud Functions Node 22.
La solicitud directa añade Android/iOS al alcance comercial originalmente web.

| Requisitos | Pantallas | Entidades / operación servidor | Prueba de aceptación |
|---|---|---|---|
| RF01–07,18–19 | Agenda, camillas | beds, artists, appointments, locks; reservar/cancelar, intervalos reales | concurrencia, completo, medianoche, filtros |
| RF08,10 | Ventas, cartera, caja | sales, payments, deposits, ledger; confirmar, cobrar, aplicar anticipo, reversar | venta mixta, pagos parciales, stock una vez |
| RF09 | Gastos, compras, CxP | expenses, purchases; recibir/pagar/reversar | compra pendiente, pago sin doble stock |
| RF11–12,23–24 | Inicio, reportes | dailyTotals, ledger, exportaciones PDF/XLSX | devengo vs caja, sumas, no doble comisión |
| RF13–17 | Artistas, liquidaciones | ruleVersions, accruals, artistMonths, settlements | 8/6 de ejemplo, cruce, mes, parciales, reverso, snapshot |
| RF20–22 | Acceso, usuarios | members, invitaciones administradas, auditoría | artista aislado, auditor lectura, recepción sin configuración |
| V2 catálogo | Catálogo | servicios/productos/materiales, categorías, medios, cuentas | validación SKU, histórico de precio/costo |
| V2 inventario | Existencias, kardex | inventoryMovements; compra, venta, consumo y ajuste | atómico, stock no negativo, reversos |
| V2 migración | Importación | importJobs, origen/hoja/fila, claves de deduplicación | vista previa, errores por celda, dos cargas sin duplicar |
| RNF01–04,06 | Todas | responsive, studyId, reglas, índices, paginación, respaldos | análisis, widgets, emuladores, compilaciones y humo QA |

## Decisiones y preguntas que cambian negocio

- COP en pesos enteros; tasas en puntos básicos; redondeo aritmético entero por línea.
- Zona America/Bogota, intervalos semiabiertos [inicio,fin). Horarios de QA ficticios
  y editables; completo une AM+PM; nocturno puede terminar al día siguiente.
- La tasa siempre representa al ESTUDIO. 8 % / 6 % / 2.000.000 son datos de ejemplo.
  Tasas y horarios reales requieren validación del dueño antes de producción.
- Propuesta a validar: asignar pagos a líneas en orden; contar un servicio para umbral
  sólo al terminar de cobrarlo; congelar tasa al confirmar la venta según acumulado
  cobrado hasta entonces. El servicio que cruza conserva tasa anterior. Devoluciones
  corrigen el mes contado original sin recalcular ventas posteriores.
- Comisión devengada al confirmar; liquidación parcial limitada a saldo del artista.
  Reversos con liquidación previa generan saldo compensable explícito, sin borrados.
- Neto operativo = ingresos devengados − parte artista generada − costo vendido −
  gastos devengados. Compras de inventario capitalizan; pagos no duplican devengos.
- IVA/impuestos son importes informativos ingresados, sin tasas tributarias asumidas.
- Alta administrada mediante correo autorizado; una cuenta autenticada sin membresía
  activa carece de acceso. Falta identificar el administrador inicial.
- Pendiente confirmar si el Firebase existente es QA; no hay apps y Firestore API
  estaba deshabilitada durante inspección. No mutar producción sin autorización.
- iOS requiere macOS/Xcode para compilar y cuenta/firma Apple para distribuir.
- Importación real requiere aprobar mapeos, filas dudosas y conciliación; ninguna
  copia del Excel ni dato personal se incorpora al repositorio público.

## Hallazgos del Excel (sin datos personales)

Hojas: LEER, Config, Ingresos, CXC, Gastos, CXP, Reporte Mensual, Reporte Anual,
Impuestos, Oculta, Inventario, Materiales, Productos, RESUMEN. Miles de filas
contienen fórmulas de plantilla, no transacciones reales. Hay 3 referencias rotas
en Reporte Mensual, 3 en Reporte Anual y 6 en Oculta. CXC/CXP contienen saldos
derivados: no deben importarse otra vez si la transacción origen está representada.
Productos vendibles e insumos se mantienen separados. RESUMEN se concilia, no se
convierte automáticamente en ventas. El importador ignora hojas de reportes y
señala fórmulas en campos transaccionales en vez de confiar en cachés calculadas.

## Secuencia de incrementos verificables

1. Núcleo de dominio, repositorio transaccional, seguridad y pruebas de aceptación.
2. Acceso y navegación Flutter; formularios y consultas por módulo.
3. Importación, exportación, documentación y pruebas con emuladores.
4. Configurar Firebase QA, desplegar, probar flujo remoto, compilar web/Android;
   preparar proyecto iOS/CI y dejar constancia de validación real disponible.
