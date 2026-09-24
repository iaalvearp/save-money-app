import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliente_app/screens/crear_evento_screen.dart';
import 'package:cliente_app/screens/organizador_home_screen.dart';
import 'package:cliente_app/screens/revision_entradas_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';
import 'package:cliente_app/services/hunt_service.dart';

class _FakeAuth extends AuthService {
  @override
  Future<String?> getAccessToken() async => 'token-de-prueba';

  @override
  Future<String?> rolActual() async => 'organizador';

  @override
  Future<int?> userId() async => 7;

  @override
  Future<void> logout() async {}
}

HuntService _servicioHuntCon(MockClient mock) {
  return HuntService(
    api: ApiClient(baseUrl: 'http://test', httpClient: mock),
  );
}

void main() {
  group('CrearEventoScreen', () {
    Future<void> llenarInicioYFin(WidgetTester tester) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Hunt nocturno',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Fecha/hora de inicio'),
        '2026-10-01 19:00:00',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Fecha/hora de fin'),
        '2026-10-01 20:00:00',
      );
    }

    testWidgets('valida fecha de fin anterior al inicio antes de enviar',
        (WidgetTester tester) async {
      var peticiones = 0;
      final servicio = _servicioHuntCon(
        MockClient((request) async {
          peticiones++;
          return http.Response('{"error": "no"}', 400,
              headers: {'content-type': 'application/json'});
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CrearEventoScreen(
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Hunt nocturno',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Fecha/hora de inicio'),
        '2026-10-01 20:00:00',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Fecha/hora de fin'),
        '2026-10-01 19:00:00',
      );
      await tester.ensureVisible(find.text('Crear evento'));
      await tester.tap(find.text('Crear evento'));
      await tester.pumpAndSettle();

      expect(
        find.text('La fecha de fin debe ser posterior al inicio'),
        findsOneWidget,
      );
      expect(peticiones, 0);
    });

    testWidgets('envía datos válidos al crear el evento',
        (WidgetTester tester) async {
      String? cuerpoEnviado;
      String? ruta;
      final servicio = _servicioHuntCon(
        MockClient((request) async {
          ruta = request.url.path;
          cuerpoEnviado = request.body;
          return http.Response(
            '{"evento": {"id": 1, "organizador_id": 7, '
            '"nombre": "Hunt nocturno", '
            '"fecha_inicio": "2026-10-01 19:00:00", '
            '"fecha_fin": "2026-10-01 20:00:00"}}',
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CrearEventoScreen(
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );

      await llenarInicioYFin(tester);
      await tester.ensureVisible(find.text('Crear evento'));
      await tester.tap(find.text('Crear evento'));
      await tester.pumpAndSettle();

      expect(ruta, '/hunt/eventos');
      expect(cuerpoEnviado, contains('"nombre":"Hunt nocturno"'));
      expect(cuerpoEnviado, contains('"fecha_inicio":"2026-10-01 19:00:00"'));
      expect(cuerpoEnviado, contains('"fecha_fin":"2026-10-01 20:00:00"'));
    });
  });

  group('OrganizadorHomeScreen', () {
    testWidgets('muestra estado vacío cuando no hay eventos propios',
        (WidgetTester tester) async {
      final servicio = _servicioHuntCon(
        MockClient((request) async {
          return http.Response(
            '{"eventos": [{"id": 99, "organizador_id": 1, '
            '"nombre": "De otro organizador", '
            '"fecha_inicio": "2026-10-01 19:00:00", '
            '"fecha_fin": "2026-10-01 20:00:00"}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OrganizadorHomeScreen(
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aún no creas eventos de búsqueda'), findsOneWidget);
      expect(find.text('Crear evento'), findsOneWidget);
      expect(find.text('De otro organizador'), findsNothing);
    });

    testWidgets('lista solo los eventos del organizador autenticado',
        (WidgetTester tester) async {
      final servicio = _servicioHuntCon(
        MockClient((request) async {
          return http.Response(
            '{"eventos": [{"id": 1, "organizador_id": 7, '
            '"nombre": "Mi Hunt", '
            '"fecha_inicio": "2026-10-01 19:00:00", '
            '"fecha_fin": "2026-10-01 20:00:00"}, '
            '{"id": 2, "organizador_id": 3, '
            '"nombre": "Hunt ajeno", '
            '"fecha_inicio": "2026-10-01 19:00:00", '
            '"fecha_fin": "2026-10-01 20:00:00"}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OrganizadorHomeScreen(
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mi Hunt'), findsOneWidget);
      expect(find.text('Hunt ajeno'), findsNothing);
    });
  });

  group('RevisionEntradasScreen', () {
    Future<void> montarCon(WidgetTester tester, MockClient mock) async {
      final servicio = _servicioHuntCon(mock);
      await tester.pumpWidget(
        MaterialApp(
          home: RevisionEntradasScreen(
            eventoId: 1,
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String bodyEntradas({String estado = 'pendiente_revision_comprobante'}) {
      return '{"entradas": [{"id": 10, "evento_id": 1, '
          '"cliente_id": 5, "estado": "$estado", "monto": 10, '
          '"comprobante_foto": "https://ejemplo.com/comprobante.jpg", '
          '"cliente_nombre": "Ana López", "cliente_email": "ana@test.com"}]}';
    }

    testWidgets('lista entradas pendientes con comprobante',
        (WidgetTester tester) async {
      await montarCon(
        tester,
        MockClient((request) async {
          return http.Response(
            bodyEntradas(),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(find.text('Ana López'), findsNWidgets(2));
      expect(find.text('\$10.00'), findsOneWidget);
      expect(find.text('Aprobar'), findsOneWidget);
      expect(find.text('Rechazar'), findsOneWidget);
    });

    testWidgets('aprueba una entrada pendiente y la mueve al historial',
        (WidgetTester tester) async {
      String? ruta;
      var podreSetearAprobada = false;
      final servicio = _servicioHuntCon(
        MockClient((request) async {
          if (request.method == 'POST') {
            ruta = request.url.path;
            return http.Response(
              '{"mensaje": "Entrada aprobada"}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          var estado = 'pendiente_revision_comprobante';
          if (podreSetearAprobada) estado = 'aprobada';
          return http.Response(
            bodyEntradas(estado: estado),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RevisionEntradasScreen(
            eventoId: 1,
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      podreSetearAprobada = true;
      await tester.tap(find.text('Aprobar'));
      await tester.pumpAndSettle();

      expect(ruta, '/hunt/entradas/10/revisar');
      expect(find.text('Aprobada'), findsOneWidget);
    });

    testWidgets('rechaza una entrada pendiente',
        (WidgetTester tester) async {
      String? ruta;
      String? cuerpo;
      var podreSetearRechazada = false;
      final servicio = _servicioHuntCon(
        MockClient((request) async {
          if (request.method == 'POST') {
            ruta = request.url.path;
            cuerpo = request.body;
            return http.Response(
              '{"mensaje": "Entrada rechazada"}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          var estado = 'pendiente_revision_comprobante';
          if (podreSetearRechazada) estado = 'rechazada';
          return http.Response(
            bodyEntradas(estado: estado),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RevisionEntradasScreen(
            eventoId: 1,
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      podreSetearRechazada = true;
      await tester.tap(find.text('Rechazar'));
      await tester.pumpAndSettle();

      expect(ruta, '/hunt/entradas/10/revisar');
      expect(cuerpo, contains('"aprueba":false'));
      expect(find.text('Rechazada'), findsOneWidget);
    });

    testWidgets('usa Image.memory para comprobantes en base64',
        (WidgetTester tester) async {
      final base64 = 'iVBORw0KGgoAAAANSUhEUg==';
      final servicio = _servicioHuntCon(
        MockClient((request) async {
          return http.Response(
            '{"entradas": [{"id": 10, "evento_id": 1, '
            '"cliente_id": 5, "estado": "pendiente_revision_comprobante", '
            '"comprobante_foto": "$base64", '
            '"cliente_nombre": "Ana López"}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RevisionEntradasScreen(
            eventoId: 1,
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sin comprobante'), findsNothing);
    });
  });
}