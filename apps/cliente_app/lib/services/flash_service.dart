import 'api_client.dart';

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

  bool get estaActiva {
    final now = DateTime.now();
    final inicio = DateTime.parse(iniciaEn);
    final fin = DateTime.parse(terminaEn);
    return now.isAfter(inicio) && now.isBefore(fin);
  }

  String get estadoTexto {
    final now = DateTime.now();
    final inicio = DateTime.parse(iniciaEn);
    final fin = DateTime.parse(terminaEn);
    if (now.isBefore(inicio)) return 'Próximamente';
    if (now.isAfter(fin)) return 'Finalizada';
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

class FlashService {
  final ApiClient _api;

  FlashService({ApiClient? api})
      : _api = api ??
            ApiClient(
                baseUrl: 'https://save-money-backend.iaalvearp.workers.dev');

  Future<List<PromocionFlash>> listarPromociones({
    double? lat,
    double? lng,
    String? categoria,
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

    final response = await _api.get(path);
    final promos = response['promociones'] as List<dynamic>? ?? [];
    return promos
        .map((p) => PromocionFlash.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> obtenerPromocion(int id) async {
    final response = await _api.get('/flash/promociones/$id');
    return response;
  }

  Future<Map<String, dynamic>> reclamarPromocion(int promocionId) async {
    final response = await _api.post(
      '/flash/promociones/$promocionId/claim',
      body: {},
    );
    return response;
  }

  Future<List<Cupon>> misCupones() async {
    final response = await _api.get('/flash/mis-cupones');
    final cupones = response['cupones'] as List<dynamic>? ?? [];
    return cupones
        .map((c) => Cupon.fromJson(c as Map<String, dynamic>))
        .toList();
  }
}
