import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';

class _AuthFake extends AuthService {
  final String? _nuevoToken;
  int llamadasRefresh = 0;

  _AuthFake(this._nuevoToken);

  @override
  Future<String?> refreshAccessToken() async {
    llamadasRefresh++;
    return _nuevoToken;
  }
}

const _jsonHeaders = {'content-type': 'application/json'};

void main() {
  group('ApiClient renovación automática en 401', () {
    test('401: refresca, reintenta una vez y devuelve el resultado bueno',
        () async {
      var llamadas = 0;
      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          llamadas++;
          final auth = request.headers['Authorization'];
          if (llamadas == 1) {
            expect(auth, 'Bearer token-viejo');
            return http.Response(
              '{"error": "Token inválido o expirado"}',
              401,
              headers: _jsonHeaders,
            );
          }
          expect(auth, 'Bearer token-nuevo');
          return http.Response(
            '{"datos": "ok"}',
            200,
            headers: _jsonHeaders,
          );
        }),
        authService: _AuthFake('token-nuevo'),
      );

      final resultado = await api.get('/protegido', token: 'token-viejo');

      expect(resultado, {'datos': 'ok'});
      expect(llamadas, 2);
    });

    test('401: el refresh también falla y el error original se propaga',
        () async {
      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          return http.Response(
            '{"error": "Token inválido o expirado"}',
            401,
            headers: _jsonHeaders,
          );
        }),
        authService: _AuthFake(null),
      );

      await expectLater(
        api.get('/protegido', token: 'token-viejo'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'Token inválido o expirado'),
        ),
      );
    });

    test('una llamada sin token no dispara el mecanismo', () async {
      final auth = _AuthFake('token-nuevo');
      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          return http.Response(
            '{"error": "Token de autenticación requerido"}',
            401,
            headers: _jsonHeaders,
          );
        }),
        authService: auth,
      );

      await expectLater(
        api.get('/publico'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );

      expect(auth.llamadasRefresh, 0);
    });

    test('/auth/refresh nunca dispara el mecanismo sobre sí mismo', () async {
      final auth = _AuthFake('token-nuevo');
      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          return http.Response(
            '{"error": "Refresh token inválido o expirado"}',
            401,
            headers: _jsonHeaders,
          );
        }),
        authService: auth,
      );

      await expectLater(
        api.post(
          '/auth/refresh',
          body: {'refresh_token': 'tok-refresh'},
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );

      expect(auth.llamadasRefresh, 0);
    });

    test('la llamada /auth/login tampoco dispara el mecanismo', () async {
      final auth = _AuthFake('token-nuevo');
      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          return http.Response(
            '{"error": "Credenciales inválidas"}',
            401,
            headers: _jsonHeaders,
          );
        }),
        authService: auth,
      );

      await expectLater(
        api.post(
          '/auth/login',
          body: {'email': 'a@b.c', 'password': 'wrong'},
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );

      expect(auth.llamadasRefresh, 0);
    });
  });
}