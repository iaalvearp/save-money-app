import 'package:cliente_app/screens/flash_screen.dart';
import 'package:cliente_app/screens/home_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/comercios_service.dart';
import 'package:cliente_app/services/flash_service.dart';
import 'package:cliente_app/services/permiso_ubicacion_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mocks_geolocator.dart';

/// Estos casos hablan con geolocator y con el almacenamiento del dispositivo como
/// lo harían en el teléfono, sin inyectar el permiso: lo que se comprueba es la
/// decisión de la app, no una costura.
///
/// El sistema de aquí se deja en `denied` a propósito y para siempre, que es
/// justo lo que hace Android cuando alguien marca "no volver a preguntar": no
/// pasa a `deniedForever` y sigue admitiendo que se le pregunte. Con el sistema
/// diciendo siempre que sí se puede preguntar, la app era la que tenía que
/// notar que ya no debía hacerlo.

ComerciosService _comerciosCon(String respuesta) => ComerciosService(
  api: ApiClient(
    baseUrl: 'http://test',
    httpClient: MockClient(
      (_) async => http.Response(
        respuesta,
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

/// Simula que la app se va a segundo plano y vuelve.
///
/// No basta con saltar de `resumed` a `paused`: Flutter comprueba que la
/// transición sea posible y hay que pasar por los estados intermedios, que es
/// justo el camino que hace el sistema cuando la app pierde el foco.
Future<void> _vaASegundoPlanoYVuelve(WidgetTester tester) async {
  const ida = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const vuelta = [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  for (final estado in [...ida, ...vuelta]) {
    tester.binding.handleAppLifecycleStateChanged(estado);
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LlamadasAlSistema sistema;

  setUp(() {
    // La cuenta de intentos vive en el dispositivo, así que cada caso empieza
    // de cero. Sin esto, el contador se cuela de un caso al siguiente y el botón
    // cambia de texto sin que nadie lo haya tocado.
    SharedPreferences.setMockInitialValues({});
    sistema = LlamadasAlSistema();
    // GPS encendido y permiso denegado, y el sistema no cambia nunca de opinión.
    sistema.instalar(
      gpsEncendido: true,
      permiso: denegado,
      siempreDeniega: true,
    );
  });

  tearDown(() => sistema.desinstalar());

  group('Bug 1: dos negativas bastan para ofrecer los ajustes', () {
    testWidgets('Discover: sin llegar nunca a "denegado para siempre"', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comerciosCon(
              '{"comercios": [], "cercanos": [], "categorias": []}',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Primer intento, al abrir la pantalla.
      expect(sistema.solicitudes, 1);
      expect(find.text('Activar ubicación'), findsOneWidget);

      await tester.tap(find.text('Activar ubicación'));
      await tester.pumpAndSettle();

      // La clave: el sistema sigue diciendo "denegado" y la app lo tiene en
      // cuenta. Si solo mirara lo que dice el sistema, seguiría ofrecer un
      // botón que no vuelve a hacer nada.
      expect(sistema.solicitudes, 2);
      expect(find.text('Activar ubicación'), findsNothing);
      expect(find.text('Abrir configuración'), findsOneWidget);
    });

    testWidgets('Flash: igual, con el mismo permiso del sistema', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: FlashScreen(servicio: _flashVacio())),
      );
      await tester.pumpAndSettle();

      expect(sistema.solicitudes, 1);
      expect(find.text('Activar ubicación'), findsOneWidget);

      await tester.tap(find.text('Activar ubicación'));
      await tester.pumpAndSettle();

      expect(sistema.solicitudes, 2);
      expect(find.text('Abrir configuración'), findsOneWidget);
    });

    testWidgets('la cuenta es del sistema, no de cada pantalla', (
      tester,
    ) async {
      // Dos rechazos en Discover y uno en Flash: en total tres, pero el permiso
      // es el mismo y ya está agotado. Con una cuenta por pantalla, en Flash
      // seguiríavuciendo a preguntar.
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comerciosCon(
              '{"comercios": [], "cercanos": [], "categorias": []}',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activar ubicación'));
      await tester.pumpAndSettle();
      expect(find.text('Abrir configuración'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(home: FlashScreen(servicio: _flashVacio())),
      );
      await tester.pumpAndSettle();

      expect(sistema.solicitudes, 2);
      expect(find.text('Abrir configuración'), findsOneWidget);
    });

    testWidgets('el botón ofrece los ajustes y no otro diálogo', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comerciosCon(
              '{"comercios": [], "cercanos": [], "categorias": []}',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activar ubicación'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir configuración'));
      await tester.pumpAndSettle();

      // Ni un diálogo más: eso era justo lo que no ocurría antes.
      expect(sistema.aperturasDeAjustes, 1);
      expect(sistema.solicitudes, 2);
    });

    testWidgets('con los intentos agotados no se vuelve a preguntar', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comerciosCon(
              '{"comercios": [], "cercanos": [], "categorias": []}',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activar ubicación'));
      await tester.pumpAndSettle();
      expect(sistema.solicitudes, 2);

      // Volver a abrir la pantalla es un caso normal, no una razón para
      // enseñar otro diálogo que el sistema ya no va a mostrar.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comerciosCon(
              '{"comercios": [], "cercanos": [], "categorias": []}',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sistema.solicitudes, 2);
      expect(find.text('Abrir configuración'), findsOneWidget);
    });
  });

  group('la cuenta se borra cuando el permiso se concede', () {
    test('volver a negar después de conceder empieza de cero', () async {
      sistema.instalar(
        gpsEncendido: true,
        permiso: denegado,
        siempreDeniega: true,
      );

      expect(await solicitarPermisoUbicacion(), ResultadoUbicacion.denegado);
      expect(
        await solicitarPermisoUbicacion(),
        ResultadoUbicacion.denegadoPermanente,
      );

      // Concedido, y a propósito en el sistema y no tocando los ajustes: así se
      // comprueba que lo borra el propio servicio y no la pantalla.
      sistema.permisoActual = permitido;
      expect(await solicitarPermisoUbicacion(), ResultadoUbicacion.ok);

      // Si no se hubiera borrado, esto ya sería "denegado para siempre" y el
      // botón no volvería a preguntar nunca más.
      sistema.permisoActual = denegado;
      expect(await solicitarPermisoUbicacion(), ResultadoUbicacion.denegado);
    });

    test('consultar sin preguntar no gasta intentos', () async {
      sistema.instalar(
        gpsEncendido: true,
        permiso: denegado,
        siempreDeniega: true,
      );

      // Las consultas en silencio son las que se hacen al volver de segundo
      // plano. Si contaran, dos vueltas a otra app bastarían para agotar los
      // intentos sin que nadie viera un solo diálogo.
      for (var i = 0; i < 5; i++) {
        expect(await comprobarPermisoUbicacion(), ResultadoUbicacion.denegado);
      }

      expect(sistema.solicitudes, 0);
      expect(await solicitarPermisoUbicacion(), ResultadoUbicacion.denegado);
      expect(sistema.solicitudes, 1);
    });
  });

  group('Bug 2: volver de segundo plano no interrumpe', () {
    testWidgets('con el permiso denegado no pide nada', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comerciosCon(
              '{"comercios": [], "cercanos": [], "categorias": []}',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final hechasAlAbrir = sistema.solicitudes;
      expect(find.text('Activar ubicación'), findsOneWidget);

      // Dos idas y venidas, como las que pasan al buscar la app en el
      // conmutador o al mirar una notificación.
      await _vaASegundoPlanoYVuelve(tester);
      await _vaASegundoPlanoYVuelve(tester);

      // La clave: ningún diálogo nuevo. Volver a segundo plano no es consentir
      // nada, y preguntar ahí saca un diálogo que nadie pidió.
      expect(sistema.solicitudes, hechasAlAbrir);
      expect(sistema.consultas, greaterThan(0));
      expect(find.text('Activar ubicación'), findsOneWidget);
    });

    testWidgets('con el permiso ya concedido recarga la lista solo', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comerciosCon(
              '{"comercios": [], "cercanos": [], "categorias": []}',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Activar ubicación'), findsOneWidget);

      // La persona lo activa en los ajustes del sistema y vuelve.
      sistema.permisoActual = permitido;
      final hechasAlAbrir = sistema.solicitudes;

      await _vaASegundoPlanoYVuelve(tester);

      // La lista aparece sola, sin que tenga que reintentar a mano.
      expect(find.text('Activar ubicación'), findsNothing);
      // Se lee la posición y se recarga, que es lo que faltaba sin consultar el
      // permiso al volver: la app se quedaba con la lista vacía.
      expect(sistema.lecturasDePosicion, greaterThan(0));
      // Y sin preguntar: el permiso ya estaba concedido.
      expect(sistema.solicitudes, hechasAlAbrir);
    });

    testWidgets('tocar el botón sigue siendo la única forma de preguntar', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _comerciosCon(
              '{"comercios": [], "cercanos": [], "categorias": []}',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Activar ubicación'));
      await tester.pumpAndSettle();

      // A propósito: el segundo diálogo sí se muestra.
      expect(sistema.solicitudes, 2);
    });
  });
}
