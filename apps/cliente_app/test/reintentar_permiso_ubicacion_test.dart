import 'package:cliente_app/screens/flash_screen.dart';
import 'package:cliente_app/screens/home_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/comercios_service.dart';
import 'package:cliente_app/services/flash_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Estos casos no inyectan el permiso: hablan con geolocator como lo haria el
/// telefono. Asi se comprueba que el boton vuelve a preguntar al sistema y no
/// se limita a abrir Ajustes, que es justo lo que hacia mal.
///
/// En una prueba de widget no se registra el plugin, asi que geolocator usa su
/// implementacion de canal generico y no la de Android. Se simulan los dos
/// canales para que el caso sirva igual si algun dia corre en un equipo con el
/// registrant activo.
const _canales = [
  MethodChannel('flutter.baseflow.com/geolocator'),
  MethodChannel('flutter.baseflow.com/geolocator_android'),
];

/// Abrir Ajustes lo hace permission_handler, el mismo que usa la cámara.
const _canalAjustes = MethodChannel('flutter.baseflow.com/permissions/methods');

/// Valores que el plugin devuelve como enteros.
const _denegado = 0;
const _denegadoParaSiempre = 1;
const _concedido = 2;

/// Registro de lo que se le pide al sistema.
class _LlamadasAlSistema {
  int solicitudes = 0;
  int consultas = 0;
  int aperturasDeAjustes = 0;
  int aperturasDeGps = 0;

  /// [permisoTrasSolicitar] permite reproducir la denial de verdad: la primera
  /// vez se rechaza sin querer y la segunda Android ya la da por definitiva.
  void instalar({
    required bool gpsEncendido,
    required int permiso,
    int? permisoTrasSolicitar,
  }) {
    Future<Object?> responder(MethodCall call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return gpsEncendido;
        case 'checkPermission':
          consultas++;
          return permiso;
        case 'requestPermission':
          // Cada llamada es un dialogo nativo nuevo.
          solicitudes++;
          return solicitudes == 1 ? permiso : (permisoTrasSolicitar ?? permiso);
        case 'openAppSettings':
          aperturasDeAjustes++;
          return true;
        case 'openLocationSettings':
          aperturasDeGps++;
          return true;
        default:
          return null;
      }
    }

    for (final canal in _canales) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, responder);
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalAjustes, (call) async {
          if (call.method == 'openAppSettings') {
            aperturasDeAjustes++;
            return true;
          }
          if (call.method == 'openLocationSettings') {
            aperturasDeGps++;
            return true;
          }
          return null;
        });
  }

  void desinstalar() {
    for (final canal in [..._canales, _canalAjustes]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, null);
    }
  }
}

ComerciosService _comerciosVacio() => ComerciosService(
  api: ApiClient(
    baseUrl: 'http://test',
    httpClient: MockClient(
      (_) async => http.Response(
        '{"comercios": [], "cercanos": [], "categorias": []}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
  ),
);

FlashService _flashVacio() => FlashService(
  api: ApiClient(
    baseUrl: 'http://test',
    httpClient: MockClient(
      (_) async => http.Response(
        '{"promociones": []}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _LlamadasAlSistema sistema;

  // El servicio lleva la cuenta de cuántos intentos lleva en el dispositivo, así
  // que cada caso arranca en cero: si no, el contador de uno se colaría al
  // siguiente y el botón cambiaría de texto sin que nadie lo tocara.
  setUp(() {
    sistema = _LlamadasAlSistema();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => sistema.desinstalar());

  group('Permiso denegado sin querer: se vuelve a preguntar', () {
    testWidgets('Discover: tocar el botón pide el permiso otra vez', (
      tester,
    ) async {
      sistema.instalar(gpsEncendido: true, permiso: _denegado);

      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(servicio: _comerciosVacio())),
      );
      await tester.pumpAndSettle();

      // La primera vez, al abrir la pantalla.
      expect(sistema.solicitudes, 1);
      expect(find.text('Activar ubicación'), findsOneWidget);
      expect(find.text('Abrir configuración'), findsNothing);

      await tester.tap(find.text('Activar ubicación'));
      await tester.pumpAndSettle();

      // La clave: una peticion nueva al sistema, no un salto a Ajustes.
      expect(sistema.solicitudes, 2);
      expect(sistema.aperturasDeAjustes, 0);
    });

    testWidgets('Flash: tocar el botón pide el permiso otra vez', (
      tester,
    ) async {
      sistema.instalar(gpsEncendido: true, permiso: _denegado);

      await tester.pumpWidget(
        MaterialApp(home: FlashScreen(servicio: _flashVacio())),
      );
      await tester.pumpAndSettle();

      expect(sistema.solicitudes, 1);
      expect(find.text('Activar ubicación'), findsOneWidget);

      await tester.tap(find.text('Activar ubicación'));
      await tester.pumpAndSettle();

      expect(sistema.solicitudes, 2);
      expect(sistema.aperturasDeAjustes, 0);
    });
  });

  group('El segundo rechazo es el que manda a Ajustes', () {
    testWidgets('Discover: reintentar sin querer y acabar en configuración', (
      tester,
    ) async {
      sistema.instalar(
        gpsEncendido: true,
        permiso: _denegado,
        permisoTrasSolicitar: _denegadoParaSiempre,
      );

      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(servicio: _comerciosVacio())),
      );
      await tester.pumpAndSettle();

      // Tras el primer rechazo se puede volver a preguntar.
      expect(find.text('Activar ubicación'), findsOneWidget);
      expect(sistema.solicitudes, 1);

      await tester.tap(find.text('Activar ubicación'));
      await tester.pumpAndSettle();

      // El usuario vuelve a decir que no. Ahora si, y solo ahora, Ajustes.
      expect(sistema.solicitudes, 2);
      expect(sistema.aperturasDeAjustes, 0);
      expect(find.text('Abrir configuración'), findsOneWidget);
      expect(find.text('Activar ubicación'), findsNothing);
    });

    testWidgets('Flash: reintentar sin querer y acabar en configuración', (
      tester,
    ) async {
      sistema.instalar(
        gpsEncendido: true,
        permiso: _denegado,
        permisoTrasSolicitar: _denegadoParaSiempre,
      );

      await tester.pumpWidget(
        MaterialApp(home: FlashScreen(servicio: _flashVacio())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Activar ubicación'), findsOneWidget);

      await tester.tap(find.text('Activar ubicación'));
      await tester.pumpAndSettle();

      expect(find.text('Abrir configuración'), findsOneWidget);
      expect(sistema.solicitudes, 2);
    });
  });

  group('Permiso denegado para siempre: solo Ajustes', () {
    testWidgets('Discover: el botón abre la configuración', (tester) async {
      sistema.instalar(gpsEncendido: true, permiso: _denegadoParaSiempre);

      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(servicio: _comerciosVacio())),
      );
      await tester.pumpAndSettle();

      // El sistema no vuelve a preguntar cuando ya se le dijo que no siempre.
      expect(sistema.solicitudes, 0);
      expect(find.text('Abrir configuración'), findsOneWidget);
      expect(find.text('Activar ubicación'), findsNothing);

      await tester.tap(find.text('Abrir configuración'));
      await tester.pumpAndSettle();

      expect(sistema.aperturasDeAjustes, 1);
      // Y al volver se vuelve a comprobar, sin volver a molestar.
      expect(sistema.solicitudes, 0);
    });

    testWidgets('Flash: el botón abre la configuración', (tester) async {
      sistema.instalar(gpsEncendido: true, permiso: _denegadoParaSiempre);

      await tester.pumpWidget(
        MaterialApp(home: FlashScreen(servicio: _flashVacio())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Abrir configuración'), findsOneWidget);

      await tester.tap(find.text('Abrir configuración'));
      await tester.pumpAndSettle();

      expect(sistema.aperturasDeAjustes, 1);
    });
  });

  group('GPS apagado: los ajustes de ubicación, no los de la app', () {
    testWidgets('Discover: enciende el GPS sin pedir el permiso', (
      tester,
    ) async {
      sistema.instalar(gpsEncendido: false, permiso: _concedido);

      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(servicio: _comerciosVacio())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Encender GPS'), findsOneWidget);

      await tester.tap(find.text('Encender GPS'));
      await tester.pumpAndSettle();

      expect(sistema.aperturasDeGps, 1);
      expect(sistema.aperturasDeAjustes, 0);
      expect(sistema.solicitudes, 0);
    });
  });
}
