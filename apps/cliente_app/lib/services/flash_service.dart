import 'api_client.dart';
import 'auth_service.dart';

class PromocionFlash {
  final int id;
  final int comercioId;
  final String titulo;
  final String? descripcion;
  final double descuentoPorcentaje;
  final String iniciaEn;
  final String terminaEn;
  final double? latitud;
  final double? longitud;
  final double radioKm;
  final String? categoria;
  final int? maxUsuarios;
  final int usuariosNotificados;
  final String? comercioNombre;

  PromocionFlash({
    required this.id,
    required this.comercioId,
    required this.titulo,
    this.descripcion,
    required this.descuentoPorcentaje,
    required this.iniciaEn,
    required this.terminaEn,
    this.latitud,
    this.longitud,
    this.radioKm = 5,
    this.categoria,
    this.maxUsuarios,
    this.usuariosNotificados = 0,
    this.comercioNombre,
  });

  factory PromocionFlash.fromJson(Map<String, dynamic> json) {
    return PromocionFlash(
      id: json['id'] as int,
      comercioId: json['comercio_id'] as int,
      titulo: json['titulo'] as String,
      descripcion: json['descripcion'] as String?,
      descuentoPorcentaje: (json['descuento_porcentaje'] as num).toDouble(),
      iniciaEn: json['inicia_en'] as String,
      terminaEn: json['termina_en'] as String,
      latitud: (json['latitud'] as num?)?.toDouble(),
      longitud: (json['longitud'] as num?)?.toDouble(),
      radioKm: (json['radio_km'] as num?)?.toDouble() ?? 5,
      categoria: json['categoria'] as String?,
      maxUsuarios: json['max_usuarios'] as int?,
      usuariosNotificados: json['usuarios_notificados'] as int? ?? 0,
      comercioNombre: json['comercio_nombre'] as String?,
    );
  }

  /// Si la promocion se puede usar ahora mismo.
  ///
  /// Los dos limites se cuentan como los cuenta el backend, que es lo unico
  /// que decide si la promo aparece en la lista: empieza inclusive y termina
  /// exclusive, `inicia_en <= ahora < termina_en`.
  bool get estaActiva {
    final now = DateTime.now().toUtc();
    final inicio = _leerComoUtc(iniciaEn);
    final fin = _leerComoUtc(terminaEn);
    return !now.isBefore(inicio) && now.isBefore(fin);
  }

  String get estadoTexto {
    final now = DateTime.now().toUtc();
    final inicio = _leerComoUtc(iniciaEn);
    final fin = _leerComoUtc(terminaEn);
    if (now.isBefore(inicio)) return 'Próximamente';
    if (!now.isBefore(fin)) return 'Finalizada';
    return 'Activa';
  }
}

class Cupon {
  final int id;
  final String codigoQr;
  final double? descuento;
  final String estado;
  final String tipo;
  final String? expiraEn;
  final String? canjeadoEn;
  final String? comercioNombre;
  final String? comercioFoto;

  Cupon({
    required this.id,
    required this.codigoQr,
    this.descuento,
    required this.estado,
    required this.tipo,
    this.expiraEn,
    this.canjeadoEn,
    this.comercioNombre,
    this.comercioFoto,
  });

  factory Cupon.fromJson(Map<String, dynamic> json) {
    return Cupon(
      id: json['id'] as int,
      codigoQr: json['codigo_qr'] as String,
      descuento: (json['descuento'] as num?)?.toDouble(),
      estado: json['estado'] as String,
      tipo: json['tipo'] as String,
      expiraEn: json['expira_en'] as String?,
      canjeadoEn: json['canjeado_en'] as String?,
      comercioNombre: json['comercio_nombre'] as String?,
      comercioFoto: json['comercio_foto'] as String?,
    );
  }

  bool get estaActivo => estado == 'activo';
}

final formatearFecha = (DateTime dt) =>
      dt.toUtc().toIso8601String().replaceFirst('T', ' ').substring(0, 19);

/// Una fecha como la guarda [formatearFecha]: AAAA-MM-DD HH:MM:SS, sin zona.
final _fechaHoraSinZona =
    RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$');

/// Lee una fecha como la guarda [formatearFecha]: en UTC, sin zona.
///
/// `DateTime.parse` no sirve aqui. Esa fecha viene escrita en UTC pero sin la
/// marca de zona, asi que el parseo la tomaria por hora local y la dejaria
/// cinco horas temprano en Ecuador: una promocion que ya empezo apareceria
/// como "Proximamente" y una que termino seguiria vigente.
DateTime _leerComoUtc(String texto) {
  final partes = _fechaHoraSinZona.firstMatch(texto.trim());
  if (partes == null) return DateTime.parse(texto).toUtc();
  return DateTime.utc(
    int.parse(partes.group(1)!),
    int.parse(partes.group(2)!),
    int.parse(partes.group(3)!),
    int.parse(partes.group(4)!),
    int.parse(partes.group(5)!),
    int.parse(partes.group(6) ?? '0'),
  );
}

class FlashService {
  final ApiClient _api;
  final AuthService _auth;

  FlashService({ApiClient? api, AuthService? auth})
      : _api = api ??
            ApiClient(
                baseUrl: 'https://save-money-backend.iaalvearp.workers.dev'),
        _auth = auth ?? AuthService();

  /// El token que se manda en cada peticion.
  ///
  /// Si quien llama no trae uno, se busca el de la sesion. Sin esto la
  /// peticion sale sin cabecera `Authorization`, el backend contesta 401 y la
  /// pantalla se queda vacia sin llegar a saber por que.
  Future<String?> _tokenDe(String? token) async {
    if (token != null) return token;
    return _auth.getAccessToken();
  }

  Future<List<PromocionFlash>> listarPromociones({
    double? lat,
    double? lng,
    String? categoria,
    String? token,
  }) async {
    final params = <String>[];
    if (lat != null && lng != null) {
      params.add('lat=$lat');
      params.add('lng=$lng');
    }
    if (categoria != null && categoria.isNotEmpty) {
      params.add('categoria=${Uri.encodeComponent(categoria)}');
    }

    final path = params.isEmpty
        ? '/flash/promociones'
        : '/flash/promociones?${params.join('&')}';

    final response = await _api.get(path, token: await _tokenDe(token));
    final promos = response['promociones'] as List<dynamic>? ?? [];
    return promos
        .map((p) => PromocionFlash.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<List<PromocionFlash>> promocionesDeComercio(
    int comercioId, {
    String? token,
  }) async {
    final promos = await listarPromociones(token: token);
    return promos.where((p) => p.comercioId == comercioId).toList();
  }

  Future<PromocionFlash> crearPromocion({
    required int comercioId,
    required String titulo,
    required double descuentoPorcentaje,
    required DateTime iniciaEn,
    required DateTime terminaEn,
    String? descripcion,
    double? latitud,
    double? longitud,
    double radioKm = 5,
    String? categoria,
    int? maxUsuarios,
    String? token,
  }) async {
    final response = await _api.post(
      '/flash/promociones',
      body: {
        'comercio_id': comercioId,
        'titulo': titulo,
        if (descripcion != null) 'descripcion': descripcion,
        'descuento_porcentaje': descuentoPorcentaje,
        'inicia_en': formatearFecha(iniciaEn),
        'termina_en': formatearFecha(terminaEn),
        if (latitud != null) 'latitud': latitud,
        if (longitud != null) 'longitud': longitud,
        'radio_km': radioKm,
        if (categoria != null) 'categoria': categoria,
        if (maxUsuarios != null) 'max_usuarios': maxUsuarios,
      },
      token: token,
    );
    return PromocionFlash.fromJson(response['promocion'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> obtenerPromocion(int id, {String? token}) async {
    final response = await _api.get(
      '/flash/promociones/$id',
      token: await _tokenDe(token),
    );
    return response;
  }

  Future<Map<String, dynamic>> reclamarPromocion(
    int promocionId, {
    String? token,
  }) async {
    final response = await _api.post(
      '/flash/promociones/$promocionId/claim',
      body: {},
      token: await _tokenDe(token),
    );
    return response;
  }

  Future<List<Cupon>> misCupones({String? token}) async {
    final response = await _api.get(
      '/flash/mis-cupones',
      token: await _tokenDe(token),
    );
    final cupones = response['cupones'] as List<dynamic>? ?? [];
    return cupones
        .map((c) => Cupon.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> canjearCupon(
    String codigoQr, {
    String? token,
  }) async {
    return _api.post(
      '/cupones/$codigoQr/canjear',
      body: {},
      token: await _tokenDe(token),
    );
  }
}
