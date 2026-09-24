import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliente_app/screens/mi_comercio_form_screen.dart';
import 'package:cliente_app/screens/negocio_home_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';
import 'package:cliente_app/services/comercios_service.dart';

class _FakeAuth extends AuthService {
  @override
  Future<String?> getAccessToken() async => 'token-de-prueba';

  @override
  Future<void> logout() async {}
}

ComerciosService _servicioCon(MockClient mock) {
  return ComerciosService(
    api: ApiClient(baseUrl: 'http://test', httpClient: mock),
  );
}

void main() {
  group('NegocioHomeScreen', () {
    testWidgets('muestra estado vacío e invita a crear el primer comercio',
        (WidgetTester tester) async {
      final servicio = _servicioCon(
        MockClient((request) async {
          return http.Response('{"comercios": []}', 200,
              headers: {'content-type': 'application/json'});
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NegocioHomeScreen(
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aún no tienes comercios'), findsOneWidget);
      expect(find.text('Crear mi comercio'), findsOneWidget);
      expect(find.text('Nuevo comercio'), findsOneWidget);
    });

    testWidgets('lista los comercios propios', (WidgetTester tester) async {
      final servicio = _servicioCon(
        MockClient((request) async {
          return http.Response(
            '{"comercios": [{"id": 1, "nombre": "Cafetería Central", '
            '"categoria": "Café"}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NegocioHomeScreen(
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cafetería Central'), findsOneWidget);
      expect(find.text('Café'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });
  });

  group('MiComercioFormScreen', () {
    testWidgets('solicita nombre antes de guardar', (WidgetTester tester) async {
      var peticiones = 0;
      final servicio = _servicioCon(
        MockClient((request) async {
          peticiones++;
          return http.Response(
            '{"error": "no esperado"}',
            400,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MiComercioFormScreen(
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );

      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Requerido'), findsOneWidget);
      expect(peticiones, 0);
    });

    testWidgets('valida formato HH:MM antes de enviar',
        (WidgetTester tester) async {
      var peticiones = 0;
      final servicio = _servicioCon(
        MockClient((request) async {
          peticiones++;
          return http.Response(
            '{"error": "no esperado"}',
            400,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MiComercioFormScreen(
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Mi Tienda',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Apertura (HH:MM)'),
        '9:00',
      );
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Formato HH:MM'), findsOneWidget);
      expect(peticiones, 0);
    });

    testWidgets('envía datos válidos al crear', (WidgetTester tester) async {
      String? cuerpoEnviado;
      String? ruta;
      final servicio = _servicioCon(
        MockClient((request) async {
          ruta = request.url.path;
          cuerpoEnviado = request.body;
          return http.Response(
            '{"comercio": {"id": 7, "nombre": "Mi Tienda"}}',
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MiComercioFormScreen(
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Mi Tienda',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Apertura (HH:MM)'),
        '09:00',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Cierre (HH:MM)'),
        '18:30',
      );
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(ruta, '/comercios');
      expect(cuerpoEnviado, contains('"nombre":"Mi Tienda"'));
      expect(cuerpoEnviado, contains('"hora_apertura":"09:00"'));
      expect(cuerpoEnviado, contains('"hora_cierre":"18:30"'));
    });
  });
}