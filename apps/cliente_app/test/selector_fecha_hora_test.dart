import 'package:flutter_test/flutter_test.dart';

import 'package:cliente_app/widgets/selector_fecha_hora.dart';

void main() {
  group('SelectorFechaHora.formatear', () {
    test('devuelve el texto que espera el backend', () {
      expect(
        SelectorFechaHora.formatear(DateTime(2026, 10, 1, 19, 5, 7)),
        '2026-10-01 19:05:07',
      );
    });

    test('rellena con ceros los meses, días, horas y minutos de un digito', () {
      expect(
        SelectorFechaHora.formatear(DateTime(2026, 1, 2, 3, 4, 5)),
        '2026-01-02 03:04:05',
      );
    });

    test('rellena con ceros el año si llega con menos de cuatro cifras', () {
      // Solo por robustez: los selectores nunca devuelven años de tres cifras.
      expect(
        SelectorFechaHora.formatear(DateTime(26, 1, 2, 3, 4, 5)),
        '0026-01-02 03:04:05',
      );
    });

    test('guarda la hora del reloj sin convertirla a UTC', () {
      // El backend interpreta este texto como hora de Ecuador. Si aquí se
      // convirtiera a UTC, todos los eventos quedarían corridos cinco horas.
      final elegido = DateTime(2026, 10, 1, 19, 0);
      final texto = SelectorFechaHora.formatear(elegido);
      expect(texto, '2026-10-01 19:00:00');
      expect(SelectorFechaHora.leer(texto)!.hour, 19);
    });
  });

  group('SelectorFechaHora.leer', () {
    test('lee el texto que escribe el propio selector', () {
      final original = DateTime(2026, 10, 1, 19, 0);
      expect(SelectorFechaHora.leer(SelectorFechaHora.formatear(original)),
          original);
    });

    test('acepta espacios alrededor', () {
      expect(
        SelectorFechaHora.leer('  2026-10-01 19:00:00  '),
        DateTime(2026, 10, 1, 19, 0),
      );
    });

    test('devuelve null si el texto no es una fecha', () {
      expect(SelectorFechaHora.leer('mañana'), isNull);
      expect(SelectorFechaHora.leer(''), isNull);
      expect(SelectorFechaHora.leer(null), isNull);
    });
  });
}
