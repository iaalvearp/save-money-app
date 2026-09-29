import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
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

/// Un aviso recibido, tal como se guarda en el dispositivo.
///
/// Se guarda local y no contra el backend porque el aviso se relé para que
/// siga ahí al volver a entrar, y porque así se lee aunque la app no tenga red.
/// El backend solo manda; el registro de lo que se envió está en su auditoría.
class Notificacion {
  final String id;
  final String titulo;
  final String cuerpo;

  /// Lo que el backend manda en `data`: el tipo de aviso y las referencias que
  /// necesita, como el evento o la promoción. Se conserva para poder abrir el
  /// destino al tocarla.
  final Map<String, String> data;

  /// Cuándo la recibió el dispositivo, no cuándo la generó el backend. Es lo
  /// que ordena la lista y lo que decide si se conserva.
  final DateTime fecha;

  final bool leida;

  const Notificacion({
    required this.id,
    required this.titulo,
    required this.cuerpo,
    required this.data,
    required this.fecha,
    this.leida = false,
  });

  Notificacion copyWith({bool? leida}) => Notificacion(
    id: id,
    titulo: titulo,
    cuerpo: cuerpo,
    data: data,
    fecha: fecha,
    leida: leida ?? this.leida,
  );

  Map<String, dynamic> aJson() => {
    'id': id,
    'titulo': titulo,
    'cuerpo': cuerpo,
    'data': data,
    'fecha': fecha.toIso8601String(),
    'leida': leida,
  };

  /// Lee un aviso guardado. Un registro incompleto o de una versión anterior no
  /// puede romper la bandeja entera, así que los campos se rellenan con lo que
  /// haya en vez de lanzar.
  factory Notificacion.desdeJson(Map<String, dynamic> json) {
    final dataBruta = json['data'];
    return Notificacion(
      id: json['id']?.toString() ?? '',
      titulo: json['titulo']?.toString() ?? '',
      cuerpo: json['cuerpo']?.toString() ?? '',
      data: dataBruta is Map
          ? dataBruta.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      fecha:
          DateTime.tryParse(json['fecha']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      leida: json['leida'] == true,
    );
  }
}

class NotificacionesService extends ChangeNotifier {
  /// Dónde se guarda el buzón.
  static const _claveBuzon = 'notificaciones_buzon';

  /// Lo que se conserva. Un aviso más viejo que esto ya no informa de nada: la
  /// promoción que anunciaba terminó y el evento ya pasó.
  static const ventanaAntigua = Duration(hours: 72);

  final ApiClient _api;
  final AuthService _auth;
  final Future<String?> Function() _obtenerTokenFcm;

  /// Inyectan la consulta y la solicitud del permiso en vez de hablar con
  /// Firebase. Solo se usan en pruebas; en la app van las de Firebase.
  final Future<AuthorizationStatus> Function()? estadoOverride;
  final Future<AuthorizationStatus> Function()? solicitarOverride;

  /// Inyectan los tres orígenes de Firebase Messaging, para poder provocar un
  /// aviso en las pruebas sin un proyecto de Firebase detrás.
  final Stream<RemoteMessage>? alRecibirMensaje;
  final Stream<RemoteMessage>? alAbrirMensaje;
  final Future<RemoteMessage?> Function()? mensajeInicial;

  List<Notificacion> _lista = <Notificacion>[];
  final List<StreamSubscription<RemoteMessage>> _suscripciones = [];

  NotificacionesService({
    ApiClient? api,
    AuthService? auth,
    Future<String?> Function()? obtenerTokenFcm,
    this.estadoOverride,
    this.solicitarOverride,
    this.alRecibirMensaje,
    this.alAbrirMensaje,
    this.mensajeInicial,
  }) : _api =
           api ??
           ApiClient(
             baseUrl: 'https://save-money-backend.iaalvearp.workers.dev',
           ),
       _auth = auth ?? AuthService(),
       _obtenerTokenFcm = obtenerTokenFcm ?? _tokenFcmPorDefecto;

  /// La instancia que usa la app.
  ///
  /// El buzón tiene que ser uno solo: la campana de la pantalla de inicio
  /// cuenta las no leídas y el servicio que escucha Firebase las guarda. Si cada
  /// uno tuviera el suyo, el contador siempre marcaría cero.
  static NotificacionesService? _compartido;

  static NotificacionesService compartido() {
    return _compartido ??= NotificacionesService();
  }

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

  // Buzón local.

  /// Los avisos, del más reciente al más antiguo.
  List<Notificacion> get lista => List.unmodifiable(_lista);

  /// Cuántos hay sin leer. Es lo que muestra la insignia de la campana.
  int get noLeidas => _lista.where((n) => !n.leida).length;

  /// Lee el buzón del dispositivo y descarta lo que ya no informa.
  ///
  /// Se purga al abrir, no al escribir: un aviso que se borra por su cuenta es
  /// un aviso que nadie vio, y la cuenta se lleva con la app cerrada.
  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final leidas = _leer(prefs.getString(_claveBuzon));

    final ahora = DateTime.now();
    final vigentes = leidas
        .where((n) => ahora.difference(n.fecha) <= ventanaAntigua)
        .toList();
    _lista = _ordenar(vigentes);

    notifyListeners();
    if (vigentes.length != leidas.length) await _persistir();
  }

  /// Escucha los avisos de Firebase. Se llama una vez al arrancar.
  ///
  /// Los tres caminos importan y no son equivalentes: con la app abierta el
  /// aviso entra como no leído; si la persona lo tocó con la app en segundo
  /// plano, o la abrió desde el aviso con la app cerrada, ya lo vio, así que
  /// entra leído.
  Future<void> escucharMensajes() async {
    final recibir = alRecibirMensaje ?? FirebaseMessaging.onMessage;
    final abrir = alAbrirMensaje ?? FirebaseMessaging.onMessageOpenedApp;
    final inicial =
        mensajeInicial ?? FirebaseMessaging.instance.getInitialMessage;

    _suscripciones.add(recibir.listen((m) => registrarMensaje(m)));

    _suscripciones.add(abrir.listen((m) => registrarMensaje(m, leida: true)));

    // Con la app cerrada no hay stream al que suscribirse: el mensaje llega
    // suelto y solo se recupera una vez.
    final primerAviso = await inicial();
    if (primerAviso != null) {
      await registrarMensaje(primerAviso, leida: true);
    }
  }

  @override
  void dispose() {
    for (final s in _suscripciones) {
      s.cancel();
    }
    _suscripciones.clear();
    super.dispose();
  }

  /// Guarda un aviso recibido.
  ///
  /// [leida] lo marca en el momento de entrar: quien lo abrió desde el aviso ya
  /// lo leyó, y dejarlo sin leer sería un contador que no baja nunca.
  Future<void> registrarMensaje(
    RemoteMessage mensaje, {
    bool leida = false,
  }) async {
    final ahora = DateTime.now();
    final aviso = Notificacion(
      // FCM no garantiza un id utilizable, así que se compone con la hora de
      // recepción: dos avisos del mismo tipo seguidos no se pisan.
      id: '${mensaje.messageId ?? mensaje.sentTime?.millisecondsSinceEpoch ?? ''}-${ahora.microsecondsSinceEpoch}',
      titulo: mensaje.notification?.title ?? '',
      cuerpo: mensaje.notification?.body ?? '',
      data: mensaje.data.map((k, v) => MapEntry(k, v.toString())),
      fecha: ahora,
      leida: leida,
    );

    _lista = _ordenar([aviso, ..._lista]);
    notifyListeners();
    await _persistir();
  }

  /// Marca un aviso como leído y lo deja en la lista.
  ///
  /// Tocar un aviso no lo borra: se puede querer volver a consultarlo.
  Future<void> marcarLeida(String id) async {
    final indice = _lista.indexWhere((n) => n.id == id);
    if (indice < 0 || _lista[indice].leida) return;
    _lista = [..._lista]..[indice] = _lista[indice].copyWith(leida: true);
    notifyListeners();
    await _persistir();
  }

  /// Marca todos los avisos como leídos sin borrar ninguno.
  Future<void> marcarTodasLeidas() async {
    if (_lista.every((n) => n.leida)) return;
    _lista = _lista.map((n) => n.copyWith(leida: true)).toList();
    notifyListeners();
    await _persistir();
  }

  /// Vacía el buzón del dispositivo. Lo que ya se envió no se puede deshacer:
  /// es una limpieza local, no una baja de la cuenta.
  Future<void> borrarTodas() async {
    if (_lista.isEmpty) return;
    _lista = <Notificacion>[];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_claveBuzon);
  }

  List<Notificacion> _ordenar(List<Notificacion> avisos) {
    return [...avisos]..sort((a, b) => b.fecha.compareTo(a.fecha));
  }

  List<Notificacion> _leer(String? crudo) {
    if (crudo == null || crudo.isEmpty) return <Notificacion>[];
    try {
      final decodificado = jsonDecode(crudo);
      if (decodificado is! List) return <Notificacion>[];
      return decodificado
          .whereType<Map>()
          .map((m) => Notificacion.desdeJson(m.cast<String, dynamic>()))
          .where((n) => n.id.isNotEmpty)
          .toList();
    } catch (e) {
      // Un buzón corrupto no puede impedir abrir la app. Se descarta y se
      // sigue, en vez de dejar la pantalla en blanco sin explicación.
      debugPrint('[notificaciones] Buzón ilegible, se empieza vacío: $e');
      return <Notificacion>[];
    }
  }

  Future<void> _persistir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _claveBuzon,
      jsonEncode(_lista.map((n) => n.aJson()).toList()),
    );
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
      throw ApiException(statusCode: 401, message: 'No hay sesión iniciada');
    }
    return _api.post(
      '/notificaciones/test',
      body: const <String, dynamic>{},
      token: accessToken,
    );
  }
}

/// Expone el buzón a las pantallas que lo necesitan, sobre todo a la campana de
/// la pantalla de inicio para su insignia de no leídas.
class NotificacionesScope extends InheritedNotifier<NotificacionesService> {
  const NotificacionesScope({
    super.key,
    required NotificacionesService super.notifier,
    required super.child,
  });

  /// El buzón si está en el árbol, o `null` si la pantalla se está probando o
  /// se usa sin él. La campana se dibuja igual en ese caso, solo que sin
  /// contador.
  static NotificacionesService? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NotificacionesScope>()
        ?.notifier;
  }
}
