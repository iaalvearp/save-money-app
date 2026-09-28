import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cliente_app/main.dart';
import 'package:cliente_app/widgets/icono_cuadrado.dart';

/// Busca el `shape` que el tema le pone a un botón de cada tipo.
///
/// En los botones viene envuelto en un `WidgetStateProperty`, así que se resuelve
/// con los estados vacíos para leer la forma base.
ShapeBorder? _formaDe(ThemeData tema, String tipo) {
  const estados = <WidgetState>{};
  switch (tipo) {
    case 'elevated':
      return tema.elevatedButtonTheme.style?.shape?.resolve(estados);
    case 'filled':
      return tema.filledButtonTheme.style?.shape?.resolve(estados);
    case 'outlined':
      return tema.outlinedButtonTheme.style?.shape?.resolve(estados);
    case 'text':
      return tema.textButtonTheme.style?.shape?.resolve(estados);
    case 'fab':
      return tema.floatingActionButtonTheme.shape;
  }
  throw ArgumentError('tipo desconocido: $tipo');
}

const _tiposDeBoton = ['elevated', 'filled', 'outlined', 'text', 'fab'];

void main() {
  // Los dos temas salen del mismo metodo, asi que se prueban los dos.
  final temas = <String, ThemeData>{
    'claro': MyApp.temaDePruebas(Brightness.light),
    'oscuro': MyApp.temaDePruebas(Brightness.dark),
  };

  group('Tema: forma de los botones', () {
    for (final entrada in temas.entries) {
      test('el tema ${entrada.key} da radio 8 a todos los botones', () {
        for (final tipo in _tiposDeBoton) {
          final forma = _formaDe(entrada.value, tipo);
          expect(
            forma,
            isA<RoundedRectangleBorder>(),
            reason: 'el boton $tipo del tema ${entrada.key} no es redondeado',
          );
          expect(
            (forma! as RoundedRectangleBorder).borderRadius,
            BorderRadius.circular(8),
            reason: 'el boton $tipo del tema ${entrada.key} no tiene radio 8',
          );
        }
      });
    }

    testWidgets('un ElevatedButton real toma la forma del tema',
        (tester) async {
      late ShapeBorder? formaDelBoton;
      await tester.pumpWidget(
        MaterialApp(
          theme: MyApp.temaDePruebas(Brightness.light),
          home: Builder(
            builder: (context) {
              formaDelBoton = Theme.of(context)
                  .elevatedButtonTheme
                  .style
                  ?.shape
                  ?.resolve(const <WidgetState>{});
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      expect(formaDelBoton, isA<RoundedRectangleBorder>());
      expect(
        (formaDelBoton! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(8),
      );
    });
  });

  group('IconoCuadrado', () {
    testWidgets('es un cuadrado con esquinas de radio 8, no un circulo',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: IconoCuadrado(child: Text('C'))),
          ),
        ),
      );

      final contenedor = tester.widget<Container>(
        find.descendant(
          of: find.byType(IconoCuadrado),
          matching: find.byType(Container),
        ),
      );

      final decoracion = contenedor.decoration! as BoxDecoration;
      expect(decoracion.borderRadius, BorderRadius.circular(8));
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('mantiene el lado pedido', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: IconoCuadrado(tamano: 56, child: Icon(Icons.event))),
          ),
        ),
      );

      final size = tester.getSize(find.byType(IconoCuadrado));
      expect(size.width, 56);
      expect(size.height, 56);
    });

    testWidgets('es cuadrado: alto y ancho iguales', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: IconoCuadrado(child: Text('50%'))),
          ),
        ),
      );

      final size = tester.getSize(find.byType(IconoCuadrado));
      expect(size.width, size.height);
    });
  });
}
