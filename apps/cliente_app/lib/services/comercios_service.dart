import 'api_client.dart';

class Comercio {
  final int id;
  final String nombre;
  final String? categoria;
  final String? ruc;
  final double? latitud;
  final double? longitud;
  final bool esPatrocinado;
  final String? horario;
  final String? fotoUrl;
  final String? propietario;
  final double? distanciaKm;

  Comercio({
    required this.id,
    required this.nombre,
    this.categoria,
    this.ruc,
    this.latitud,
    this.longitud,
    this.esPatrocinado = false,
    this.horario,
    this.fotoUrl,
    this.propietario,
    this.distanciaKm,
  });

  factory Comercio.fromJson(Map<String, dynamic> json) {
    return Comercio(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      categoria: json['categoria'] as String?,
      ruc: json['ruc'] as String?,
      latitud: (json['latitud'] as num?)?.toDouble(),
      longitud: (json['longitud'] as num?)?.toDouble(),
      esPatrocinado: json['es_patrocinado'] == true ||
          json['es_patrocinado'] == 1,
      horario: json['horario'] as String?,
      fotoUrl: json['foto_url'] as String?,
      propietario: json['propietario'] as String?,
      distanciaKm: (json['distancia_km'] as num?)?.toDouble(),
    );
  }
}

class Promocion {
  final int id;
  final String codigoQr;
  final double? descuento;
  final String? expiraEn;

  Promocion({
    required this.id,
    required this.codigoQr,
    this.descuento,
    this.expiraEn,
  });

  factory Promocion.fromJson(Map<String, dynamic> json) {
    return Promocion(
      id: json['id'] as int,
      codigoQr: json['codigo_qr'] as String,
      descuento: (json['descuento'] as num?)?.toDouble(),
      expiraEn: json['expira_en'] as String?,
    );
  }
}

class ComerciosService {
  final ApiClient _api;

  ComerciosService({ApiClient? api})
      : _api = api ??
            ApiClient(
                baseUrl: 'https://save-money-backend.iaalvearp.workers.dev');

  Future<List<Comercio>> listar({
    String? categoria,
    String? busqueda,
    bool? conPromociones,
    double? lat,
    double? lng,
  }) async {
    final params = <String>[];
    if (busqueda != null && busqueda.isNotEmpty) {
      params.add('q=${Uri.encodeComponent(busqueda)}');
    }
    if (categoria != null && categoria.isNotEmpty) {
      params.add('categoria=${Uri.encodeComponent(categoria)}');
    }
    if (conPromociones == true) {
      params.add('con_promociones=true');
    }
    if (lat != null && lng != null) {
      params.add('lat=$lat');
      params.add('lng=$lng');
    }

    final path = params.isEmpty
        ? '/comercios'
        : '/comercios?${params.join('&')}';

    final response = await _api.get(path);
    final comerciosJson = response['comercios'] as List<dynamic>? ?? [];
    return comerciosJson
        .map((json) => Comercio.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<Comercio>> cercanos({
    required double lat,
    required double lng,
    double radio = 5,
  }) async {
    final response = await _api.get(
      '/comercios/cercanos?lat=$lat&lng=$lng&radio=$radio',
    );
    final comerciosJson = response['comercios'] as List<dynamic>? ?? [];
    return comerciosJson
        .map((json) => Comercio.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> obtener(int id) async {
    final response = await _api.get('/comercios/$id');
    return response;
  }

  Future<List<Comercio>> misComercios() async {
    final response = await _api.get('/mis-comercios');
    final comerciosJson = response['comercios'] as List<dynamic>? ?? [];
    return comerciosJson
        .map((json) => Comercio.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Comercio> crear({
    required String nombre,
    String? categoria,
    double? latitud,
    double? longitud,
    String? horario,
    String? fotoUrl,
  }) async {
    final response = await _api.post('/comercios', body: {
      'nombre': nombre,
      if (categoria != null) 'categoria': categoria,
      if (latitud != null) 'latitud': latitud,
      if (longitud != null) 'longitud': longitud,
      if (horario != null) 'horario': horario,
      if (fotoUrl != null) 'foto_url': fotoUrl,
    });
    return Comercio.fromJson(response['comercio'] as Map<String, dynamic>);
  }

  Future<Comercio> actualizar(int id, {
    String? nombre,
    String? categoria,
    double? latitud,
    double? longitud,
    String? horario,
    String? fotoUrl,
  }) async {
    final body = <String, dynamic>{};
    if (nombre != null) body['nombre'] = nombre;
    if (categoria != null) body['categoria'] = categoria;
    if (latitud != null) body['latitud'] = latitud;
    if (longitud != null) body['longitud'] = longitud;
    if (horario != null) body['horario'] = horario;
    if (fotoUrl != null) body['foto_url'] = fotoUrl;

    final response = await _api.patch('/comercios/$id', body: body);
    return Comercio.fromJson(response['comercio'] as Map<String, dynamic>);
  }
}
