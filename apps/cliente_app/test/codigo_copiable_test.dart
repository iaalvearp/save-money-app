import 'package:cliente_app/widgets/codigo_copiable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // El portapapeles de verdad no existe en un test: se sustituye por este
  // double, que guarda lo último que le escribieron.
  final portapapeles = StringBuffer();

  setUp(() {
    portapapeles.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        portapapeles.clear();
        portapapeles.write(
          (call.arguments as Map<Object?, Object?>)['text'] as String?,
        );
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('CodigoCopiable', () {
    testWidgets('tocar el ícono copia el código y avisa', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CodigoCopiable(codigo: 'FL-123-ABC'),
          ),
        ),
      );

      expect(find.text('FL-123-ABC'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();

      expect(portapapeles.toString(), 'FL-123-ABC');
      expect(find.text('Código copiado'), findsOneWidget);
    });

    testWidgets('copia el código tal cual, con sus guiones', (tester) async {
      const codigo = '2X9K-4M7Q-TR8B-ZL5N';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CodigoCopiable(codigo: codigo)),
        ),
      );

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();

      expect(portapapeles.toString(), codigo);
    });

    testWidgets('el aviso se va solo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CodigoCopiable(codigo: 'ABC')),
        ),
      );

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();
      expect(find.text('Código copiado'), findsOneWidget);

      // El Snackbar no se queda pegado encima del código.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Código copiado'), findsNothing);
    });

    testWidgets('copiar dos veces no deja avisos apilados', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CodigoCopiable(codigo: 'ABC')),
        ),
      );

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();

      expect(find.text('Código copiado'), findsOneWidget);
      expect(portapapeles.toString(), 'ABC');
    });

    testWidgets('el ícono lleva tooltip para el lector de pantalla',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CodigoCopiable(codigo: 'ABC')),
        ),
      );

      final boton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.copy),
          matching: find.byType(IconButton),
        ),
      );
      expect(boton.tooltip, 'Copiar código');
    });
  });
}
