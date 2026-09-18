import 'api_client.dart';

class Factura {
  final int id;
  final int? nivelVerificacion;
  final String? numeroFactura;
  final String? rucEmisor;
  final String? nombreCompradorFactura;
  final String? fechaFactura;
  final double? montoTotal;
  final double? descuentoAplicado;
  final String estado;
  final String? motivoRechazo;
  final String? createdAt;

  Factura({
    required this.id,
    this.nivelVerificacion,
    this.numeroFactura,
    this.rucEmisor,
    this.nombreCompradorFactura,
    this.fechaFactura,
    this.montoTotal,
    this.descuentoAplicado,
    required this.estado,
    this.motivoRechazo,
    this.createdAt,
  });

  factory Factura.fromJson(Map<String, dynamic> json) {
    return Factura(
      id: json['id'] as int,
      nivelVerificacion: json['nivel_verificacion'] as int?,
      numeroFactura: json['numero_factura'] as String?,
      rucEmisor: json['ruc_emisor'] as String?,
      nombreCompradorFactura: json['nombre_comprador_factura'] as String?,
      fechaFactura: json['fecha_factura'] as String?,
      montoTotal: (json['monto_total'] as num?)?.toDouble(),
      descuentoAplicado: (json['descuento_aplicado'] as num?)?.toDouble(),
      estado: json['estado'] as String,
      motivoRechazo: json['motivo_rechazo'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}

class RegistroResult {
  final int facturaId;
  final String estado;
  final String? motivoRechazo;
  final String? sriEstado;
  final String? mensaje;

  RegistroResult({
    required this.facturaId,
    required this.estado,
    this.motivoRechazo,
    this.sriEstado,
    this.mensaje,
  });

  factory RegistroResult.fromJson(Map<String, dynamic> json) {
    return RegistroResult(
      facturaId: json['factura_id'] as int,
      estado: json['estado'] as String,
      motivoRechazo: json['motivo_rechazo'] as String?,
      sriEstado: json['sri_estado'] as String?,
      mensaje: json['mensaje'] as String?,
    );
  }
}

class FacturasService {
  final ApiClient _api;

  FacturasService({ApiClient? api})
      : _api = api ??
            ApiClient(
                baseUrl: 'https://save-money-backend.iaalvearp.workers.dev');

  Future<RegistroResult> registrar({
    required String? token,
    required int comercioId,
    required String claveAcceso,
  }) async {
    final response = await _api.post(
      '/facturas/registrar',
      token: token,
      body: {
        'nivel_verificacion': 1,
        'comercio_id': comercioId,
        'clave_acceso_49': claveAcceso,
      },
    );

    return RegistroResult.fromJson(response);
  }

  Future<List<Factura>> listarMisFacturas({String? token}) async {
    final response = await _api.get('/facturas/mias', token: token);
    final facturasJson = response['facturas'] as List<dynamic>? ?? [];
    return facturasJson
        .map((json) => Factura.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
