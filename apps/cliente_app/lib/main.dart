import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/role_navigation.dart';
import 'services/auth_service.dart';
import 'services/notificaciones_service.dart';
import 'services/theme_service.dart';
import 'widgets/reporte_ubicacion.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final themeService = await ThemeService.cargar();
  // El buzón se lee y se queda escuchando antes de dibujar nada: un aviso que
  // llegue con la app recién abierta tiene que estar en la lista, no aparecer
  // un segundo después de que la persona mire la campana.
  final notificaciones = NotificacionesService.compartido();
  await notificaciones.cargar();
  notificaciones.escucharMensajes();
  runApp(MyApp(themeService: themeService));
}

class MyApp extends StatelessWidget {
  final ThemeService themeService;

  const MyApp({super.key, required this.themeService});

  /// Radio de las esquinas de los botones y del botón flotante.
  static const double radioBoton = 8;

  /// El tema claro y el oscuro salen de acá para que no se separen.
  static ThemeData _tema(Brightness brillo) {
    final colores = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: brillo,
    );
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radioBoton),
    );

    return ThemeData(
      colorScheme: colores,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: forma),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: forma),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: forma),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: forma),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(shape: forma),
    );
  }

  /// El tema tal como lo arma la app, expuesto para las pruebas.
  @visibleForTesting
  static ThemeData temaDePruebas(Brightness brillo) => _tema(brillo);

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      notifier: themeService,
      child: ListenableBuilder(
        listenable: themeService,
        builder: (context, _) {
          return MaterialApp(
            title: 'Save Money',
            theme: _tema(Brightness.light),
            darkTheme: _tema(Brightness.dark),
            themeMode: themeService.modo,
            home: const SessionGate(),
          );
        },
      ),
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  late Future<Widget> _pantallaInicial;

  @override
  void initState() {
    super.initState();
    _pantallaInicial = _resolverPantallaInicial();
  }

  Future<Widget> _resolverPantallaInicial() async {
    final auth = AuthService();
    final hasSession = await auth.hasSession();
    if (!hasSession) return const LoginScreen();
    // TODO: implementar refresh automático del access token vencido
    // El aviso de notificaciones, y con él el registro del token FCM, va
    // dentro de pantallaInicialPorRol: así también ocurre tras un login en
    // caliente, que aquí no pasa por este código.
    final rol = await auth.rolActual();
    return pantallaInicialPorRol(rol);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _pantallaInicial,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final pantalla = snapshot.data ?? const LoginScreen();
        if (pantalla is LoginScreen) return pantalla;

        return ReporteUbicacion(child: pantalla);
      },
    );
  }
}
