import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'api.dart';
import '../domain/format.dart';

Future<void> saveWorkbook(
  String filename,
  List<String> headers,
  List<List<dynamic>> rows,
) async {
  final book = Excel.createExcel();
  final sheet = book['Findink'];
  book.delete('Sheet1');
  sheet.appendRow(headers.map(TextCellValue.new).toList());
  for (final row in rows) {
    sheet.appendRow(
      row
          .map(
            (v) =>
                v is int ? IntCellValue(v) : TextCellValue(v?.toString() ?? ''),
          )
          .toList(),
    );
  }
  final bytes = book.encode()!;
  await FilePicker.saveFile(
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    bytes: Uint8List.fromList(bytes),
  );
}

Future<void> exportReport(Json report, bool pdf) async {
  final totals = asJson(report['totals']);
  final range = '${report['from']} a ${report['to']}';
  if (!pdf) {
    await saveWorkbook(
      'findink-${report['from']}.xlsx',
      ['Concepto', 'Monto COP'],
      [
        for (final e in totals.entries) [label(e.key), e.value],
        ['Rango', range],
        ['Filtro', report['dimension']],
        [
          'Neto',
          'Ingresos devengados menos parte artista, costo vendido y gastos; pagos no se descuentan de nuevo.',
        ],
        [],
        ['Día', ...totals.keys.map(label)],
        for (final r in asRows(report['rows']))
          [r['day'], ...totals.keys.map((k) => asJson(r['metrics'])[k] ?? 0)],
      ],
    );
    return;
  }
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Text(
          'FINDINK HOUSE',
          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Text('Reporte QA - $range'),
        pw.Text('Filtro: ${report['dimension']}'),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headers: ['Concepto', 'Monto COP'],
          data: [
            for (final e in totals.entries) [label(e.key), money(e.value)],
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          'Neto = ingresos devengados - parte del artista generada - costo vendido - gastos devengados. Los pagos al artista afectan caja, sin duplicar el gasto. Impuestos informativos.',
        ),
      ],
    ),
  );
  await Printing.sharePdf(
    bytes: await document.save(),
    filename: 'findink-${report['from']}.pdf',
  );
}
