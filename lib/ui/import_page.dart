import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../data/api.dart';
import '../data/exports.dart';
import '../domain/importer.dart';
import '../domain/format.dart';
import 'forms.dart';

class ImportPage extends StatefulWidget {
  final Api api;
  final Lookups look;
  const ImportPage({super.key, required this.api, required this.look});
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  WorkbookPreview? book;
  String filename = '', sheet = '', mode = 'sale';
  int header = 8, done = 0;
  bool busy = false, approved = false;
  String? error;
  Map<String, int> columns = {};
  Json defaults = {};
  ImportResult? result;
  List<String> get fields => switch (mode) {
    'sale' => ['date', 'name', 'amount', 'paid'],
    'expense' => ['date', 'name', 'amount', 'paid', 'supplier', 'tax'],
    'artist' => ['name', 'styles', 'baseBps', 'reducedBps', 'threshold'],
    _ => [
      'name',
      'sku',
      'unit',
      'description',
      'supplier',
      'cost',
      'price',
      'stock',
      'minimum',
    ],
  };
  final names = {
    'date': 'Fecha',
    'name': 'Nombre / descripción',
    'amount': 'Total de la transacción COP',
    'paid': 'Efectivo ya cobrado/pagado COP',
    'supplier': 'Proveedor',
    'tax': 'Impuesto informativo',
    'sku': 'SKU',
    'unit': 'Unidad',
    'description': 'Descripción',
    'cost': 'Costo unitario',
    'price': 'Precio de venta',
    'stock': 'Saldo inicial de stock',
    'minimum': 'Stock mínimo',
    'styles': 'Estilos',
    'baseBps': 'Tasa estudio (puntos básicos)',
    'reducedBps': 'Tasa reducida (puntos básicos)',
    'threshold': 'Umbral COP',
  };
  void reset() {
    result = null;
    approved = false;
    done = 0;
  }

  Future<void> pick() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (file == null) return;
      final parsed = WorkbookPreview.read(await file.readAsBytes());
      setState(() {
        book = parsed;
        filename = file.name;
        sheet = parsed.sheets.contains('Ingresos')
            ? 'Ingresos'
            : parsed.sheets.first;
        columns = {};
        reset();
      });
    } catch (e) {
      setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void preview() {
    try {
      setState(() {
        error = null;
        result = mapWorkbook(book!, sheet, header, mode, columns, defaults);
        approved = false;
      });
    } catch (e) {
      setState(() => error = readableError(e));
    }
  }

  Future<void> commit() async {
    if (!approved || result == null) return;
    setState(() {
      busy = true;
      error = null;
      done = 0;
    });
    try {
      for (final draft in result!.drafts) {
        await widget.api.command('importRow', {
          'approved': true,
          'fileHash': book!.fingerprint,
          'sheet': sheet,
          'row': draft.row,
          'operation': draft.operation,
          'data': draft.data,
        });
        if (mounted) setState(() => done++);
      }
      if (mounted) setState(() => approved = false);
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'La carga se detuvo en la fila ${result!.drafts[done].row}: ${readableError(e)}. Puedes reintentar; las filas confirmadas no se duplicarán.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget select(String key, String title, Map<String, String> options) =>
      SizedBox(
        width: 270,
        child: DropdownButtonFormField<String>(
          initialValue: defaults[key],
          isExpanded: true,
          decoration: InputDecoration(labelText: title),
          items: options.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (v) => setState(() {
                  defaults[key] = v;
                  reset();
                }),
        ),
      );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '1. Elige el archivo y define las equivalencias',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'El archivo se lee en tu dispositivo. Sólo las filas que apruebes se envían al estudio. Las fórmulas se señalan como errores. CxC/CxP se derivan de total menos pagos; no cargues los mismos saldos otra vez.',
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: busy ? null : pick,
                icon: const Icon(Icons.upload_file),
                label: Text(
                  filename.isEmpty ? 'Seleccionar Excel XLSX' : filename,
                ),
              ),
              if (book != null) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 230,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(filename),
                        initialValue: sheet,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Hoja'),
                        items: book!.sheets
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                sheet = v!;
                                columns = {};
                                reset();
                              }),
                      ),
                    ),
                    SizedBox(
                      width: 230,
                      child: DropdownButtonFormField<String>(
                        initialValue: mode,
                        decoration: const InputDecoration(labelText: 'Destino'),
                        items: const [
                          DropdownMenuItem(
                            value: 'sale',
                            child: Text('Ingresos / servicios'),
                          ),
                          DropdownMenuItem(
                            value: 'expense',
                            child: Text('Gastos / CxP'),
                          ),
                          DropdownMenuItem(
                            value: 'product',
                            child: Text('Productos'),
                          ),
                          DropdownMenuItem(
                            value: 'material',
                            child: Text('Materiales'),
                          ),
                          DropdownMenuItem(
                            value: 'service',
                            child: Text('Catálogo de servicios'),
                          ),
                          DropdownMenuItem(
                            value: 'artist',
                            child: Text('Artistas'),
                          ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                mode = v!;
                                columns = {};
                                reset();
                              }),
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: TextFormField(
                        initialValue: header.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Fila del encabezado',
                        ),
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          if (n != null &&
                              n > 0 &&
                              n < book!.rows(sheet).length) {
                            setState(() {
                              header = n;
                              columns = {};
                              reset();
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final key in fields)
                      SizedBox(
                        width: 270,
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('$sheet-$mode-$header-$key'),
                          initialValue: columns[key],
                          isExpanded: true,
                          decoration: InputDecoration(labelText: names[key]),
                          items: [
                            for (
                              var i = 0;
                              i < book!.rows(sheet)[header - 1].length;
                              i++
                            )
                              DropdownMenuItem(
                                value: i,
                                child: Text(
                                  '${WorkbookPreview.column(i)} · ${book!.rows(sheet)[header - 1][i]?.value ?? ''}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: busy
                              ? null
                              : (v) => setState(() {
                                  columns[key] = v!;
                                  reset();
                                }),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    select(
                      'categoryId',
                      'Categoría conciliada',
                      widget.look.list('categories'),
                    ),
                    if (mode == 'sale') ...[
                      select(
                        'artistId',
                        'Artista conciliado',
                        choices(widget.look.artists),
                      ),
                      select(
                        'itemId',
                        'Servicio conciliado',
                        choices(
                          widget.look.catalog
                              .where((r) => r['kind'] == 'service')
                              .toList(),
                        ),
                      ),
                    ],
                    if (['sale', 'expense'].contains(mode)) ...[
                      select(
                        'methodId',
                        'Medio para pagos históricos',
                        widget.look.list('methods'),
                      ),
                      select(
                        'accountId',
                        'Cuenta para pagos históricos',
                        widget.look.list('accounts'),
                      ),
                    ],
                    if (mode == 'artist')
                      SizedBox(
                        width: 230,
                        child: TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'Vigencia AAAA-MM-DD',
                          ),
                          onChanged: (v) => defaults['effectiveFrom'] = v,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (mode == 'sale')
                  const Text(
                    'La participación se calcula con la regla vigente del artista en la fecha importada. Concilia esta equivalencia contra las columnas de artista/estudio del Excel antes de aprobar. Se importa por grupos de artista y medio; separa las hojas si contienen equivalencias diferentes.',
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : preview,
                  child: const Text('Generar vista previa'),
                ),
              ],
            ],
          ),
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (result != null) ...[
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '2. Revisa y concilia',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  '${result!.drafts.length} filas válidas · ${result!.issues.length} errores · Total preliminar ${money(result!.total)}',
                ),
                const SizedBox(height: 12),
                for (final d in result!.drafts.take(20))
                  Text(
                    'Fila ${d.row}: ${d.data['name'] ?? d.data['description'] ?? d.data['clientName'] ?? label(d.operation)} · ${d.data['amount'] != null
                        ? money(d.data['amount'])
                        : d.data['lines'] != null
                        ? money(d.data['lines'][0]['price'])
                        : 'Catálogo'}',
                  ),
                if (result!.drafts.length > 20)
                  const Text(
                    'Se muestran las primeras 20 filas. Exporta la vista completa para revisar.',
                  ),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: () => saveWorkbook(
                        'findink-vista-previa.xlsx',
                        ['Hoja', 'Fila', 'Operación', 'Datos'],
                        [
                          for (final d in result!.drafts)
                            [sheet, d.row, d.operation, d.data.toString()],
                        ],
                      ),
                      child: const Text('Exportar vista previa'),
                    ),
                    TextButton(
                      onPressed: () => saveWorkbook(
                        'findink-errores.xlsx',
                        ['Hoja', 'Fila', 'Campo', 'Error'],
                        [
                          for (final e in result!.issues)
                            [sheet, e.row, e.field, e.message],
                        ],
                      ),
                      child: const Text('Descargar errores'),
                    ),
                  ],
                ),
                for (final e in result!.issues.take(8))
                  Text(
                    'Fila ${e.row} · ${e.field}: ${e.message}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: approved,
                  onChanged: busy ? null : (v) => setState(() => approved = v!),
                  title: const Text(
                    'Apruebo las equivalencias, las filas válidas y su conciliación. Entiendo que las filas con error no se cargarán.',
                  ),
                ),
                FilledButton(
                  onPressed: busy || !approved || result!.drafts.isEmpty
                      ? null
                      : commit,
                  child: Text(
                    busy
                        ? 'Importando $done / ${result!.drafts.length}'
                        : 'Cargar filas aprobadas',
                  ),
                ),
                if (done > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '$done filas confirmadas. La carga repetida del mismo archivo/hoja/fila no crea duplicados.',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}
