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

  group('HuntScreen cliente - progreso de premios por frecuencia', () {
    String bodyDetalleConFrecuencia() {
      return '{"evento": {"id": 1, "organizador_id": 7, '
          '"nombre": "Hunt Nocturno", '
          '"fecha_inicio": "${_fechaActivaInicio()}", '
          '"fecha_fin": "${_fechaActivaFin()}", '
          '"requiere_entrada": 0, '
          '"organizador_nombre": "Casa Hunt"}, '
          '"premios": [{"id": 7, "evento_id": 1, '
          '"nombre": "Combo del mes", "stock": 10, '
          '"tipo": "frecuencia", "criterio_frecuencia": 5, "entregados": 0}], '
          '"rondas": [], "sponsors": []}';
    }

    String bodyProgreso({
      int compras = 2,
      int criterio = 5,
      bool cumple = false,
      int sinFechaLegible = 0,
    }) {
      return '{"premio_id": 7, "nombre": "Combo del mes", '
          '"compras": $compras, "criterio": $criterio, '
          '"faltan": ${criterio - compras}, '
          '"cumple": $cumple, '
          '"ventana": "evento (2026-09-01 08:00:00 a 2026-09-30 20:00:00)", '
          '"sin_fecha_legible": $sinFechaLegible}';
    }

    /// Monta la pantalla con un evento que tiene un premio por frecuencia y
    /// deja que responderProgresso decida que contesta el backend al pedir el
    /// progreso.
    Future<List<String>> irAlDetalleConFrecuencia(
      WidgetTester tester,
      http.Response Function(String ruta) responderProgresso,
    ) async {
      final rutasProgreso = <String>[];

      final mock = MockClient((request) async {
        final ruta = request.url.path;
        if (ruta == '/hunt/eventos') {
          return http.Response(
            _bodyListaEventos(),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (ruta.endsWith('/progreso')) {
          rutasProgreso.add(ruta);
          return responderProgresso(ruta);
        }
        return http.Response(
          bodyDetalleConFrecuencia(),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

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

      return rutasProgreso;
    }

    FilledButton botonReclamar(WidgetTester tester) {
      return tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Reclamar'),
      );
    }

    testWidgets('muestra cuantas compras faltan y bloquea el reclamo',
        (WidgetTester tester) async {
      final rutas = await irAlDetalleConFrecuencia(
        tester,
        (_) => http.Response(
          bodyProgreso(),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(rutas, ['/hunt/eventos/1/premios/7/progreso']);
      expect(find.text('Llevas 2 de 5 compras'), findsOneWidget);
      expect(
        find.text(
            'Cuentan compras de: evento (2026-09-01 08:00:00 a 2026-09-30 20:00:00)'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Todavia no cumple, asi que no se puede reclamar todavia.
      expect(botonReclamar(tester).onPressed, isNull);
    });

    testWidgets('deja reclamar cuando ya cumple el criterio',
        (WidgetTester tester) async {
      await irAlDetalleConFrecuencia(
        tester,
        (_) => http.Response(
          bodyProgreso(compras: 5, cumple: true),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(find.text('Llevas 5 de 5 compras'), findsOneWidget);
      expect(botonReclamar(tester).onPressed, isNotNull);
    });

    testWidgets('avisa cuantas facturas quedaron fuera por fecha ilegible',
        (WidgetTester tester) async {
      await irAlDetalleConFrecuencia(
        tester,
        (_) => http.Response(
          bodyProgreso(sinFechaLegible: 2),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(
        find.text(
            '2 factura(s) no se contaron porque no se pudo leer su fecha.'),
        findsOneWidget,
      );
    });

    testWidgets('si el progreso no se puede cargar, no muestra barra y deja '
        'reclamar', (WidgetTester tester) async {
      await irAlDetalleConFrecuencia(
        tester,
        (_) => http.Response(
          '{"error": "Este premio no tiene un criterio de frecuencia '
          'configurado, asi que no se puede calcular el progreso"}',
          422,
          headers: {'content-type': 'application/json'},
        ),
      );

      // El evento se sigue viendo igual, solo que sin barra.
      expect(find.text('Combo del mes'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('Llevas'), findsNothing);

      // Y se puede reclamar: el backend valida al reclamar.
      expect(botonReclamar(tester).onPressed, isNotNull);
    });

    testWidgets('no pregunta el progreso de los premios que no son por '
        'frecuencia', (WidgetTester tester) async {
      final rutas = <String>[];

      final mock = MockClient((request) async {
        final ruta = request.url.path;
        if (ruta == '/hunt/eventos') {
          return http.Response(
            _bodyListaEventos(),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (ruta.endsWith('/progreso')) {
          rutas.add(ruta);
          return http.Response(bodyProgreso(), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response(
          _bodyDetalleEvento(),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

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

      // El premio de prueba es de tipo principal: no se le pregunta nada y se
      // sigue viendo igual que antes.
      expect(rutas, isEmpty);
      expect(find.text('Premio Mayor'), findsOneWidget);
      expect(find.text('Stock: 2/3'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(botonReclamar(tester).onPressed, isNotNull);
    });
  });
}