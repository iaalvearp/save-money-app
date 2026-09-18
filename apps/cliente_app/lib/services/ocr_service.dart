import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrResult {
  final String? nombreNegocio;
  final String? fecha;
  final double? monto;
  final String? numeroComprobante;

  const OcrResult({
    this.nombreNegocio,
    this.fecha,
    this.monto,
    this.numeroComprobante,
  });

  int get camposDetectados {
    int count = 0;
    if (nombreNegocio != null && nombreNegocio!.isNotEmpty) count++;
    if (fecha != null && fecha!.isNotEmpty) count++;
    if (monto != null) count++;
    if (numeroComprobante != null && numeroComprobante!.isNotEmpty) count++;
    return count;
  }

  bool get tieneTodosLosCampos => camposDetectados == 4;
}

class OcrService {
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<OcrResult> extraerDatos(Uint8List imagenBytes) async {
    final inputImage = InputImage.fromBytes(
      bytes: imagenBytes,
      metadata: InputImageMetadata(
        size: const Size(1920, 1080),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.nv21,
        bytesPerRow: 1920,
      ),
    );
    final recognizedText = await _textRecognizer.processImage(inputImage);
    final lines = recognizedText.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return const OcrResult();
    }

    return OcrResult(
      nombreNegocio: _extraerNombreNegocio(lines),
      fecha: _extraerFecha(lines),
      monto: _extraerMonto(lines),
      numeroComprobante: _extraerNumeroComprobante(lines),
    );
  }

  String? _extraerNombreNegocio(List<String> lines) {
    final montoPattern = RegExp(
      'total|subtotal|suma|importe|pagado|efectivo|cambio',
      caseSensitive: false,
    );
    final fechaPattern = RegExp(r'\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}');
    final comprobantePattern = RegExp(
      r'(?:n[o\u00ba\u00aa]|#|comprobante|factura|ticket)\s*[:.]?\s*\d',
      caseSensitive: false,
    );

    for (final line in lines) {
      if (montoPattern.hasMatch(line)) continue;
      if (fechaPattern.hasMatch(line)) continue;
      if (comprobantePattern.hasMatch(line)) continue;
      if (line.length < 3) continue;
      if (RegExp(r'^[\d\s\.\,\$\-]+$').hasMatch(line)) continue;

      return line;
    }

    return null;
  }

  String? _extraerFecha(List<String> lines) {
    final patterns = [
      RegExp(r'(\d{1,2}/\d{1,2}/\d{4})'),
      RegExp(r'(\d{1,2}-\d{1,2}-\d{4})'),
      RegExp(r'(\d{4}-\d{2}-\d{2})'),
      RegExp(r'(\d{1,2}/\d{1,2}/\d{2})'),
    ];

    for (final line in lines) {
      for (final pattern in patterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          return match.group(1);
        }
      }
    }

    return null;
  }

  double? _extraerMonto(List<String> lines) {
    final montoPatterns = [
      RegExp(r'total\s*:?\s*\$?\s*([\d,]+\.?\d*)', caseSensitive: false),
      RegExp(
        r'(?:suma|importe|pagado|efectivo)\s*:?\s*\$?\s*([\d,]+\.?\d*)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:subtotal|sub total)\s*:?\s*\$?\s*([\d,]+\.?\d*)',
        caseSensitive: false,
      ),
      RegExp(r'\$\s*([\d,]+\.?\d*)'),
    ];

    for (final line in lines) {
      for (final pattern in montoPatterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          final montoStr = match.group(1)?.replaceAll(',', '');
          if (montoStr != null) {
            final monto = double.tryParse(montoStr);
            if (monto != null && monto > 0) {
              return monto;
            }
          }
        }
      }
    }

    return null;
  }

  String? _extraerNumeroComprobante(List<String> lines) {
    final patterns = [
      RegExp(
        r'(?:n[o\u00ba\u00aa]|#|comprobante|factura|ticket)\s*[:.]?\s*(\d[\d\-]*)',
        caseSensitive: false,
      ),
      RegExp(r'(\d{3}-\d{3}-\d{7})'),
    ];

    for (final line in lines) {
      for (final pattern in patterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          return match.group(1);
        }
      }
    }

    return null;
  }

  void dispose() {
    _textRecognizer.close();
  }
}
