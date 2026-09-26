import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:findink_house/domain/importer.dart';
import 'package:findink_house/ui/login.dart';
import 'package:findink_house/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Login validates empty fields without network at mobile and desktop widths',
    (tester) async {
      for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(theme: appTheme(), home: const LoginPage()),
        );
        await tester.ensureVisible(find.text('Entrar al estudio'));
        await tester.tap(find.text('Entrar al estudio'));
        await tester.pump();
        expect(find.text('Escribe tu correo'), findsOneWidget);
        expect(find.text('Escribe tu contraseña'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  test(
    'Importer identifies formula field/row and rejects derived balances',
    () {
      final x = Excel.createExcel();
      final s = x['Ingresos'];
      s.appendRow([
        TextCellValue('Fecha'),
        TextCellValue('Nombre'),
        TextCellValue('Total'),
      ]);
      s.appendRow([
        TextCellValue('2026-09-26'),
        TextCellValue('Ficticio'),
        IntCellValue(200000),
      ]);
      s.appendRow([
        TextCellValue('2026-09-27'),
        TextCellValue('Fórmula'),
        FormulaCellValue('SUM(C2)'),
      ]);
      final book = WorkbookPreview.read(Uint8List.fromList(x.encode()!));
      final result = mapWorkbook(
        book,
        'Ingresos',
        1,
        'sale',
        {'date': 0, 'name': 1, 'amount': 2},
        {'artistId': 'a', 'itemId': 's'},
      );
      expect(result.drafts.length, 1);
      expect(result.total, 200000);
      expect(result.issues.single.row, 3);
      expect(result.issues.single.field, 'amount');
    },
  );
  test('Supplied Excel opens locally without exposing its records', () {
    final file = File(
      '../Docs/Plantilla de Contabilidad de Negocios FINDINK HOUSE .xlsx',
    );
    if (!file.existsSync()) return;
    final book = WorkbookPreview.read(file.readAsBytesSync());
    expect(
      book.sheets,
      containsAll(['Ingresos', 'Gastos', 'Productos', 'Materiales']),
    );
    expect(
      mapWorkbook(book, 'CXC', 9, 'sale', {}, {}).issues.single.field,
      'hoja',
    );
  });
}
