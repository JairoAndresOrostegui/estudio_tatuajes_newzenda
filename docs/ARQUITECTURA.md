# Arquitectura y decisiones

Flutter comparte interfaz y dominio de importación entre web, Android e iOS.
`lib/ui` contiene vistas/formularios; `lib/data` las llamadas y exportaciones;
`lib/domain` formato e importación. Cloud Functions valida todos los cambios:
no se confía en precios, roles, pertenencia, totales ni saldos enviados por UI.

`functions/src/domain.js` es el motor de negocio independiente de Firestore.
Su unidad de trabajo primero lee y acumula cambios, y escribe al final de la
transacción. Así cumple el requisito de Firestore de lecturas antes de escrituras.
`index.js` añade Auth, autorización por membresía, consultas y agregaciones.

## Esquema

Todos los documentos se ubican bajo `studies/findink-house-qa` y conservan studyId.
No existe selector de estudio ni superadministrador.

| Colección | Propósito |
|---|---|
| members / invitations | Rol, activo, artista asociado / correo autorizado por administrador |
| settings | Zona, moneda, turnos, categorías, medios, cuentas |
| beds / artists / ruleVersions | Camillas, perfiles, reglas versionadas y vigencia |
| appointments / scheduleLocks | Agenda e historial / exclusión por recurso y día |
| catalog / skus | Tipo, SKU único, costo, precio, unidad, proveedor, mínimos y stock |
| movements | Cantidad firmada, costo total, valor y stock posterior, referencia y autor |
| sales / deposits | Líneas históricas, pagos, saldo, reverso / anticipos y aplicación única |
| payables | Compra recibida o gasto, pagos, vencimiento y saldo |
| accruals / artistMonths | Parte artista por línea / servicios terminados de cobrar por mes |
| artistBalances / settlements | Generado, pagado, pendiente / pagos parciales al artista |
| ledger / daily / balances | Hechos financieros firmados / agregados diarios / saldos actuales |
| commands / imports / audit | Idempotencia / origen y aprobación / bitácora sin contraseñas |

## Dinero y participación

COP en pesos enteros, máximo por operación 10^12; tasas en puntos básicos
(800 = 8 %). Multiplicación de tasa con BigInt y redondeo a peso más cercano.
No se utilizan fracciones binarias para importes. Cantidades son enteros en la
unidad mínima definida por catálogo; para consumos fraccionarios elegir primero
una unidad suficientemente pequeña.

La **tasa del estudio** se congela al confirmar la línea de servicio. Se elige
la regla con vigencia más reciente que no exceda la fecha del servicio y se
consulta el acumulado cobrado del mes local de la operación. El artista recibe
el complemento. Una venta puede asignar distintos artistas por línea.

Los pagos se asignan a líneas en orden. Un servicio suma al umbral sólo al quedar
totalmente cobrado, una vez, en el mes de su último cobro. El que cruza el umbral
conserva su tasa; ventas posteriores toman la tasa reducida. Anticipos sin aplicar,
productos y anulaciones no cuentan. Esta interpretación está explícita y queda
sujeta a aceptación del dueño antes de producción.

Los cambios de regla no alteran snapshots. Un reverso corrige el acumulado en el
mes donde se contó originalmente; no reescribe ventas posteriores. El saldo del
artista puede ser negativo si ya se liquidó una venta que luego se devolvió: es
una compensación visible para próximas liquidaciones, nunca un gasto duplicado.

Neto = ingreso devengado − parte artista generada − costo vendido − gasto
devengado. Caja = cobros − pagos, incluidos anticipos. Un pago de cartera no crea
otro ingreso. Un pago a artista afecta caja y saldo, no vuelve a restar utilidad.
Los impuestos son importes informativos incluidos en el total, no cálculos
tributarios. No hay facturación electrónica ni declaraciones.

## Stock y reversos

Compras recibidas, ventas y movimientos actualizan stock y kardex en la misma
transacción. Valor de existencias conserva pesos enteros; costo unitario promedio
redondeado y última salida absorbe el residuo para no crear valor ficticio.
Cada venta guarda el costo total realmente descargado; su devolución restaura
ese valor. Una compra no se puede reversar si deja stock o valoración negativos.
Los ajustes registran motivo; un faltante/consumo devenga costo y un sobrante lo
compensa. No se deducen recetas de insumos por servicio.

Anulaciones son totales por operación y devuelven los pagos a medios/cuentas
originales. La interfaz pide verificar el reintegro. No se integra una pasarela:
registrar el reverso no ejecuta por sí mismo una transferencia bancaria.

## Agenda y seguridad

Intervalos semiabiertos [inicio, fin), Bogotá UTC−05. Completo abarca inicio AM
hasta fin PM; nocturno puede cruzar medianoche. Locks por camilla/día y artista/día
serializan reservas incluso bajo concurrencia; un nocturno toma ambos días.
Cancelación/no asistencia libera locks, conservando historial.

La cuenta autenticada requiere membresía activa. El artista sólo recibe su agenda,
devengos, liquidaciones, saldo y reporte propio; no obtiene ventas mixtas que
revelarían a otros artistas. Auditor sólo reportes. Recepción opera, pero no edita
reglas, usuarios ni configuración. El servidor vuelve a consultar membresía por
solicitud; una revocación no depende de renovar claims. Escrituras Firestore desde
cliente se deniegan incluso al administrador; se usan funciones transaccionales.

Consultas paginadas a 50 registros, catálogos con límite de selección 2000,
operaciones de hasta 20 líneas y 100 pagos. Reportes leen agregados de hasta 367
días; saldos son actuales y se muestran separados del rango. Exportar una vista
lista exporta sólo lo cargado y lo dice en el botón; los reportes exportan todo su
rango. Las claves idempotentes no se caducan ni se borran automáticamente.

## Diferencias deliberadas frente al Excel

- Reportes y saldos son derivados; no se importan como nuevos hechos.
- Fórmulas en campos mapeados generan errores con fila/campo; no se confía en cachés.
- SKU, unidades, tipos y categorías se normalizan y validan.
- Participación define explícitamente estudio y artista, conservando histórico.
- Compras, consumo, venta y pago no son capturas independientes duplicadas.
- Históricos dudosos requieren conciliación; ningún dato real fue cargado.

Fuentes técnicas: [transacciones Firestore](https://firebase.google.com/docs/firestore/manage-data/transactions),
[configuración FlutterFire](https://firebase.google.com/docs/flutter/setup),
[autenticación federada Flutter](https://firebase.google.com/docs/auth/flutter/federated-auth),
[runtime y costos de Functions](https://firebase.google.com/docs/functions/manage-functions).
