import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:cliente_app/screens/comprobante_entrada_screen.dart';
import 'package:cliente_app/screens/nivel3_capture_screen.dart';
import 'package:cliente_app/screens/ocr_capture_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';
import 'package:cliente_app/services/facturas_service.dart';

import 'helpers/falso_permisos.dart';

class _AuthFalso extends AuthService {
  @override
  Future<String?> getAccessToken() async => 'token-de-prueba';
}

void main() {
  group('Aviso de cámara denegado permanentemente', () {
    late FalsoPermisos permisos;

    setUp(() {
      permisos = FalsoPermisos.denegadoPermanente()..instalar();
    });

    tearDown(() {
      permisos.desinstalar();
    });

    void esperarAviso(WidgetTester tester) {
      expect(find.text('Permiso de cámara requerido'), findsOneWidget);
      expect(
        find.textContaining('denegado permanentemente'),
        findsOneWidget,
      );
      expect(find.text('Abrir configuración'), findsOneWidget);
    }

    testWidgets('ComprobanteEntradaScreen lo muestra al pedir la foto',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ComprobanteEntradaScreen(
            entradaId: 1,
            soportaCamara: true,
            picker: (source) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Permiso de cámara requerido'), findsNothing);

      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      esperarAviso(tester);
    });

    testWidgets('OcrCaptureScreen lo muestra al pedir la foto',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OcrCaptureScreen(
            comercioId: 1,
            comercioNombre: 'C',
            soportaCamara: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Permiso de cámara requerido'), findsNothing);

      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      esperarAviso(tester);
    });

    testWidgets('Nivel3CaptureScreen lo muestra al pedir la foto',
        (WidgetTester tester) async {
      // El desafío ya vence en el pasado. El estado solo cambia cuando el
      // bucle de la cuenta regresiva hace tick, así que la pantalla arranca en
      // "capturando" y el tick final lo deja en error cerrando el bucle. Eso
      // termina el Future.delayed y deja el árbol sin timers pendientes.
      final expiraEnPasado = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toIso8601String()
          .substring(0, 19)
          .replaceFirst('T', ' ');

      await tester.pumpWidget(
        MaterialApp(
          home: Nivel3CaptureScreen(
            comercioId: 1,
            comercioNombre: 'C',
            soportaCamara: true,
            auth: _AuthFalso(),
            facturasService: FacturasService(
              api: ApiClient(
                baseUrl: 'http://test',
                httpClient: MockClient((request) async => http.Response(
                      '{"nonce": "abc123", "expira_en": "$expiraEnPasado"}',
                      201,
                      headers: {'content-type': 'application/json'},
                    )),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Permiso de cámara requerido'), findsNothing);

      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      esperarAviso(tester);

      // Dejamos que el bucle de la cuenta regresiva llegue a su fin.
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Permiso de cámara válido no interrumpe la captura', () {
    late FalsoPermisos permisos;

    setUp(() {
      permisos = FalsoPermisos()..instalar();
    });

    tearDown(() {
      permisos.desinstalar();
    });

    testWidgets('ComprobanteEntradaScreen sigue funcionando si se concede',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ComprobanteEntradaScreen(
            entradaId: 1,
            soportaCamara: true,
            picker: (source) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      expect(permisos.seSolicitoCamara, isTrue);
      expect(find.text('Permiso de cámara requerido'), findsNothing);
    });

    testWidgets('elegir de galería no pide el permiso de cámara',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ComprobanteEntradaScreen(
            entradaId: 1,
            soportaCamara: true,
            picker: (source) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Elegir de galería'));
      await tester.pumpAndSettle();

      expect(permisos.llamadas, isEmpty);
      expect(find.text('Permiso de cámara requerido'), findsNothing);
    });
  });

  group('El estado denegado se distingue del permanente', () {
    testWidgets('un denegado simple ofrece reintentar, no configuración',
        (WidgetTester tester) async {
      final permisos = FalsoPermisos(statusActual: 0, statusTrasPedir: 0)
        ..instalar();
      addTearDown(permisos.desinstalar);

      await tester.pumpWidget(
        MaterialApp(
          home: ComprobanteEntradaScreen(
            entradaId: 1,
            soportaCamara: true,
            picker: (source) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      expect(find.text('Permiso de cámara requerido'), findsOneWidget);
      expect(find.text('Abrir configuración'), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(Permission.camera, isNotNull);
    });
  });
}
