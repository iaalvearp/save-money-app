import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliente_app/screens/comprobante_entrada_screen.dart';
import 'package:cliente_app/screens/hunt_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';
import 'package:cliente_app/services/hunt_service.dart';

class _FakeAuth extends AuthService {
  @override
  Future<String?> getAccessToken() async => 'token-de-prueba';

  @override
  Future<String?> rolActual() async => 'cliente';

  @override
  Future<int?> userId() async => 5;

  @override
  Future<void> logout() async {}
}

HuntService _servicioHuntCon(MockClient mock) {
  return HuntService(
    api: ApiClient(baseUrl: 'http://test', httpClient: mock),
  );
}

String _fechaActivaInicio() {
  final now = DateTime.now().subtract(const Duration(hours: 1));
  final s = now.toIso8601String().replaceFirst('T', ' ').substring(0, 19);
  return s;
}

String _fechaActivaFin() {
  final now = DateTime.now().add(const Duration(hours: 1));
  final s = now.toIso8601String().replaceFirst('T', ' ').substring(0, 19);
  return s;
}

String _bodyListaEventos() {
  return '{"eventos": [{"id": 1, "organizador_id": 7, '
      '"nombre": "Hunt Nocturno", '
      '"fecha_inicio": "${_fechaActivaInicio()}", '
      '"fecha_fin": "${_fechaActivaFin()}", '
      '"requiere_entrada": 1, "precio_entrada": 10.0, '
      '"organizador_nombre": "Casa Hunt"}]}';
}

String _bodyDetalleEvento() {
  return '{"evento": {"id": 1, "organizador_id": 7, '
      '"nombre": "Hunt Nocturno", '
      '"fecha_inicio": "${_fechaActivaInicio()}", '
      '"fecha_fin": "${_fechaActivaFin()}", '
      '"requiere_entrada": 1, "precio_entrada": 10.0, '
      '"organizador_nombre": "Casa Hunt"}, '
      '"premios": [{"id": 5, "evento_id": 1, '
      '"nombre": "Premio Mayor", "stock": 3, '
      '"tipo": "principal", "entregados": 1}], '
      '"rondas": [], "sponsors": []}';
}

String _bodyEntradaComprada() {
  return '{"entrada": {"id": 10, "evento_id": 1, '
      '"cliente_id": 5, "estado": "pendiente_pago", "monto": 10}}';
}

void main() {
  group('HuntScreen cliente - compra de entrada', () {
    testWidgets('compra una entrada y muestra su estado pendiente de pago',
        (WidgetTester tester) async {
      String? rutaComprar;
      final servicio = _servicioHuntCon(
        MockClient((request) async {
          if (request.url.path == '/hunt/eventos') {
            return http.Response(
              _bodyListaEventos(),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/entradas/comprar')) {
            rutaComprar = request.url.path;
            return http.Response(
              _bodyEntradaComprada(),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            _bodyDetalleEvento(),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HuntScreen(servicio: servicio, auth: _FakeAuth()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hunt Nocturno'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Comprar entrada - \$10.00'));
      await tester.tap(find.text('Comprar entrada - \$10.00'));
      await tester.pumpAndSettle();

      expect(rutaComprar, '/hunt/eventos/1/entradas/comprar');
      expect(find.text('Pendiente de pago'), findsOneWidget);
      expect(find.text('Subir comprobante de pago'), findsOneWidget);
    });

    testWidgets('muestra mensaje del backend si ya existe una entrada',
        (WidgetTester tester) async {
      final servicio = _servicioHuntCon(
        MockClient((request) async {
          if (request.url.path == '/hunt/eventos') {
            return http.Response(
              _bodyListaEventos(),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/entradas/comprar')) {
            return http.Response(
              '{"error": "Ya tienes una entrada con estado: aprobada"}',
              409,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            _bodyDetalleEvento(),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HuntScreen(servicio: servicio, auth: _FakeAuth()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hunt Nocturno'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Comprar entrada - \$10.00'));
      await tester.tap(find.text('Comprar entrada - \$10.00'));
      await tester.pumpAndSettle();

      expect(
        find.text('Ya tienes una entrada con estado: aprobada'),
        findsOneWidget,
      );
    });
  });

  group('ComprobanteEntradaScreen', () {
    const png1x1 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

    Future<void> montar(WidgetTester tester, MockClient mock) async {
      final servicio = _servicioHuntCon(mock);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ComprobanteEntradaScreen(
                      entradaId: 10,
                      servicio: servicio,
                      auth: _FakeAuth(),
                      picker: (source) async => base64Decode(png1x1),
                    ),
                  ),
                ),
                child: const Text('Abrir comprobante'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir comprobante'));
      await tester.pumpAndSettle();
    }

    testWidgets('envía la foto en base64 al subir el comprobante',
        (WidgetTester tester) async {
      String? ruta;
      String? cuerpo;
      final mock = MockClient((request) async {
        ruta = request.url.path;
        cuerpo = request.body;
        return http.Response(
          '{"mensaje": "Comprobante registrado"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await montar(tester, mock);

      await tester.tap(find.text('Elegir de galería'));
      await tester.pumpAndSettle();

      expect(find.text('Enviar comprobante'), findsOneWidget);

      await tester.tap(find.text('Enviar comprobante'));
      await tester.pumpAndSettle();

      expect(ruta, '/hunt/entradas/10/comprobante');
      expect(cuerpo, contains('"comprobante_foto":"$png1x1"'));
    });

    testWidgets('muestra el mensaje de error real del backend',
        (WidgetTester tester) async {
      String? ruta;
      final mock = MockClient((request) async {
        ruta = request.url.path;
        return http.Response(
          '{"error": "Entrada con estado: aprobada"}',
          422,
          headers: {'content-type': 'application/json'},
        );
      });

      await montar(tester, mock);

      await tester.tap(find.text('Elegir de galería'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar comprobante'));
      await tester.pumpAndSettle();

      expect(ruta, '/hunt/entradas/10/comprobante');
      expect(find.text('Entrada con estado: aprobada'), findsOneWidget);
    });
  });

  group('HuntScreen cliente - reclamo de premio', () {
    Future<void> irAlDetalle(WidgetTester tester, MockClient mock) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HuntScreen(
            servicio: _servicioHuntCon(mock),
            auth: _FakeAuth(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hunt Nocturno'));
      await tester.pumpAndSettle();
    }

    MockClient mockConReclamo({
      required http.Response Function(String ruta) responder,
      void Function(String ruta)? onReclamar,
    }) {
      return MockClient((request) async {
        if (request.url.path == '/hunt/eventos') {
          return http.Response(
            _bodyListaEventos(),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/reclamar')) {
          onReclamar?.call(request.url.path);
          return responder(request.url.path);
        }
        return http.Response(
          _bodyDetalleEvento(),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
    }

    testWidgets('reclama un premio y muestra los puntos ganados',
        (WidgetTester tester) async {
      String? ruta;
      final mock = mockConReclamo(
        onReclamar: (path) => ruta = path,
        responder: (ruta) => http.Response(
          '{"mensaje": "Premio \\"Premio Mayor\\" reclamado", '
          '"premio_id": 5, "puntos_ganados": 10}',
          201,
          headers: {'content-type': 'application/json'},
        ),
      );

      await irAlDetalle(tester, mock);

      expect(find.text('Hunt Nocturno'), findsWidgets);
      expect(find.text('Premio Mayor'), findsOneWidget);
      expect(find.text('Reclamar'), findsOneWidget);
      await tester.tap(find.text('Reclamar'));
      await tester.pumpAndSettle();

      expect(ruta, '/hunt/eventos/1/premios/5/reclamar');
      expect(find.text('Premio "Premio Mayor" reclamado · +10 puntos'),
          findsOneWidget);
    });

    testWidgets('muestra mensaje real cuando la ronda ya fue reclamada',
        (WidgetTester tester) async {
      final mock = mockConReclamo(
        responder: (ruta) => http.Response(
          '{"error": "Ya reclamaste un premio en esta ronda"}',
          409,
          headers: {'content-type': 'application/json'},
        ),
      );

      await irAlDetalle(tester, mock);
      await tester.tap(find.text('Reclamar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Ya reclamaste un premio en esta ronda'),
        findsOneWidget,
      );
    });

    testWidgets('muestra mensaje real fuera del horario del evento',
        (WidgetTester tester) async {
      final mock = mockConReclamo(
        responder: (ruta) => http.Response(
          '{"error": "Fuera del horario del evento"}',
          422,
          headers: {'content-type': 'application/json'},
        ),
      );

      await irAlDetalle(tester, mock);
      await tester.tap(find.text('Reclamar'));
      await tester.pumpAndSettle();

      expect(find.text('Fuera del horario del evento'), findsOneWidget);
    });

    testWidgets('muestra mensaje real si falta entrada aprobada',
        (WidgetTester tester) async {
      final mock = mockConReclamo(
        responder: (ruta) => http.Response(
          '{"error": "Se requiere una entrada aprobada para reclamar premios"}',
          403,
          headers: {'content-type': 'application/json'},
        ),
      );

      await irAlDetalle(tester, mock);
      await tester.tap(find.text('Reclamar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Se requiere una entrada aprobada para reclamar premios'),
        findsOneWidget,
      );
    });

    testWidgets('muestra mensaje real cuando no queda stock',
        (WidgetTester tester) async {
      final mock = mockConReclamo(
        responder: (ruta) => http.Response(
          '{"error": "Premio sin stock disponible"}',
          422,
          headers: {'content-type': 'application/json'},
        ),
      );

      await irAlDetalle(tester, mock);
      await tester.tap(find.text('Reclamar'));
      await tester.pumpAndSettle();

      expect(find.text('Premio sin stock disponible'), findsOneWidget);
    });
  });
}