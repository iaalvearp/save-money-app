import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/facturas_service.dart';
import '../services/ocr_service.dart';

class Nivel3CaptureScreen extends StatefulWidget {
  final int comercioId;
  final String comercioNombre;

  const Nivel3CaptureScreen({
    super.key,
    required this.comercioId,
    required this.comercioNombre,
  });

  @override
  State<Nivel3CaptureScreen> createState() => _Nivel3CaptureScreenState();
}

enum _Estado { solicitando, capturando, procesando, resultado, error }

class _Nivel3CaptureScreenState extends State<Nivel3CaptureScreen> {
  final _facturasService = FacturasService();
  final _authService = AuthService();
  final _ocrService = OcrService();
  final _imagePicker = ImagePicker();

  _Estado _estado = _Estado.solicitando;
  ChallengeResult? _challenge;
  OcrResult? _ocrResult;
  RegistroResult? _resultado;
  String? _error;
  int _segundosRestantes = 300;

  @override
  void initState() {
    super.initState();
    _solicitarDesafio();
  }

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  Future<void> _solicitarDesafio() async {
    try {
      final token = await _authService.getAccessToken();
      final challenge = await _facturasService.crearChallenge(token: token);

      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _estado = _Estado.capturando;
      });

      _iniciarCuentaRegresiva();
    } catch (e) {
      debugPrint('[nivel3_capture] Error al solicitar desafío: $e');
      if (!mounted) return;
      setState(() {
        _estado = _Estado.error;
        _error = 'No se pudo solicitar el desafío. Intente de nuevo.';
      });
    }
  }

  void _iniciarCuentaRegresiva() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;

      final expira = _challenge?.expiraEnDateTime;
      if (expira == null) return false;

      final restantes = expira.difference(DateTime.now()).inSeconds;
      if (restantes <= 0) {
        setState(() {
          _estado = _Estado.error;
          _error = 'El desafío ha expirado. Solicite uno nuevo.';
        });
        return false;
      }

      setState(() => _segundosRestantes = restantes);
      return true;
    });
  }

  bool _soportaCamara() {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  String _formatearTiempo(int segundos) {
    final min = segundos ~/ 60;
    final seg = segundos % 60;
    return '${min.toString().padLeft(2, '0')}:${seg.toString().padLeft(2, '0')}';
  }

  Future<void> _capturarFoto() async {
    try {
      final xFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
      );

      if (xFile == null) return;
      if (!mounted) return;

      setState(() => _estado = _Estado.procesando);

      final bytes = await File(xFile.path).readAsBytes();
      final claimHash = sha256.convert(bytes).toString();

      final ocrResult = await _ocrService.extraerDatos(bytes);

      if (!mounted) return;
      setState(() => _ocrResult = ocrResult);

      await _enviarClaim(claimHash: claimHash);
    } catch (e) {
      debugPrint('[nivel3_capture] Error al capturar la foto: $e');
      if (!mounted) return;
      setState(() {
        _estado = _Estado.error;
        _error = 'Error al capturar la foto. Intente de nuevo.';
      });
    }
  }

  Future<void> _enviarClaim({String? claimHash}) async {
    if (_challenge == null) return;

    setState(() => _estado = _Estado.procesando);

    try {
      final token = await _authService.getAccessToken();
      final result = await _facturasService.claimNivel3(
        token: token,
        comercioId: widget.comercioId,
        challengeNonce: _challenge!.nonce,
        claimHash: claimHash,
        numeroFactura: _ocrResult?.numeroComprobante,
        nombreCompradorFactura: _ocrResult?.nombreNegocio,
        fechaFactura: _ocrResult?.fecha,
        montoTotal: _ocrResult?.monto,
      );

      if (!mounted) return;
      setState(() {
        _resultado = result;
        _estado = _Estado.resultado;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _estado = _Estado.error;
        _error = e.message;
      });
    } catch (e) {
      debugPrint('[nivel3_capture] Error de conexión al enviar claim: $e');
      if (!mounted) return;
      setState(() {
        _estado = _Estado.error;
        _error = 'Error de conexión. Verifique su internet.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sin comprobante'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_estado) {
      case _Estado.solicitando:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Solicitando desafío...'),
            ],
          ),
        );
      case _Estado.capturando:
        return _buildCaptura();
      case _Estado.procesando:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Procesando...'),
            ],
          ),
        );
      case _Estado.resultado:
        return _buildResultado();
      case _Estado.error:
        return _buildError();
    }
  }

  Widget _buildCaptura() {
    final colorTiempo = _segundosRestantes <= 60 ? Colors.red : Colors.orange;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Column(
              children: [
                Icon(Icons.timer, color: colorTiempo, size: 32),
                const SizedBox(height: 8),
                Text(
                  'Tiempo restante: ${_formatearTiempo(_segundosRestantes)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorTiempo,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Este desafío expira en 5 minutos',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Icon(Icons.receipt_long, size: 64, color: Colors.deepPurple),
          const SizedBox(height: 16),
          const Text(
            'Declarar compra sin comprobante',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Tome una foto como evidencia. La imagen queda en su dispositivo '
            'y no se envía al servidor.',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (_ocrResult != null) ...[
            _buildOcrPreview(),
            const SizedBox(height: 16),
          ],
          if (_soportaCamara()) ...[
            ElevatedButton.icon(
              onPressed: _capturarFoto,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Tomar foto'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final xFile = await _imagePicker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 85,
                  maxWidth: 1920,
                );
                if (xFile == null) return;
                if (!mounted) return;
                setState(() => _estado = _Estado.procesando);
                final bytes = await File(xFile.path).readAsBytes();
                final claimHash = sha256.convert(bytes).toString();
                final ocr = await _ocrService.extraerDatos(bytes);
                if (!mounted) return;
                setState(() => _ocrResult = ocr);
                await _enviarClaim(claimHash: claimHash);
              },
              icon: const Icon(Icons.photo_library),
              label: const Text('Elegir de galería'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700]),
                  const SizedBox(height: 8),
                  Text(
                    'La cámara no está disponible en esta plataforma.',
                    style: TextStyle(color: Colors.orange[700]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Widget _buildOcrPreview() {
    final ocr = _ocrResult!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Datos detectados (opcionales):',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 8),
          if (ocr.nombreNegocio != null)
            Text('Negocio: ${ocr.nombreNegocio}'),
          if (ocr.fecha != null) Text('Fecha: ${ocr.fecha}'),
          if (ocr.monto != null)
            Text('Monto: \$${ocr.monto!.toStringAsFixed(2)}'),
          if (ocr.numeroComprobante != null)
            Text('Nº: ${ocr.numeroComprobante}'),
          if (ocr.camposDetectados == 0)
            Text(
              'No se detectaron campos en la imagen',
              style: TextStyle(color: Colors.grey[600]),
            ),
        ],
      ),
    );
  }

  Widget _buildResultado() {
    final result = _resultado!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pending, size: 72, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'Compra declarada',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Su declaración fue registrada como '
              '"${result.estado}". Un administrador revisará su solicitud.',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            if (_ocrResult != null && _ocrResult!.camposDetectados > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Datos adjuntos:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (_ocrResult!.nombreNegocio != null)
                      Text('Negocio: ${_ocrResult!.nombreNegocio}'),
                    if (_ocrResult!.monto != null)
                      Text(
                          'Monto: \$${_ocrResult!.monto!.toStringAsFixed(2)}'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Volver'),
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
              _error ?? 'Error desconocido',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _estado = _Estado.solicitando;
                  _error = null;
                  _challenge = null;
                  _ocrResult = null;
                });
                _solicitarDesafio();
              },
              child: const Text('Reintentar'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
