import 'package:cliente_app/screens/flash_screen.dart';
import 'package:cliente_app/services/notificaciones_service.dart';
import 'package:cliente_app/services/permiso_ubicacion_service.dart';
import 'package:cliente_app/widgets/reporte_ubicacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('Flash pide su propio permiso de ubicación', () {
    testWidgets('un permiso denegado muestra el mensaje de activarlo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FlashScreen(
            permisoUbicacion: _denegar,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Activa tu ubicación para ver promociones cercanas'),
        findsOneWidget,
      );
    });

    testWidgets('un permiso denegado para siempre ofrece abrir la configuración', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FlashScreen(
            permisoUbicacion: _denegarParaSiempre,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Abrir configuración'), findsOneWidget);
      expect(find.text('Activa tu ubicación para ver promociones cercanas'),
          findsNothing);
    });

    testWidgets('con permiso concedido no se muestra ningún aviso', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FlashScreen(
            permisoUbicacion: _conceder,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Abrir configuración'), findsNothing);
      expect(
        find.text('Activa tu ubicación para ver promociones cercanas'),
        findsNothing,
      );
    });

    testWidgets('volver a pulsar reintentar vuelve a pedir el permiso', (tester) async {
      var llamadas = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FlashScreen(
            permisoUbicacion: () async {
              llamadas++;
              return ResultadoUbicacion.denegado;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(llamadas, 1);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(llamadas, 2);
    });
  });

  group('Reporte de ubicación no molesta sin permiso', () {
    testWidgets('no pide posición ni lanza excepción si falta el permiso', (tester) async {
      var pidioPosicion = false;

      await tester.pumpWidget(
        MaterialApp(
          home: ReporteUbicacion(
            comprobarPermiso: () async => ResultadoUbicacion.denegado,
            leerPosicion: () async {
              pidioPosicion = true;
              return Position(latitude: 0, longitude: 0, timestamp: DateTime.now(), accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
            },
            child: const Text('app'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(pidioPosicion, isFalse);
      expect(find.text('app'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un permiso denegado para siempre tampoco pide posición', (tester) async {
      var pidioPosicion = false;

      await tester.pumpWidget(
        MaterialApp(
          home: ReporteUbicacion(
            comprobarPermiso: () async => ResultadoUbicacion.denegadoPermanente,
            leerPosicion: () async {
              pidioPosicion = true;
              return Position(latitude: 0, longitude: 0, timestamp: DateTime.now(), accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
            },
            child: const Text('app'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(pidioPosicion, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con permiso concedido sí lee la posición y la reporta', (tester) async {
      final reportados = <double>[];
      var pidioPosicion = false;

      await tester.pumpWidget(
        MaterialApp(
          home: ReporteUbicacion(
            comprobarPermiso: () async => ResultadoUbicacion.ok,
            leerPosicion: () async {
              pidioPosicion = true;
              return Position(latitude: 40.4, longitude: -3.7, timestamp: DateTime.now(), accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
            },
            servicio: _NotificacionesFalsa(
              onUbicacion: (lat, lng) => reportados.add(lat),
            ),
            child: const Text('app'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(pidioPosicion, isTrue);
      expect(reportados, [40.4]);
    });
  });
}

Future<ResultadoUbicacion> _conceder() async => ResultadoUbicacion.ok;
Future<ResultadoUbicacion> _denegar() async => ResultadoUbicacion.denegado;
Future<ResultadoUbicacion> _denegarParaSiempre() async =>
    ResultadoUbicacion.denegadoPermanente;

/// NotificacionesService con la llamada de reporte sustituida por un callback.
class _NotificacionesFalsa extends NotificacionesService {
  final void Function(double lat, double lng) onUbicacion;

  _NotificacionesFalsa({required this.onUbicacion});

  @override
  Future<void> reportarUbicacion({
    required double latitude,
    required double longitude,
  }) async {
    onUbicacion(latitude, longitude);
  }
}
