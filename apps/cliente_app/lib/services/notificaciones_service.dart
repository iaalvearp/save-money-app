import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  /// Marca de aviso cerrado. Se escribe cuando ya no tiene sentido volver a
  /// preguntar: el usuario dijo "Ahora no", o aceptó y el sistema le concedió
  /// el permiso o se lo denegó para siempre.
  static const claveAvisoCerrado = 'notificaciones_aviso_cerrado';

  /// Veces que se ha mostrado el aviso. Es el tope de seguridad para que un
  /// usuario que rechaza el diálogo del sistema no lo vea indefinidamente.
  static const claveVecesAviso = 'notificaciones_aviso_veces';

  /// Tope de seguridad: el aviso se muestra como máximo este número de veces
  /// por instalación.
  static const maximoVecesAviso = 2;

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
  })  : _api = api ??
            ApiClient(
                baseUrl: 'https://save-money-backend.iaalvearp.workers.dev'),
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

  /// Si el aviso está cerrado para siempre: el usuario dijo "Ahora no", o
  /// aceptó y el sistema le concedió el permiso o se lo denegó para siempre.
  Future<bool> avisoCerrado() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(claveAvisoCerrado) ?? false;
  }

  /// Cuántas veces se ha mostrado el aviso en esta instalación.
  Future<int> vecesAviso() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(claveVecesAviso) ?? 0;
  }

  /// Anota que el aviso se ha mostrado. Se llama cada vez que se enseña.
  Future<void> registrarAvisoMostrado() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(claveVecesAviso, (prefs.getInt(claveVecesAviso) ?? 0) + 1);
  }

  Future<void> cerrarAviso() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(claveAvisoCerrado, true);
  }

  /// Si toca mostrar el aviso.
  ///
  /// Devuelve false si el usuario eligió "Ahora no"; false si el aviso ya se
  /// mostró [maximoVecesAviso] veces o más; false si el permiso está concedido
  /// o denegado de forma permanente, porque no habría respuesta posible.
  ///
  /// Devuelve true si el permiso sigue sin decidir o está denegado de forma
  /// simple, porque en ambos casos el sistema todavía puede volver a preguntar.
  Future<bool> debeMostrarAviso() async {
    if (await avisoCerrado()) return false;
    if (await vecesAviso() >= maximoVecesAviso) return false;
    final estado = await estadoPermiso();
    return estado == EstadoPermisoNotificaciones.noDeterminado ||
        estado == EstadoPermisoNotificaciones.denegado;
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