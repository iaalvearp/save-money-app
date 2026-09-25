import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';
import 'package:cliente_app/services/notificaciones_service.dart';

class _FakeAuth extends AuthService {
  final String? accessToken;

  _FakeAuth({this.accessToken});

  @override
  Future<String?> getAccessToken() async => accessToken;
}

void main() {
  group('NotificacionesService.registrarToken', () {
    test('envía el token FCM por PUT /auth/fcm-token', () async {
      String? ruta;
      String? authHeader;
      Map<String, dynamic>? body;

      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          ruta = request.url.path;
          authHeader = request.headers['Authorization'];
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            '{"ok": true}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final servicio = NotificacionesService(
        api: api,
        auth: _FakeAuth(accessToken: 'token-de-prueba'),
        obtenerTokenFcm: () async => 'token-fcm-abc',
      );

      await servicio.registrarToken();

      expect(ruta, '/auth/fcm-token');
      expect(authHeader, 'Bearer token-de-prueba');
      expect(body, {'fcm_token': 'token-fcm-abc'});
    });

    test('no llama al backend si la sesión no tiene access token', () async {
      var llamadas = 0;

      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          llamadas++;
          return http.Response(
            '{"ok": true}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final servicio = NotificacionesService(
        api: api,
        auth: _FakeAuth(accessToken: null),
        obtenerTokenFcm: () async => 'token-fcm-abc',
      );

      await servicio.registrarToken();

      expect(llamadas, 0);
    });

    test('no llama al backend si no se obtiene token FCM', () async {
      var llamadas = 0;

      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          llamadas++;
          return http.Response(
            '{"ok": true}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final servicio = NotificacionesService(
        api: api,
        auth: _FakeAuth(accessToken: 'token-de-prueba'),
        obtenerTokenFcm: () async => null,
      );

      await servicio.registrarToken();

      expect(llamadas, 0);
    });
  });
}