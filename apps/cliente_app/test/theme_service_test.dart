import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cliente_app/services/theme_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeService', () {
    test('sin preferencia guardada usa el tema del sistema', () async {
      SharedPreferences.setMockInitialValues({});

      final service = await ThemeService.cargar();

      expect(service.modo, ThemeMode.system);
      expect(service.esOscuro, isFalse);
    });

    test('al cambiar a oscuro el ThemeMode cambia y se persiste', () async {
      SharedPreferences.setMockInitialValues({});
      final service = await ThemeService.cargar();

      await service.setModo(ThemeMode.dark);

      expect(service.modo, ThemeMode.dark);
      expect(service.esOscuro, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), 'dark');
    });

    test('al cambiar a claro el ThemeMode cambia y se persiste', () async {
      SharedPreferences.setMockInitialValues({});
      final service = await ThemeService.cargar();

      await service.setModo(ThemeMode.light);

      expect(service.modo, ThemeMode.light);
      expect(service.esOscuro, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), 'light');
    });

    test('al cargar de nuevo recupera la preferencia persistida', () async {
      SharedPreferences.setMockInitialValues({'tema_modo': 'dark'});

      final service = await ThemeService.cargar();

      expect(service.modo, ThemeMode.dark);
    });

    test('notifica a los oyentes al cambiar el modo y no al fijar el mismo',
        () async {
      SharedPreferences.setMockInitialValues({});
      final service = await ThemeService.cargar();
      var notificaciones = 0;
      service.addListener(() => notificaciones++);

      await service.setModo(ThemeMode.dark);
      expect(notificaciones, 1);

      await service.setModo(ThemeMode.dark);
      expect(notificaciones, 1);

      await service.setModo(ThemeMode.light);
      expect(notificaciones, 2);
    });
  });
}