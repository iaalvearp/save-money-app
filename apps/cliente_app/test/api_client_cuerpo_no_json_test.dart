import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliente_app/services/api_client.dart';

/// Construye un cliente que siempre responde lo mismo.
ApiClient _apiQueResponde(http.Response respuesta) {
  return ApiClient(
    baseUrl: 'http://test',
    httpClient: MockClient((_) async => respuesta),
  );
}

void main() {
  group('ApiClient cuerpo que no es JSON', () {
    test('un 500 con HTML lanza ApiException con el estado y el texto real',
        () async {
      final api = _apiQueResponde(
        http.Response(
          '<html><body><h1>502 Bad Gateway</h1></body></html>',
          500,
          headers: {'content-type': 'text/html'},
        ),
      );

      await expectLater(
        api.get('/cualquiera'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.message, 'message', contains('502 Bad Gateway')),
        ),
      );
    });

    test('un 404 con texto plano conserva el texto del servidor', () async {
      final api = _apiQueResponde(
        http.Response('No encontrado', 404, headers: {'content-type': 'text/plain'}),
      );

      await expectLater(
        api.get('/no-existe'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'No encontrado'),
        ),
      );
    });

    test('un cuerpo vacio usa el mensaje generico, sin romperse', () async {
      final api = _apiQueResponde(http.Response('', 503));

      await expectLater(
        api.get('/caido'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.message, 'message', 'Error desconocido'),
        ),
      );
    });

    test('un JSON que no es objeto (una lista) tambien es un error legible',
        () async {
      final api = _apiQueResponde(http.Response('[1, 2, 3]', 400));

      await expectLater(
        api.post('/algo', body: const {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.message, 'message', contains('[1, 2, 3]')),
        ),
      );
    });

    test('si el JSON trae error, ese mensaje gana sobre el texto crudo',
        () async {
      final api = _apiQueResponde(
        http.Response('{"error": "La clave ya fue registrada"}', 409),
      );

      await expectLater(
        api.post('/facturas', body: const {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', 'La clave ya fue registrada'),
        ),
      );
    });

    test('un 200 sin cuerpo se interpreta como un mapa vacio', () async {
      final api = _apiQueResponde(http.Response('', 204));

      expect(await api.get('/sin-cuerpo'), <String, dynamic>{});
    });

    test('un 200 con HTML no se devuelve como si fuera un resultado bueno',
        () async {
      final api = _apiQueResponde(http.Response('<html>mantenimiento</html>', 200));

      await expectLater(
        api.get('/lista'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 200),
        ),
      );
    });

    test('un 200 con JSON normal sigue devolviendo el mapa', () async {
      final api = _apiQueResponde(
        http.Response('{"comercios": [{"id": 1}]}', 200),
      );

      expect(await api.get('/comercios'), {
        'comercios': [
          {'id': 1}
        ]
      });
    });
  });
}
