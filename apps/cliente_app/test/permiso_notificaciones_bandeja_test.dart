import 'package:cliente_app/screens/bandeja_notificaciones_screen.dart';
import 'package:cliente_app/services/notificaciones_service.dart';
import 'package:cliente_app/widgets/barra_permiso_notificaciones.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';

/// Registro de lo que hizo el servicio, para comprobar qué se llamó y cuántas
/// veces. El orden importa: dice si algo se preguntó sin que nadie lo pidiera.
class Registro {
  final List<String> llamadas = <String>[];

  int veces(String llamada) => llamadas.where((c) => c == llamada).length;

  void anota(String llamada) => llamadas.add(llamada);
}

class _FakeAuth extends AuthService {
  @override
  Future<String?> getAccessToken() async => 'token-de-prueba';

  @override
  Future<void> logout() async {}
}

NotificacionesService _servicio(
  Registro registro, {
  required AuthorizationStatus estado,
  AuthorizationStatus? trasSolicitar,
  String? tokenFcm = 'token-fake',
}) {
  return NotificacionesService(
    api: ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((_) async {
        registro.anota('PUT /auth/fcm-token');
        return http.Response(
          '{"ok":true}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
    auth: _FakeAuth(),
    obtenerTokenFcm: () async => tokenFcm,
    estadoOverride: () async {
      registro.anota('estadoPermiso');
      return estado;
    },
    solicitarOverride: () async {
      registro.anota('solicitarPermiso');
      return trasSolicitar ?? AuthorizationStatus.denied;
    },
  );
}

Future<void> _abrir(WidgetTester tester, NotificacionesService notis) async {
  await tester.pumpWidget(
    MaterialApp(home: BandejaNotificacionesScreen(servicio: notis)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('la barra según el estado del permiso', () {
    Future<void> barra(
      WidgetTester tester,
      EstadoPermisoNotificaciones estado,
    ) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BarraPermisoNotificaciones(
              estado: estado,
              onReintentar: () {},
            ),
          ),
        ),
      );
    }

    testWidgets('con el permiso concedido no se muestra nada', (tester) async {
      await barra(tester, EstadoPermisoNotificaciones.concedido);

      expect(find.byType(BarraPermisoNotificaciones), findsOneWidget);
      // El widget existe pero no dibuja la franja.
      expect(find.text('Activar'), findsNothing);
      expect(
        find.text('Activa las notificaciones para recibir avisos al instante'),
        findsNothing,
      );
    });

    testWidgets('denegado: ofrece el segundo intento', (tester) async {
      await barra(tester, EstadoPermisoNotificaciones.denegado);

      expect(
        find.text('Activa las notificaciones para recibir avisos al instante'),
        findsOneWidget,
      );
      expect(find.text('Activar'), findsOneWidget);
      expect(find.text('Abrir configuración'), findsNothing);
    });

    testWidgets('denegado de forma permanente: ofrece los ajustes', (
      tester,
    ) async {
      await barra(tester, EstadoPermisoNotificaciones.denegadoPermanente);

      expect(
        find.text('Activa las notificaciones para recibir avisos al instante'),
        findsOneWidget,
      );
      expect(find.text('Abrir configuración'), findsOneWidget);
      expect(find.text('Activar'), findsNothing);
    });

    testWidgets('denegado: tocar el botón vuelve a pedir el permiso', (
      tester,
    ) async {
      var reintentos = 0;
      var ajustes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BarraPermisoNotificaciones(
              estado: EstadoPermisoNotificaciones.denegado,
              onReintentar: () => reintentos++,
              onAbrirConfiguracion: () => ajustes++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Activar'));
      expect(reintentos, 1);
      expect(ajustes, 0);
    });

    testWidgets(
      'denegado de forma permanente: tocar el botón abre los ajustes',
      (tester) async {
        var reintentos = 0;
        var ajustes = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BarraPermisoNotificaciones(
                estado: EstadoPermisoNotificaciones.denegadoPermanente,
                onReintentar: () => reintentos++,
                onAbrirConfiguracion: () => ajustes++,
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir configuración'));
        expect(ajustes, 1);
        // Nada de volver a preguntar: el sistema ya no mostraría nada.
        expect(reintentos, 0);
      },
    );
  });

  group('primer intento: al abrir la bandeja, sin aviso previo', () {
    testWidgets('con el permiso sin decidir, se pregunta directamente', (
      tester,
    ) async {
      final registro = Registro();

      await _abrir(
        tester,
        _servicio(registro, estado: AuthorizationStatus.notDetermined),
      );

      // Un solo intento, y sin pantalla explicativa delante: lo que se ve al
      // abrir es la bandeja, no un diálogo de la app.
      expect(registro.veces('solicitarPermiso'), 1);
      expect(find.text('Activar notificaciones'), findsNothing);
    });

    testWidgets('el sistema concedió: la barra no aparece', (tester) async {
      final registro = Registro();

      await _abrir(
        tester,
        _servicio(
          registro,
          estado: AuthorizationStatus.notDetermined,
          trasSolicitar: AuthorizationStatus.authorized,
        ),
      );

      expect(registro.veces('solicitarPermiso'), 1);
      expect(find.text('Activar'), findsNothing);
      expect(find.text('Abrir configuración'), findsNothing);
    });

    testWidgets('el sistema denegó: queda la barra con el segundo intento', (
      tester,
    ) async {
      final registro = Registro();

      await _abrir(
        tester,
        _servicio(
          registro,
          estado: AuthorizationStatus.notDetermined,
          trasSolicitar: AuthorizationStatus.denied,
        ),
      );

      expect(registro.veces('solicitarPermiso'), 1);
      expect(find.text('Activar'), findsOneWidget);
    });

    testWidgets('concedido: registra el token en el backend', (tester) async {
      final registro = Registro();

      await _abrir(
        tester,
        _servicio(
          registro,
          estado: AuthorizationStatus.notDetermined,
          trasSolicitar: AuthorizationStatus.authorized,
        ),
      );

      // Sin el token el backend no sabe a quién avisar, así que conceder el
      // permiso sin registrarlo dejaría las notificaciones sin funcionar.
      expect(registro.llamadas, contains('PUT /auth/fcm-token'));
    });

    testWidgets('denegado: no se registra el token, no serviría de nada', (
      tester,
    ) async {
      final registro = Registro();

      await _abrir(
        tester,
        _servicio(
          registro,
          estado: AuthorizationStatus.notDetermined,
          trasSolicitar: AuthorizationStatus.denied,
        ),
      );

      // Android entrega el token aunque el permiso esté denegado: mandarlo
      // dejaría un registro que parece bueno y no recibe nada.
      expect(registro.llamadas, isNot(contains('PUT /auth/fcm-token')));
    });
  });

  group('al abrir con el permiso ya decidido', () {
    testWidgets('denegado: no se vuelve a preguntar solo', (tester) async {
      final registro = Registro();

      await _abrir(
        tester,
        _servicio(registro, estado: AuthorizationStatus.denied),
      );

      // La segunda negativa es decisión de la persona, y la toma tocando.
      expect(registro.veces('solicitarPermiso'), 0);
      expect(find.text('Activar'), findsOneWidget);
    });

    testWidgets('denegado de forma permanente: no se intenta el diálogo', (
      tester,
    ) async {
      final registro = Registro();

      await _abrir(
        tester,
        _servicio(registro, estado: AuthorizationStatus.deniedPermanently),
      );

      expect(registro.veces('solicitarPermiso'), 0);
      expect(find.text('Abrir configuración'), findsOneWidget);
    });

    testWidgets('concedido: ni barra ni preguntas', (tester) async {
      final registro = Registro();

      await _abrir(
        tester,
        _servicio(registro, estado: AuthorizationStatus.authorized),
      );

      expect(registro.veces('solicitarPermiso'), 0);
      expect(find.text('Activar'), findsNothing);
      expect(find.text('Abrir configuración'), findsNothing);
    });
  });

  group('segundo intento desde la barra', () {
    testWidgets('el botón vuelve a pedir el permiso', (tester) async {
      final registro = Registro();

      await _abrir(
        tester,
        _servicio(
          registro,
          estado: AuthorizationStatus.denied,
          trasSolicitar: AuthorizationStatus.authorized,
        ),
      );
      expect(registro.veces('solicitarPermiso'), 0);

      await tester.tap(find.text('Activar'));
      await tester.pumpAndSettle();

      expect(registro.veces('solicitarPermiso'), 1);
      // Concedido a la segunda: la barra desaparece sola.
      expect(find.text('Activar'), findsNothing);
    });

    testWidgets('tras el segundo rechazo sigue en denegado, barra mantenida', (
      tester,
    ) async {
      final registro = Registro();

      await _abrir(
        tester,
        _servicio(
          registro,
          estado: AuthorizationStatus.denied,
          trasSolicitar: AuthorizationStatus.denied,
        ),
      );

      await tester.tap(find.text('Activar'));
      await tester.pumpAndSettle();

      // Si el sistema sigue diciendo "denegado" simple, se sigue pudiendo
      // preguntar. Que lo decida el sistema, no un contador de la app.
      expect(registro.veces('solicitarPermiso'), 1);
      expect(find.text('Activar'), findsOneWidget);
    });
  });

  group('denegado de forma permanente: ir a los ajustes', () {
    testWidgets('el botón abre los ajustes y relee el permiso al volver', (
      tester,
    ) async {
      final registro = Registro();
      var ajustes = 0;
      var estadoActual = AuthorizationStatus.deniedPermanently;

      final notis = NotificacionesService(
        auth: _FakeAuth(),
        obtenerTokenFcm: () async => 'token-fake',
        estadoOverride: () async {
          registro.anota('estadoPermiso');
          return estadoActual;
        },
        solicitarOverride: () async {
          registro.anota('solicitarPermiso');
          return AuthorizationStatus.denied;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BandejaNotificacionesScreen(
            servicio: notis,
            abrirConfiguracion: () async {
              ajustes++;
              // La persona concede el permiso desde los ajustes del sistema.
              estadoActual = AuthorizationStatus.authorized;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Abrir configuración'), findsOneWidget);

      await tester.tap(find.text('Abrir configuración'));
      await tester.pumpAndSettle();

      expect(ajustes, 1);
      // Vuelve a comprobar, para que la barra se vaya sin cerrar la pantalla.
      expect(registro.veces('estadoPermiso'), 2);
      expect(find.text('Abrir configuración'), findsNothing);
    });

    testWidgets('la barra no vuelve a pedir el diálogo al releer', (
      tester,
    ) async {
      final registro = Registro();

      await _abrir(
        tester,
        _servicio(registro, estado: AuthorizationStatus.deniedPermanently),
      );

      // Ni al abrir ni al releer: con el permiso a perpetuidad solo hay Ajustes.
      expect(registro.veces('solicitarPermiso'), 0);
    });
  });

  group('la campana abre la bandeja', () {
    testWidgets('y no dispara la prueba de notificación', (tester) async {
      final registro = Registro();
      final notis = _servicio(registro, estado: AuthorizationStatus.authorized);

      await tester.pumpWidget(
        MaterialApp(home: BandejaNotificacionesScreen(servicio: notis)),
      );
      await tester.pumpAndSettle();

      // La prueba vive dentro de la bandeja, no en el ícono de la barra.
      // Lo que importa aquí es que abrir no envíe nada por su cuenta.
      expect(registro.llamadas, isNot(contains('solicitarPermiso')));
      expect(registro.llamadas, isNot(contains('PUT /auth/fcm-token')));
    });
  });
}
