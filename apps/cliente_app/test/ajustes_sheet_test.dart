import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cliente_app/screens/login_screen.dart';
import 'package:cliente_app/screens/negocio_home_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';
import 'package:cliente_app/services/comercios_service.dart';
import 'package:cliente_app/services/theme_service.dart';

class _FakeAuth extends AuthService {
  bool cerrada = false;

  @override
  Future<String?> getAccessToken() async => 'token-de-prueba';

  @override
  Future<void> logout() async {
    cerrada = true;
  }
}

class _CapturadorBrightness extends StatelessWidget {
  final ValueChanged<Brightness> onCambio;
  final Widget child;

  const _CapturadorBrightness({required this.onCambio, required this.child});

  @override
  Widget build(BuildContext context) {
    onCambio(Theme.of(context).brightness);
    return child;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAuth auth;

  setUp(() {
    auth = _FakeAuth();
  });

  /// El interruptor refleja el tema efectivo, no el modo guardado.
  ///
  /// Asi que para saber si esta encendido hay que fijarse en el brillo que se
  /// esta viendo, y para eso conviene saber tambien que brillo pidio el
  /// sistema.
  void sistemaEn(WidgetTester tester, Brightness brillo) {
    tester.platformDispatcher.platformBrightnessTestValue = brillo;
    // platformBrightnessTestValue no admite null: se devuelve a claro, que es
    // lo que usan las pruebas por defecto.
    addTearDown(
      () => tester.platformDispatcher.platformBrightnessTestValue =
          Brightness.light,
    );
  }

  bool interruptorEncendido(WidgetTester tester) =>
      tester
          .widget<SwitchListTile>(find.byKey(const Key('ajustes-tema-oscuro')))
          .value;

  Widget appConTema(
    ThemeService themeService, {
    ValueChanged<Brightness>? onBrightness,
  }) {
    final servicio = ComerciosService(
      api: ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient(
          (request) async => http.Response('{"comercios": []}', 200),
        ),
      ),
    );

    return ThemeScope(
      notifier: themeService,
      child: ListenableBuilder(
        listenable: themeService,
        builder: (context, _) {
          return MaterialApp(
            theme: ThemeData(brightness: Brightness.light),
            darkTheme: ThemeData(brightness: Brightness.dark),
            themeMode: themeService.modo,
            builder: (context, child) => _CapturadorBrightness(
              onCambio: (valor) => onBrightness?.call(valor),
              child: child ?? const SizedBox.shrink(),
            ),
            home: NegocioHomeScreen(servicio: servicio, auth: auth),
          );
        },
      ),
    );
  }

  /// Abre el panel de ajustes desde el engranaje.
  Future<void> abrirPanel(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
  }

  group('Panel de ajustes', () {
    testWidgets('el engranaje de la AppBar abre el panel de ajustes',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(tester, Brightness.light);
      final themeService = await ThemeService.cargar();
      await tester.pumpWidget(appConTema(themeService));
      await tester.pumpAndSettle();

      expect(find.text('Ajustes'), findsNothing);

      await abrirPanel(tester);

      expect(find.text('Ajustes'), findsOneWidget);
      expect(find.byKey(const Key('ajustes-tema-oscuro')), findsOneWidget);
      expect(find.byKey(const Key('ajustes-cerrar-sesion')), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
    });

    testWidgets('sin preferencia y con el sistema en claro el interruptor '
        'está apagado', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(tester, Brightness.light);
      final themeService = await ThemeService.cargar();
      var brightness = Brightness.dark;
      await tester.pumpWidget(
        appConTema(themeService, onBrightness: (v) => brightness = v),
      );
      await tester.pumpAndSettle();

      expect(brightness, Brightness.light);

      await abrirPanel(tester);

      expect(interruptorEncendido(tester), isFalse);
    });

    testWidgets('con el sistema en oscuro el interruptor está encendido',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(tester, Brightness.dark);
      final themeService = await ThemeService.cargar();
      var brightness = Brightness.light;
      await tester.pumpWidget(
        appConTema(themeService, onBrightness: (v) => brightness = v),
      );
      await tester.pumpAndSettle();

      // Lo que se esta viendo ya es oscuro, sin haber tocado nada.
      expect(brightness, Brightness.dark);

      await abrirPanel(tester);

      expect(interruptorEncendido(tester), isTrue);
    });

    testWidgets('el panel no menciona la opción "Según el sistema"',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(tester, Brightness.light);
      final themeService = await ThemeService.cargar();
      await tester.pumpWidget(appConTema(themeService));
      await tester.pumpAndSettle();

      await abrirPanel(tester);

      expect(find.text('Ajustes'), findsOneWidget);
      expect(find.text('Tema oscuro'), findsOneWidget);
      expect(find.text('Según el sistema'), findsNothing);
      expect(find.textContaining('sistema'), findsNothing);
    });

    testWidgets('tocar pasa al opuesto, repinta la app y lo guarda',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      // Sistema en oscuro: el interruptor arranca encendido.
      sistemaEn(tester, Brightness.dark);
      final themeService = await ThemeService.cargar();
      var brightness = Brightness.light;
      await tester.pumpWidget(
        appConTema(themeService, onBrightness: (v) => brightness = v),
      );
      await tester.pumpAndSettle();
      await abrirPanel(tester);

      expect(interruptorEncendido(tester), isTrue);

      await tester.tap(find.byKey(const Key('ajustes-tema-oscuro')));
      await tester.pumpAndSettle();

      // Al opuesto, y la app entera se repinta.
      expect(interruptorEncendido(tester), isFalse);
      expect(brightness, Brightness.light);
      expect(themeService.modo, ThemeMode.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), 'light');

      // Un segundo toque vuelve a oscuro y vuelve a guardar.
      await tester.tap(find.byKey(const Key('ajustes-tema-oscuro')));
      await tester.pumpAndSettle();

      expect(interruptorEncendido(tester), isTrue);
      expect(brightness, Brightness.dark);
      expect(themeService.modo, ThemeMode.dark);
      final prefs2 = await SharedPreferences.getInstance();
      expect(prefs2.getString('tema_modo'), 'dark');
    });

    testWidgets('tocar con el sistema en claro pasa a oscuro y lo guarda',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(tester, Brightness.light);
      final themeService = await ThemeService.cargar();
      var brightness = Brightness.dark;
      await tester.pumpWidget(
        appConTema(themeService, onBrightness: (v) => brightness = v),
      );
      await tester.pumpAndSettle();
      await abrirPanel(tester);

      expect(interruptorEncendido(tester), isFalse);

      await tester.tap(find.byKey(const Key('ajustes-tema-oscuro')));
      await tester.pumpAndSettle();

      // El interruptor estaba apagado, asi que el opuesto es "oscuro".
      expect(interruptorEncendido(tester), isTrue);
      expect(brightness, Brightness.dark);
      expect(themeService.modo, ThemeMode.dark);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), 'dark');
    });

    testWidgets('reiniciar la app mantiene la elección', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(tester, Brightness.dark);
      final themeService = await ThemeService.cargar();
      var brightness = Brightness.light;
      await tester.pumpWidget(
        appConTema(themeService, onBrightness: (v) => brightness = v),
      );
      await tester.pumpAndSettle();
      await abrirPanel(tester);

      // El sistema en oscuro, un toque lo deja en claro y lo guarda.
      await tester.tap(find.byKey(const Key('ajustes-tema-oscuro')));
      await tester.pumpAndSettle();
      expect(themeService.modo, ThemeMode.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), 'light');

      // Se cierra el panel antes de "reiniciar", porque showModalBottomSheet
      // deja una ruta en el Navigator y el arbol se reutiliza.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Ajustes'), findsNothing);

      // Sesion nueva: arranca con la eleccion guardada, sin pedir nada y sin
      // mirar el sistema, que ahora sigue en oscuro.
      final nuevaSesion = await ThemeService.cargar();
      expect(nuevaSesion.modo, ThemeMode.light);
      expect(nuevaSesion.esOscuro, isFalse);

      brightness = Brightness.dark;
      await tester.pumpWidget(
        appConTema(nuevaSesion, onBrightness: (v) => brightness = v),
      );
      await tester.pumpAndSettle();

      expect(brightness, Brightness.light);
      await abrirPanel(tester);

      expect(interruptorEncendido(tester), isFalse);
    });

    testWidgets('cerrar sesión desde el panel redirige a la pantalla de login',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(tester, Brightness.light);
      final themeService = await ThemeService.cargar();
      await tester.pumpWidget(appConTema(themeService));
      await tester.pumpAndSettle();

      await abrirPanel(tester);

      await tester.tap(find.byKey(const Key('ajustes-cerrar-sesion')));
      await tester.pumpAndSettle();

      expect(auth.cerrada, isTrue);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);
    });
  });
}
