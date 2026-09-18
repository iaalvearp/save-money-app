import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cliente_app/screens/facturacion_screen.dart';

void main() {
  group('FacturacionScreen', () {
    testWidgets('renderiza campos de clave y botones',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FacturacionScreen(
            comercioId: 1,
            comercioNombre: 'Test Commerce',
          ),
        ),
      );

      expect(
        find.widgetWithText(TextFormField, 'Clave de acceso'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ElevatedButton, 'Validar factura'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Escanear ticket'),
        findsOneWidget,
      );
    });

    testWidgets('muestra error si la clave tiene menos de 49 dígitos',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FacturacionScreen(
            comercioId: 1,
            comercioNombre: 'Test Commerce',
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Clave de acceso'),
        '12345',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Validar factura'));
      await tester.pump();

      expect(
        find.text('Debe ingresar 49 dígitos'),
        findsOneWidget,
      );
    });

    testWidgets('muestra título del comercio en AppBar',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FacturacionScreen(
            comercioId: 1,
            comercioNombre: 'Mi Comercio',
          ),
        ),
      );

      expect(find.text('Mi Comercio'), findsOneWidget);
    });

    testWidgets('muestra indicador de OCR disponible solo en plataformas compatibles',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FacturacionScreen(
            comercioId: 1,
            comercioNombre: 'Test',
          ),
        ),
      );

      // En test (Linux), el scanner no está disponible
      expect(
        find.widgetWithText(OutlinedButton, 'Escanear código QR'),
        findsNothing,
      );

      // El botón de OCR siempre visible
      expect(
        find.widgetWithText(OutlinedButton, 'Escanear ticket'),
        findsOneWidget,
      );
    });
  });
}
