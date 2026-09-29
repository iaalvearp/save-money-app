import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;

import 'api_client.dart';
import 'auth_service.dart';

/// Estado del permiso de notificaciones, en los términos en que la app decide
/// si tiene sentido ofrecer activarlo.
enum EstadoPermisoNotificaciones {
  /// El usuario todavía no ha visto el diálogo del sistema. Es el único estado
  /// en el que se le puede preguntar.
  noDeterminado,

  /// Permitido. Android 13+ concede `POST_NOTIFICATIONS`; en iOS es
  /// `authorized` o `provisional`.
  concedido,

  /// Lo negó, pero el sistema todavía puede volver a mostrar el diálogo.
  denegado,

  /// Lo negó de forma permanente: solo se puede revertir desde los ajustes del
  /// dispositivo, así que volver a preguntar molesta sin resultado.
  denegadoPermanente,
}

class NotificacionesService {
  final ApiClient _api;
  final AuthService _auth;
  final Future<String?> Function() _obtenerTokenFcm;

  /// Inyectan la consulta y la solicitud del permiso en vez de hablar con
  /// Firebase. Solo se usan en pruebas; en la app van las de Firebase.
  final Future<AuthorizationStatus> Function()? estadoOverride;
  final Future<AuthorizationStatus> Function()? solicitarOverride;

  NotificacionesService({
    ApiClient? api,
    AuthService? auth,
    Future<String?> Function()? obtenerTokenFcm,
    this.estadoOverride,
    this.solicitarOverride,
  }) : _api =
           api ??
           ApiClient(
             baseUrl: 'https://save-money-backend.iaalvearp.workers.dev',
           ),
       _auth = auth ?? AuthService(),
       _obtenerTokenFcm = obtenerTokenFcm ?? _tokenFcmPorDefecto;

  static Future<String?> _tokenFcmPorDefecto() async {
    return FirebaseMessaging.instance.getToken();
  }

  /// Estado actual del permiso, sin lanzar ningún diálogo.
  Future<EstadoPermisoNotificaciones> estadoPermiso() async {
    final obtener = estadoOverride;
    if (obtener != null) {
      return _traducir(await obtener());
    }
    final ajustes = await FirebaseMessaging.instance.getNotificationSettings();
    return _traducir(ajustes.authorizationStatus);
  }

  /// Muestra el diálogo del sistema. Devuelve el estado resultante.
  ///
  /// `FirebaseMessaging.requestPermission` cubre las dos plataformas: en
  /// Android 13+ pide `POST_NOTIFICATIONS` vía `ActivityCompat` y distingue
  /// denegado de denegado permanentemente; en iOS muestra el diálogo nativo.
  Future<EstadoPermisoNotificaciones> solicitarPermiso() async {
    final solicitar = solicitarOverride;
    if (solicitar != null) {
      return _traducir(await solicitar());
    }
    final ajustes = await FirebaseMessaging.instance.requestPermission();
    return _traducir(ajustes.authorizationStatus);
  }

  static EstadoPermisoNotificaciones _traducir(AuthorizationStatus status) {
    switch (status) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return EstadoPermisoNotificaciones.concedido;
      case AuthorizationStatus.deniedPermanently:
        return EstadoPermisoNotificaciones.denegadoPermanente;
      case AuthorizationStatus.denied:
        return EstadoPermisoNotificaciones.denegado;
      case AuthorizationStatus.notDetermined:
        return EstadoPermisoNotificaciones.noDeterminado;
    }
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
    } catch (e, st) {
      // Registrar el token no debe impedir el uso normal de la app, así que el
      // error se traga. Antes ni siquiera se anotaba, y cuando el registro
      // fallaba no había forma de saber por qué las notificaciones no
      // llegaban. Se deja rastro en consola y el flujo sigue igual.
      debugPrint('[notificaciones] No se pudo registrar el token FCM: $e');
      debugPrintStack(
        stackTrace: st,
        label: '[notificaciones] origen del fallo al registrar el token FCM',
      );
    }
  }

  /// Abre los ajustes de la app, único camino para revertir un permiso de
  /// notificaciones denegado de forma permanente.
  ///
  /// Se separa de [solicitarPermiso] a propósito: cuando el sistema ya no va a
  /// mostrar el diálogo, volver a pedirlo solo le da a la persona la impresión de
  /// que la app no funciona.
  static Future<void> abrirConfiguracion() => openAppSettings();

  /// Reporta la posición actual del usuario para que el backend evalúe
  /// promociones Flash cercanas. Solo se llama con la app en primer plano.
  Future<void> reportarUbicacion({
    required double latitude,
    required double longitude,
  }) async {
    final accessToken = await _auth.getAccessToken();
    if (accessToken == null) return;

    await _api.put(
      '/auth/ubicacion',
      body: {'latitud': latitude, 'longitud': longitude},
      token: accessToken,
    );
  }

  Future<Map<String, dynamic>> probarNotificacion() async {
    final accessToken = await _auth.getAccessToken();
    if (accessToken == null) {
      throw ApiException(statusCode: 401, message: 'No hay sesión iniciada');
    }
    return _api.post(
      '/notificaciones/test',
      body: const <String, dynamic>{},
      token: accessToken,
    );
  }
}
