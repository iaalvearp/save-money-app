import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/role_navigation.dart';
import 'services/auth_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Save Money',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const SessionGate(),
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
