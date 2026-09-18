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
    );
  }
}

class ComerciosService {
  final ApiClient _api;

  ComerciosService({ApiClient? api})
      : _api = api ??
            ApiClient(
                baseUrl: 'https://save-money-backend.iaalvearp.workers.dev');

  Future<List<Comercio>> listar({String? categoria}) async {
    final path = categoria != null && categoria.isNotEmpty
        ? '/comercios?categoria=${Uri.encodeComponent(categoria)}'
        : '/comercios';

    final response = await _api.get(path);
    final comerciosJson = response['comercios'] as List<dynamic>? ?? [];
    return comerciosJson
        .map((json) => Comercio.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Comercio> obtener(int id) async {
    final response = await _api.get('/comercios/$id');
    final comercioJson = response['comercio'] as Map<String, dynamic>;
    return Comercio.fromJson(comercioJson);
  }
}
