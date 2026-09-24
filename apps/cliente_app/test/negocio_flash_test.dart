import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliente_app/screens/canjear_cupon_screen.dart';
import 'package:cliente_app/screens/crear_promocion_flash_screen.dart';
import 'package:cliente_app/screens/mis_promociones_flash_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';
import 'package:cliente_app/services/comercios_service.dart';
import 'package:cliente_app/services/flash_service.dart';

class _FakeAuth extends AuthService {
  @override
  Future<String?> getAccessToken() async => 'token-de-prueba';

  @override
  Future<void> logout() async {}
}

FlashService _servicioFlashCon(MockClient mock) {
  return FlashService(
    api: ApiClient(baseUrl: 'http://test', httpClient: mock),
  );
}

ComerciosService _servicioComerciosCon(MockClient mock) {
  return ComerciosService(
    api: ApiClient(baseUrl: 'http://test', httpClient: mock),
  );
}

void main() {
  group('CrearPromocionFlashScreen', () {
    Future<void> llenarValidos(WidgetTester tester) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Título'),
        'Viernes loco',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Descuento (%)'),
        '25',
      );
    }

    testWidgets('valida descuento fuera de rango antes de enviar',
        (WidgetTester tester) async {
      var peticiones = 0;
      final servicio = _servicioFlashCon(
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
          home: CrearPromocionFlashScreen(
            comercio: _comercioPrueba(),
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Título'),
        'Viernes loco',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Descuento (%)'),
        '101',
      );
      await tester.ensureVisible(find.text('Crear promoción'));
      await tester.tap(find.text('Crear promoción'));
      await tester.pumpAndSettle();

      expect(find.text('Entre 1 y 100'), findsOneWidget);
      expect(peticiones, 0);
    });

    testWidgets('valida descuento 0 antes de enviar',
        (WidgetTester tester) async {
      var peticiones = 0;
      final servicio = _servicioFlashCon(
        MockClient((request) async {
          peticiones++;
          return http.Response('{"error": "no"}', 400,
              headers: {'content-type': 'application/json'});
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CrearPromocionFlashScreen(
            comercio: _comercioPrueba(),
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Título'),
        'Viernes loco',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Descuento (%)'),
        '0',
      );
      await tester.ensureVisible(find.text('Crear promoción'));
      await tester.tap(find.text('Crear promoción'));
      await tester.pumpAndSettle();

      expect(find.text('Entre 1 y 100'), findsOneWidget);
      expect(peticiones, 0);
    });

    testWidgets('envía datos válidos al crear la promoción',
        (WidgetTester tester) async {
      String? cuerpoEnviado;
      String? ruta;
      final servicio = _servicioFlashCon(
        MockClient((request) async {
          ruta = request.url.path;
          cuerpoEnviado = request.body;
          return http.Response(
            '{"promocion": {"id": 3, "comercio_id": 1, '
            '"titulo": "Viernes loco", "descuento_porcentaje": 25}}',
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CrearPromocionFlashScreen(
            comercio: _comercioPrueba(),
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );

      await llenarValidos(tester);
      await tester.ensureVisible(find.text('Crear promoción'));
      await tester.tap(find.text('Crear promoción'));
      await tester.pumpAndSettle();

      expect(ruta, '/flash/promociones');
      expect(cuerpoEnviado, contains('"comercio_id":1'));
      expect(cuerpoEnviado, contains('"descuento_porcentaje":25.0'));
      expect(cuerpoEnviado, contains('"titulo":"Viernes loco"'));
      expect(cuerpoEnviado, contains('"termina_en"'));
    });
  });

  group('MisPromocionesFlashScreen', () {
    testWidgets('lista promociones del único comercio propio',
        (WidgetTester tester) async {
      final flash = _servicioFlashCon(
        MockClient((request) async {
          return http.Response(
            '{"promociones": [{"id": 1, "comercio_id": 1, '
            '"titulo": "Martes de café", "descuento_porcentaje": 15, '
            '"inicia_en": "2026-01-01 00:00:00", '
            '"termina_en": "2030-01-01 00:00:00"}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final comercios = _servicioComerciosCon(
        MockClient((request) async {
          return http.Response(
            '{"comercios": [{"id": 1, "nombre": "Cafetería Central"}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MisPromocionesFlashScreen(
            servicio: flash,
            comerciosServicio: comercios,
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Martes de café'), findsOneWidget);
      expect(find.text('Activa'), findsOneWidget);
      expect(find.text('Nueva promoción'), findsOneWidget);
    });
  });

  group('CanjearCuponScreen', () {
    Future<void> poderCanjear(WidgetTester tester, MockClient mock) async {
      final servicio = _servicioFlashCon(mock);
      await tester.pumpWidget(
        MaterialApp(
          home: CanjearCuponScreen(
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Código del cupón'),
        'FLASH-EXITO-0001',
      );
      await tester.tap(find.text('Canjear'));
      await tester.pumpAndSettle();
    }

    testWidgets('muestra éxito al canjear un cupón válido',
        (WidgetTester tester) async {
      await poderCanjear(
        tester,
        MockClient((request) async {
          return http.Response(
            '{"mensaje": "Cupón canjeado exitosamente"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(find.text('Cupón canjeado exitosamente'), findsOneWidget);
    });

    testWidgets('muestra mensaje de cupón inválido (404)',
        (WidgetTester tester) async {
      await poderCanjear(
        tester,
        MockClient((request) async {
          return http.Response(
            '{"error": "Cupón no encontrado"}',
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(
        find.text('Cupón inválido: verifica el código del cliente'),
        findsOneWidget,
      );
    });

    testWidgets('muestra mensaje de cupón ya usado (422)',
        (WidgetTester tester) async {
      await poderCanjear(
        tester,
        MockClient((request) async {
          return http.Response(
            '{"error": "Cupon ya fue utilizado"}',
            422,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(find.text('El cupón ya fue usado'), findsOneWidget);
    });

    testWidgets('muestra mensaje de cupón de otro comercio (403)',
        (WidgetTester tester) async {
      await poderCanjear(
        tester,
        MockClient((request) async {
          return http.Response(
            '{"error": "No tienes permiso para canjear este cupón"}',
            403,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(
        find.text('Este cupón pertenece a otro comercio'),
        findsOneWidget,
      );
    });
  });
}

Comercio _comercioPrueba() {
  return Comercio(
    id: 1,
    nombre: 'Cafetería Central',
    categoria: 'Café',
  );
}