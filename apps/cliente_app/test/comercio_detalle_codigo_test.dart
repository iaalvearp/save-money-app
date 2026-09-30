import 'package:cliente_app/screens/comercio_detail_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/comercios_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Un servicio de prueba que devuelve un comercio con una promoción, para llegar
/// a la tarjeta donde se muestra el código.
ComerciosService _servicioConPromocion(String codigoQr) {
  final cliente = MockClient((peticion) async {
    return http.Response(
      '''
      {
        "comercio": {
          "id": 7,
          "nombre": "Cafe Central",
          "direccion": "Av. Siempre Viva 742",
          "categoria": "Cafeteria",
          "latitud": -2.1894,
          "longitud": -79.8891
        },
        "promociones": [
          {
            "id": 3,
            "codigo_qr": "$codigoQr",
            "descuento": 15,
            "expira_en": "2026-10-05T00:00:00Z"
          }
        ]
      }
      ''',
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  return ComerciosService(
    api: ApiClient(baseUrl: 'https://ejemplo.test', httpClient: cliente),
  );
}

void main() {
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

  testWidgets('copia el código de la promoción del comercio', (tester) async {
    const codigo = 'PROMO-9Z4K-2X7B';
    await tester.pumpWidget(
      MaterialApp(
        home: ComercioDetailScreen(
          comercioId: 7,
          servicio: _servicioConPromocion(codigo),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Código: $codigo'), findsOneWidget);

    final copiar = find.ancestor(
      of: find.byIcon(Icons.copy),
      matching: find.byType(IconButton),
    );
    expect(copiar, findsOneWidget);

    await tester.tap(copiar);
    await tester.pumpAndSettle();

    // Solo el código, sin el prefijo que lo rotula en pantalla.
    expect(portapapeles.toString(), codigo);
    expect(find.text('Código copiado'), findsOneWidget);
  });
}
