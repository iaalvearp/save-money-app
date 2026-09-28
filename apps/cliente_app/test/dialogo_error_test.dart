import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cliente_app/widgets/dialogo_error.dart';

void main() {
  group('mostrarErrorDialog', () {
    testWidgets('muestra el titulo, el mensaje y el boton Entendido',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => mostrarErrorDialog(
                  context,
                  titulo: 'QR no válido',
                  mensaje: 'Este código QR no es una clave de acceso válida.',
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('QR no válido'), findsOneWidget);
      expect(
        find.text('Este código QR no es una clave de acceso válida.'),
        findsOneWidget,
      );
      expect(find.text('Entendido'), findsOneWidget);
    });

    testWidgets('el dialogo no se cierra solo: sigue abierto sin tocar nada',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => mostrarErrorDialog(
                  context,
                  titulo: 'No se pudo reclamar',
                  mensaje: 'La promoción ha expirado.',
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // Se avanza el reloj de pruebas mas alla de la duracion de un SnackBar.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('no se cierra tocando fuera, pero si con Entendido',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => mostrarErrorDialog(
                  context,
                  titulo: 'Error',
                  mensaje: 'Algo fallo',
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // Un toque en la barrera no debe cerrar el aviso.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('el boton Entendido devuelve un futuro que termina al cerrar',
        (tester) async {
      var cerrado = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  await mostrarErrorDialog(
                    context,
                    titulo: 'Error',
                    mensaje: 'Algo fallo',
                  );
                  cerrado = true;
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(cerrado, isFalse);

      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(cerrado, isTrue);
    });

    testWidgets('un mensaje largo se puede leer entero sin desbordarse',
        (tester) async {
      final largo = List.filled(60, 'frase del error').join(' ');

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => mostrarErrorDialog(
                  context,
                  titulo: 'Error',
                  mensaje: largo,
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });
}
