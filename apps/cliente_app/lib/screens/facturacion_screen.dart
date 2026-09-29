import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/facturas_service.dart';
import '../services/permiso_camara_service.dart';
import '../widgets/aviso_permiso_camara.dart';
import '../widgets/dialogo_error.dart';
import 'nivel3_capture_screen.dart';
import 'ocr_capture_screen.dart';

class FacturacionScreen extends StatefulWidget {
  final int comercioId;
  final String comercioNombre;

  /// Fuerza la disponibilidad del escáner en vez de autodetectarla. Solo se
  /// usa en pruebas, donde `dart:io Platform` no es Android ni iOS.
  final bool? scannerDisponible;

  const FacturacionScreen({
    super.key,
    required this.comercioId,
    required this.comercioNombre,
    this.scannerDisponible,
  });

  @override
  State<FacturacionScreen> createState() => _FacturacionScreenState();
}

enum _EstadoFactura { inicial, validando, resultado, error }

class _FacturacionScreenState extends State<FacturacionScreen> {
  final _facturasService = FacturasService();
  final _authService = AuthService();
  final _claveController = TextEditingController();
  final _claveFormKey = GlobalKey<FormState>();

  _EstadoFactura _estado = _EstadoFactura.inicial;
  RegistroResult? _resultado;
  String? _mensajeError;
  bool _scannerDisponible = false;

  @override
  void initState() {
    super.initState();
    _scannerDisponible = widget.scannerDisponible ?? _verificarScannerDisponible();
  }

  @override
  void dispose() {
    _claveController.dispose();
    super.dispose();
  }

  bool _verificarScannerDisponible() {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  String _normalizarClave(String valor) {
    return valor.replaceAll(RegExp(r'[^0-9]'), '');
  }

  Future<void> _registrarFactura({String? claveManual}) async {
    final clave = claveManual ?? _normalizarClave(_claveController.text);

    if (clave.length != 49) {
      setState(() {
        _estado = _EstadoFactura.error;
        _mensajeError = 'La clave de acceso debe tener 49 dígitos';
      });
      return;
    }

    setState(() {
      _estado = _EstadoFactura.validando;
      _mensajeError = null;
    });

    try {
      final token = await _authService.getAccessToken();
      final result = await _facturasService.registrar(
        token: token,
        comercioId: widget.comercioId,
        claveAcceso: clave,
      );

      if (!mounted) return;
      setState(() {
        _resultado = result;
        _estado = _EstadoFactura.resultado;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _estado = _EstadoFactura.error;
        _mensajeError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _estado = _EstadoFactura.error;
        _mensajeError = 'Error de conexión. Verifique su internet.';
      });
    }
  }

  void _escanearQR() {
    Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
    ).then((clave) {
      if (clave != null && clave.isNotEmpty) {
        _claveController.text = clave;
        _registrarFactura(claveManual: clave);
      }
    });
  }

  void _reiniciar() {
    setState(() {
      _estado = _EstadoFactura.inicial;
      _resultado = null;
      _mensajeError = null;
      _claveController.clear();
    });
  }

  void _escanearTicket() {
    Navigator.of(context).push<OcrTicketResult>(
      MaterialPageRoute(
        builder: (_) => OcrCaptureScreen(
          comercioId: widget.comercioId,
          comercioNombre: widget.comercioNombre,
        ),
      ),
    ).then((resultado) {
      if (resultado == null || !mounted) return;

      switch (resultado) {
        // El OCR leyo la clave entera: se registra con el mismo metodo que
        // usa el codigo de barras o el QR, con la misma validacion y los
        // mismos errores.
        case OcrClaveAccesoLeida(:final claveAcceso):
          _registrarFactura(claveManual: claveAcceso);
        case OcrEnviadoAMano(:final facturaId, :final estado):
          setState(() {
            _resultado = RegistroResult(
              facturaId: facturaId,
              estado: estado,
              motivoRechazo: estado == 'pendiente_revision_nombre'
                  ? 'Comprobante verificado por OCR, pendiente validación'
                  : null,
            );
            _estado = _EstadoFactura.resultado;
          });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.comercioNombre),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_estado) {
      case _EstadoFactura.inicial:
        return _buildFormulario();
      case _EstadoFactura.validando:
        return _buildValidando();
      case _EstadoFactura.resultado:
        return _buildResultado();
      case _EstadoFactura.error:
        return _buildError();
    }
  }

  Widget _buildFormulario() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.receipt_long, size: 64, color: Colors.deepPurple),
          const SizedBox(height: 16),
          const Text(
            'Registrar compra',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Ingrese la clave de acceso de 49 dígitos de su factura electrónica',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Form(
            key: _claveFormKey,
            child: TextFormField(
              controller: _claveController,
              keyboardType: TextInputType.number,
              maxLength: 49,
              decoration: const InputDecoration(
                labelText: 'Clave de acceso',
                hintText: '49 dígitos',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
              validator: (value) {
                final normalizado = _normalizarClave(value ?? '');
                if (normalizado.length != 49) {
                  return 'Debe ingresar 49 dígitos';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              if (_claveFormKey.currentState?.validate() ?? false) {
                _registrarFactura();
              }
            },
            icon: const Icon(Icons.send),
            label: const Text('Validar factura'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 16),
            ),
          ),
          if (_scannerDisponible) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _escanearQR,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Escanear clave de acceso'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            '¿Tiene un ticket físico?',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _escanearTicket,
            icon: const Icon(Icons.document_scanner),
            label: const Text('Escanear ticket'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            '¿No tiene comprobante?',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Nivel3CaptureScreen(
                    comercioId: widget.comercioId,
                    comercioNombre: widget.comercioNombre,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Declarar sin comprobante'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 16),
              side: BorderSide(color: Colors.orange[300]!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidando() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text(
            'Validando factura con el SRI...',
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Esto puede tomar unos segundos',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildResultado() {
    final result = _resultado!;

    switch (result.estado) {
      case 'aprobada':
        return _buildEstadoExito(
          titulo: 'Factura aprobada',
          mensaje: 'Su factura fue validada exitosamente.',
          icono: Icons.check_circle,
          color: Colors.green,
        );
      case 'pendiente_verificacion_sri':
        return _buildEstadoPendiente(
          titulo: 'Verificación pendiente',
          mensaje: result.mensaje ??
              'El SRI no está disponible. Puede reintentar más tarde.',
        );
      case 'pendiente_revision_nombre':
        return _buildEstadoExito(
          titulo: 'Revisión manual',
          mensaje:
              'El nombre en la factura no coincide con su nombre. '
              'Un administrador revisará su solicitud.',
          icono: Icons.pending,
          color: Colors.orange,
        );
      case 'rechazada':
        return _buildEstadoRechazada(
          titulo: 'Factura rechazada',
          mensaje: result.motivoRechazo ?? 'La factura fue rechazada por el SRI.',
        );
      default:
        return _buildEstadoExito(
          titulo: result.estado,
          mensaje: result.motivoRechazo ?? '',
          icono: Icons.info_outline,
          color: Colors.blue,
        );
    }
  }

  Widget _buildEstadoExito({
    required String titulo,
    required String mensaje,
    required IconData icono,
    required Color color,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 72, color: color),
            const SizedBox(height: 16),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mensaje,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _reiniciar,
              child: const Text('Registrar otra factura'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadoPendiente({
    required String titulo,
    required String mensaje,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top, size: 72, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mensaje,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _registrarFactura,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _reiniciar,
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadoRechazada({
    required String titulo,
    required String mensaje,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cancel, size: 72, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mensaje,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _reiniciar,
              child: const Text('Intentar con otra factura'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 72, color: Colors.red[400]),
            const SizedBox(height: 16),
            const Text(
              'Error',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _mensajeError ?? 'Error desconocido',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _reiniciar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

bool esClaveAccesoValida(String valor) =>
    RegExp(r'^\d{49}$').hasMatch(valor);

/// El texto que trae una captura del escáner, o null si no leyó nada.
///
/// Da igual de qué formato venga el código. Los comprobantes ecuatorianos
/// imprimen la clave como código de barras Code128 casi nunca como QR, y los
/// dos llevan el mismo texto, así que se leen igual. Si el código no se puede
/// leer se devuelve null para que la pantalla no se queje: el fotograma puede
/// haber pillado medio comprobante. La validación de los 49 dígitos es la de
/// siempre, [esClaveAccesoValida]: no se repite por formato.
String? valorDeCaptura(BarcodeCapture captura) {
  for (final barcode in captura.barcodes) {
    final valor = barcode.rawValue;
    if (valor != null && valor.isNotEmpty) return valor;
  }
  return null;
}

class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  // Sin lista de formatos: en mobile_scanner 7 eso es "todos". La lista
  // solo se manda a la camara cuando no esta vacia, asi que ya se detectan
  // los codigos de barras (Code128) y no solo los QR. Limitarla seria
  // quitar formatos que hoy funcionan.
  final MobileScannerController _controller = MobileScannerController();
  bool _dialogoVisible = false;
  bool _resolvidoValido = false;
  EstadoPermisoCamara _estadoPermiso = EstadoPermisoCamara.concediendo;

  @override
  void initState() {
    super.initState();
    _verificarPermisoCamara();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verificarPermisoCamara() async {
    final estado = await solicitarPermisoCamara();
    if (!mounted) return;
    setState(() => _estadoPermiso = estado);
  }

  Future<void> _onDetect(BarcodeCapture captura) async {
    if (_resolvidoValido) return;

    final valor = valorDeCaptura(captura);
    if (valor == null) return;

    if (esClaveAccesoValida(valor)) {
      _resolvidoValido = true;
      Navigator.of(context).pop(valor);
      return;
    }

    // Mientras el aviso está abierto el mismo código no vuelve a disparar el
    // diálogo. El escáner sigue leyendo fotogramas y, con el diálogo encima,
    // se acumulaban varios avisos apilados.
    if (_dialogoVisible) return;
    _dialogoVisible = true;

    await mostrarErrorDialog(
      context,
      titulo: 'Código no válido',
      mensaje: 'Este código no corresponde a una clave de acceso válida.',
    );

    if (!mounted) return;
    _dialogoVisible = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear clave de acceso')),
      body: switch (_estadoPermiso) {
        EstadoPermisoCamara.concediendo =>
          const Center(child: CircularProgressIndicator()),
        EstadoPermisoCamara.denegado ||
        EstadoPermisoCamara.denegadoPermanente =>
          AvisoPermisoCamara(
            estado: _estadoPermiso,
            onReintentar: _verificarPermisoCamara,
            onCerrar: () => Navigator.of(context).pop(),
            mensaje: 'Sin acceso a la cámara no es posible escanear el código.',
          ),
        EstadoPermisoCamara.concedido => MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
      },
    );
  }
}
