import 'package:cliente_app/services/notificaciones_service.dart';
import 'package:cliente_app/widgets/aviso_permiso_notificaciones.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Monta el aviso sobre una pantalla trivial y deja correr los frames.
Future<void> montar(WidgetTester tester, NotificacionesService notis) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AvisoPermisoNotificaciones(
        servicio: notis,
        child: const Scaffold(body: Text('pantalla de inicio')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('el aviso aparece solo si no hay decisión previa', () {
    testWidgets('con el permiso sin decidir se muestra el texto y los botones',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final registro = Registro();

      await montar(tester, servicio(registro, AuthorizationStatus.notDetermined));

      expect(
        find.text('Te avisamos cuando empiece un Hunt, te aprueben una entrada, ganes un premio o haya una promo cerca.'),
        findsOneWidget,
      );
      expect(find.text('Activar'), findsOneWidget);
      expect(find.text('Ahora no'), findsOneWidget);
    });

    testWidgets('el aviso no tapa la pantalla de inicio: se ve detrás',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final registro = Registro();

      await montar(tester, servicio(registro, AuthorizationStatus.notDetermined));

      // El dialogo se muestra encima, no en lugar de la pantalla.
      expect(find.text('pantalla de inicio'), findsOneWidget);
      expect(find.text('Activar notificaciones'), findsOneWidget);
    });

    testWidgets('si ya se respondió antes, el aviso no reaparece', (tester) async {
      SharedPreferences.setMockInitialValues({
        NotificacionesService.claveAvisoMostrado: true,
      });
      final registro = Registro();

      await montar(tester, servicio(registro, AuthorizationStatus.notDetermined));

      expect(find.text('Activar notificaciones'), findsNothing);
      expect(find.text('Activar'), findsNothing);
    });
  });

  group('Activar y Ahora no', () {
    testWidgets('"Activar" lanza la solicitud del sistema', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final registro = Registro();

      await montar(tester, servicio(registro, AuthorizationStatus.notDetermined));
      await tester.tap(find.text('Activar'));
      await tester.pumpAndSettle();

      expect(registro.llamadas, contains('solicitarPermiso'));
    });

    testWidgets('"Ahora no" no lanza la solicitud', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final registro = Registro();

      await montar(tester, servicio(registro, AuthorizationStatus.notDetermined));
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();

      expect(registro.llamadas, isNot(contains('solicitarPermiso')));
    });

    testWidgets('"Ahora no" deja constancia para que no reaparezca',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final registro = Registro();

      await montar(tester, servicio(registro, AuthorizationStatus.notDetermined));
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(NotificacionesService.claveAvisoMostrado), isTrue);
    });

    testWidgets('el token se registra despues de la decision, nunca antes',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final registro = Registro();

      await montar(tester, servicio(registro, AuthorizationStatus.notDetermined));

      // El aviso esta en pantalla: todavia no se ha registrado el token.
      expect(registro.llamadas, isEmpty);

      await tester.tap(find.text('Activar'));
      await tester.pumpAndSettle();

      expect(registro.llamadas, ['solicitarPermiso', 'registrarToken']);
    });

    testWidgets('"Ahora no" tambien registra el token en el backend',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final registro = Registro();

      await montar(tester, servicio(registro, AuthorizationStatus.notDetermined));
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();

      expect(registro.llamadas, ['registrarToken']);
    });
  });

  group('un permiso ya decidido no muestra el aviso', () {
    testWidgets('si ya esta concedido no hay aviso', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final registro = Registro();

      await montar(tester, servicio(registro, AuthorizationStatus.authorized));

      expect(find.text('Activar notificaciones'), findsNothing);
    });

    testWidgets('si esta denegado permanentemente no hay aviso', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final registro = Registro();

      await montar(tester, servicio(registro, AuthorizationStatus.deniedPermanently));

      expect(find.text('Activar notificaciones'), findsNothing);
    });

    testWidgets('si solo lo denego, el sistema puede volver a preguntar y se insiste',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final registro = Registro();

      await montar(tester, servicio(registro, AuthorizationStatus.denied));

      expect(find.text('Activar notificaciones'), findsOneWidget);
    });

    testWidgets('el token se registra igual aunque no haya aviso', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final registro = Registro();

      await montar(tester, servicio(registro, AuthorizationStatus.authorized));

      expect(registro.llamadas, ['registrarToken']);
    });
  });
}
