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

  Entrada({
    required this.id,
    required this.eventoId,
    required this.clienteId,
    required this.estado,
    this.monto,
    this.comprobanteFoto,
    this.clienteNombre,
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
    );
  }
}

class HuntService {
  final ApiClient _api;

  HuntService({ApiClient? api})
      : _api = api ??
            ApiClient(
                baseUrl: 'https://save-money-backend.iaalvearp.workers.dev');

  Future<List<Evento>> listarEventos() async {
    final response = await _api.get('/hunt/eventos');
    final eventos = response['eventos'] as List<dynamic>? ?? [];
    return eventos
        .map((e) => Evento.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> obtenerEvento(int id) async {
    final response = await _api.get('/hunt/eventos/$id');
    return response;
  }

  Future<Evento> crearEvento({
    required String nombre,
    required String fechaInicio,
    required String fechaFin,
    bool requiereEntrada = false,
    double? precioEntrada,
  }) async {
    final response = await _api.post('/hunt/eventos', body: {
      'nombre': nombre,
      'fecha_inicio': fechaInicio,
      'fecha_fin': fechaFin,
      'requiere_entrada': requiereEntrada,
      if (precioEntrada != null) 'precio_entrada': precioEntrada,
    });
    return Evento.fromJson(response['evento'] as Map<String, dynamic>);
  }

  Future<void> comprarEntrada(int eventoId) async {
    await _api.post('/hunt/eventos/$eventoId/entradas/comprar', body: {});
  }

  Future<List<Entrada>> listarEntradas(int eventoId) async {
    final response = await _api.get('/hunt/eventos/$eventoId/entradas');
    final entradas = response['entradas'] as List<dynamic>? ?? [];
    return entradas
        .map((e) => Entrada.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> revisarEntrada(int entradaId, {required bool aprueba}) async {
    await _api.post('/hunt/entradas/$entradaId/revisar', body: {
      'aprueba': aprueba,
    });
  }
}
