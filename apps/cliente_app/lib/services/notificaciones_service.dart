import 'package:firebase_messaging/firebase_messaging.dart';

import 'api_client.dart';
import 'auth_service.dart';

class NotificacionesService {
  final ApiClient _api;
  final AuthService _auth;
  final Future<String?> Function() _obtenerTokenFcm;

  NotificacionesService({
    ApiClient? api,
    AuthService? auth,
    Future<String?> Function()? obtenerTokenFcm,
  })  : _api = api ??
            ApiClient(
                baseUrl: 'https://save-money-backend.iaalvearp.workers.dev'),
        _auth = auth ?? AuthService(),
        _obtenerTokenFcm = obtenerTokenFcm ?? _tokenFcmPorDefecto;

  static Future<String?> _tokenFcmPorDefecto() async {
    return FirebaseMessaging.instance.getToken();
  }

  Future<void> registrarToken() async {
    try {
      final fcmToken = await _obtenerTokenFcm();
      if (fcmToken == null || fcmToken.trim().isEmpty) return;

      final accessToken = await _auth.getAccessToken();
      if (accessToken == null) return;

      await _api.put(
        '/auth/fcm-token',
        body: {'fcm_token': fcmToken},
        token: accessToken,
      );
    } catch (_) {
      // Registrar el token no debe impedir el uso normal de la app
    }
  }

  Future<Map<String, dynamic>> probarNotificacion() async {
    final accessToken = await _auth.getAccessToken();
    if (accessToken == null) {
      throw ApiException(
        statusCode: 401,
        message: 'No hay sesión iniciada',
      );
    }
    return _api.post(
      '/notificaciones/test',
      body: const <String, dynamic>{},
      token: accessToken,
    );
  }
}