import 'package:cliente_app/services/ocr_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// ML Kit no corre en un equipo de pruebas, asi que se simula su canal para
/// que la extracción se pruebe sobre el texto exacto que salio del
/// reconocimiento, sin reescribirlo.
const _canal = MethodChannel('google_mlkit_text_recognizer');

/// Texto tal cual lo devolvio el reconocimiento del ticket delusuario.
/// No se ha corregido ni reordered: si aqui hay un error, tambien lo habia.
const _textoDelTicket = '''
CORPORACION EL ROSADO S.A.MATRIZ AV. 9 DE OCTUBRE 729
BOYACA - GARCIA AVILES -GUAYAQUIL-
RUC:0990004196001


HIPERMARKET VERGELES
DETALLE DE FACTURA ELECTRONICA
RESOLUCION N NAC-DGERCGC12-00105


CODIGO DESCR. CANT. P.UNIT. VALOR
452674 CREMA C 1 3.78 3.78
583502 HISOPOS 1 0.91 0.91
646358 NESCAFE 1 5.73 5.73
SUBTOTAL 1.56
I.V.A. 15% 0.00
I.V.A. 5% 11.98
TOTAL 11.98
ITEMS: 3
2026/09/25 TIENDA:169 POS:202
CAJERO(A)#:99916902 SCO OPERA
T.CONT.:5572 06:03:41


COMPROBANTE FACT: 121-202-000167353
NOMBRE : PESANTEZ LAINEZ ELSY MARILYN
RUC/CED/PAS: 0906653456


CLAVE DE ACCESO / AUTORIZACION
2509202601099004196001212120200016735
30016735315
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String textoSimulado = _textoDelTicket;

  setUp(() {
    textoSimulado = _textoDelTicket;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canal, (call) async {
      if (call.method == 'vision#startTextRecognizer') {
        return <String, dynamic>{'text': textoSimulado, 'blocks': []};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canal, null);
  });

  Future<OcrResult> leer() async {
    final servicio = OcrService();
    addTearDown(servicio.dispose);
    return servicio.extraerDatos('/tmp/ticket.jpg');
  }

  group('Ticket real del HIPERMARKET VERGELES', () {
    test('el RUC es el del comercio, no el del cliente', () async {
      final resultado = await leer();

      // "RUC:0990004196001" de la cabecera. El 0906653456 de "RUC/CED/PAS" es
      // el documento de quien compra y no sirve para nada aqui.
      expect(resultado.rucEmisor, '0990004196001');
      expect(resultado.rucEmisor, isNot('0906653456'));
    });

    test('el numero de factura no es el numero de cajero', () async {
      final resultado = await leer();

      expect(resultado.numeroComprobante, '121-202-000167353');
      expect(resultado.numeroComprobante, isNot('99916902'));
    });

    test('la fecha se lee entera, con el año', () async {
      final resultado = await leer();

      expect(resultado.fecha, '2026/09/25');
    });

    test('el monto es el TOTAL, no el SUBTOTAL', () async {
      final resultado = await leer();

      expect(resultado.monto, 11.98);
      expect(resultado.monto, isNot(1.56));
    });

    test('la clave de acceso sale incompleta, asi que no se usa', () async {
      final resultado = await leer();

      // Las dos lineas de la clave dan 37 + 11 = 48 digitos. Falta uno para
      // los 49 que exige el SRI, asi que no se manda a validar: caeria en
      // revision manual, donde el usuario puede escribirla bien.
      final digitosImpresos =
          '2509202601099004196001212120200016735' '30016735315';
      expect(digitosImpresos.length, 48);
      expect(digitosImpresos.length, isNot(49));

      expect(resultado.claveAcceso, isNull);
    });

    test('los campos de la revision manual si se llenan', () async {
      final resultado = await leer();

      // El nombre sale de la primera linea, que es la del comercio. Antes de
      // esta correccion tampoco se detectaba.
      expect(resultado.nombreNegocio, isNotNull);
      expect(resultado.camposDetectados, greaterThanOrEqualTo(3));
    });
  });

  group('Clave de acceso completa', () {
    test('si llega a 49 digitos se devuelve para validar contra el SRI',
        () async {
      // A este ticket le falta un digito en la segunda linea. Se lo devolvemos
      // para comprobar el camino bueno, que el SRI siPodria leer.
      textoSimulado = _textoDelTicket.replaceFirst(
        '30016735315',
        '330016735315',
      );

      final resultado = await leer();

      expect(
        resultado.claveAcceso,
        '2509202601099004196001212120200016735330016735315',
      );
      expect(resultado.claveAcceso, hasLength(49));
    });

    test('la clave se arma con los digitos aunque esten partidos en lineas',
        () async {
      textoSimulado = '''
TICKET DE PRUEBA
CLAVE DE ACCESO
2509
2026
010999004196001
2121202000167
3533016735315
''';

      final resultado = await leer();

      expect(resultado.claveAcceso, hasLength(49));
      expect(resultado.claveAcceso!.substring(0, 8), '25092026');
    });

    test('si faltan digitos, no devuelve una clave a medias', () async {
      textoSimulado = '''
TICKET DE PRUEBA
CLAVE DE ACCESO
2509202601099004196
''';

      final resultado = await leer();

      expect(resultado.claveAcceso, isNull);
    });

    test('si no hay clave de acceso, no inventa ninguna', () async {
      textoSimulado = '''
TICKET SIN CLAVE
RUC: 0990004196001
TOTAL 5.00
''';

      final resultado = await leer();

      expect(resultado.claveAcceso, isNull);
    });
  });
}
