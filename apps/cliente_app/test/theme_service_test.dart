import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cliente_app/services/theme_service.dart';

/// El dispatcher de pruebas: en un `test()` normal no es el de verdad, asi que
/// hay que buscarlo con el tipo especifico para poder darle valores.
TestPlatformDispatcher get plataforma =>
    WidgetsBinding.instance.platformDispatcher as TestPlatformDispatcher;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Fija el brillo que "dice" el sistema y lo devuelve al valor inicial al
  /// terminar, para que un test no se bledee en el siguiente.
  void sistemaEn(Brightness brillo) {
    plataforma.platformBrightnessTestValue = brillo;
    // platformBrightnessTestValue no admite null: se devuelve a claro, que es
    // lo que usan las pruebas por defecto.
    addTearDown(() => plataforma.platformBrightnessTestValue = Brightness.light);
  }

  group('ThemeService sin eleccion guardada', () {
    test('usa el tema del sistema y no persiste nada', () async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(Brightness.light);

      final service = await ThemeService.cargar();

      // Sin preferencia guardada, el modo sigue siendo `system`: eso es
      // interno, no una opcion que se le muestre a nadie.
      expect(service.modo, ThemeMode.system);
      expect(service.esOscuro, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), isNull);
    });

    test('con el sistema en oscuro lo que se ve es oscuro', () async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(Brightness.dark);

      final service = await ThemeService.cargar();

      expect(service.modo, ThemeMode.system);
      expect(service.esOscuro, isTrue);
    });
  });

  group('El interruptor siempre va al opuesto', () {
    test('sistema en claro, tocar deja oscuro explicito y lo guarda', () async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(Brightness.light);
      final service = await ThemeService.cargar();

      await service.alternar();

      expect(service.modo, ThemeMode.dark);
      expect(service.esOscuro, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), 'dark');
    });

    test('sistema en oscuro, tocar deja claro explicito y lo guarda',
        () async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(Brightness.dark);
      final service = await ThemeService.cargar();

      await service.alternar();

      expect(service.modo, ThemeMode.light);
      expect(service.esOscuro, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), 'light');
    });

    test('en claro explicito, tocar pasa a oscuro y lo guarda', () async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(Brightness.light);
      final service = await ThemeService.cargar();
      await service.setModo(ThemeMode.light);

      await service.alternar();

      expect(service.modo, ThemeMode.dark);
      expect(service.esOscuro, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), 'dark');
    });

    test('en oscuro explicito, tocar pasa a claro y lo guarda', () async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(Brightness.light);
      final service = await ThemeService.cargar();
      await service.setModo(ThemeMode.dark);

      await service.alternar();

      expect(service.modo, ThemeMode.light);
      expect(service.esOscuro, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), 'light');
    });

    test('darle muchas veces nunca vuelve a `system`', () async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(Brightness.light);
      final service = await ThemeService.cargar();

      for (var i = 0; i < 6; i++) {
        await service.alternar();
        expect(
          service.modo,
          isNot(ThemeMode.system),
          reason: 'en la vuelta $i el modo no debe volver a ser system',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), 'light');
    });
  });

  group('Despues del primer toque ya no se sigue al sistema', () {
    test('con eleccion oscura, el sistema en claro no cambia nada', () async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(Brightness.light);
      final service = await ThemeService.cargar();
      // El sistema esta en claro, asi que alternar deja oscuro.
      await service.alternar();
      expect(service.modo, ThemeMode.dark);

      // Ahora el sistema pasa a oscuro. La eleccion del usuario manda.
      plataforma.platformBrightnessTestValue = Brightness.dark;

      expect(service.esOscuro, isTrue);
    });

    test('con eleccion clara, el sistema en oscuro no cambia nada', () async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(Brightness.dark);
      final service = await ThemeService.cargar();
      // El sistema esta en oscuro, asi que alternar deja claro.
      await service.alternar();
      expect(service.modo, ThemeMode.light);

      plataforma.platformBrightnessTestValue = Brightness.light;

      expect(service.esOscuro, isFalse);
    });

    test('el aviso de cambio del sistema solo suena si no hay eleccion',
        () async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(Brightness.light);
      final service = await ThemeService.cargar();
      var avisos = 0;
      service.addListener(() => avisos++);

      plataforma.platformBrightnessTestValue = Brightness.dark;
      await pumpEventQueue();

      // Sin eleccion todavia, el interruptor tiene que enterarse.
      expect(avisos, 1);
      expect(service.esOscuro, isTrue);

      await service.alternar();
      avisos = 0;
      plataforma.platformBrightnessTestValue = Brightness.light;
      await pumpEventQueue();

      // Ya hay eleccion: el sistema deja de mandar y no se avisa a nadie.
      expect(avisos, 0);
      expect(service.esOscuro, isFalse);
    });
  });

  group('Preferencia guardada', () {
    test('reiniciar mantiene la eleccion', () async {
      SharedPreferences.setMockInitialValues({'tema_modo': 'dark'});
      sistemaEn(Brightness.light);

      final service = await ThemeService.cargar();

      // El sistema en claro no importa: hay eleccion guardada.
      expect(service.modo, ThemeMode.dark);
      expect(service.esOscuro, isTrue);
    });

    test('reiniciar mantiene la eleccion clara con el sistema en oscuro',
        () async {
      SharedPreferences.setMockInitialValues({'tema_modo': 'light'});
      sistemaEn(Brightness.dark);

      final service = await ThemeService.cargar();

      expect(service.modo, ThemeMode.light);
      expect(service.esOscuro, isFalse);
    });

    test('una preferencia que no se entiende cae en el tema del sistema',
        () async {
      SharedPreferences.setMockInitialValues({'tema_modo': 'inventado'});
      sistemaEn(Brightness.light);

      final service = await ThemeService.cargar();

      expect(service.modo, ThemeMode.system);
    });

    test('el ciclo sobrevive a un reinicio en ambos sentidos', () async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(Brightness.light);

      // Sesion 1: el usuario elige oscuro.
      final primera = await ThemeService.cargar();
      await primera.alternar();
      expect(primera.modo, ThemeMode.dark);

      // Sesion 2: arranca en oscuro y un toque lo pasa a claro.
      final segunda = await ThemeService.cargar();
      expect(segunda.modo, ThemeMode.dark);
      await segunda.alternar();
      expect(segunda.modo, ThemeMode.light);

      // Sesion 3: arranca en claro.
      final tercera = await ThemeService.cargar();
      expect(tercera.modo, ThemeMode.light);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), 'light');
    });
  });

  group('setModo explicito', () {
    test('persiste los dos valores y avisa solo al cambiar de verdad',
        () async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(Brightness.light);
      final service = await ThemeService.cargar();
      var avisos = 0;
      service.addListener(() => avisos++);

      await service.setModo(ThemeMode.dark);
      expect(avisos, 1);
      expect(service.esOscuro, isTrue);

      await service.setModo(ThemeMode.dark);
      expect(avisos, 1);

      await service.setModo(ThemeMode.light);
      expect(avisos, 2);
      expect(service.esOscuro, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), 'light');
    });

    test('fijar claro o oscuro a mano funciona igual que tocar', () async {
      SharedPreferences.setMockInitialValues({});
      sistemaEn(Brightness.dark);
      final service = await ThemeService.cargar();

      await service.setModo(ThemeMode.dark);
      expect(service.esOscuro, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tema_modo'), 'dark');
    });
  });
}
