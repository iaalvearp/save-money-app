import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/theme_service.dart';
import 'historial_facturas_screen.dart';
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
                    themeService.esOscuro ? Icons.dark_mode : Icons.light_mode,
                  ),
                  title: const Text('Tema oscuro'),
                  // Sin subtitulo: no hay una tercera opcion que describir.
                  value: themeService.esOscuro,
                  onChanged: (_) {
                    themeService.alternar();
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('ajustes-mis-facturas'),
                  leading: const Icon(Icons.receipt_long),
                  title: const Text('Mis facturas'),
                  subtitle: const Text('Consulta el estado de tus facturas'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HistorialFacturasScreen(),
                      ),
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
