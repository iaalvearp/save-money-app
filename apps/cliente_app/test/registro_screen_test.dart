import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cliente_app/screens/registro_screen.dart';

CheckboxListTile _checkbox(WidgetTester tester) {
  return tester.widget<CheckboxListTile>(
    find.widgetWithText(
      CheckboxListTile,
      'Acepto recibir información publicitaria',
    ),
  );
}

Future<void> _ingresarFecha(WidgetTester tester, String fecha) async {
  final partes = fecha.split('-');
  final ano = int.parse(partes[0]);
  final mes = int.parse(partes[1]);
  final dia = int.parse(partes[2]);

  await tester.tap(
    find.widgetWithText(TextFormField, 'Fecha de nacimiento (opcional)'),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();

  final campoInput = find.descendant(
    of: find.byType(DatePickerDialog),
    matching: find.byType(TextFormField),
  );
  expect(campoInput, findsOneWidget);
  await tester.enterText(campoInput, '$mes/$dia/$ano');
  await tester.pumpAndSettle();

  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  group('RegistroScreen consentimiento publicitario', () {
    testWidgets('sin fecha de nacimiento queda deshabilitado y sin marcar',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: RegistroScreen()));

      final checkbox = _checkbox(tester);
      expect(checkbox.onChanged, isNull);
      expect(checkbox.value, isFalse);
    });

    testWidgets('mayor de edad queda habilitado y sin marcar',
        (WidgetTester tester) async {
      final hoy = DateTime.now();
      final mayor = '${hoy.year - 20}-${_dosDigitos(hoy.month)}'
          '-${_dosDigitos(hoy.day)}';

      await tester.pumpWidget(const MaterialApp(home: RegistroScreen()));
      await _ingresarFecha(tester, mayor);

      var checkbox = _checkbox(tester);
      expect(checkbox.onChanged, isNotNull);
      expect(checkbox.value, isFalse);

      await tester.tap(
        find.widgetWithText(
          CheckboxListTile,
          'Acepto recibir información publicitaria',
        ),
      );
      await tester.pumpAndSettle();

      checkbox = _checkbox(tester);
      expect(checkbox.value, isTrue);
    });

    testWidgets('menor de edad queda deshabilitado y sin marcar, sin excepción',
        (WidgetTester tester) async {
      final hoy = DateTime.now();
      final menor = '${hoy.year - 10}-${_dosDigitos(hoy.month)}'
          '-${_dosDigitos(hoy.day)}';

      await tester.pumpWidget(const MaterialApp(home: RegistroScreen()));
      await _ingresarFecha(tester, menor);

      final checkbox = _checkbox(tester);
      expect(checkbox.onChanged, isNull);
      expect(checkbox.value, isFalse);

      await tester.tap(
        find.widgetWithText(
          CheckboxListTile,
          'Acepto recibir información publicitaria',
        ),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(_checkbox(tester).value, isFalse);
    });

    testWidgets('corregir la fecha recalcula y vuelve a aplicar las reglas',
        (WidgetTester tester) async {
      final hoy = DateTime.now();
      final mayor = '${hoy.year - 30}-${_dosDigitos(hoy.month)}'
          '-${_dosDigitos(hoy.day)}';
      final menor = '${hoy.year - 15}-${_dosDigitos(hoy.month)}'
          '-${_dosDigitos(hoy.day)}';

      await tester.pumpWidget(const MaterialApp(home: RegistroScreen()));

      await _ingresarFecha(tester, mayor);
      expect(_checkbox(tester).value, isFalse);

      await _ingresarFecha(tester, menor);
      var checkbox = _checkbox(tester);
      expect(checkbox.onChanged, isNull);
      expect(checkbox.value, isFalse);

      await _ingresarFecha(tester, mayor);
      checkbox = _checkbox(tester);
      expect(checkbox.onChanged, isNotNull);
      expect(checkbox.value, isFalse);
    });
  });
}

String _dosDigitos(int n) => n.toString().padLeft(2, '0');