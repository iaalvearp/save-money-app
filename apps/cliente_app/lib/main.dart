import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/role_navigation.dart';
import 'services/auth_service.dart';
import 'services/notificaciones_service.dart';
import 'services/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final themeService = await ThemeService.cargar();
  runApp(MyApp(themeService: themeService));
}

class MyApp extends StatelessWidget {
  final ThemeService themeService;

  const MyApp({super.key, required this.themeService});

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      notifier: themeService,
      child: ListenableBuilder(
        listenable: themeService,
        builder: (context, _) {
          return MaterialApp(
            title: 'Save Money',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.deepPurple,
                brightness: Brightness.dark,
              ),
            ),
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
    unawaited(NotificacionesService(auth: auth).registrarToken());
    // TODO: implementar refresh automático del access token vencido
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

        return snapshot.data ?? const LoginScreen();
      },
    );
  }
}
