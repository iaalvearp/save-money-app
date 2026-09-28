import 'package:cliente_app/services/notificaciones_service.dart';
import 'package:cliente_app/widgets/aviso_permiso_notificaciones.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regresión del ciclo completo del aviso a lo largo de varios arranques:
/// qué pasa después de que el usuario pulse "Activar" y el sistema lo rechace,
/// y por qué "Ahora no" sí es definitivo.
///
/// Estas pruebas arrancan siempre sin preferencias y dejan que el propio
/// widget escriba, en vez de preparar el estado a mano. Así se comprueba el
/// ciclo real y no una situación que la app nunca produce.
///
/// `SharedPreferences` mantiene estado entre pruebas del mismo archivo, por eso
/// cada caso reinicia los valores al principio.

/// Cuenta cuántas veces se pidió el permiso al sistema.
int solicitudesHechas = 0;

/// Construye un servicio con las costuras inyectadas.
///
/// [estado] es lo que el sistema responde al consultar, y lo que devuelve tras
/// la solicitud. Se usa el mismo valor en ambos casos salvo que se indique otro
/// con [trasSolicitar].
NotificacionesService servicio(
  AuthorizationStatus estado, {
  AuthorizationStatus? trasSolicitar,
}) {
  return NotificacionesService(
    obtenerTokenFcm: () async => 'token-fake',
    estadoOverride: () async => estado,
    solicitarOverride: () async {
      solicitudesHechas++;
      return trasSolicitar ?? estado;
    },
  );
}

/// Clave distinta por arranque, para que el framework cree un `State` nuevo.
/// Sin esto Flutter reutiliza el `State` anterior y el aviso no vuelve a
/// evaluarse, que es justo lo que este archivo quiere comprobar.
int _arranques = 0;

/// Monta el aviso como si la app acabara de arrancar y deja correr los frames.
Future<void> arrancar(
  WidgetTester tester,
  AuthorizationStatus estado, {
  AuthorizationStatus? trasSolicitar,
}) async {
  _arranques++;
  await tester.pumpWidget(
    MaterialApp(
      home: AvisoPermisoNotificaciones(
        key: ValueKey('arranque_$_arranques'),
        servicio: servicio(estado, trasSolicitar: trasSolicitar),
        child: const Scaffold(body: Text('pantalla de inicio')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool avisoVisible(WidgetTester tester) =>
    find.text('Activar notificaciones').evaluate().isNotEmpty;

Future<bool> avisoCerrado() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(NotificacionesService.claveAvisoCerrado) ?? false;
}

Future<int> vecesAviso() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(NotificacionesService.claveVecesAviso) ?? 0;
}

/// Reinicia el estado persistente. En `setUp` y no dentro de cada test, para que
/// un test que falla no deje prefs sucias que silencien al siguiente.
void reiniciarPreferencias() {
  SharedPreferences.setMockInitialValues({});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    reiniciarPreferencias();
    solicitudesHechas = 0;
  });

  testWidgets(
      '1) "Activar" seguido de rechazo simple: el aviso vuelve a mostrarse',
      (tester) async {
    // Primer arranque: permiso sin decidir, el aviso aparece.
    await arrancar(tester, AuthorizationStatus.notDetermined);
    expect(avisoVisible(tester), isTrue, reason: 'primer arranque');
    expect(await vecesAviso(), 1);

    // Acepta, pero el sistema lo rechaza de forma simple.
    await tester.tap(find.text('Activar'));
    await tester.pumpAndSettle();

    expect(solicitudesHechas, 1, reason: 'se pidió el permiso al sistema');
    expect(await avisoCerrado(), isFalse,
        reason: 'rechazar el sistema NO debe cerrar el aviso');

    // Segundo arranque: con el permiso ya en "denegado simple".
    await arrancar(tester, AuthorizationStatus.denied);
    expect(avisoVisible(tester), isTrue,
        reason: 'el aviso debe volver a mostrarse tras un rechazo simple');
    expect(await vecesAviso(), 2);
  });

  testWidgets('2) tras mostrarse 2 veces el aviso no vuelve a aparecer',
      (tester) async {
    for (var arranque = 1; arranque <= 2; arranque++) {
      await arrancar(tester, AuthorizationStatus.denied);
      expect(avisoVisible(tester), isTrue, reason: 'arranque $arranque');
      await tester.tap(find.text('Activar'));
      await tester.pumpAndSettle();
    }

    expect(await vecesAviso(), NotificacionesService.maximoVecesAviso);
    expect(solicitudesHechas, 2);

    // Tercer arranque: ya se agotó el tope de seguridad.
    await arrancar(tester, AuthorizationStatus.denied);
    expect(avisoVisible(tester), isFalse,
        reason: 'el tope de seguridad impide una tercera vez');
    expect(await vecesAviso(), NotificacionesService.maximoVecesAviso);
    expect(solicitudesHechas, 2, reason: 'no se vuelve a pedir el permiso');
  });

  testWidgets('3) "Activar" con rechazo permanente: el aviso no vuelve',
      (tester) async {
    await arrancar(tester, AuthorizationStatus.notDetermined);
    expect(avisoVisible(tester), isTrue);

    await tester.tap(find.text('Activar'));
    await tester.pumpAndSettle();

    // Concede, pero el sistema lo deja en denegado para siempre.
    await arrancar(tester, AuthorizationStatus.deniedPermanently);
    expect(avisoVisible(tester), isFalse,
        reason: 'un rechazo permanente no se puede repetir');
  });

  testWidgets('3b) "Activar" que el sistema concede: el aviso no vuelve',
      (tester) async {
    await arrancar(
      tester,
      AuthorizationStatus.notDetermined,
      trasSolicitar: AuthorizationStatus.authorized,
    );
    await tester.tap(find.text('Activar'));
    await tester.pumpAndSettle();

    expect(await avisoCerrado(), isTrue);

    await arrancar(tester, AuthorizationStatus.authorized);
    expect(avisoVisible(tester), isFalse);
  });

  testWidgets('4) "Ahora no": el aviso no vuelve nunca', (tester) async {
    await arrancar(tester, AuthorizationStatus.notDetermined);
    expect(avisoVisible(tester), isTrue);

    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();

    expect(solicitudesHechas, 0, reason: 'no se pide nada al sistema');
    expect(await avisoCerrado(), isTrue);

    // Aunque el permiso siga sin decidir, el aviso está cerrado para siempre.
    for (var arranque = 2; arranque <= 4; arranque++) {
      await arrancar(tester, AuthorizationStatus.notDetermined);
      expect(avisoVisible(tester), isFalse, reason: 'arranque $arranque');
    }

    expect(await vecesAviso(), 1,
        reason: 'solo se contó la vez que se mostró de verdad');
  });

  testWidgets('5) permiso ya concedido: el aviso nunca aparece', (tester) async {
    await arrancar(tester, AuthorizationStatus.authorized);
    expect(avisoVisible(tester), isFalse);
    expect(solicitudesHechas, 0);
    expect(await vecesAviso(), 0, reason: 'ni siquiera se cuenta');
  });
}
