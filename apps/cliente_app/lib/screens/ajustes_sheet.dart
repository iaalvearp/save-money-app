import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/theme_service.dart';
import 'logout.dart';

Future<void> abrirAjustes(
  BuildContext context, {
  AuthService? auth,
}) async {
  final themeService = ThemeScope.of(context);
  final authService = auth ?? AuthService();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return ListenableBuilder(
        listenable: themeService,
        builder: (context, _) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Ajustes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                SwitchListTile(
                  key: const Key('ajustes-tema-oscuro'),
                  secondary: Icon(
                    themeService.modo == ThemeMode.dark
                        ? Icons.dark_mode
                        : Icons.light_mode,
                  ),
                  title: const Text('Tema oscuro'),
                  subtitle: Text(_descripcionModo(themeService.modo)),
                  value: themeService.modo == ThemeMode.dark,
                  onChanged: (oscuro) {
                    themeService.setModo(
                      oscuro ? ThemeMode.dark : ThemeMode.light,
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('ajustes-cerrar-sesion'),
                  leading: const Icon(Icons.logout),
                  title: const Text('Cerrar sesión'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await cerrarSesion(context, auth: authService);
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

String _descripcionModo(ThemeMode modo) {
  switch (modo) {
    case ThemeMode.light:
      return 'Siempre claro';
    case ThemeMode.dark:
      return 'Siempre oscuro';
    case ThemeMode.system:
      return 'Según el sistema';
  }
}
