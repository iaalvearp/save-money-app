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

  group('Panel de ajustes', () {
    testWidgets('el engranaje de la AppBar abre el panel de ajustes',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final themeService = await ThemeService.cargar();
      await tester.pumpWidget(appConTema(themeService));
      await tester.pumpAndSettle();

      expect(find.text('Ajustes'), findsNothing);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.text('Ajustes'), findsOneWidget);
      expect(find.byKey(const Key('ajustes-tema-oscuro')), findsOneWidget);
      expect(find.byKey(const Key('ajustes-cerrar-sesion')), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
    });

    testWidgets('el switch cambia visualmente el tema y lo persiste',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final themeService = await ThemeService.cargar();
      var brightness = Brightness.light;

      await tester.pumpWidget(
        appConTema(themeService, onBrightness: (valor) => brightness = valor),
      );
      await tester.pumpAndSettle();

      // La preferencia aún no existe, así que manda el tema del sistema (claro en test).
      expect(themeService.modo, ThemeMode.system);
      expect(brightness, Brightness.light);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ajustes-tema-oscuro')));
      await tester.pumpAndSettle();

      // El modo cambia y la app entera se repinta en oscuro.
      expect(themeService.modo, ThemeMode.dark);
      expect(brightness, Brightness.dark);

      // Queda persistido en la preferencia 'tema_modo'.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), 'dark');

      // Y una sesión nueva arranca con el tema ya oscuro, sin tocar nada.
      final nuevaSesion = await ThemeService.cargar();
      expect(nuevaSesion.modo, ThemeMode.dark);
    });

    testWidgets('cerrar sesión desde el panel redirige a la pantalla de login',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final themeService = await ThemeService.cargar();
      await tester.pumpWidget(appConTema(themeService));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ajustes-cerrar-sesion')));
      await tester.pumpAndSettle();

      expect(auth.cerrada, isTrue);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);
    });
  });
}