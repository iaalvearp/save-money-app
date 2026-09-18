import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

class AuthService {
  final ApiClient _api;
  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  AuthService({ApiClient? api, FlutterSecureStorage? storage})
      : _api = api ??
            ApiClient(
                baseUrl: 'https://save-money-backend.iaalvearp.workers.dev'),
        _storage = storage ?? const FlutterSecureStorage();

  Future<void> registro({
    required String email,
    required String password,
    required String nombreCompleto,
    required String rol,
    String? fechaNacimiento,
    bool? consentimientoPublicidad,
  }) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
      'nombre_completo': nombreCompleto,
      'rol': rol,
    };
    if (fechaNacimiento != null) {
      body['fecha_nacimiento'] = fechaNacimiento;
    }
    if (consentimientoPublicidad != null) {
      body['consentimiento_publicidad'] = consentimientoPublicidad;
    }

    await _api.post('/auth/registro', body: body);
  }

  Future<void> actualizarConsentimiento({
    required bool consentimientoPublicidad,
  }) async {
    await _api.patch('/auth/consentimiento', body: {
      'consentimiento_publicidad': consentimientoPublicidad,
    });
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.post('/auth/login', body: {
      'email': email,
      'password': password,
    });

    final accessToken = response['access_token'] as String?;
    final refreshToken = response['refresh_token'] as String?;

    if (accessToken == null || refreshToken == null) {
      throw ApiException(
        statusCode: 500,
        message: 'Respuesta del servidor sin tokens',
      );
    }

    await _saveTokens(accessToken: accessToken, refreshToken: refreshToken);
  }

  Future<bool> hasSession() async {
    final token = await _storage.read(key: _accessTokenKey);
    return token != null && token.isNotEmpty;
  }

  Future<String?> getAccessToken() async {
    return _storage.read(key: _accessTokenKey);
  }

  Future<String?> getRefreshToken() async {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> logout() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<void> _saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }
}
