import 'package:cliente_app/screens/flash_screen.dart';
import 'package:cliente_app/screens/home_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/comercios_service.dart';
import 'package:cliente_app/services/flash_service.dart';
import 'package:cliente_app/services/permiso_ubicacion_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Aviso de que hace falta ubicación. El texto es el de la fase 4, tal cual.
const _mensaje = 'Necesitamos tu ubicación para mostrarte lo que hay cerca';

Position _posicion({double lat = -0.1807, double lng = -78.4678}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// Cuenta cuántas veces se pidieron comercios, para comprobar que sin
/// ubicación no se pregunta la lista ni una vez.
class _Llamadas {
  int veces = 0;
}

/// Comercio de prueba, con coordenadas y sin coordenadas.
ComerciosService _comercios(_Llamadas llamadas, {bool conGps = true}) {
  return ComerciosService(
    api: ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((_) async {
        llamadas.veces++;
        return http.Response(
          conGps
              ? '{"comercios": [{"id": 1, "nombre": "Cafe"}, {"id": 2, '
                  '"nombre": "Farmacia"}], "cercanos": [{"id": 1, '
                  '"nombre": "Cafe"}], "categorias": ["Cafe"]}'
              : '{"comercios": [{"id": 1, "nombre": "Cafe"}], "cercanos": [], '
                  '"categorias": ["Cafe"]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
  );
}

/// Servicio de_flash que registra si le pidieron lista y con qué coordenadas.
class _FlashQueRegistra {
  int peticiones = 0;

  FlashService servicio() => FlashService(
        api: ApiClient(
          baseUrl: 'http://test',
          httpClient: MockClient((_) async {
            peticiones++;
            return http.Response(
              '{"promociones": [{"id": 1, "titulo": "2x1 en cafe"}]}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
}

void main() {
  group('Discover sin ubicación no muestra la lista', () {
    testWidgets('permiso denegado ofrece activar la ubicación y no lista',
        (tester) async {
      final llamadas = _Llamadas();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comercios(llamadas),
            permisoUbicacion: () async => ResultadoUbicacion.denegado,
            leerPosicion: () async => _posicion(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_mensaje), findsOneWidget);
      expect(find.text('Activar ubicación'), findsOneWidget);
      expect(find.text('Cafe'), findsNothing);
      expect(find.text('Farmacia'), findsNothing);
      expect(llamadas.veces, 0);
    });

    testWidgets('GPS apagado ofrece encender el GPS y no lista',
        (tester) async {
      final llamadas = _Llamadas();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comercios(llamadas),
            permisoUbicacion: () async => ResultadoUbicacion.sinPosicion,
            leerPosicion: () async => _posicion(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_mensaje), findsOneWidget);
      expect(find.text('Encender GPS'), findsOneWidget);
      expect(find.text('Activar ubicación'), findsNothing);
      expect(find.text('Abrir configuración'), findsNothing);
      expect(find.text('Cafe'), findsNothing);
      expect(llamadas.veces, 0);
    });

    testWidgets('permiso denegado para siempre ofrece abrir la configuración',
        (tester) async {
      final llamadas = _Llamadas();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comercios(llamadas),
            permisoUbicacion: () async => ResultadoUbicacion.denegadoPermanente,
            leerPosicion: () async => _posicion(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_mensaje), findsOneWidget);
      expect(find.text('Abrir configuración'), findsOneWidget);
      expect(find.text('Encender GPS'), findsNothing);
      expect(llamadas.veces, 0);
    });

    testWidgets('con permiso y posición sí lista los comercios', (tester) async {
      final llamadas = _Llamadas();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comercios(llamadas),
            permisoUbicacion: () async => ResultadoUbicacion.ok,
            leerPosicion: () async => _posicion(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_mensaje), findsNothing);
      expect(find.text('Cafe'), findsWidgets);
      expect(llamadas.veces, greaterThan(0));
    });

    testWidgets('el botón de activar ubicación vuelve a comprobar el permiso',
        (tester) async {
      var permisos = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comercios(_Llamadas()),
            permisoUbicacion: () async {
              permisos++;
              // La primera vez no hay permiso, la segunda ya sí.
              return permisos == 1
                  ? ResultadoUbicacion.denegado
                  : ResultadoUbicacion.ok;
            },
            leerPosicion: () async => _posicion(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(permisos, 1);

      await tester.tap(find.text('Activar ubicación'));
      await tester.pumpAndSettle();

      expect(permisos, 2);
      expect(find.text(_mensaje), findsNothing);
      expect(find.text('Cafe'), findsWidgets);
    });

    testWidgets('volver a la app recarga la lista si ya dieron permiso',
        (tester) async {
      final llamadas = _Llamadas();
      var permisoConcedido = false;

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comercios(llamadas),
            permisoUbicacion: () async => permisoConcedido
                ? ResultadoUbicacion.ok
                : ResultadoUbicacion.denegado,
            leerPosicion: () async => _posicion(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(_mensaje), findsOneWidget);
      expect(llamadas.veces, 0);

      // El usuario concede el permiso en los ajustes y vuelve a la app.
      permisoConcedido = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text(_mensaje), findsNothing);
      expect(find.text('Cafe'), findsWidgets);
      expect(llamadas.veces, greaterThan(0));
    });

    testWidgets('el GPS apagado abre los ajustes del dispositivo',
        (tester) async {
      var abrioGps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comercios(_Llamadas()),
            permisoUbicacion: () async => ResultadoUbicacion.sinPosicion,
            leerPosicion: () async => _posicion(),
            abrirGps: () async => abrioGps++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Encender GPS'));
      await tester.pumpAndSettle();

      expect(abrioGps, 1);
    });
  });

  group('Flash sin ubicación no pide la lista', () {
    testWidgets('GPS apagado avisa igual que un permiso denegado',
        (tester) async {
      final flash = _FlashQueRegistra();

      await tester.pumpWidget(
        MaterialApp(
          home: FlashScreen(
            servicio: flash.servicio(),
            permisoUbicacion: () async => ResultadoUbicacion.sinPosicion,
            leerPosicion: () async => _posicion(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_mensaje), findsOneWidget);
      expect(find.text('Encender GPS'), findsOneWidget);
      expect(flash.peticiones, 0);
    });

    testWidgets('sin posición obtenida no se llama a la lista', (tester) async {
      final flash = _FlashQueRegistra();

      await tester.pumpWidget(
        MaterialApp(
          home: FlashScreen(
            servicio: flash.servicio(),
            permisoUbicacion: () async => ResultadoUbicacion.ok,
            // El permiso está concedido pero el GPS no entrega posición.
            leerPosicion: () async => throw Exception('sin señal GPS'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_mensaje), findsOneWidget);
      expect(find.text('Encender GPS'), findsOneWidget);
      expect(flash.peticiones, 0);
    });

    testWidgets('con posición la lista se pide con esas coordenadas',
        (tester) async {
      final flash = _FlashQueRegistra();

      await tester.pumpWidget(
        MaterialApp(
          home: FlashScreen(
            servicio: flash.servicio(),
            permisoUbicacion: () async => ResultadoUbicacion.ok,
            leerPosicion: () async => _posicion(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_mensaje), findsNothing);
      expect(flash.peticiones, 1);
    });

    testWidgets('el aviso se ve aunque no haya promociones', (tester) async {
      final flash = _FlashQueRegistra();

      await tester.pumpWidget(
        MaterialApp(
          home: FlashScreen(
            servicio: flash.servicio(),
            permisoUbicacion: () async => ResultadoUbicacion.sinPosicion,
            leerPosicion: () async => _posicion(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // El aviso vive fuera de la lista, así que sigue visible con la lista
      // vacía, que es cuando antes desaparecía.
      expect(find.text(_mensaje), findsOneWidget);
      expect(find.text('No hay promociones flash activas'), findsOneWidget);
      expect(find.text('Encender GPS'), findsOneWidget);
    });
  });
}