import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const _preferenceKey = 'tema_modo';

  ThemeMode _modo = ThemeMode.system;

  ThemeMode get modo => _modo;

  bool get esOscuro => _modo == ThemeMode.dark;

  static Future<ThemeService> cargar() async {
    final service = ThemeService();
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(_preferenceKey);
    if (guardado != null) {
      service._modo = ThemeMode.values.firstWhere(
        (m) => m.name == guardado,
        orElse: () => ThemeMode.system,
      );
    }
    return service;
  }

  Future<void> setModo(ThemeMode modo) async {
    if (modo == _modo) return;
    _modo = modo;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferenceKey, modo.name);
  }
}

class ThemeScope extends InheritedNotifier<ThemeService> {
  const ThemeScope({super.key, required ThemeService super.notifier, required super.child});

  static ThemeService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope?.notifier != null, 'ThemeScope no encontrado en el árbol');
    return scope!.notifier!;
  }
}
