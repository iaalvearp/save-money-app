import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/hunt_service.dart';

class ComprobanteEntradaScreen extends StatefulWidget {
  final int entradaId;
  final HuntService? servicio;
  final AuthService? auth;
  final Future<Uint8List?> Function(ImageSource source)? picker;

  const ComprobanteEntradaScreen({
    super.key,
    required this.entradaId,
    this.servicio,
    this.auth,
    this.picker,
  });

  @override
  State<ComprobanteEntradaScreen> createState() =>
      _ComprobanteEntradaScreenState();
}

class _ComprobanteEntradaScreenState extends State<ComprobanteEntradaScreen> {
  late final HuntService _servicio;
  late final AuthService _auth;
  Uint8List? _imagen;
  bool _enviando = false;
  String? _error;
  String? _exito;

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio ?? HuntService();
    _auth = widget.auth ?? AuthService();
  }

  bool _soportaCamara() {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  Future<void> _seleccionarImagen(ImageSource source) async {
    try {
      final bytes = widget.picker == null
          ? await _capturarConImagePicker(source)
          : await widget.picker!(source);
      if (bytes == null) return;
      if (!mounted) return;
      setState(() {
        _imagen = bytes;
        _error = null;
        _exito = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar la imagen. Intente de nuevo.');
    }
  }

  Future<Uint8List?> _capturarConImagePicker(ImageSource source) async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (xFile == null) return null;
    return File(xFile.path).readAsBytes();
  }

  Future<void> _enviar() async {
    final imagen = _imagen;
    if (imagen == null) return;
    setState(() {
      _enviando = true;
      _error = null;
      _exito = null;
    });

    try {
      final token = await _auth.getAccessToken();
      await _servicio.subirComprobante(
        widget.entradaId,
        foto: base64Encode(imagen),
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _exito = 'Comprobante registrado';
      });
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = 'Error al enviar el comprobante';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subir comprobante')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.receipt_long, size: 64, color: Colors.deepPurple),
            const SizedBox(height: 16),
            const Text(
              'Comprobante de pago de entrada',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'El comprobante será revisado por el organizador del evento.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_error != null)
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
            if (_exito != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Text(
                  _exito!,
                  style: TextStyle(color: Colors.green[700]),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_error != null || _exito != null) const SizedBox(height: 16),
            if (_imagen != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _imagen!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_enviando)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (_imagen != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _enviar,
                    icon: const Icon(Icons.upload),
                    label: const Text('Enviar comprobante'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_soportaCamara()) ...[
                ElevatedButton.icon(
                  onPressed: () => _seleccionarImagen(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Tomar foto'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _seleccionarImagen(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Elegir de galería'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: () => _seleccionarImagen(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Elegir de galería'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}