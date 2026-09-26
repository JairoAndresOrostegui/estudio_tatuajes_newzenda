import 'package:intl/intl.dart';

final _cop = NumberFormat.decimalPattern('es_CO');
String money(dynamic v) => '\$ ${_cop.format(v is num ? v : 0)}';
DateTime bogotaNow() =>
    DateTime.now().toUtc().subtract(const Duration(hours: 5));
String today() => DateFormat('yyyy-MM-dd').format(bogotaNow());
String isoNow() => DateTime.now().toUtc().toIso8601String();
String isoLocal(String v) => DateTime.parse(
  v.contains('T') ? v : '${v}T12:00:00-05:00',
).toUtc().toIso8601String();
String dateLabel(dynamic v) {
  if (v == null || v == '') return '—';
  final d = DateTime.tryParse(v.toString());
  if (d == null) return v.toString();
  return DateFormat(
    'dd MMM yyyy',
    'es_CO',
  ).format(d.isUtc ? d.subtract(const Duration(hours: 5)) : d);
}

const labels = {
  'admin': 'Administrador',
  'reception': 'Recepción',
  'artist': 'Artista',
  'auditor': 'Auditor',
  'service': 'Servicio',
  'product': 'Producto',
  'material': 'Insumo',
  'reserved': 'Reservada',
  'arrived': 'En atención',
  'completed': 'Finalizada',
  'cancelled': 'Cancelada',
  'noShow': 'No asistió',
  'confirmed': 'Confirmado',
  'void': 'Anulado',
  'available': 'Disponible',
  'applied': 'Aplicado',
  'refunded': 'Devuelto',
  'am': 'AM',
  'pm': 'PM',
  'full': 'Día completo',
  'night': 'Nocturno',
  'appointment': 'Cita',
  'reservation': 'Reserva',
  'block': 'Bloqueo',
  'purchase': 'Compra',
  'expense': 'Gasto',
  'sale': 'Venta',
  'consumption': 'Consumo',
  'adjustment': 'Ajuste',
  'gross': 'Ingresos devengados',
  'studio': 'Ingreso del estudio',
  'artistGenerated': 'Parte del artista generada',
  'artistPaid': 'Pagos a artistas',
  'artistPending': 'Parte del artista pendiente',
  'cogs': 'Costo de mercancía vendida',
  'expenses': 'Gastos devengados',
  'cash': 'Flujo neto de caja',
  'receivable': 'Cuentas por cobrar',
  'payable': 'Cuentas por pagar',
  'net': 'Neto operativo',
  'taxCollected': 'Impuestos cobrados (informativo)',
  'taxPaid': 'Impuestos pagados (informativo)',
  'depositLiability': 'Anticipos sin aplicar',
  'purchases': 'Compras de inventario',
};
String label(dynamic v) => labels[v] ?? v?.toString() ?? '—';
