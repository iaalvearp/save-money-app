import 'package:flutter_test/flutter_test.dart';
import 'package:cliente_app/services/ocr_service.dart';

void main() {
  group('OcrResult', () {
    test('camposDetectados cuenta solo campos no nulos y no vacíos', () {
      const result = OcrResult(
        nombreNegocio: 'Mi Negocio',
        fecha: '15/09/2026',
        monto: 25.50,
        numeroComprobante: '001-001-0000123',
      );
      expect(result.camposDetectados, 4);
      expect(result.tieneTodosLosCampos, true);
    });

    test('camposDetectados retorna 0 cuando todo es nulo', () {
      const result = OcrResult();
      expect(result.camposDetectados, 0);
      expect(result.tieneTodosLosCampos, false);
    });

    test('camposDetectados cuenta solo campos parciales', () {
      const result = OcrResult(monto: 10.0);
      expect(result.camposDetectados, 1);
      expect(result.tieneTodosLosCampos, false);
    });

    test('ignora strings vacíos como no detectados', () {
      const result = OcrResult(
        nombreNegocio: '',
        fecha: '',
      );
      expect(result.camposDetectados, 0);
    });

    test('monto con valor', () {
      const result = OcrResult(monto: 25.50);
      expect(result.monto, 25.50);
    });

    test('todos los campos nulos', () {
      const result = OcrResult();
      expect(result.nombreNegocio, isNull);
      expect(result.fecha, isNull);
      expect(result.monto, isNull);
      expect(result.numeroComprobante, isNull);
    });

    test('monto sin otros campos', () {
      const result = OcrResult(monto: 15.00);
      expect(result.camposDetectados, 1);
      expect(result.nombreNegocio, isNull);
      expect(result.fecha, isNull);
      expect(result.numeroComprobante, isNull);
    });

    test('campos mixtos', () {
      const result = OcrResult(
        nombreNegocio: 'Cafeteria Central',
        monto: 4.50,
      );
      expect(result.camposDetectados, 2);
      expect(result.nombreNegocio, 'Cafeteria Central');
      expect(result.monto, 4.50);
      expect(result.fecha, isNull);
      expect(result.numeroComprobante, isNull);
    });

    test('numeroComprobante formato guiones', () {
      const result = OcrResult(numeroComprobante: '001-002-0000456');
      expect(result.numeroComprobante, '001-002-0000456');
      expect(result.camposDetectados, 1);
    });

    test('fecha formato DD/MM/YYYY', () {
      const result = OcrResult(fecha: '15/09/2026');
      expect(result.fecha, '15/09/2026');
      expect(result.camposDetectados, 1);
    });

    test('fecha formato YYYY-MM-DD', () {
      const result = OcrResult(fecha: '2026-09-15');
      expect(result.fecha, '2026-09-15');
    });
  });
}
