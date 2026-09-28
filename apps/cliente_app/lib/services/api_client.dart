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

    return _interpretar(response);
  }

  /// Convierte la respuesta en un mapa, o lanza el error que corresponde.
  ///
  /// El estado se mira antes de intentar leer el cuerpo. Si el servidor
  /// devolvió una página de error, un HTML o un texto plano, antes esto
  /// reventaba con un error de formato y se perdía tanto el estado real como
  /// el mensaje que el backend sí había escrito.
  Map<String, dynamic> _interpretar(http.Response response) {
    final cuerpo = response.body.trim();
    final objeto = cuerpo.isEmpty ? null : _leerJson(cuerpo);

    if (response.statusCode >= 400) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _mensajeDeError(cuerpo, objeto),
      );
    }

    // Una respuesta correcta sin cuerpo (por ejemplo un 204) no es un error:
    // simplemente no trae datos.
    if (objeto == null) {
      if (cuerpo.isEmpty) return <String, dynamic>{};
      throw ApiException(
        statusCode: response.statusCode,
        message: 'La respuesta del servidor no se pudo leer '
            '(se esperaba un objeto JSON)',
      );
    }

    return objeto;
  }

  /// Lee el cuerpo como objeto JSON, o devuelve null si no lo es.
  static Map<String, dynamic>? _leerJson(String cuerpo) {
    try {
      final decodificado = jsonDecode(cuerpo);
      return decodificado is Map<String, dynamic> ? decodificado : null;
    } on FormatException {
      return null;
    }
  }

  /// Elige el mensaje que se le va a mostrar a la persona.
  ///
  /// Se prefiere el campo "error" del backend; si no viene, se usa el texto
  /// crudo que respondió el servidor, y solo si no hay nada se cae en un
  /// mensaje genérico.
  static String _mensajeDeError(String cuerpo, Map<String, dynamic>? objeto) {
    final delJson = objeto?['error'];
    if (delJson is String && delJson.trim().isNotEmpty) {
      return delJson;
    }

    if (cuerpo.isNotEmpty) {
      return cuerpo;
    }

    return 'Error desconocido';
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