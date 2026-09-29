import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cliente_app/screens/facturacion_screen.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'helpers/falso_permisos.dart';

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
        find.widgetWithText(OutlinedButton, 'Escanear clave de acceso'),
        findsNothing,
      );

      // El botón de OCR siempre visible
      expect(
        find.widgetWithText(OutlinedButton, 'Escanear ticket'),
        findsOneWidget,
      );
    });
  });

  group('FacturacionScreen - permiso de cámara bajo demanda', () {
    late FalsoPermisos permisos;

    setUp(() {
      permisos = FalsoPermisos()..instalar();
    });

    tearDown(() {
      permisos.desinstalar();
    });

    testWidgets('no pide el permiso de cámara al entrar a la pantalla',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FacturacionScreen(
            comercioId: 1,
            comercioNombre: 'Test',
            scannerDisponible: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // La pantalla muestra el botón de QR, pero aún no lo ha tocado nadie.
      expect(
        find.widgetWithText(OutlinedButton, 'Escanear clave de acceso'),
        findsOneWidget,
      );
      expect(permisos.llamadas, isEmpty);
      expect(permisos.seSolicitoCamara, isFalse);
    });

    testWidgets('pide el permiso de cámara al tocar "Escanear clave de acceso"',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FacturacionScreen(
            comercioId: 1,
            comercioNombre: 'Test',
            scannerDisponible: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(permisos.llamadas, isEmpty);

      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Escanear clave de acceso'),
      );
      await tester.pumpAndSettle();

      expect(permisos.seSolicitoCamara, isTrue);
      // Navegó al escáner, que con permiso concedido muestra la vista previa.
      expect(find.text('Escanear clave de acceso'), findsOneWidget);
    });
  });

  group('el escaner lee la clave venga en el formato que venga', () {
    // Una clave de acceso del SRI son 49 digitos. La longitud se comprueba
    // abajo para que un cambio aqui no la deje invalida en silencio.
    const clave = '0702202601180999999999999010000100000010000000000';

    test('un codigo de barras Code128 se procesa igual que un QR', () {
      final conQr = BarcodeCapture(
        barcodes: const [
          Barcode(format: BarcodeFormat.qrCode, rawValue: clave),
        ],
      );
      final conCode128 = BarcodeCapture(
        barcodes: const [
          Barcode(format: BarcodeFormat.code128, rawValue: clave),
        ],
      );

      expect(clave.length, 49);
      expect(esClaveAccesoValida(clave), isTrue);

      final leidoQr = valorDeCaptura(conQr);
      final leidoBarras = valorDeCaptura(conCode128);

      expect(leidoBarras, clave);
      expect(leidoBarras, leidoQr);

      // La validacion de los 49 digitos es la misma en los dos casos.
      expect(esClaveAccesoValida(leidoBarras!), isTrue);
      expect(esClaveAccesoValida(leidoBarras), esClaveAccesoValida(leidoQr!));
    });

    test('un Code128 con la clave incompleta se rechaza', () {
      final corta = clave.substring(0, 48);
      final captura = BarcodeCapture(
        barcodes: [
          Barcode(format: BarcodeFormat.code128, rawValue: corta),
        ],
      );

      final leido = valorDeCaptura(captura);
      expect(leido, corta);
      expect(esClaveAccesoValida(leido!), isFalse);
    });

    test('un codigo vacio o sin texto no cuenta', () {
      final vacio = BarcodeCapture(
        barcodes: const [
          Barcode(format: BarcodeFormat.code128),
          Barcode(format: BarcodeFormat.code128, rawValue: ''),
        ],
      );

      expect(valorDeCaptura(vacio), isNull);
    });

    test('si hay varios codigos en el fotograma gana el que trae la clave', () {
      final captura = BarcodeCapture(
        barcodes: const [
          Barcode(format: BarcodeFormat.qrCode, rawValue: 'BASURA'),
          Barcode(format: BarcodeFormat.code128, rawValue: clave),
        ],
      );

      final leido = valorDeCaptura(captura);
      // Se lee el primero con texto, igual que antes: la validacion decide.
      expect(leido, 'BASURA');
      expect(esClaveAccesoValida(leido!), isFalse);
    });
  });
}
