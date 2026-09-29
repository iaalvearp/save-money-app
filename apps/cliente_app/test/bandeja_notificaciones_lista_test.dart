import 'dart:convert';

import 'package:cliente_app/screens/bandeja_notificaciones_screen.dart';
import 'package:cliente_app/screens/home_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';
import 'package:cliente_app/services/comercios_service.dart';
import 'package:cliente_app/services/notificaciones_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mocks_geolocator.dart';

const _claveBuzon = 'notificaciones_buzon';

class _FakeAuth extends AuthService {
  @override
  Future<String?> getAccessToken() async => 'token-de-prueba';

  @override
  Future<void> logout() async {}
}

Map<String, dynamic> _avisoJson({
  required String id,
  required String titulo,
  required DateTime fecha,
  bool leida = false,
  String cuerpo = 'cuerpo del aviso',
}) {
  return {
    'id': id,
    'titulo': titulo,
    'cuerpo': cuerpo,
    'data': const {'tipo': 'prueba'},
    'fecha': fecha.toIso8601String(),
    'leida': leida,
  };
}

void _dejarEnElDispositivo(List<Map<String, dynamic>> avisos) {
  SharedPreferences.setMockInitialValues({_claveBuzon: jsonEncode(avisos)});
}

NotificacionesService _servicio({
  AuthorizationStatus permiso = AuthorizationStatus.authorized,
  List<String> peticiones = const [],
}) {
  return NotificacionesService(
    api: ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((req) async {
        peticiones.add('${req.method} ${req.url.path}');
        return http.Response(
          '{"ok":true}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
    auth: _FakeAuth(),
    obtenerTokenFcm: () async => 'token-fake',
    estadoOverride: () async => permiso,
    solicitarOverride: () async => AuthorizationStatus.denied,
  );
}

/// La pantalla de inicio con el buzón al alcance, para poder ver la insignia
/// de la campana.
Widget _homeConBuzon(NotificacionesService buzon) {
  return NotificacionesScope(
    notifier: buzon,
    child: HomeScreen(
      servicio: ComerciosService(
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
      ),
    ),
  );
}

Future<void> _abrir(WidgetTester tester, NotificacionesService servicio) async {
  await tester.pumpWidget(
    MaterialApp(home: BandejaNotificacionesScreen(servicio: servicio)),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('la lista', () {
    testWidgets('vacía explica que no hay nada todavía', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await _abrir(tester, _servicio());

      expect(find.text('Todavía no hay notificaciones'), findsOneWidget);
    });

    testWidgets('muestra los avisos guardados', (tester) async {
      final ahora = DateTime.now();
      _dejarEnElDispositivo([
        _avisoJson(
          id: 'a',
          titulo: 'Empezó un Hunt',
          fecha: ahora.subtract(const Duration(minutes: 5)),
        ),
        _avisoJson(
          id: 'b',
          titulo: 'Ganaste un premio',
          cuerpo: 'Canjea tu cupón en el comercio',
          fecha: ahora.subtract(const Duration(minutes: 30)),
        ),
      ]);

      await _abrir(tester, _servicio());

      expect(find.text('Empezó un Hunt'), findsOneWidget);
      expect(find.text('Ganaste un premio'), findsOneWidget);
      expect(find.text('Canjea tu cupón en el comercio'), findsOneWidget);
    });

    testWidgets('el más reciente va primero', (tester) async {
      final ahora = DateTime.now();
      _dejarEnElDispositivo([
        _avisoJson(
          id: 'viejo',
          titulo: 'el primero en la lista',
          fecha: ahora.subtract(const Duration(hours: 1)),
        ),
        _avisoJson(
          id: 'nuevo',
          titulo: 'el segundo en la lista',
          fecha: ahora.subtract(const Duration(minutes: 1)),
        ),
      ]);

      await _abrir(tester, _servicio());

      final titulos = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((d) => d != null)
          .toList();
      expect(
        titulos.indexOf('el segundo en la lista'),
        lessThan(titulos.indexOf('el primero en la lista')),
      );
    });

    testWidgets('al abrir se purga lo que caducó', (tester) async {
      final ahora = DateTime.now();
      _dejarEnElDispositivo([
        _avisoJson(
          id: 'caducado',
          titulo: 'promo de hace cuatro días',
          fecha: ahora.subtract(const Duration(days: 4)),
        ),
        _avisoJson(
          id: 'vigente',
          titulo: 'promo de hace un rato',
          fecha: ahora.subtract(const Duration(minutes: 10)),
        ),
      ]);

      await _abrir(tester, _servicio());

      expect(find.text('promo de hace un rato'), findsOneWidget);
      expect(find.text('promo de hace cuatro días'), findsNothing);
    });

    testWidgets('un aviso que llega con la pantalla abierta aparece solo', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final servicio = _servicio();
      await _abrir(tester, servicio);

      expect(find.text('Todavía no hay notificaciones'), findsOneWidget);

      // Llega por el listener de foreground, sin tocar nada.
      await servicio.registrarMensaje(
        RemoteMessage(
          messageId: 'nuevo',
          data: const {'tipo': 'prueba'},
          notification: const RemoteNotification(
            title: 'Entró tu participación',
            body: 'Ya puedes ver el mapa',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Entró tu participación'), findsOneWidget);
      expect(find.text('Todavía no hay notificaciones'), findsNothing);
    });
  });

  group('lo no leído', () {
    testWidgets('se distingue de lo leído', (tester) async {
      final ahora = DateTime.now();
      _dejarEnElDispositivo([
        _avisoJson(id: 'nuevo', titulo: 'sin leer', fecha: ahora),
        _avisoJson(
          id: 'viejo',
          titulo: 'ya leido',
          fecha: ahora.subtract(const Duration(hours: 2)),
          leida: true,
        ),
      ]);

      await _abrir(tester, _servicio());

      // El título sin leer va en negrita; el leído no.
      final sinLeer = tester
          .widgetList<Text>(find.byType(Text))
          .firstWhere((t) => t.data == 'sin leer');
      final leido = tester
          .widgetList<Text>(find.byType(Text))
          .firstWhere((t) => t.data == 'ya leido');

      expect(sinLeer.style?.fontWeight, FontWeight.w700);
      expect(leido.style?.fontWeight, FontWeight.w400);
    });

    testWidgets('tocar un aviso lo marca leído y no lo borra', (tester) async {
      final ahora = DateTime.now();
      _dejarEnElDispositivo([
        _avisoJson(id: 'a', titulo: 'sin leer', fecha: ahora),
      ]);

      final servicio = _servicio();
      await _abrir(tester, servicio);
      expect(servicio.noLeidas, 1);

      await tester.tap(find.text('sin leer'));
      await tester.pumpAndSettle();

      expect(servicio.noLeidas, 0);
      // Se conserva: se puede querer volver a consultarlo.
      expect(find.text('sin leer'), findsOneWidget);
    });

    testWidgets('marcar todas deja la lista intacta', (tester) async {
      final ahora = DateTime.now();
      _dejarEnElDispositivo([
        _avisoJson(id: 'a', titulo: 'uno', fecha: ahora),
        _avisoJson(id: 'b', titulo: 'dos', fecha: ahora),
      ]);

      final servicio = _servicio();
      await _abrir(tester, servicio);
      expect(servicio.noLeidas, 2);

      await tester.tap(find.byTooltip('Marcar todas como leídas'));
      await tester.pumpAndSettle();

      expect(servicio.noLeidas, 0);
      expect(find.text('uno'), findsOneWidget);
      expect(find.text('dos'), findsOneWidget);
    });

    testWidgets('borrar todas pide confirmación y vacía', (tester) async {
      final ahora = DateTime.now();
      _dejarEnElDispositivo([_avisoJson(id: 'a', titulo: 'uno', fecha: ahora)]);

      final servicio = _servicio();
      await _abrir(tester, servicio);

      await tester.tap(find.byTooltip('Borrar todas'));
      await tester.pumpAndSettle();

      // Es una acción sin vuelta atrás: se pregunta.
      expect(find.text('¿Borrar todas las notificaciones?'), findsOneWidget);

      await tester.tap(find.text('Borrar'));
      await tester.pumpAndSettle();

      expect(servicio.lista, isEmpty);
      expect(find.text('Todavía no hay notificaciones'), findsOneWidget);
    });

    testWidgets('cancelar el borrado no borra nada', (tester) async {
      final ahora = DateTime.now();
      _dejarEnElDispositivo([_avisoJson(id: 'a', titulo: 'uno', fecha: ahora)]);

      final servicio = _servicio();
      await _abrir(tester, servicio);

      await tester.tap(find.byTooltip('Borrar todas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(servicio.lista, hasLength(1));
      expect(find.text('uno'), findsOneWidget);
    });

    testWidgets('sin avisos no hay acciones de lista', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await _abrir(tester, _servicio());

      expect(find.byTooltip('Marcar todas como leídas'), findsNothing);
      expect(find.byTooltip('Borrar todas'), findsNothing);
    });
  });

  group('el botón de prueba', () {
    testWidgets('manda el aviso de prueba al backend', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final peticiones = <String>[];

      await _abrir(tester, _servicio(peticiones: peticiones));

      await tester.tap(find.text('Enviar una de prueba'));
      await tester.pumpAndSettle();

      expect(peticiones, ['POST /notificaciones/test']);
      expect(
        find.text('Notificación de prueba enviada. Tarda unos segundos.'),
        findsOneWidget,
      );
    });

    testWidgets('está en la pantalla, no en la campana', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await _abrir(tester, _servicio());

      // Con la app abierta el aviso llega directo, sin tocar nada.
      expect(find.text('Enviar una de prueba'), findsOneWidget);
    });
  });

  group('la campana lleva a la bandeja y cuenta lo no leído', () {
    late LlamadasAlSistema sistema;

    setUp(() => sistema = LlamadasAlSistema());
    tearDown(() => sistema.desinstalar());

    testWidgets('con avisos sin leer muestra la insignia', (tester) async {
      final ahora = DateTime.now();
      _dejarEnElDispositivo([
        _avisoJson(id: 'a', titulo: 'uno', fecha: ahora),
        _avisoJson(id: 'b', titulo: 'dos', fecha: ahora),
      ]);

      sistema.instalar(gpsEncendido: true, permiso: denegadoParaSiempre);
      final buzon = _servicio();
      await buzon.cargar();

      await tester.pumpWidget(MaterialApp(home: _homeConBuzon(buzon)));
      await tester.pumpAndSettle();

      expect(find.byType(Badge), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('sin nada sin leer no enseña insignia', (tester) async {
      SharedPreferences.setMockInitialValues({});
      sistema.instalar(gpsEncendido: true, permiso: denegadoParaSiempre);
      final buzon = _servicio();
      await buzon.cargar();

      await tester.pumpWidget(MaterialApp(home: _homeConBuzon(buzon)));
      await tester.pumpAndSettle();

      // Un "0" colgado en la campana solo ocupa sitio.
      final insignia = tester.widget<Badge>(find.byType(Badge));
      expect(insignia.isLabelVisible, isFalse);
    });

    testWidgets('el contador baja al marcar como leída', (tester) async {
      final ahora = DateTime.now();
      _dejarEnElDispositivo([_avisoJson(id: 'a', titulo: 'uno', fecha: ahora)]);

      sistema.instalar(gpsEncendido: true, permiso: denegadoParaSiempre);
      sistema.instalar(gpsEncendido: true, permiso: denegadoParaSiempre);
      final buzon = _servicio();
      await buzon.cargar();

      await tester.pumpWidget(MaterialApp(home: _homeConBuzon(buzon)));
      await tester.pumpAndSettle();
      expect(find.byType(Badge), findsOneWidget);

      await buzon.marcarTodasLeidas();
      await tester.pumpAndSettle();

      final insignia = tester.widget<Badge>(find.byType(Badge));
      expect(insignia.isLabelVisible, isFalse);
    });
  });
}
