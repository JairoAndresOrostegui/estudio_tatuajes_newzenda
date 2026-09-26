# Guía de uso por rol

## Administrador

Entrar con Google o correo/contraseña. El correo inicial del dueño tiene una
invitación; cualquier otra cuenta sin alta queda bloqueada. En Usuarios se puede
autorizar un correo existente para Google, crear una cuenta con contraseña
temporal o editar/desactivar una membresía. El rol artista exige vincular un
perfil. La función de contraseña olvidada permite al usuario establecer su clave.

Configurar primero medios/cuentas/categorías, camillas, artistas con tasas y
vigencia, y catálogo. En configuración las listas usan `código | nombre`, una por
línea. Conservar los códigos usados históricamente; el nombre puede editarse.
El ejemplo QA 8/6 no es una regla aprobada para artistas reales.

## Recepción

Agenda: elegir día/semana, artista y camilla; crear cita, reserva o bloqueo. Los
conflictos los resuelve el servidor. Cambiar estado desde el detalle de la cita.
La lista se actualiza cada 30 segundos, y también con el botón Actualizar.

Ventas: agregar servicios y productos, asignar artista por servicio, registrar
descuentos con motivo, impuesto incluido si aplica, y un pago inicial opcional.
Para varias formas de pago, confirmar el primer pago y añadir los siguientes
desde el detalle. Un anticipo disponible se aplica una sola vez. El saldo queda
visible en Ventas y CxC; Registrar cobro agrega pagos sin descontar stock otra vez.

Gastos y compras: Registrar gasto crea una obligación; Recibir compra agrega
existencias y una cuenta por pagar. Pago inicial 0 deja todo pendiente. Desde el
detalle, Registrar pago reduce el saldo sin crear otra compra. Anular y devolver
requiere motivo y confirmación del reintegro físico del dinero.

Inventario: Consumo usa cantidades negativas y sólo admite insumos; Ajuste usa
positivo o negativo y motivo. Kardex muestra stock posterior, referencia y costo.
Las compras actualizan el costo promedio. El precio de venta sí puede editarlo el
administrador; los precios/costos históricos permanecen en cada venta.

Liquidaciones: elegir artista, importe, medio y cuenta. El servidor impide pagar
más que la participación pendiente. Las participaciones generadas se consultan
por separado de los pagos.

## Artista

Consulta únicamente su agenda, participación generada, pagos recibidos y reportes
de su producción. No puede alterar reglas ni acceder a ventas/datos de otros.

## Auditor

Consulta reportes por fecha, artista/categoría o medio/cuenta y exporta PDF/XLSX.
No tiene acciones de escritura. El filtro por medio/cuenta representa caja; las
ventas devengadas se filtran por artista/categoría.

## Demostración disponible en QA

Hay dos artistas y dos camillas ficticios, servicios, crema e insumos. Las citas
del 28 de septiembre de 2026 usan turnos AM y PM. Los ejemplos identificados
`qa_demo_*` incluyen:

1. Anticipo $30.000 aplicado a venta mixta de $225.000, pago adicional $95.000,
   saldo $100.000 y una crema descargada.
2. Servicio de otro artista de $150.000 completamente pagado.
3. Compra recibida de insumos por $35.000 pendiente.
4. Gasto $30.000 con pago $10.000 y saldo $20.000.
5. Liquidación parcial de $50.000 a la artista Ada.

En el reporte de esa fecha: bruto $375.000, estudio $86.000, artista generado
$289.000, costo vendido $12.000, gastos $30.000, neto $44.000, caja neta $215.000,
CxC $100.000, CxP $55.000 y artista pendiente $239.000 (antes de nuevas pruebas o
cambios del usuario). Cobrar el pendiente debe subir caja y bajar CxC, manteniendo
el ingreso devengado y el stock. Los otros movimientos de pruebas se reversaron
con motivo explícito para conservar trazabilidad.

## Importación

Seleccionar XLSX, hoja, fila del encabezado (numeración Excel) y destino. Mapear
columnas y equivalencias. Los importes deben ser pesos enteros. El sistema no
interpreta separadores ambiguos ni fórmulas como hechos aprobados.

Ingresos/gastos: total y pagos existentes producen automáticamente saldo CxC/CxP.
Si no se mapea pago se considera pendiente; revisar y aprobar explícitamente.
Los saldos iniciales de inventario se cargan por catálogo. Las hojas CXC, CXP,
RESUMEN y reportes se bloquean como origen de nuevas transacciones para evitar
duplicados. Para ingresos por varios artistas o medios, preparar grupos con la
misma equivalencia o usar el archivo de carga normalizado del script.

Exportar vista previa y errores, conciliar total y participación histórica,
aprobar y cargar. Una interrupción puede reintentarse: origen/huella/hoja/fila
evita duplicados. Cambiar una equivalencia ya cargada requiere reverso conciliado;
no se reescribe silenciosamente. No se ha aprobado ni ejecutado la carga real.
