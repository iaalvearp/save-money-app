import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/facturas_service.dart';
import 'nivel3_capture_screen.dart';
import 'ocr_capture_screen.dart';
import 'ocr_confirm_screen.dart';

class FacturacionScreen extends StatefulWidget {
  final int comercioId;
  final String comercioNombre;

  const FacturacionScreen({
    super.key,
    required this.comercioId,
    required this.comercioNombre,
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
    _scannerDisponible = _verificarScannerDisponible();
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
    Navigator.of(context).push<OcrConfirmResult>(
      MaterialPageRoute(
        builder: (_) => OcrCaptureScreen(
          comercioId: widget.comercioId,
          comercioNombre: widget.comercioNombre,
        ),
      ),
    ).then((resultado) {
      if (resultado != null && mounted) {
        setState(() {
          _resultado = RegistroResult(
            facturaId: resultado.facturaId,
            estado: resultado.estado,
            motivoRechazo: resultado.estado == 'pendiente_revision_nombre'
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
              label: const Text('Escanear código QR'),
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

class _QrScannerScreen extends StatelessWidget {
  const _QrScannerScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_scanner, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'Escáner no disponible en esta plataforma',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ingrese la clave manualmente',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}
