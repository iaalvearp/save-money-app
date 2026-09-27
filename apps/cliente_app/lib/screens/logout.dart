import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';

Future<void> cerrarSesion(BuildContext context, {AuthService? auth}) async {
  await (auth ?? AuthService()).logout();
  if (!context.mounted) return;
  await Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    (route) => false,
  );
}
