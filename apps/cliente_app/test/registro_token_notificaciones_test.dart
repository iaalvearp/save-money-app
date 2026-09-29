import 'package:cliente_app/services/notificaciones_service.dart';
import 'package:cliente_app/widgets/registro_token_notificaciones.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registro de lo que hizo el servicio, para comprobar qué se llamó y cuándo.
class Registro {
  final List<String> llamadas = <String>[];

  void anota(String llamada) => llamadas.add(llamada);
}

/// Servicio con las tres costuras inyectadas: estado, solicitud y token.
NotificacionesService servicio(
  Registro registro,
  AuthorizationStatus estado, {
  AuthorizationStatus? trasSolicitar,
}) {
  return NotificacionesService(
    obtenerTokenFcm: () async {
      registro.anota('registrarToken');
      return 'token-fake';
    },
    estadoOverride: () async => estado,
    solicitarOverride: () async {
      registro.anota('solicitarPermiso');
      return trasSolicitar ?? AuthorizationStatus.authorized;
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('al entrar ya no se pregunta nada', () {
    testWidgets('no aparece ningún diálogo', (tester) async {
      final registro = Registro();

      await tester.pumpWidget(
        MaterialApp(
          home: RegistroTokenNotificaciones(
            servicio: servicio(registro, AuthorizationStatus.notDetermined),
            child: const Scaffold(body: Text('pantalla de inicio')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // La pantalla se ve de verdad: el envoltorio no la tapa.
      expect(find.text('pantalla de inicio'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Activar notificaciones'), findsNothing);
      expect(registro.llamadas, isNot(contains('solicitarPermiso')));
    });

    testWidgets('tampoco consulta el estado del permiso', (tester) async {
      final registro = Registro();

      await tester.pumpWidget(
        MaterialApp(
          home: RegistroTokenNotificaciones(
            servicio: servicio(registro, AuthorizationStatus.notDetermined),
            child: const Scaffold(body: Text('pantalla de inicio')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nada del permiso se necesita para registrar el token: preguntar el
      // estado era trabajo del aviso que ya no existe.
      expect(registro.llamadas, isNot(contains('estadoPermiso')));
    });
  });

  group('el token se sigue registrando', () {
    testWidgets('al entrar, una sola vez', (tester) async {
      final registro = Registro();

      await tester.pumpWidget(
        MaterialApp(
          home: RegistroTokenNotificaciones(
            servicio: servicio(registro, AuthorizationStatus.authorized),
            child: const Scaffold(body: Text('pantalla de inicio')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(registro.llamadas, ['registrarToken']);
    });

    testWidgets('aunque el permiso esté denegado', (tester) async {
      final registro = Registro();

      await tester.pumpWidget(
        MaterialApp(
          home: RegistroTokenNotificaciones(
            servicio: servicio(registro, AuthorizationStatus.denied),
            child: const Scaffold(body: Text('pantalla de inicio')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Registrar el token no depende del permiso: si la persona lo activó más
      // tarde desde los ajustes, el backend ya tiene a quién avisar.
      expect(registro.llamadas, ['registrarToken']);
    });

    testWidgets('aunque el permiso esté denegado para siempre',
        (tester) async {
      final registro = Registro();

      await tester.pumpWidget(
        MaterialApp(
          home: RegistroTokenNotificaciones(
            servicio: servicio(registro, AuthorizationStatus.deniedPermanently),
            child: const Scaffold(body: Text('pantalla de inicio')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(registro.llamadas, ['registrarToken']);
    });

    testWidgets('no vuelve a registrar en cada reconstrucción',
        (tester) async {
      final registro = Registro();

      await tester.pumpWidget(
        MaterialApp(
          home: RegistroTokenNotificaciones(
            servicio: servicio(registro, AuthorizationStatus.authorized),
            child: const Scaffold(body: Text('pantalla de inicio')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Cambiar el árbol no debe reenviar el token en cada frame.
      await tester.pumpWidget(
        MaterialApp(
          home: RegistroTokenNotificaciones(
            servicio: servicio(registro, AuthorizationStatus.authorized),
            child: const Scaffold(body: Text('otra pantalla')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(registro.llamadas, ['registrarToken']);
    });
  });
}
