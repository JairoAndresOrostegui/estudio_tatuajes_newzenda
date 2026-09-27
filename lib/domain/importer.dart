import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:excel_community/excel_community.dart';
import '../data/api.dart';
import 'format.dart';

class ImportIssue {
  final int row;
  final String field, message;
  const ImportIssue(this.row, this.field, this.message);
}

class ImportDraft {
  final int row;
  final String operation;
  final Json data;
  const ImportDraft(this.row, this.operation, this.data);
}

class WorkbookPreview {
  final Excel workbook;
  final String fingerprint;
  WorkbookPreview._(this.workbook, this.fingerprint);
  factory WorkbookPreview.read(Uint8List bytes) {
    if (bytes.length > 15 * 1024 * 1024) {
      throw StateError('El límite es 15 MB por archivo.');
    }
    return WorkbookPreview._(
      Excel.decodeBytes(bytes),
      sha256.convert(bytes).toString(),
    );
  }
  List<String> get sheets => workbook.tables.keys.toList();
  List<List<Data?>> rows(String sheet) => workbook.tables[sheet]!.rows;
  static dynamic value(Data? cell) {
    final v = cell?.value;
    return switch (v) {
      null => null,
      TextCellValue() => v.value.toString(),
      IntCellValue() => v.value,
      DoubleCellValue() => v.value,
      DateCellValue() => v.asDateTimeLocal().toIso8601String().substring(0, 10),
      DateTimeCellValue() => v.asDateTimeLocal().toIso8601String().substring(
        0,
        10,
      ),
      FormulaCellValue() => throw StateError(
        'Celda calculada: requiere revisión, no se importa como transacción.',
      ),
      _ => v.toString(),
    };
  }

  static String column(int i) {
    var n = i + 1, s = '';
    while (n > 0) {
      n--;
      s = String.fromCharCode(65 + n % 26) + s;
      n ~/= 26;
    }
    return s;
  }
}

class ImportResult {
  final List<ImportDraft> drafts;
  final List<ImportIssue> issues;
  const ImportResult(this.drafts, this.issues);
  int get total => drafts.fold(
    0,
    (sum, d) =>
        sum +
        (d.data['amount'] as int? ??
            (d.data['lines'] is List
                ? ((d.data['lines'] as List).first['price'] as int? ?? 0)
                : 0)),
  );
}

ImportResult mapWorkbook(
  WorkbookPreview book,
  String sheet,
  int headerRow,
  String mode,
  Map<String, int> columns,
  Json defaults,
) {
  final drafts = <ImportDraft>[], issues = <ImportIssue>[];
  final rows = book.rows(sheet);
  if ([
    'Reporte Mensual',
    'Reporte Anual',
    'Impuestos',
    'Inventario',
    'RESUMEN',
    'Oculta',
    'CXC',
    'CXP',
  ].contains(sheet)) {
    return const ImportResult([], [
      ImportIssue(
        0,
        'hoja',
        'Esta hoja contiene reportes o saldos derivados. Concilia contra Ingresos/Gastos; no se carga como nuevas transacciones.',
      ),
    ]);
  }
  for (var index = headerRow; index < rows.length; index++) {
    final row = rows[index];
    // Only real identifiers/dates identify a source row; template formulas do not.
    final anchor =
        columns[mode == 'sale' || mode == 'expense' ? 'date' : 'name'];
    if (anchor == null || anchor >= row.length || row[anchor]?.value == null) {
      continue;
    }
    final data = <String, dynamic>{};
    var invalid = false;
    for (final entry in columns.entries) {
      try {
        final raw = entry.value < row.length
            ? WorkbookPreview.value(row[entry.value])
            : null;
        if (raw != null && raw.toString().trim().isNotEmpty) {
          data[entry.key] = raw;
        }
      } catch (e) {
        issues.add(ImportIssue(index + 1, entry.key, readableError(e)));
        invalid = true;
      }
    }
    if (invalid) continue;
    try {
      String text(String field, {bool optional = false}) {
        final v = data[field]?.toString().trim() ?? '';
        if (v.isEmpty && !optional) {
          throw StateError('$field: valor obligatorio');
        }
        return v;
      }

      int number(String field, {int? fallback}) {
        final v = data[field];
        if (v == null && fallback != null) return fallback;
        final n = v is num ? v : int.tryParse(v?.toString() ?? '');
        if (n == null || n < 0 || n > 1000000000000 || n != n.roundToDouble()) {
          throw StateError(
            '$field: importe/cantidad debe ser entero no negativo, sin separadores',
          );
        }
        return n.toInt();
      }

      String eventDate() {
        final v = data['date'];
        String d;
        if (v is num) {
          d = DateTime(
            1899,
            12,
            30,
          ).add(Duration(days: v.toInt())).toIso8601String().substring(0, 10);
        } else {
          d = text('date');
        }
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d) ||
            DateTime.tryParse(d) == null) {
          throw StateError(
            'date: fecha inválida; usa una fecha Excel o AAAA-MM-DD',
          );
        }
        return isoLocal(d);
      }

      final category = defaults['categoryId'];
      final artist = defaults['artistId'];
      String operation;
      Json payload;
      if (mode == 'sale') {
        final amount = number('amount');
        final paid = number('paid', fallback: 0);
        if (amount == 0 || paid > amount) {
          throw StateError(
            'amount/paid: total positivo y pago no mayor al total',
          );
        }
        if (artist == null || artist == '') {
          throw StateError('artistId: selecciona el artista conciliado');
        }
        final at = eventDate();
        operation = 'sale';
        payload = {
          'at': at,
          'clientName': text('name', optional: true),
          'lines': [
            {
              'itemId': defaults['itemId'],
              'quantity': 1,
              'price': amount,
              'artistId': artist,
            },
          ],
          if (paid > 0)
            'payment': {
              'amount': paid,
              'at': at,
              'methodId': defaults['methodId'],
              'accountId': defaults['accountId'],
            },
        };
      } else if (mode == 'expense') {
        final amount = number('amount'), paid = number('paid', fallback: 0);
        if (amount == 0 || paid > amount) {
          throw StateError('amount/paid: revisa total y pago');
        }
        final at = eventDate();
        operation = 'expense';
        payload = {
          'at': at,
          'amount': amount,
          'description': text('name'),
          'categoryId': category,
          'supplier': text('supplier', optional: true),
          'notes': 'Saldo y clasificación conciliados en importación',
          'tax': number('tax', fallback: 0),
          if (paid > 0)
            'payment': {
              'amount': paid,
              'at': at,
              'methodId': defaults['methodId'],
              'accountId': defaults['accountId'],
            },
        };
      } else if (mode == 'artist') {
        operation = 'saveArtist';
        payload = {
          'id':
              'legacy_${sha256.convert('$sheet:${index + 1}:${text('name')}'.codeUnits).toString().substring(0, 24)}',
          'name': text('name'),
          'styles': text('styles', optional: true),
          'bedIds': defaults['bedIds'] ?? [],
          'rule': {
            'baseBps': number('baseBps'),
            'reducedBps': number('reducedBps'),
            'threshold': number('threshold'),
            'effectiveFrom': defaults['effectiveFrom'],
          },
        };
      } else {
        operation = 'saveCatalog';
        payload = {
          'name': text('name'),
          'sku': text('sku'),
          'kind': mode,
          'unit': text('unit', optional: true).isEmpty
              ? 'unidad'
              : text('unit'),
          'description': text('description', optional: true),
          'supplier': text('supplier', optional: true),
          'categoryId': category,
          'cost': number('cost', fallback: 0),
          'price': number('price', fallback: 0),
          'minimum': number('minimum', fallback: 0),
          'initialStock': number('stock', fallback: 0),
        };
      }
      drafts.add(ImportDraft(index + 1, operation, payload));
    } catch (e) {
      final message = readableError(e);
      issues.add(ImportIssue(index + 1, message.split(':').first, message));
    }
  }
  return ImportResult(drafts, issues);
}
