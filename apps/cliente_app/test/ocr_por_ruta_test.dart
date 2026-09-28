import 'package:cliente_app/services/ocr_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// ML Kit no se puede instalar en un equipo de pruebas, asi que se simula su
/// canal de plataforma. Lo importante es comprobar que la app le manda la
/// RUTA del archivo, que es lo que hace que el plugin deduzca el tamaño, el
/// formato y la rotacion reales.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canal = MethodChannel('google_mlkit_text_recognizer');
  late Map<String, dynamic> ultimaImagen;

  /// Texto que el reconocimiento simulado devuelve.
  String textoSimulado = '';

  setUp(() {
    ultimaImagen = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, (call) async {
      if (call.method == 'vision#startTextRecognizer') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        ultimaImagen = Map<String, dynamic>.from(args['imageData'] as Map);
        return <String, dynamic>{'text': textoSimulado, 'blocks': []};
      }
      if (call.method == 'vision#closeTextRecognizer') {
        return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, null);
  });

  test('manda la ruta del archivo, no los bytes con metadatos inventados',
      () async {
    final servicio = OcrService();
    addTearDown(servicio.dispose);

    await servicio.extraerDatos('/tmp/ticket-de-prueba.jpg');

    expect(ultimaImagen['type'], 'file');
    expect(ultimaImagen['path'], '/tmp/ticket-de-prueba.jpg');
    // Con bytes habia que inventarse el tamaño y el formato, y por eso el
    // reconocimiento leia ruido.
    expect(ultimaImagen['bytes'], isNull);
    expect(ultimaImagen['metadata'], isNull);
  });

  test('lee los campos del ticket que devuelve el reconocimiento', () async {
    textoSimulado = '''
CAFETERIA LA ESQUINA
RUC: 1790012345001
Factura: 001-001-00000042
Fecha: 15/03/2026
Total: \$12.50
''';

    final servicio = OcrService();
    addTearDown(servicio.dispose);

    final resultado = await servicio.extraerDatos('/tmp/ticket.jpg');

    expect(resultado.nombreNegocio, 'CAFETERIA LA ESQUINA');
    expect(resultado.fecha, '15/03/2026');
    expect(resultado.monto, 12.50);
    expect(resultado.numeroComprobante, '001-001-00000042');
    expect(resultado.camposDetectados, 4);
    expect(resultado.tieneTodosLosCampos, isTrue);
  });

  test('si el plugin falla, el error sube y no se inventa un resultado',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, (call) async {
      // Solo falla el reconocimiento: cerrar el reconocedor, al.dispose, sigue
      // funcionando.
      if (call.method == 'vision#startTextRecognizer') {
        throw PlatformException(code: 'no_disponible');
      }
      return null;
    });

    final servicio = OcrService();
    addTearDown(servicio.dispose);

    // Sin datos inventados: la pantalla decide que avise al usuario.
    await expectLater(
      servicio.extraerDatos('/tmp/no-existe.jpg'),
      throwsA(isA<PlatformException>()),
    );
  });

  test('si el texto viene vacio, el resultado va vacio', () async {
    textoSimulado = '';

    final servicio = OcrService();
    addTearDown(servicio.dispose);

    final resultado = await servicio.extraerDatos('/tmp/ticket.jpg');

    expect(resultado.camposDetectados, 0);
    expect(resultado.tieneTodosLosCampos, isFalse);
  });
}
