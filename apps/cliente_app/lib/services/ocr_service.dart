import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrResult {
  final String? nombreNegocio;
  final String? fecha;
  final double? monto;
  final String? numeroComprobante;

  /// RUC del comercio que emitió la factura, no el del cliente. Es el que
  /// empieza por 09 o 17 y viene en la cabecera del comprobante.
  final String? rucEmisor;

  /// Clave de acceso del SRI, solo si se pudo leer completa. Con los 49
  /// dígitos la factura se valida contra el SRI igual que si se escanea el QR;
  /// sin los 49 no sirve y se sigue por la revisión manual.
  final String? claveAcceso;

  const OcrResult({
    this.nombreNegocio,
    this.fecha,
    this.monto,
    this.numeroComprobante,
    this.rucEmisor,
    this.claveAcceso,
  });

  /// Cuenta los campos de la revisión manual. La clave de acceso y el RUC van
  /// aparte: no se revisan a mano, se usan o se muestran como dato de apoyo.
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

  /// Lee la foto del comprobante desde su ruta en disco.
  ///
  /// Antes se pasaba la imagen como bytes con unos metadatos inventados
  /// (1920x1080, nv21, sin rotacion) que no tenian nada que ver con la foto.
  /// ML Kit necesita saber el tamaño real, el formato y la rotacion, asi que
  /// con esos datos leia ruido y el OCR no encontraba los campos. Con la ruta
  /// el propio plugin deduce todo eso. Ademas asi la imagen no se carga en
  /// memoria ni se manda a ningun sitio: se queda en el telefono.
  Future<OcrResult> extraerDatos(String rutaImagen) async {
    final inputImage = InputImage.fromFilePath(rutaImagen);
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
      rucEmisor: _extraerRucEmisor(lines),
      claveAcceso: _extraerClaveAcceso(lines),
    );
  }

  /// Busca la clave de acceso impresa en el ticket.
  ///
  /// Va en un bloque que empieza por "CLAVE DE ACCESO" o "AUTORIZACION" y
  /// sigue en las lineas de abajo, partida en dos o mas, sin guiones ni
  /// espacios: solo se concatenan los digitos.
  ///
  /// Devuelve `null` salvo que se junten exactamente 49. Una clave a la que
  /// le falta un digito no se puede validar contra el SRI, y mandarla igual
  /// solo produciria un rechazo que el usuario no podria entender. Es mejor
  /// caer en la revision manual, donde puede escribirla.
  String? _extraerClaveAcceso(List<String> lines) {
    final encabezado = RegExp(
      r'(?:clave\s*(?:de\s*)?acceso|autORIZACI[OÓ]N)',
      caseSensitive: false,
    );

    final indice =
        lines.indexWhere((linea) => encabezado.hasMatch(linea));
    if (indice == -1) return null;

    final digitos = StringBuffer();
    for (final linea in lines.sublist(indice + 1)) {
      for (final codigo in linea.runes) {
        final caracter = String.fromCharCode(codigo);
        if (caracter.compareTo('0') >= 0 && caracter.compareTo('9') <= 0) {
          digitos.write(caracter);
          if (digitos.length == 49) {
            return digitos.toString();
          }
        }
      }
    }

    return null;
  }

  /// RUC del emisor.
  ///
  /// Busca "RUC" o "RUC EMISOR" seguidos de 13 digitos. La linea "RUC/CED/PAS"
  /// no encaja porque despues de RUC hay una barra y no un numero, y asi el
  /// documento del cliente no se confunde con el del comercio.
  String? _extraerRucEmisor(List<String> lines) {
    final patron = RegExp(
      r'\bRUC(?:\s+EMISOR)?\s*[:.]?\s*(\d{13})',
      caseSensitive: false,
    );

    for (final linea in lines) {
      final encontrado = patron.firstMatch(linea);
      if (encontrado != null) {
        return encontrado.group(1);
      }
    }

    return null;
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
    // El año de cuatro cifras va primero. Con "2026/09/25" los patrones
    // antiguos se comian los ultimos dos digitos y devolvian "09/25", que no
    // dice nada.
    final patterns = [
      RegExp(r'(\d{4}[/\-]\d{1,2}[/\-]\d{1,2})'),
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
    // Se prueban por grupos y no linea por linea. Recorriendo las lineas en
    // orden, la primera que casa gana, y en este ticket "SUBTOTAL 1.56" va
    // antes que "TOTAL 11.98": el monto salia siendo el subtotal. Con \b antes
    // de TOTAL, "SUBTOTAL" ya no cuenta como total, y aun asi el subtotal solo
    // se usa cuando no hay ningun total en todo el ticket.
    final grupos = [
      [
        // Admite palabras entre TOTAL y la cifra, para "TOTAL A PAGAR 11.98".
        RegExp(
          r'\bTOTAL\b(?:\s+[A-ZÁÉÍÓÚÑ]+)*\s*:?\s*\$?\s*([\d,]+\.?\d*)',
          caseSensitive: false,
        ),
        RegExp(
          r'(?:suma|importe|pagado|efectivo)\s*:?\s*\$?\s*([\d,]+\.?\d*)',
          caseSensitive: false,
        ),
        RegExp(r'\$\s*([\d,]+\.?\d*)'),
      ],
      [
        RegExp(
          r'(?:subtotal|sub total)\s*:?\s*\$?\s*([\d,]+\.?\d*)',
          caseSensitive: false,
        ),
      ],
    ];

    for (final grupo in grupos) {
      for (final line in lines) {
        for (final pattern in grupo) {
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
    }

    return null;
  }

  String? _extraerNumeroComprobante(List<String> lines) {
    // El "#" que antes se aceptaba cogia el numero de cajero ("CAJERO(A)#:99916902")
    // en vez del comprobante. Ahora se busca la linea del comprobante, y
    // "CAJERO" y "POS" quedan fuera a proposito.
    final patterns = [
      RegExp(
        r'\bCOMPROBANTE\s*(?:DE\s+)?FACT(?:URA)?\s*:?\s*(\d[\d\-]*)',
        caseSensitive: false,
      ),
      RegExp(
        r'\bFACTURA\b\s*(?:N\s*[o\u00ba\u00aa]?|#)?\s*:?\s*(\d[\d\-]*)',
        caseSensitive: false,
      ),
      RegExp(r'(\d{3}-\d{3}-\d{7,9})'),
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
