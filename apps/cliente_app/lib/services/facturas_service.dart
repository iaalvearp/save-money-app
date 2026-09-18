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

class ChallengeResult {
  final String nonce;
  final String expiraEn;

  ChallengeResult({required this.nonce, required this.expiraEn});

  factory ChallengeResult.fromJson(Map<String, dynamic> json) {
    return ChallengeResult(
      nonce: json['nonce'] as String,
      expiraEn: json['expira_en'] as String,
    );
  }

  DateTime get expiraEnDateTime => DateTime.parse(expiraEn);
  bool get expirado => DateTime.now().isAfter(expiraEnDateTime);
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

  Future<RegistroResult> registrarOCR({
    required String? token,
    required int comercioId,
    String? numeroFactura,
    String? rucEmisor,
    String? nombreCompradorFactura,
    String? fechaFactura,
    double? montoTotal,
  }) async {
    final response = await _api.post(
      '/facturas/registrar',
      token: token,
      body: {
        'nivel_verificacion': 2,
        'comercio_id': comercioId,
        if (numeroFactura != null) 'numero_factura': numeroFactura,
        if (rucEmisor != null) 'ruc_emisor': rucEmisor,
        if (nombreCompradorFactura != null)
          'nombre_comprador_factura': nombreCompradorFactura,
        if (fechaFactura != null) 'fecha_factura': fechaFactura,
        if (montoTotal != null) 'monto_total': montoTotal,
      },
    );

    return RegistroResult.fromJson(response);
  }

  Future<ChallengeResult> crearChallenge({String? token}) async {
    final response = await _api.post(
      '/facturas/challenge',
      token: token,
      body: <String, dynamic>{},
    );

    return ChallengeResult.fromJson(response);
  }

  Future<RegistroResult> claimNivel3({
    required String? token,
    required int comercioId,
    required String challengeNonce,
    String? claimHash,
    String? numeroFactura,
    String? rucEmisor,
    String? nombreCompradorFactura,
    String? fechaFactura,
    double? montoTotal,
  }) async {
    final response = await _api.post(
      '/facturas/registrar',
      token: token,
      body: {
        'nivel_verificacion': 3,
        'comercio_id': comercioId,
        'challenge_nonce': challengeNonce,
        if (claimHash != null) 'claim_hash': claimHash,
        if (numeroFactura != null) 'numero_factura': numeroFactura,
        if (rucEmisor != null) 'ruc_emisor': rucEmisor,
        if (nombreCompradorFactura != null)
          'nombre_comprador_factura': nombreCompradorFactura,
        if (fechaFactura != null) 'fecha_factura': fechaFactura,
        if (montoTotal != null) 'monto_total': montoTotal,
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
