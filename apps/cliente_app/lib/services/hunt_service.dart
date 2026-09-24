import 'api_client.dart';

class Evento {
  final int id;
  final int organizadorId;
  final String nombre;
  final String fechaInicio;
  final String fechaFin;
  final bool requiereEntrada;
  final double? precioEntrada;
  final String? organizadorNombre;
  final int? entradasVendidas;

  Evento({
    required this.id,
    required this.organizadorId,
    required this.nombre,
    required this.fechaInicio,
    required this.fechaFin,
    this.requiereEntrada = false,
    this.precioEntrada,
    this.organizadorNombre,
    this.entradasVendidas,
  });

  factory Evento.fromJson(Map<String, dynamic> json) {
    return Evento(
      id: json['id'] as int,
      organizadorId: json['organizador_id'] as int,
      nombre: json['nombre'] as String,
      fechaInicio: json['fecha_inicio'] as String,
      fechaFin: json['fecha_fin'] as String,
      requiereEntrada: json['requiere_entrada'] == 1,
      precioEntrada: (json['precio_entrada'] as num?)?.toDouble(),
      organizadorNombre: json['organizador_nombre'] as String?,
      entradasVendidas: json['entradas_vendidas'] as int?,
    );
  }

  bool get estaActivo {
    final now = DateTime.now();
    return now.isAfter(DateTime.parse(fechaInicio)) &&
        now.isBefore(DateTime.parse(fechaFin));
  }
}

class Ronda {
  final int id;
  final int eventoId;
  final String? nombre;
  final String horaInicio;
  final String horaFin;

  Ronda({
    required this.id,
    required this.eventoId,
    this.nombre,
    required this.horaInicio,
    required this.horaFin,
  });

  factory Ronda.fromJson(Map<String, dynamic> json) {
    return Ronda(
      id: json['id'] as int,
      eventoId: json['evento_id'] as int,
      nombre: json['nombre'] as String?,
      horaInicio: json['hora_inicio'] as String,
      horaFin: json['hora_fin'] as String,
    );
  }
}

class Sponsor {
  final int id;
  final int eventoId;
  final int comercioId;
  final String estado;
  final String? comercioNombre;
  final String? categoria;

  Sponsor({
    required this.id,
    required this.eventoId,
    required this.comercioId,
    required this.estado,
    this.comercioNombre,
    this.categoria,
  });

  factory Sponsor.fromJson(Map<String, dynamic> json) {
    return Sponsor(
      id: json['id'] as int,
      eventoId: json['evento_id'] as int,
      comercioId: json['comercio_id'] as int,
      estado: json['estado'] as String,
      comercioNombre: json['comercio_nombre'] as String?,
      categoria: json['categoria'] as String?,
    );
  }
}

class Premio {
  final int id;
  final int eventoId;
  final int? rondaId;
  final String nombre;
  final int stock;
  final String tipo;
  final int? criterioFrecuencia;
  final int? entregados;

  Premio({
    required this.id,
    required this.eventoId,
    this.rondaId,
    required this.nombre,
    required this.stock,
    required this.tipo,
    this.criterioFrecuencia,
    this.entregados,
  });

  factory Premio.fromJson(Map<String, dynamic> json) {
    return Premio(
      id: json['id'] as int,
      eventoId: json['evento_id'] as int,
      rondaId: json['ronda_id'] as int?,
      nombre: json['nombre'] as String,
      stock: json['stock'] as int,
      tipo: json['tipo'] as String,
      criterioFrecuencia: json['criterio_frecuencia'] as int?,
      entregados: json['entregados'] as int?,
    );
  }

  int get stockDisponible => stock - (entregados ?? 0);
}

class Entrada {
  final int id;
  final int eventoId;
  final int clienteId;
  final String estado;
  final double? monto;
  final String? comprobanteFoto;
  final String? clienteNombre;
  final String? clienteEmail;

  Entrada({
    required this.id,
    required this.eventoId,
    required this.clienteId,
    required this.estado,
    this.monto,
    this.comprobanteFoto,
    this.clienteNombre,
    this.clienteEmail,
  });

  factory Entrada.fromJson(Map<String, dynamic> json) {
    return Entrada(
      id: json['id'] as int,
      eventoId: json['evento_id'] as int,
      clienteId: json['cliente_id'] as int,
      estado: json['estado'] as String,
      monto: (json['monto'] as num?)?.toDouble(),
      comprobanteFoto: json['comprobante_foto'] as String?,
      clienteNombre: json['cliente_nombre'] as String?,
      clienteEmail: json['cliente_email'] as String?,
    );
  }
}

class GanadorPremio {
  final int id;
  final int premioId;
  final int usuarioId;
  final int? rondaId;
  final String estado;
  final String? entregadoEn;
  final String? reclamadoEn;
  final String? usuarioNombre;
  final String? usuarioEmail;

  GanadorPremio({
    required this.id,
    required this.premioId,
    required this.usuarioId,
    this.rondaId,
    required this.estado,
    this.entregadoEn,
    this.reclamadoEn,
    this.usuarioNombre,
    this.usuarioEmail,
  });

  factory GanadorPremio.fromJson(Map<String, dynamic> json) {
    return GanadorPremio(
      id: json['id'] as int,
      premioId: json['premio_id'] as int,
      usuarioId: json['usuario_id'] as int,
      rondaId: json['ronda_id'] as int?,
      estado: json['estado'] as String,
      entregadoEn: json['entregado_en'] as String?,
      reclamadoEn: json['reclamado_en'] as String?,
      usuarioNombre: json['usuario_nombre'] as String?,
      usuarioEmail: json['usuario_email'] as String?,
    );
  }

  bool get estaEntregado => estado == 'entregado';
}

class ParticipanteSinPremio {
  final int id;
  final String nombreCompleto;
  final String email;

  ParticipanteSinPremio({
    required this.id,
    required this.nombreCompleto,
    required this.email,
  });

  factory ParticipanteSinPremio.fromJson(Map<String, dynamic> json) {
    return ParticipanteSinPremio(
      id: json['id'] as int,
      nombreCompleto: json['nombre_completo'] as String,
      email: json['email'] as String,
    );
  }
}

final formatearFecha = (DateTime dt) =>
    dt.toUtc().toIso8601String().replaceFirst('T', ' ').substring(0, 19);

class HuntService {
  final ApiClient _api;

  HuntService({ApiClient? api})
      : _api = api ??
            ApiClient(
                baseUrl: 'https://save-money-backend.iaalvearp.workers.dev');

  Future<List<Evento>> listarEventos({String? token}) async {
    final response = await _api.get('/hunt/eventos', token: token);
    final eventos = response['eventos'] as List<dynamic>? ?? [];
    return eventos
        .map((e) => Evento.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> obtenerEvento(
    int id, {
    String? token,
  }) async {
    return _api.get('/hunt/eventos/$id', token: token);
  }

  Future<Evento> crearEvento({
    required String nombre,
    required String fechaInicio,
    required String fechaFin,
    bool requiereEntrada = false,
    double? precioEntrada,
    String? token,
  }) async {
    final response = await _api.post('/hunt/eventos', body: {
      'nombre': nombre,
      'fecha_inicio': fechaInicio,
      'fecha_fin': fechaFin,
      'requiere_entrada': requiereEntrada,
      if (precioEntrada != null) 'precio_entrada': precioEntrada,
    }, token: token);
    return Evento.fromJson(response['evento'] as Map<String, dynamic>);
  }

  Future<Ronda> crearRonda({
    required int eventoId,
    required String nombre,
    required String horaInicio,
    required String horaFin,
    String? token,
  }) async {
    final response = await _api.post(
      '/hunt/eventos/$eventoId/rondas',
      body: {
        'nombre': nombre,
        'hora_inicio': horaInicio,
        'hora_fin': horaFin,
      },
      token: token,
    );
    return Ronda.fromJson(response['ronda'] as Map<String, dynamic>);
  }

  Future<void> invitarSponsor({
    required int eventoId,
    required int comercioId,
    String? token,
  }) async {
    await _api.post(
      '/hunt/eventos/$eventoId/sponsors',
      body: {'comercio_id': comercioId},
      token: token,
    );
  }

  Future<Premio> crearPremio({
    required int eventoId,
    required String nombre,
    required int stock,
    required String tipo,
    int? rondaId,
    int? criterioFrecuencia,
    String? token,
  }) async {
    final response = await _api.post(
      '/hunt/eventos/$eventoId/premios',
      body: {
        'nombre': nombre,
        'stock': stock,
        'tipo': tipo,
        if (rondaId != null) 'ronda_id': rondaId,
        if (criterioFrecuencia != null)
          'criterio_frecuencia': criterioFrecuencia,
      },
      token: token,
    );
    return Premio.fromJson(response['premio'] as Map<String, dynamic>);
  }

  Future<void> comprarEntrada(int eventoId) async {
    await _api.post('/hunt/eventos/$eventoId/entradas/comprar', body: {});
  }

  Future<List<Entrada>> listarEntradas(
    int eventoId, {
    String? token,
  }) async {
    final response = await _api.get(
      '/hunt/eventos/$eventoId/entradas',
      token: token,
    );
    final entradas = response['entradas'] as List<dynamic>? ?? [];
    return entradas
        .map((e) => Entrada.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> revisarEntrada(
    int entradaId, {
    required bool aprueba,
    String? token,
  }) async {
    await _api.post('/hunt/entradas/$entradaId/revisar', body: {
      'aprueba': aprueba,
    }, token: token);
  }

  Future<void> entregarPremio({
    required int eventoId,
    required int premioId,
    required int usuarioId,
    int? rondaId,
    String? token,
  }) async {
    await _api.post(
      '/hunt/eventos/$eventoId/premios/$premioId/entregar',
      body: {
        'usuario_id': usuarioId,
        if (rondaId != null) 'ronda_id': rondaId,
      },
      token: token,
    );
  }

  Future<void> emitirCuponesConsolacion({
    required int eventoId,
    required int comercioId,
    required List<int> usuarioIds,
    required int descuento,
    String? token,
  }) async {
    await _api.post(
      '/hunt/eventos/$eventoId/cupones-consolacion',
      body: {
        'comercio_id': comercioId,
        'usuario_ids': usuarioIds,
        'descuento': descuento,
      },
      token: token,
    );
  }

  Future<List<GanadorPremio>> ganadoresDePremio(
    int eventoId,
    int premioId, {
    String? token,
  }) async {
    final response = await _api.get(
      '/hunt/eventos/$eventoId/premios/$premioId/ganadores',
      token: token,
    );
    final ganadores = response['ganadores'] as List<dynamic>? ?? [];
    return ganadores
        .map((g) => GanadorPremio.fromJson(g as Map<String, dynamic>))
        .toList();
  }

  Future<List<ParticipanteSinPremio>> participantesSinPremio(
    int eventoId, {
    String? token,
  }) async {
    final response = await _api.get(
      '/hunt/eventos/$eventoId/participantes-sin-premio',
      token: token,
    );
    final participantes = response['participantes'] as List<dynamic>? ?? [];
    return participantes
        .map((p) => ParticipanteSinPremio.fromJson(p as Map<String, dynamic>))
        .toList();
  }
}
