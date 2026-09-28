import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier with WidgetsBindingObserver {
  static const _preferenceKey = 'tema_modo';

  ThemeMode _modo = ThemeMode.system;
  Brightness _brilloDelSistema = Brightness.light;

  ThemeMode get modo => _modo;

  /// Lo que de verdad se esta viendo ahora mismo.
  ///
  /// Mientras el usuario no haya tocado el interruptor, `_modo` es
  /// [ThemeMode.system] y lo que se ve es lo que diga el sistema. En cuanto
  /// toca, `_modo` pasa a ser `light` o `dark` y manda su eleccion, no el
  /// sistema. Ese cambio de comportamiento es el esperado y no se revierte.
  Brightness get brilloEfectivo {
    if (_modo == ThemeMode.dark) return Brightness.dark;
    if (_modo == ThemeMode.light) return Brightness.light;
    return _brilloDelSistema;
  }

  /// El interruptor del panel de ajustes muestra esto, no el modo guardado.
  ///
  /// Antes se comparaba contra `ThemeMode.dark`, y con el sistema en oscuro
  /// eso daba falso: el interruptor se veia apagado mientras la pantalla ya
  /// estaba en oscuro. El interruptor tiene que reflejar lo que se ve.
  bool get esOscuro => brilloEfectivo == Brightness.dark;

  ThemeService() {
    WidgetsBinding.instance.addObserver(this);
    _brilloDelSistema = _leerBrilloDelSistema();
  }

  static Brightness _leerBrilloDelSistema() =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  @override
  void didChangePlatformBrightness() {
    // Ya no seguimos al sistema: el usuario hizo su eleccion y manda ella.
    if (_modo != ThemeMode.system) return;
    _brilloDelSistema = _leerBrilloDelSistema();
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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

  /// El interruptor: pasa al opuesto de lo que se esta viendo y lo guarda.
  ///
  /// No hay un tercer estado al que volver. Si todavia no hay eleccion guardada
  /// el modo es `system`, y tocar aqui lo convierte en `light` o `dark`
  /// explicito: es el primer toque el que deja de seguir al sistema.
  Future<void> alternar() async {
    await setModo(esOscuro ? ThemeMode.light : ThemeMode.dark);
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
