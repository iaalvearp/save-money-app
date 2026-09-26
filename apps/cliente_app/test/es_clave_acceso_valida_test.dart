import 'package:flutter_test/flutter_test.dart';

import 'package:cliente_app/screens/facturacion_screen.dart';

void main() {
  group('esClaveAccesoValida', () {
    const claveValida = '0123456789012345678901234567890123456789012345678';

    test('acepta una clave de exactamente 49 dígitos numéricos', () {
      expect(esClaveAccesoValida(claveValida), isTrue);
    });

    test('rechaza claves con longitud incorrecta', () {
      expect(esClaveAccesoValida('12345'), isFalse);
      expect(
        esClaveAccesoValida(
          '012345678901234567890123456789012345678901234567890',
        ),
        isFalse,
      );
    });

    test('rechaza claves con caracteres no numéricos', () {
      expect(esClaveAccesoValida('012345678901234567890123456789012345678901234567A'), isFalse);
      expect(
        esClaveAccesoValida(
          '0123-56789012345678901234567890123456789012345678',
        ),
        isFalse,
      );
    });

    test('rechaza una cadena vacía', () {
      expect(esClaveAccesoValida(''), isFalse);
    });
  });
}