import 'package:flutter/material.dart';
import '../data/api.dart';
import '../domain/format.dart';

class Field {
  final String key, title, type;
  final bool required;
  final Map<String, String>? options;
  final dynamic initial;
  const Field(
    this.key,
    this.title, {
    this.type = 'text',
    this.required = true,
    this.options,
    this.initial,
  });
}

Map<String, String> choices(List<Json> rows) => {
  for (final r in rows)
    r['id'].toString():
        r['name']?.toString() ?? r['email']?.toString() ?? r['id'].toString(),
};

class Lookups {
  List<Json> artists = [], beds = [], catalog = [], deposits = [];
  Json settings = {};
  Future<void> load(Api api, String role) async {
    final names = role == 'artist'
        ? ['artists', 'beds']
        : role == 'auditor'
        ? ['artists', 'beds', 'catalog', 'settings']
        : ['artists', 'beds', 'catalog', 'settings', 'deposits'];
    final result = await Future.wait(names.map(api.lookup));
    for (var i = 0; i < names.length; i++) {
      switch (names[i]) {
        case 'artists':
          artists = result[i];
        case 'beds':
          beds = result[i];
        case 'catalog':
          catalog = result[i];
        case 'settings':
          settings = result[i].isEmpty ? {} : result[i].first;
        case 'deposits':
          deposits = result[i];
      }
    }
  }

  Map<String, String> list(String key) => choices(asRows(settings[key]));
}

Future<bool?> operationDialog(
  BuildContext context,
  Api api,
  Lookups look,
  String action,
  String title, {
  Json initial = const {},
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => OperationDialog(
    api: api,
    look: look,
    action: action,
    title: title,
    initial: initial,
  ),
);

class OperationDialog extends StatefulWidget {
  final Api api;
  final Lookups look;
  final String action, title;
  final Json initial;
  const OperationDialog({
    super.key,
    required this.api,
    required this.look,
    required this.action,
    required this.title,
    this.initial = const {},
  });
  @override
  State<OperationDialog> createState() => _OperationDialogState();
}

class _OperationDialogState extends State<OperationDialog> {
  final form = GlobalKey<FormState>();
  late Json values;
  late List<Field> fields;
  final lines = <Json>[];
  bool busy = false;
  String? error;
  int lineSeq = 0;
  @override
  void initState() {
    super.initState();
    values = {...widget.initial};
    fields = spec();
    for (final f in fields) {
      values.putIfAbsent(
        f.key,
        () =>
            f.initial ??
            (f.type == 'bool'
                ? true
                : f.type == 'multi'
                ? <String>[]
                : ''),
      );
    }
    if (['sale', 'purchase'].contains(widget.action)) addLine();
  }

  List<Field> payment({bool optional = false}) => [
    Field(
      'amount',
      optional ? 'Pago inicial (0 = pendiente)' : 'Monto del pago (COP)',
      type: 'int',
      initial: optional
          ? 0
          : widget.initial['balance'] ?? widget.initial['pending'] ?? '',
    ),
    Field(
      'methodId',
      'Medio de pago',
      options: widget.look.list('methods'),
      required: !optional,
    ),
    Field(
      'accountId',
      'Cuenta destino / origen',
      options: widget.look.list('accounts'),
      required: !optional,
    ),
    const Field('reference', 'Referencia bancaria', required: false),
  ];
  List<Field> spec() {
    final l = widget.look;
    final a = widget.action;
    final dated = Field(
      'at',
      'Fecha de la operación',
      type: 'date',
      initial: today(),
    );
    switch (a) {
      case 'saveBed':
        return [
          const Field('name', 'Nombre de la camilla'),
          const Field('notes', 'Notas', required: false),
          const Field('active', 'Activa', type: 'bool'),
        ];
      case 'saveArtist':
        final r = asJson(values['rule'] ?? {});
        return [
          const Field('name', 'Nombre del artista'),
          const Field('styles', 'Estilos', required: false),
          Field(
            'bedIds',
            'Camillas habilitadas',
            type: 'multi',
            options: choices(l.beds),
          ),
          Field(
            'baseBps',
            'Tasa del ESTUDIO (puntos básicos: 800 = 8 %)',
            type: 'int',
            initial: r['baseBps'],
          ),
          Field(
            'reducedBps',
            'Tasa reducida del ESTUDIO (600 = 6 %)',
            type: 'int',
            initial: r['reducedBps'],
          ),
          Field(
            'threshold',
            'Umbral mensual de servicios cobrados (COP)',
            type: 'int',
            initial: r['threshold'],
          ),
          Field(
            'effectiveFrom',
            'Regla vigente desde',
            type: 'date',
            initial: r['effectiveFrom'] ?? today(),
          ),
          const Field('active', 'Activo', type: 'bool'),
        ];
      case 'saveCatalog':
        return [
          const Field('name', 'Nombre'),
          const Field('sku', 'SKU / identificación'),
          const Field(
            'kind',
            'Tipo',
            options: {
              'service': 'Servicio',
              'product': 'Producto vendible',
              'material': 'Insumo consumible',
            },
            initial: 'product',
          ),
          const Field('description', 'Descripción', required: false),
          const Field('unit', 'Unidad', initial: 'unidad'),
          const Field('supplier', 'Proveedor', required: false),
          Field('categoryId', 'Categoría', options: l.list('categories')),
          const Field(
            'price',
            'Precio de venta (COP)',
            type: 'int',
            initial: 0,
          ),
          const Field('cost', 'Costo unitario (COP)', type: 'int', initial: 0),
          const Field('minimum', 'Stock mínimo', type: 'int', initial: 0),
          if (!values.containsKey('id'))
            const Field(
              'initialStock',
              'Stock inicial',
              type: 'int',
              initial: 0,
            ),
          const Field('active', 'Activo', type: 'bool'),
        ];
      case 'reserve':
        return [
          Field('day', 'Fecha de agenda', type: 'date', initial: today()),
          const Field(
            'mode',
            'Modalidad',
            options: {
              'am': 'AM',
              'pm': 'PM',
              'full': 'Día completo',
              'night': 'Nocturno',
            },
            initial: 'am',
          ),
          const Field(
            'kind',
            'Tipo',
            options: {
              'appointment': 'Cita',
              'reservation': 'Reserva',
              'block': 'Bloqueo',
            },
            initial: 'appointment',
          ),
          Field(
            'bedId',
            'Camilla',
            options: choices(l.beds.where((r) => r['active'] == true).toList()),
          ),
          Field(
            'artistId',
            'Artista (excepto bloqueos)',
            options: choices(
              l.artists.where((r) => r['active'] == true).toList(),
            ),
            required: false,
          ),
          const Field(
            'clientName',
            'Nombre del cliente (opcional)',
            required: false,
          ),
          const Field('contact', 'Contacto (opcional)', required: false),
          const Field('design', 'Diseño / notas', required: false),
        ];
      case 'appointmentStatus':
        return [
          const Field(
            'status',
            'Nuevo estado',
            options: {
              'arrived': 'En atención',
              'completed': 'Finalizada',
              'cancelled': 'Cancelada',
              'noShow': 'No asistió',
            },
          ),
          const Field('reason', 'Motivo / notas', required: false),
        ];
      case 'sale':
        return [
          dated,
          Field(
            'serviceDate',
            'Fecha del servicio',
            type: 'date',
            initial: today(),
          ),
          const Field('clientName', 'Cliente (opcional)', required: false),
          Field(
            'bedId',
            'Camilla (opcional)',
            options: choices(l.beds),
            required: false,
          ),
          Field(
            'depositId',
            'Anticipo disponible (opcional)',
            options: {
              for (final d in l.deposits.where(
                (r) => r['status'] == 'available',
              ))
                d['id']: '${d['clientName']} · ${money(d['amount'])}',
            },
            required: false,
          ),
          ...payment(optional: true),
        ];
      case 'purchase':
      case 'expense':
        return [
          dated,
          const Field('supplier', 'Proveedor / beneficiario', required: false),
          if (a == 'expense')
            const Field('description', 'Descripción del gasto'),
          if (a == 'expense')
            const Field(
              'expenseAmount',
              'Valor total del gasto (COP)',
              type: 'int',
            ),
          Field('categoryId', 'Categoría', options: l.list('categories')),
          const Field('folio', 'Folio / comprobante', required: false),
          const Field('costCenter', 'Centro de costos', required: false),
          const Field('notes', 'Notas', required: false),
          const Field(
            'dueDate',
            'Vencimiento (opcional)',
            type: 'date',
            required: false,
          ),
          const Field(
            'tax',
            'Impuesto incluido (informativo, COP)',
            type: 'int',
            initial: 0,
          ),
          ...payment(optional: true),
        ];
      case 'salePayment':
      case 'payablePayment':
        return [dated, ...payment()];
      case 'deposit':
        return [
          dated,
          const Field('clientName', 'Cliente'),
          const Field(
            'appointmentId',
            'Identificador de cita (opcional)',
            required: false,
          ),
          ...payment(),
        ];
      case 'settlement':
        return [
          dated,
          Field('artistId', 'Artista', options: choices(l.artists)),
          ...payment(),
        ];
      case 'saleVoid':
      case 'payableVoid':
      case 'depositRefund':
        return [
          dated,
          const Field('reason', 'Motivo de la anulación / devolución'),
        ];
      case 'movement':
        return [
          Field(
            'itemId',
            'Producto / insumo',
            options: choices(
              l.catalog.where((r) => r['kind'] != 'service').toList(),
            ),
          ),
          const Field(
            'kind',
            'Operación',
            options: {
              'consumption': 'Consumo de insumos',
              'adjustment': 'Ajuste de inventario',
            },
            initial: 'consumption',
          ),
          const Field(
            'quantity',
            'Cantidad (+ entrada / − salida)',
            type: 'signed',
          ),
          const Field('reason', 'Motivo obligatorio'),
        ];
      case 'createUser':
      case 'invite':
      case 'member':
        return [
          if (a == 'invite' || a == 'createUser')
            const Field('email', 'Correo autorizado', type: 'email'),
          if (a == 'createUser')
            const Field(
              'password',
              'Contraseña temporal (mínimo 12 caracteres)',
              type: 'password',
            ),
          const Field(
            'role',
            'Rol',
            options: {
              'admin': 'Administrador',
              'reception': 'Recepción',
              'artist': 'Artista',
              'auditor': 'Auditor',
            },
            initial: 'reception',
          ),
          Field(
            'artistId',
            'Artista vinculado (obligatorio para rol artista)',
            options: choices(l.artists),
            required: false,
          ),
          if (a == 'member')
            const Field('active', 'Acceso activo', type: 'bool'),
        ];
      case 'settings':
        final s = l.settings;
        final shifts = asJson(s['shifts'] ?? {});
        return [
          for (final mode in ['am', 'pm', 'night']) ...[
            Field(
              '${mode}Start',
              '${label(mode)} · inicio HH:mm',
              initial: (shifts[mode] as List?)?.first,
            ),
            Field(
              '${mode}End',
              '${label(mode)} · fin HH:mm',
              initial: (shifts[mode] as List?)?.last,
            ),
          ],
          for (final key in ['methods', 'accounts', 'categories'])
            Field(
              key,
              key == 'methods'
                  ? 'Medios: código | nombre (uno por línea)'
                  : key == 'accounts'
                  ? 'Cuentas: código | nombre (una por línea)'
                  : 'Categorías: código | nombre (una por línea)',
              type: 'multiline',
              initial: asRows(
                s[key],
              ).map((r) => '${r['id']} | ${r['name']}').join('\n'),
            ),
        ];
      default:
        return [];
    }
  }

  void addLine() {
    lines.add({
      '_key': lineSeq++,
      'quantity': 1,
      'price': 0,
      'cost': 0,
      'discount': 0,
      'tax': 0,
      'itemId': '',
      'artistId': '',
      'discountReason': '',
    });
  }

  Widget input(Field f, Json target, {ValueChanged<String?>? changed}) {
    final v = target[f.key] ?? f.initial ?? '';
    if (f.type == 'bool') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(f.title),
        value: v == true,
        onChanged: busy ? null : (v) => setState(() => target[f.key] = v),
      );
    }
    if (f.type == 'multi') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.title),
          Wrap(
            spacing: 8,
            children: [
              for (final e in f.options!.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: (v as List).contains(e.key),
                  onSelected: busy
                      ? null
                      : (selected) => setState(() {
                          final list = List<String>.from(v);
                          selected ? list.add(e.key) : list.remove(e.key);
                          target[f.key] = list;
                        }),
                ),
            ],
          ),
        ],
      );
    }
    if (f.options != null) {
      return DropdownButtonFormField<String>(
        initialValue: f.options!.containsKey(v) ? v : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: f.title),
        items: [
          if (!f.required)
            const DropdownMenuItem(value: '', child: Text('Sin asignar')),
          for (final e in f.options!.entries)
            DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: busy
            ? null
            : (v) {
                setState(() => target[f.key] = v ?? '');
                changed?.call(v);
              },
        validator: (v) => f.required && (v == null || v.isEmpty)
            ? 'Selecciona una opción'
            : null,
      );
    }
    final numeric = f.type == 'int' || f.type == 'signed';
    return TextFormField(
      obscureText: f.type == 'password',
      key: ValueKey(
        '${identityHashCode(target)}_${f.key}_${f.key == 'price' ? target['itemId'] : ''}',
      ),
      initialValue: v.toString(),
      enabled:
          !busy &&
          !(widget.action == 'saveCatalog' &&
              widget.initial.containsKey('id') &&
              f.key == 'cost'),
      maxLines: f.type == 'multiline' ? 4 : 1,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(signed: true)
          : f.type == 'email'
          ? TextInputType.emailAddress
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: f.title,
        hintText: f.type == 'date' ? 'AAAA-MM-DD' : null,
      ),
      onChanged: (v) => target[f.key] = v,
      validator: (v) {
        if (v == null || v.trim().isEmpty) {
          return f.required ? 'Campo obligatorio' : null;
        }
        if (numeric) {
          final n = int.tryParse(v);
          if (n == null ||
              n.abs() > 1000000000000 ||
              (f.type == 'int' && n < 0)) {
            return 'Escribe un entero válido, sin puntos ni comas';
          }
        }
        if (f.type == 'date') {
          final d = DateTime.tryParse(v);
          if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) ||
              d == null ||
              d.toIso8601String().substring(0, 10) != v) {
            return 'Usa una fecha válida AAAA-MM-DD';
          }
        }
        if (f.type == 'email' &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) {
          return 'Correo inválido';
        }
        return null;
      },
    );
  }

  Widget lineEditor(Json line, int index) {
    final purchase = widget.action == 'purchase';
    final items = widget.look.catalog
        .where(
          (r) =>
              r['active'] == true &&
              (purchase ? r['kind'] != 'service' : r['kind'] != 'material'),
        )
        .toList();
    final selected = items.where((r) => r['id'] == line['itemId']).firstOrNull;
    return Card(
      key: ValueKey(line['_key']),
      color: const Color(0xfff7f8f2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Línea ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Quitar línea',
                  onPressed: busy || lines.length == 1
                      ? null
                      : () => setState(() => lines.removeAt(index)),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            input(
              Field(
                'itemId',
                purchase ? 'Producto / insumo' : 'Servicio / producto',
                options: choices(items),
              ),
              line,
              changed: (v) {
                final item = items.firstWhere((r) => r['id'] == v);
                setState(() {
                  line['price'] = item['price'];
                  line['cost'] = item['cost'];
                });
              },
            ),
            const SizedBox(height: 12),
            if (!purchase && selected?['kind'] == 'service')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: input(
                  Field(
                    'artistId',
                    'Artista del servicio',
                    options: choices(
                      widget.look.artists
                          .where((r) => r['active'] == true)
                          .toList(),
                    ),
                  ),
                  line,
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: input(
                    const Field('quantity', 'Cantidad', type: 'int'),
                    line,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: input(
                    Field(
                      purchase ? 'cost' : 'price',
                      purchase ? 'Costo unitario COP' : 'Precio unitario COP',
                      type: 'int',
                    ),
                    line,
                  ),
                ),
              ],
            ),
            if (!purchase) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: input(
                      const Field('discount', 'Descuento COP', type: 'int'),
                      line,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: input(
                      const Field('tax', 'Impuesto incluido COP', type: 'int'),
                      line,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              input(
                const Field(
                  'discountReason',
                  'Motivo del descuento (si aplica)',
                  required: false,
                ),
                line,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Json payload() {
    final p = <String, dynamic>{if (values['id'] != null) 'id': values['id']};
    for (final f in fields) {
      var v = values[f.key];
      if (f.type == 'int' || f.type == 'signed') v = int.parse(v.toString());
      p[f.key] = v;
    }
    if (p['at'] != null) p['at'] = isoLocal(p['at']);
    if (widget.action == 'saveArtist') {
      p['rule'] = {
        for (final k in ['baseBps', 'reducedBps', 'threshold', 'effectiveFrom'])
          k: p.remove(k),
      };
    }
    if (['sale', 'purchase', 'expense'].contains(widget.action)) {
      final amount = p.remove('amount');
      final pay = {
        'amount': amount,
        'at': p['at'],
        for (final k in ['methodId', 'accountId', 'reference']) k: p.remove(k),
      };
      if ((amount as int) > 0) p['payment'] = pay;
      if (widget.action == 'expense') {
        p['amount'] = p.remove('expenseAmount');
      } else {
        p['lines'] = lines
            .map(
              (line) => {
                for (final e in line.entries)
                  if (e.key != '_key')
                    e.key:
                        [
                          'quantity',
                          'price',
                          'cost',
                          'discount',
                          'tax',
                        ].contains(e.key)
                        ? int.parse(e.value.toString())
                        : e.value,
              },
            )
            .toList();
      }
    }
    if (widget.action == 'settings') {
      p['shifts'] = {
        for (final m in ['am', 'pm', 'night'])
          m: [p.remove('${m}Start'), p.remove('${m}End')],
      };
      for (final k in ['methods', 'accounts', 'categories']) {
        p[k] = (p[k] as String)
            .split('\n')
            .where((s) => s.trim().isNotEmpty)
            .map((s) {
              final parts = s.split('|');
              if (parts.length != 2) {
                throw StateError('Usa código | nombre en cada línea.');
              }
              return {
                'id': parts[0].trim(),
                'name': parts[1].trim(),
                'active': true,
              };
            })
            .toList();
      }
    }
    return p;
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.command(widget.action, payload());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: busy ? null : () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.action.endsWith('Void') ||
                          widget.action == 'depositRefund')
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Confirma que se devuelve el dinero al medio y cuenta originales. El reverso conservará el historial y ajustará saldos y existencias.',
                          ),
                        ),
                      if (widget.action == 'saveArtist')
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text(
                            'La parte del artista es el complemento de la tasa del estudio. Cambiar la regla conserva los importes históricos.',
                          ),
                        ),
                      for (final f in fields)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: input(f, values),
                        ),
                      if (lines.isNotEmpty) ...[
                        const Divider(),
                        const Text(
                          'Detalle de la operación',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        for (var i = 0; i < lines.length; i++)
                          lineEditor(lines[i], i),
                        TextButton.icon(
                          onPressed: busy || lines.length >= 20
                              ? null
                              : () => setState(addLine),
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar línea'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirmar operación'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
