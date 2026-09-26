import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/ocr_service.dart';
import 'ocr_confirm_screen.dart';

class OcrCaptureScreen extends StatefulWidget {
  final int comercioId;
  final String comercioNombre;

  const OcrCaptureScreen({
    super.key,
    required this.comercioId,
    required this.comercioNombre,
  });

  @override
  State<OcrCaptureScreen> createState() => _OcrCaptureScreenState();
}

class _OcrCaptureScreenState extends State<OcrCaptureScreen> {
  final _ocrService = OcrService();
  final _imagePicker = ImagePicker();
  bool _procesando = false;
  String? _error;

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  bool _soportaCamara() {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  Future<void> _capturarFoto(ImageSource source) async {
    try {
      final xFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );

      if (xFile == null) return;

      if (!mounted) return;
      setState(() {
        _procesando = true;
        _error = null;
      });

      final bytes = await File(xFile.path).readAsBytes();
      final ocrResult = await _ocrService.extraerDatos(bytes);

      if (!mounted) return;

      final resultado = await Navigator.of(context).push<OcrConfirmResult>(
        MaterialPageRoute(
          builder: (_) => OcrConfirmScreen(
            ocrResult: ocrResult,
            comercioId: widget.comercioId,
            comercioNombre: widget.comercioNombre,
          ),
        ),
      );

      if (!mounted) return;
      setState(() => _procesando = false);

      if (resultado != null && context.mounted) {
        Navigator.of(context).pop(resultado);
      }
    } catch (e) {
      debugPrint('[ocr_capture] Error al procesar la imagen: $e');
      if (!mounted) return;
      setState(() {
        _procesando = false;
        _error = 'Error al procesar la imagen. Intente de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear ticket'),
      ),
      body: _procesando
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 24),
                  Text(
                    'Procesando imagen...',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Extrayendo datos del ticket',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            )
          : _buildOpciones(),
    );
  }

  Widget _buildOpciones() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.document_scanner, size: 64, color: Colors.deepPurple),
          const SizedBox(height: 16),
          const Text(
            'Capturar ticket físico',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Tome una foto del ticket para extraer los datos automáticamente',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red[700]),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_soportaCamara()) ...[
            ElevatedButton.icon(
              onPressed: () => _capturarFoto(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Tomar foto'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _capturarFoto(ImageSource.gallery),
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
                    'La cámara no está disponible en esta plataforma. '
                    'Ingrese los datos manualmente.',
                    style: TextStyle(color: Colors.orange[700]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.keyboard),
              label: const Text('Volver e ingresar manualmente'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
