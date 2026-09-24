import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliente_app/screens/crear_evento_screen.dart';
import 'package:cliente_app/screens/cupon_consolacion_screen.dart';
import 'package:cliente_app/screens/organizador_home_screen.dart';
import 'package:cliente_app/screens/premios_screen.dart';
import 'package:cliente_app/screens/revision_entradas_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';
import 'package:cliente_app/services/comercios_service.dart';
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

  group('PremiosScreen', () {
    String bodyEvento() {
      return '{"evento": {"id": 1, "organizador_id": 7, '
          '"nombre": "Mi Hunt", '
          '"fecha_inicio": "2026-10-01 19:00:00", '
          '"fecha_fin": "2026-10-01 20:00:00"}, '
          '"premios": [{"id": 5, "evento_id": 1, '
          '"nombre": "Premio Mayor", "stock": 3, '
          '"tipo": "principal", "entregados": 1}], "rondas": [], '
          '"sponsors": []}';
    }

    testWidgets('muestra mensaje claro cuando no hay ganadores que entregar',
        (WidgetTester tester) async {
      final servicio = _servicioHuntCon(
        MockClient((request) async {
          if (request.url.path.endsWith('/ganadores')) {
            return http.Response(
              '{"ganadores": []}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            bodyEvento(),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PremiosScreen(
            eventoId: 1,
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Marcar como entregado'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Nadie ha reclamado este premio todavía'),
        findsOneWidget,
      );
    });

    testWidgets('entrega un premio a un ganador revocado y llama a /entregar',
        (WidgetTester tester) async {
      String? ruta;
      String? cuerpo;
      final servicio = _servicioHuntCon(
        MockClient((request) async {
          if (request.method == 'POST') {
            ruta = request.url.path;
            cuerpo = request.body;
            return http.Response(
              '{"mensaje": "Premio entregado"}',
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/ganadores')) {
            return http.Response(
              '{"ganadores": [{"id": 1, "premio_id": 5, '
              '"usuario_id": 9, "estado": "revocado", '
              '"usuario_nombre": "Luis Núñez", '
              '"usuario_email": "luis@test.com"}, '
              '{"id": 2, "premio_id": 5, '
              '"usuario_id": 3, "estado": "entregado", '
              '"usuario_nombre": "Ana López", '
              '"usuario_email": "ana@test.com"}]}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            bodyEvento(),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PremiosScreen(
            eventoId: 1,
            servicio: servicio,
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Marcar como entregado'));
      await tester.pumpAndSettle();

      expect(find.text('Entregado'), findsOneWidget);
      expect(find.text('Revocado'), findsOneWidget);

      await tester.tap(find.text('Entregar'));
      await tester.pumpAndSettle();

      expect(ruta, '/hunt/eventos/1/premios/5/entregar');
      expect(cuerpo, contains('"usuario_id":9'));
      expect(
        find.text('Premio marcado como entregado'),
        findsOneWidget,
      );
    });
  });

  group('CuponConsolacionScreen', () {
    Future<void> montarCon(WidgetTester tester, MockClient mock) async {
      final servicio = _servicioHuntCon(mock);
      final comercios = ComerciosService(
        api: ApiClient(baseUrl: 'http://test', httpClient: mock),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CuponConsolacionScreen(
            eventoId: 1,
            servicio: servicio,
            comerciosServicio: comercios,
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String bodyParticipantes() {
      return '{"participantes": ['
          '{"id": 3, "nombre_completo": "Ana López", '
          '"email": "ana@test.com"}, '
          '{"id": 4, "nombre_completo": "Luis Núñez", '
          '"email": "luis@test.com"}]}';
    }

    String bodyComercios() {
      return '{"comercios": [{"id": 1, "nombre": "Café Hunt"}]}';
    }

    testWidgets('muestra mensaje claro cuando no hay participantes sin premio',
        (WidgetTester tester) async {
      await montarCon(
        tester,
        MockClient((request) async {
          if (request.url.path.endsWith('/participantes-sin-premio')) {
            return http.Response(
              '{"participantes": []}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            bodyComercios(),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(
        find.text('Aún no hay participantes sin premio'),
        findsOneWidget,
      );
    });

    testWidgets('emite cupones hacia /cupones-consolacion con los seleccionados',
        (WidgetTester tester) async {
      String? ruta;
      String? cuerpo;
      final servicio = _servicioHuntCon(
        MockClient((request) async {
          if (request.method == 'POST') {
            ruta = request.url.path;
            cuerpo = request.body;
            return http.Response(
              '{"cupones_creados": 2, "expira_en": "2026-10-08 20:00:00"}',
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/participantes-sin-premio')) {
            return http.Response(
              bodyParticipantes(),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            bodyComercios(),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final comercios = ComerciosService(
        api: ApiClient(baseUrl: 'http://test', httpClient: MockClient(
          (request) async {
            return http.Response(
              bodyComercios(),
              200,
              headers: {'content-type': 'application/json'},
            );
          },
        )),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CuponConsolacionScreen(
            eventoId: 1,
            servicio: servicio,
            comerciosServicio: comercios,
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Ana López'));
      await tester.tap(find.text('Ana López'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Luis Núñez'));
      await tester.tap(find.text('Luis Núñez'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Descuento (%)'),
        '15',
      );
      await tester.ensureVisible(find.text('Emitir cupones'));
      await tester.tap(find.text('Emitir cupones'));
      await tester.pumpAndSettle();

      expect(ruta, '/hunt/eventos/1/cupones-consolacion');
      expect(cuerpo, contains('"comercio_id":1'));
      expect(cuerpo, contains('"usuario_ids":[3,4]'));
      expect(cuerpo, contains('"descuento":15'));
      expect(
        find.text('Cupones emitidos para 2 participante(s)'),
        findsOneWidget,
      );
    });
  });
}