import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliente_app/screens/comercio_detail_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/comercios_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Lanzador simulado: guarda a donde se intento abrir y con que modo.
class _LanzadorSimulado {
  _LanzadorSimulado(this.responde);

  /// Lo que contesta el sistema: si se pudo abrir o no.
  final bool responde;
  final List<Uri> abiertas = [];
  final List<LaunchMode> modos = [];

  /// Si alguna vez se le pregunta con `canLaunchUrl` antes de abrir.
  int preguntasCanLaunchUrl = 0;

  Future<bool> abrir(Uri url, LaunchMode modo) async {
    abiertas.add(url);
    modos.add(modo);
    return responde;
  }
}

ComerciosService _servicio(double lat, double lng) {
  return ComerciosService(
    api: ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient(
        (_) async => http.Response(
          '{"comercio": {"id": 1, "nombre": "Cafe", "latitud": $lat, '
          '"longitud": $lng}, "promociones": []}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    ),
  );
}

void main() {
  group('Como llegar', () {
    late _LanzadorSimulado lanzador;

    Future<void> abrirBoton(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ComercioDetailScreen(
            comercioId: 1,
            servicio: _servicio(-0.1807, -78.4678),
            abrirUrl: lanzador.abrir,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cómo llegar'));
      await tester.pumpAndSettle();
    }

    testWidgets('abre la direccion en una app externa', (tester) async {
      lanzador = _LanzadorSimulado(true);

      await abrirBoton(tester);

      expect(lanzador.abiertas, hasLength(1));
      final url = lanzador.abiertas.single;
      expect(url.host, 'www.google.com');
      expect(url.path, '/maps/dir/');
      expect(url.queryParameters['api'], '1');
      expect(url.queryParameters['destination'], '-0.1807,-78.4678');
      expect(lanzador.modos.single, LaunchMode.externalApplication);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('si no se pudo abrir, avisa que no hay app de mapas',
        (tester) async {
      lanzador = _LanzadorSimulado(false);

      await abrirBoton(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('No se encontró una app de mapas'), findsOneWidget);

      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('el boton se dibuja con altura minima de 52 y radio 8',
        (tester) async {
      lanzador = _LanzadorSimulado(true);

      await tester.pumpWidget(
        MaterialApp(
          home: ComercioDetailScreen(
            comercioId: 1,
            servicio: _servicio(-0.1807, -78.4678),
            abrirUrl: lanzador.abrir,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boton = find.widgetWithText(ElevatedButton, 'Cómo llegar');
      expect(boton, findsOneWidget);
      expect(tester.getSize(boton).height, greaterThanOrEqualTo(52));

      final style = tester.widget<ElevatedButton>(boton).style!;
      final forma = style.shape!.resolve(const <WidgetState>{})!;
      expect(forma, isA<RoundedRectangleBorder>());
      expect(
        (forma as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(8),
      );
    });

    testWidgets('sin coordenadas no hay boton que abrir', (tester) async {
      lanzador = _LanzadorSimulado(true);

      await tester.pumpWidget(
        MaterialApp(
          home: ComercioDetailScreen(
            comercioId: 1,
            abrirUrl: lanzador.abrir,
            servicio: ComerciosService(
              api: ApiClient(
                baseUrl: 'http://test',
                httpClient: MockClient(
                  (_) async => http.Response(
                    '{"comercio": {"id": 1, "nombre": "Cafe sin gps"}, '
                    '"promociones": []}',
                    200,
                    headers: {'content-type': 'application/json'},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cómo llegar'), findsNothing);
      expect(find.text('Sin ubicación registrada'), findsOneWidget);
      expect(lanzador.abiertas, isEmpty);
    });
  });
}
