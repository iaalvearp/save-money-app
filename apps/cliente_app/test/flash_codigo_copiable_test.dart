import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';
import 'package:cliente_app/services/flash_service.dart';
import 'package:cliente_app/widgets/codigo_copiable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeAuth extends AuthService {
  @override
  Future<String?> getAccessToken() async => 'token-de-sesion';

  @override
  Future<void> logout() async {}
}

const _codigo = 'FLASH-3K9P-7ZQ2';

/// Un servicio que devuelve el cupon con el que se premia al reclamo.
FlashService _servicioDePrueba() {
  final cliente = MockClient((peticion) async {
    if (peticion.url.path.contains('claim')) {
      return http.Response(
        '''
        {
          "cupon": {
            "id": 91,
            "codigo_qr": "$_codigo",
            "descuento": 50,
            "comercio": "PRUEBA Cafe Central",
            "expira_en": null
          },
          "mensaje": "50% de descuento en PRUEBA Cafe Central"
        }
        ''',
        201,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      '{"ya_reclamada": false}',
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  return FlashService(
    auth: _FakeAuth(),
    api: ApiClient(baseUrl: 'https://ejemplo.test', httpClient: cliente),
  );
}

void main() {
  final portapapeles = StringBuffer();

  setUp(() {
    portapapeles.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (llamada) async {
      if (llamada.method == 'Clipboard.setData') {
        portapapeles.clear();
        portapapeles.write(
          (llamada.arguments as Map<Object?, Object?>)['text'] as String?,
        );
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Monta el dialogo de "promocion reclamada" con el cupon del backend.
  ///
  /// Se arma aqui porque vive dentro de la pantalla de detalle, que es
  /// privada, y lo que importa es el codigo que se copia.
  Future<void> mostrarDialogoDeCupon(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    content: CodigoCopiable(codigo: _codigo),
                  ),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('el cupon que devuelve el reclamo se puede copiar',
      (tester) async {
    // Lo primero: el backend si entrega un codigo al reclamo.
    final respuesta = await _servicioDePrueba().reclamarPromocion(3);
    expect((respuesta['cupon'] as Map<String, dynamic>)['codigo_qr'],
        _codigo);

    await mostrarDialogoDeCupon(tester);
    expect(find.text(_codigo), findsOneWidget);

    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.copy),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(portapapeles.toString(), _codigo);
    expect(find.text('Código copiado'), findsOneWidget);
  });
}
