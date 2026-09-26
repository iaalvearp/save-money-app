import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

class ApiClient {
  final String baseUrl;
  final http.Client _httpClient;
  AuthService? _authService;

  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    AuthService? authService,
  }) : _httpClient = httpClient ?? http.Client() {
    _authService = authService;
  }

  AuthService _obtenerAuthService() => _authService ??= AuthService(
        api: ApiClient(baseUrl: baseUrl, httpClient: _httpClient),
      );

  bool _requiereReintento(String path, String? token) {
    if (token == null) return false;
    if (path == '/auth/login' || path == '/auth/registro' || path == '/auth/refresh') {
      return false;
    }
    return true;
  }

  Future<Map<String, dynamic>> _enviar(
    Future<http.Response> Function(String? token) ejecutar,
    String path,
    String? token,
  ) async {
    var response = await ejecutar(token);

    if (response.statusCode == 401 && _requiereReintento(path, token)) {
      final nuevoToken = await _obtenerAuthService().refreshAccessToken();
      if (nuevoToken != null) {
        response = await ejecutar(nuevoToken);
      }
    }

    final responseBody = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw ApiException(
        statusCode: response.statusCode,
        message: responseBody['error'] as String? ?? 'Error desconocido',
      );
    }

    return responseBody;
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) {
    final uri = Uri.parse('$baseUrl$path');
    return _enviar((tokenActual) {
      return _httpClient.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
          if (tokenActual != null) 'Authorization': 'Bearer $tokenActual',
        },
        body: body != null ? jsonEncode(body) : null,
      );
    }, path, token);
  }

  Future<Map<String, dynamic>> get(
    String path, {
    String? token,
  }) {
    final uri = Uri.parse('$baseUrl$path');
    return _enviar((tokenActual) {
      return _httpClient.get(
        uri,
        headers: <String, String>{
          if (tokenActual != null) 'Authorization': 'Bearer $tokenActual',
        },
      );
    }, path, token);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) {
    final uri = Uri.parse('$baseUrl$path');
    return _enviar((tokenActual) {
      return _httpClient.patch(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
          if (tokenActual != null) 'Authorization': 'Bearer $tokenActual',
        },
        body: body != null ? jsonEncode(body) : null,
      );
    }, path, token);
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) {
    final uri = Uri.parse('$baseUrl$path');
    return _enviar((tokenActual) {
      return _httpClient.put(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
          if (tokenActual != null) 'Authorization': 'Bearer $tokenActual',
        },
        body: body != null ? jsonEncode(body) : null,
      );
    }, path, token);
  }

  void dispose() {
    _httpClient.close();
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';
}